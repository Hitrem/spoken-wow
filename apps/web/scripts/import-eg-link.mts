/**
 * Import Efficient Games' published BroadcastText rows and gossip speakers.
 *
 *   cd apps/web
 *   DATABASE_URL=postgres://… npx tsx --conditions=react-server scripts/import-eg-link.mts [--dry-run]
 *
 * github.com/JIVESCORP/eg-link-output-wowf publishes what EG Link players' caches hold, per
 * client build and language: `broadcast_text.<locale>.json` (every BroadcastText row the
 * server sent, by id) and `texts.<locale>.json` (which NPC's gossip or greeting showed which
 * ids). Licensed CC BY 4.0: anything built on these rows credits Efficient Games
 * (https://efficient.games), as docs/quests/README.md does.
 *
 * Builds are imported oldest first, so a newer build's text for an id is the one kept, the
 * same rule a cache upload follows (lib/broadcast/store.ts). Safe to re-run.
 *
 * DATABASE_URL is required and never read from .env, as for drop-known-contributions.mts.
 */
import { closeDb } from "@/lib/db";
import { recordSpeakers, recordTexts, type BroadcastRow, type BroadcastSpeaker } from "@/lib/broadcast/store";
import { isLang, type Lang } from "@/lib/lang";

if (!process.env.DATABASE_URL) {
  console.error("DATABASE_URL is unset -- say which database to import into.");
  process.exit(1);
}

const dryRun = process.argv.includes("--dry-run");
const REPO = "JIVESCORP/eg-link-output-wowf";
const BRANCH = "main";

type Variant = { broadcastTextIds?: number[] };
type TextsFile = { gossip?: Record<string, Variant[]>; greeting?: Record<string, Variant[]> };
type BroadcastFile = { texts: Record<string, { text?: string; text1?: string }> };

async function fetchJson<T>(url: string): Promise<T> {
  const response = await fetch(url, { headers: { "user-agent": "spoken-import-eg-link" } });
  if (!response.ok) throw new Error(`${url}: ${response.status}`);
  return (await response.json()) as T;
}

const raw = (path: string) => `https://raw.githubusercontent.com/${REPO}/${BRANCH}/${path}`;

// data/<product>/<clientBuild>/<dataset>.<locale>.json
const FILE = /^data\/([^/]+)\/\d+\.\d+\.\d+\.(\d+)\/(broadcast_text|texts)\.([a-z]{2}[A-Z]{2})\.json$/;

const tree = await fetchJson<{ tree: { path: string }[]; truncated: boolean }>(
  `https://api.github.com/repos/${REPO}/git/trees/${BRANCH}?recursive=1`,
);
if (tree.truncated) throw new Error("the repository listing came back truncated");

const files = tree.tree
  .map(({ path }) => {
    const match = FILE.exec(path);
    if (!match) return null;
    const [, product, build, dataset, locale] = match;
    return isLang(locale) ? { path, product, build: Number(build), dataset, locale: locale as Lang } : null;
  })
  .filter((file) => file !== null)
  .sort((a, b) => a.build - b.build);

function speakersOf(file: TextsFile): BroadcastSpeaker[] {
  const speakers: BroadcastSpeaker[] = [];
  for (const window of ["gossip", "greeting"] as const) {
    for (const [key, variants] of Object.entries(file[window] ?? {})) {
      const [kind, id] = key.split(":");
      if ((kind !== "npc" && kind !== "object") || !/^\d+$/.test(id)) continue;
      for (const variant of variants) {
        for (const broadcastTextId of variant.broadcastTextIds ?? []) {
          speakers.push({ entityKind: kind, entityId: Number(id), broadcastTextId, window });
        }
      }
    }
  }
  return speakers;
}

console.log(dryRun ? "dry run -- nothing written" : "importing");
for (const file of files) {
  if (file.dataset === "broadcast_text") {
    const body = await fetchJson<BroadcastFile>(raw(file.path));
    const rows: BroadcastRow[] = Object.entries(body.texts).map(([id, row]) => ({
      id: Number(id),
      text: row.text ?? "",
      text1: row.text1 ?? "",
    }));
    const counts = dryRun ? { texts: rows.length, added: 0, changed: 0 } : await recordTexts(file.locale, file.build, "eglink", rows);
    console.log(`  ${file.product} ${file.build} ${file.locale} texts ${counts.texts} added ${counts.added} changed ${counts.changed}`);
  } else {
    const speakers = speakersOf(await fetchJson<TextsFile>(raw(file.path)));
    const added = dryRun ? 0 : await recordSpeakers("eglink", speakers);
    console.log(`  ${file.product} ${file.build} ${file.locale} speakers ${speakers.length} added ${added}`);
  }
}

await closeDb();
