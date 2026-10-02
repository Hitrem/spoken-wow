/**
 * Name the quests and NPCs that accepted translations showed, for the rows accepted before
 * accepting did it (lib/contributions/accept.ts's namesSeenIn).
 *
 *   cd apps/web
 *   DATABASE_URL=postgres://… npx tsx --conditions=react-server \
 *     scripts/backfill-contribution-names.mts [--dry-run]
 *
 * Only accepted rows: a name is shown on the site as soon as it is written, so it waits on a
 * moderator the way the line does. Written exactly as accept writes one -- 'contributed', only
 * where the language has no current name, with the contribution's note and its resolver --
 * oldest accept first, so where two rows name one thing the one kept is the one accept would
 * have kept.
 *
 * DATABASE_URL is required and never read from .env, as for backfill-contribution-npcs.mts.
 * --dry-run reports what would be named and rolls back.
 */
import { closeDb, db } from "@/lib/db";
import { nameIfUnnamed, namesSeenIn, noteFor } from "@/lib/contributions/accept";
import { CONTRIBUTION_COLUMNS, type Contribution } from "@/lib/contributions/store";
import { BASE_LANG, isLang } from "@/lib/lang";

if (!process.env.DATABASE_URL) {
  console.error("DATABASE_URL is unset -- say which database to write to.");
  process.exit(1);
}

const dryRun = process.argv.includes("--dry-run");

const { rows } = await db().query<Contribution>(
  `select ${CONTRIBUTION_COLUMNS} from "contribution"
    where "status" = 'accepted' and "source" = 'quests' and "locale" <> $1
    order by "updatedAt", "id"`,
  [BASE_LANG],
);

const tally = new Map<string, { named: number; had: number }>();
const client = await db().connect();
try {
  await client.query("begin");
  for (const row of rows) {
    if (!isLang(row.locale)) continue;
    for (const name of namesSeenIn(row)) {
      const named = await nameIfUnnamed(client, {
        ...name,
        lang: row.locale,
        userId: row.resolvedBy,
        note: noteFor(row.id),
      });
      const key = `${row.locale} ${name.kind}`;
      const counts = tally.get(key) ?? { named: 0, had: 0 };
      counts[named ? "named" : "had"] += 1;
      tally.set(key, counts);
    }
  }
  await client.query(dryRun ? "rollback" : "commit");
} catch (error) {
  await client.query("rollback");
  throw error;
} finally {
  client.release();
}

console.log(dryRun ? "dry run -- nothing written" : "done");
console.log(`  ${"locale kind".padEnd(18)} ${(dryRun ? "would name" : "named").padStart(10)} ${"had one".padStart(8)}`);
for (const [key, counts] of [...tally].sort(([a], [b]) => a.localeCompare(b))) {
  console.log(`  ${key.padEnd(18)} ${String(counts.named).padStart(10)} ${String(counts.had).padStart(8)}`);
}

await closeDb();
