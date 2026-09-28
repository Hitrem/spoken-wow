/**
 * Fill in the speaker of already-stored quest contributions from a re-gathered file.
 *
 *   cd apps/web
 *   DATABASE_URL=postgres://… npx tsx --conditions=react-server \
 *     scripts/backfill-contribution-npcs.mts [--dry-run] FILE…
 *
 * FILE is a SpokenContributions SavedVariables file (.lua), the same thing the contribute page
 * takes, or a JSON array of { envelope } objects. Every envelope goes through the app's own
 * parseEnvelope and submissionFrom, so its "dedup" is exactly the one intake computed; a row
 * with that dedup and no NPC gets the envelope's npc/kind/model/sex/creature merged into its
 * meta (store.ts's fillContributionNpc), and its speaker is then resolved as intake would have
 * (lib/npc/resolve.ts). Nothing is inserted and no count moves: a line that was never stored,
 * or that already names an NPC, is only counted in the summary.
 *
 * DATABASE_URL is required and never read from .env: the point of this script is to be aimed
 * at a database on purpose. --dry-run reports what would change and writes nothing.
 */
import { readFileSync } from "node:fs";

import { closeDb, db } from "@/lib/db";
import { parseEnvelope } from "@/lib/contributions/envelope";
import { envelopesFromSavedVariables } from "@/lib/contributions/saved-variables";
import { fillContributionNpc } from "@/lib/contributions/store";
import { submissionFrom } from "@/lib/contributions/submission";
import { observedFrom, resolveNpc } from "@/lib/npc/resolve";

if (!process.env.DATABASE_URL) {
  console.error("DATABASE_URL is unset -- say which database to write to.");
  process.exit(2);
}

const args = process.argv.slice(2);
const dryRun = args.includes("--dry-run");
const files = args.filter((arg) => arg !== "--dry-run");
if (files.length === 0) {
  console.error("usage: backfill-contribution-npcs.mts [--dry-run] FILE…");
  process.exit(2);
}

function envelopesIn(file: string): string[] {
  const source = readFileSync(file, "utf8");
  if (file.endsWith(".json")) {
    return (JSON.parse(source) as { envelope: string }[]).map((row) => row.envelope);
  }
  return envelopesFromSavedVariables(source);
}

const tally = {
  envelopes: 0,
  refused: 0,
  noNpc: 0,
  filled: 0,
  alreadyNamed: 0,
  notStored: 0,
  resolved: 0,
  resolveFailed: 0,
};
const seen = new Set<string>();
const observations = new Map<string, ReturnType<typeof observedFrom>>();

for (const file of files) {
  for (const raw of envelopesIn(file)) {
    tally.envelopes += 1;
    const parsed = parseEnvelope(raw);
    const submission = parsed.ok && parsed.value.source === "quests" ? submissionFrom(parsed.value, raw, null) : null;
    if (!submission) {
      tally.refused += 1;
      continue;
    }
    // The same line in two files (a split upload, or two gatherings) is one row.
    if (seen.has(submission.dedup)) continue;
    seen.add(submission.dedup);
    if (!submission.meta.npc) {
      tally.noNpc += 1;
      continue;
    }

    if (!dryRun && (await fillContributionNpc(submission))) {
      tally.filled += 1;
    } else {
      // Why it was not filled -- or, on a dry run, whether it would be.
      const { rows } = await db().query<{ npc: string | null }>(
        `select "meta"->>'npc' as "npc" from "contribution" where "dedup" = $1`,
        [submission.dedup],
      );
      if (rows.length === 0) tally.notStored += 1;
      else if (rows[0].npc) tally.alreadyNamed += 1;
      else tally.filled += 1;
      continue;
    }

    // As storeSubmission does: build lives in its own column, so it goes back in for observedFrom.
    const observed = observedFrom({ ...submission.meta, build: submission.build });
    observations.set(JSON.stringify(observed), observed);
  }
}

// Once per distinct observation, as a batch upload does -- resolution reads the corpus.
if (!dryRun) {
  for (const observed of observations.values()) {
    try {
      await resolveNpc(observed);
      tally.resolved += 1;
    } catch (error) {
      tally.resolveFailed += 1;
      console.error(`could not resolve ${observed.npcKind} ${observed.npcId}:`, error);
    }
  }
}

console.log(dryRun ? "dry run -- nothing written" : "done");
console.log(`  envelopes read           ${tally.envelopes}`);
console.log(`  refused by intake checks ${tally.refused}`);
console.log(`  naming no NPC (skipped)  ${tally.noNpc}`);
console.log(`  ${(dryRun ? "would fill" : "filled").padEnd(24)} ${tally.filled}`);
console.log(`  already named an NPC     ${tally.alreadyNamed}`);
console.log(`  not stored at all        ${tally.notStored}`);
if (!dryRun) console.log(`  speakers resolved        ${tally.resolved} (${tally.resolveFailed} failed)`);

await closeDb();
