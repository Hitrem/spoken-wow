/**
 * Resolve the speakers of the WoW Forever quests from a Wowhead gathering.
 *
 *   cd apps/web
 *   DATABASE_URL=postgres://… npx tsx --conditions=react-server \
 *     scripts/import-wowhead-npcs.mts DIR
 *
 * DIR holds quest_npc_mapping.json and resolved-speakers.json: each quest's start and end NPC
 * as Wowhead's infobox names them, with the appearance ids Wowhead shows for the NPC and the
 * model and sex the 1.60.1 client tables give each one. That is what the addon's envelope
 * carries about a speaker (npc, kind, model, sex, creature, displays), so every NPC goes through
 * the app's own resolveNpc exactly as a player's report would. The rank in upsertResolution is
 * what keeps this safe to run: a corpus or moderator answer is never overwritten, and running it
 * twice changes nothing.
 *
 * Creatures only. A gameobject has no appearance or model to report, so the best it could
 * produce is a `none` row holding a name.
 *
 * Resolving an NPC does not re-voice lines already accepted for it: quest_line_speaker keeps the
 * voice it was accepted with, and moving it means regenerating the file, which spends credits.
 * So the script ends by listing every speaker row whose voice now disagrees with its NPC's
 * resolution, for a person to decide on.
 *
 * DATABASE_URL is required and never read from .env: the point of this script is to be aimed
 * at a database on purpose. Aim it at a copy (createdb -T) to preview a run.
 */
import { readFileSync } from "node:fs";
import path from "node:path";

import { closeDb, db } from "@/lib/db";
import { resolveNpc, type Observed } from "@/lib/npc/resolve";
import { getResolutions, resolutionKey, type NpcResolution } from "@/lib/npc/store";

if (!process.env.DATABASE_URL) {
  console.error("DATABASE_URL is unset -- say which database to write to.");
  process.exit(2);
}
const dir = process.argv[2];
if (!dir) {
  console.error("usage: import-wowhead-npcs.mts DIR");
  process.exit(2);
}

// The client the gathering read its tables from, in the envelope's build format.
const BUILD = "1.60.1/70009";

type Speaker = {
  kind: string;
  id: number;
  display_id?: number | null;
  model_file_id?: number | null;
  sex?: number | null;
  name_enUS?: string | null;
  creature_type_enUS?: string | null;
} | null;
type Display = { display_id: number; model_file_id: number | null; sex: number | null };

const mapping = JSON.parse(readFileSync(path.join(dir, "quest_npc_mapping.json"), "utf8")) as {
  quests: Record<string, { start: Speaker; end: Speaker }>;
};
const speakers = JSON.parse(readFileSync(path.join(dir, "resolved-speakers.json"), "utf8")) as {
  npcs: Record<string, { name_enUS: string | null; creature_type: string | null; displays: Display[] }>;
};

// One observation per NPC, both files merged: the mapping names the model of the appearance it
// shows, and resolved-speakers lists every appearance Wowhead has for the NPC.
const observations = new Map<number, Observed>();
function observe(id: number): Observed {
  let observed = observations.get(id);
  if (!observed) {
    observed = {
      npcKind: "creature", npcId: id, npcName: null, modelFileId: null, displayIds: [],
      sex: null, creatureType: null, build: BUILD,
    };
    observations.set(id, observed);
  }
  return observed;
}
function addDisplay(observed: Observed, display: Display) {
  if (!observed.displayIds.includes(display.display_id)) observed.displayIds.push(display.display_id);
  observed.modelFileId ??= display.model_file_id;
  observed.sex ??= display.sex;
}

let gameobjects = 0;
for (const quest of Object.values(mapping.quests)) {
  for (const speaker of [quest.start, quest.end]) {
    if (!speaker) continue;
    if (speaker.kind !== "creature") {
      gameobjects += 1;
      continue;
    }
    const observed = observe(speaker.id);
    observed.npcName ??= speaker.name_enUS ?? null;
    observed.creatureType ??= speaker.creature_type_enUS ?? null;
    if (speaker.display_id) {
      addDisplay(observed, { display_id: speaker.display_id, model_file_id: speaker.model_file_id ?? null, sex: speaker.sex ?? null });
    }
  }
}
for (const [id, npc] of Object.entries(speakers.npcs)) {
  const observed = observe(Number(id));
  observed.npcName ??= npc.name_enUS;
  observed.creatureType ??= npc.creature_type;
  for (const display of npc.displays) addDisplay(observed, display);
}

const voiceOf = (row: NpcResolution | undefined) =>
  row?.race ? [row.race, row.gender, row.flavor].filter(Boolean).join("-") : null;

const keys = [...observations.keys()].map((npcId) => ({ npcKind: "creature" as const, npcId }));
const before = await getResolutions(keys);

let done = 0;
let failed = 0;
for (const observed of observations.values()) {
  try {
    await resolveNpc(observed);
  } catch (error) {
    failed += 1;
    console.error(`\ncould not resolve creature ${observed.npcId}:`, error);
  }
  if (process.stderr.isTTY) process.stderr.write(`\r  resolving ${++done}/${observations.size}`);
}
if (process.stderr.isTTY) process.stderr.write("\n");

const after = await getResolutions(keys);
const tally = new Map<string, number>();
const changes: string[] = [];
const revoiced: number[] = [];
for (const { npcKind, npcId } of keys) {
  const key = resolutionKey(npcKind, npcId);
  const was = before.get(key);
  const now = after.get(key);
  const label = !now
    ? "no row"
    : !was
      ? `new ${now.provenance}`
      : was.provenance === now.provenance && voiceOf(was) === voiceOf(now)
        ? `unchanged ${now.provenance}`
        : `${was.provenance} -> ${now.provenance}`;
  tally.set(label, (tally.get(label) ?? 0) + 1);
  if (now && voiceOf(was) !== voiceOf(now)) revoiced.push(npcId);
  if (now && (!was || voiceOf(was) !== voiceOf(now) || was.provenance !== now.provenance)) {
    changes.push(`  ${String(npcId).padStart(6)} ${(now.npcName ?? "").padEnd(34)} `
      + `${was ? `${was.provenance} ${voiceOf(was) ?? "-"}` : "(none)"} -> ${now.provenance} ${voiceOf(now) ?? "-"}`);
  }
}

console.log(`${observations.size} creatures (${gameobjects} gameobject speakers skipped, ${failed} failed)`);
for (const [label, count] of [...tally].sort((a, b) => b[1] - a[1])) console.log(`  ${String(count).padStart(4)} ${label}`);
if (changes.length) console.log(`\nchanged:\n${changes.join("\n")}`);

// Speakers accepted with a voice their NPC no longer resolves to, for the NPCs this run moved.
// Unconfirmed resolutions are left out: a guess is no reason to spend credits on a line a person
// may already have chosen. NPCs this run left alone are left out too: a corpus NPC whose lines
// carry two flavors is the extraction's business, not this import's.
const { rows: stale } = await db().query<{
  npcId: number; npcName: string; lineId: string; lang: string; fileName: string | null; voice: string; resolved: string;
}>(
  `select s."npcId", s."npcName", s."lineId", s.lang, l."fileName", s.voice,
          concat_ws('-', r.race, r.gender, r.flavor) as resolved
     from quest_line_speaker s
     join npc_resolution r on r."npcKind" = s."npcType" and r."npcId" = s."npcId"
     left join quest_line l on l."lineId" = s."lineId" and l.variant = s.variant
                           and l.lang = s.lang and l."isCurrent"
    where s."npcType" = 'creature' and s."npcId" = any($1::int[])
      and r.confirmed and r.race is not null
      and s.voice <> concat_ws('-', r.race, r.gender, r.flavor)
    order by s."npcId", s."lineId", s.lang`,
  [revoiced],
);
console.log(`\n${stale.length} speaker rows voiced other than their NPC now resolves:`);
for (const row of stale) {
  console.log(`  ${String(row.npcId).padStart(6)} ${row.npcName.padEnd(28)} ${row.lineId.padEnd(20)} `
    + `${row.lang} ${row.fileName ?? "-"}  ${row.voice} -> ${row.resolved}`);
}

await closeDb();
