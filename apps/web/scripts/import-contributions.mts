/**
 * Store a batch of contributions a contributor sent us directly, as SpokenContributions files.
 *
 *   cd apps/web
 *   DATABASE_URL=postgres://… npx tsx --conditions=react-server \
 *     scripts/import-contributions.mts --name NAME [--email EMAIL] [--book-pages JSON] \
 *       [--dry-run] [--list WHAT] FILE…
 *
 * FILE is a SpokenContributions SavedVariables file (.lua), the same thing the contribute page
 * takes. The page would refuse a batch this size -- ten uploads an hour, one IP, and 2,000
 * envelopes a file -- so this is that page's path without the allowance: every envelope goes
 * through the app's own parseEnvelope and submissionFrom, so a stored row is exactly the row the
 * upload would have made, with the contributor's name and email and no IP.
 *
 * What it does not store, because triage would only have to throw it away:
 *   - an envelope the intake checks refuse, and every zones one (a file cannot carry the
 *     description that is a zones contribution's whole content);
 *   - a quest line the corpus has no English line for: not a vanilla line we could voice, and
 *     where test quests ("NEW TEST AGAIN") come in from a scrape;
 *   - a quest line pipelines/quests/corpus/ignored.json names: kept in the tables, never voiced;
 *   - a line in another language whose text is the English one's: what a scrape gets where the
 *     site still shows a page untranslated;
 *   - a quest line whose text the corpus already has in that language, compared loosely
 *     (whitespace, and the case of `$n`/`$c` tokens, which Wowhead lowercases);
 *   - a book page whose `page` is not the checksum of its own text: the addon looks a page up by
 *     that number, so the row would key on a page no client can show;
 *   - a book page the addon can already find: its checksum is one the corpus's own text for that
 *     language produces, which is what Data/Books.lua and the locale lookups are keyed on;
 *   - with --book-pages, a book page the corpus already has in that language under other words.
 *     A scrape of retail Wowhead reads today's text -- a revised translation, curly apostrophes --
 *     and nothing says a Classic client shows that rather than ours, so a page is only taken
 *     where it fills a gap. An envelope names its book by the title the client shows, which is
 *     no way to find the page id (retail renamed books, and koKR has no names on file), so the
 *     page ids come from the contributor's own map: a books_i18n.json, whose every book lists
 *     Data/Books.lua's page ids beside each language's pages. A page the map cannot place (it
 *     lists more pages than the book has ids) is skipped too: there is no telling it fills a gap.
 *   - a line already stored: see store.ts's importContributions for why it is not counted again.
 *
 * DATABASE_URL is required and never read from .env: the point of this script is to be aimed
 * at a database on purpose. --dry-run reports what would happen and writes nothing. --list
 * prints the keys of one outcome (e.g. --list differs) to stderr for a closer look.
 */
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";

import { pageChecksum } from "@books-tools/lib/naming.mjs";
import { normaliseText } from "@books-tools/lib/text.mjs";

import { closeDb, db } from "@/lib/db";
import { parseEnvelope } from "@/lib/contributions/envelope";
import { envelopesFromSavedVariables } from "@/lib/contributions/saved-variables";
import type { Submission } from "@/lib/contributions/contributions";
import { importContributions } from "@/lib/contributions/store";
import { submissionFrom } from "@/lib/contributions/submission";
import { observedFrom, resolveNpc } from "@/lib/npc/resolve";

if (!process.env.DATABASE_URL) {
  console.error("DATABASE_URL is unset -- say which database to write to.");
  process.exit(2);
}

const args = process.argv.slice(2);
function option(flag: string): string | null {
  const at = args.indexOf(flag);
  if (at === -1) return null;
  const value = args[at + 1];
  args.splice(at, 2);
  return value ?? null;
}
const name = option("--name");
const email = option("--email");
const list = option("--list");
const bookPages = option("--book-pages");
const dryRun = args.includes("--dry-run");
const files = args.filter((arg) => arg !== "--dry-run");
if (!name || files.length === 0) {
  console.error(
    "usage: import-contributions.mts --name NAME [--email EMAIL] [--book-pages JSON] [--dry-run] [--list WHAT] FILE…",
  );
  process.exit(2);
}

type Outcome =
  | "refused"
  | "zones"
  | "duplicate in batch"
  | "unknown line"
  | "ignored line"
  | "english"
  | "same as corpus"
  | "bad checksum"
  | "already findable"
  | "page in corpus"
  | "unmapped page"
  | "already stored"
  | "differs"
  | "new";

/** Every outcome that ends in a row, and so goes to the insert. */
const STORED: readonly Outcome[] = ["differs", "new"];

const tally = new Map<string, number>();
const listed: string[] = [];
function count(outcome: Outcome, submission?: Submission) {
  const group = submission ? `${submission.source} ${submission.locale}` : "-";
  const key = `${group}\t${outcome}`;
  tally.set(key, (tally.get(key) ?? 0) + 1);
  if (list === outcome && submission) listed.push(`${group} ${submission.key}`);
}

/**
 * A Wowhead page's placeholders as the game's own tokens. Wowhead renders `$n`, `$c` and `$r` as
 * `<name>`, `<class>` and `<race>`, and a `$g` as both of its sides, `<male/female>`; left so, a
 * line would be voiced saying "name" aloud, and would never compare equal to the corpus's copy.
 * Lower case, as the locale extracts write them. Every other `<...>` is the line's own words --
 * an emote such as `<bufa>` or a stage direction -- and is left alone.
 */
function fromWowhead(text: string): string {
  return text
    .replace(/<name>/gi, "$n")
    .replace(/<class>/gi, "$c")
    .replace(/<race>/gi, "$r")
    .replace(/<([^<>/]{1,60})\/([^<>/]{1,60})>/g, (_, male: string, female: string) => `$g${male}:${female};`);
}

// 1. Parse, locally, exactly as the upload route does -- except that a quest line scraped from
// Wowhead has its placeholders put back as tokens first. `raw` stays what the contributor sent.
const batch = new Map<string, Submission>();
for (const file of files) {
  const envelopes = envelopesFromSavedVariables(readFileSync(file, "utf8"));
  console.error(`read ${envelopes.length} envelopes from ${file}`);
  for (const raw of envelopes) {
    const parsed = parseEnvelope(raw);
    if (!parsed.ok) {
      count("refused");
      continue;
    }
    if (parsed.value.source === "zones") {
      count("zones");
      continue;
    }
    const envelope = parsed.value;
    if (envelope.source === "quests" && envelope.fields.from === "wowhead" && envelope.text) {
      envelope.text = fromWowhead(envelope.text);
    }
    const submission = submissionFrom(envelope, raw, null);
    if (!submission) count("refused");
    else if (batch.has(submission.dedup)) count("duplicate in batch", submission);
    else batch.set(submission.dedup, submission);
  }
}
const submissions = [...batch.values()];

/**
 * Two texts that differ only where a scrape and an extract disagree without meaning to: runs of
 * whitespace (Wowhead collapses the double space after a full stop) and the case of a `$` token.
 */
function loose(text: string): string {
  return normaliseText(text)
    .replace(/\$([A-Za-z])/g, (_, token: string) => `$${token.toLowerCase()}`)
    .replace(/\s+/g, " ")
    .trim();
}

// 2. What the corpus already has, in two queries: a round trip per line is minutes over a tunnel.
const quests = submissions.filter((submission) => submission.source === "quests" && submission.meta.quest);
const questLineId = (submission: Submission) => `q:${submission.meta.quest}:${submission.meta.event}`;
// By quest rather than by line id: a moment the game words differently per player gender is
// only in the corpus as its `:m`/`:f` variants (naming.ts's answersQuestMoment), and a
// contribution names the moment alone.
const { rows: questRows } = await db().query<{ lineId: string; lang: string; text: string | null }>(
  `select "lineId", "lang", case when "lang" = 'enUS' then "originalText" else "localeText" end as "text"
     from "quest_line"
    where "isCurrent" and "questId" = any($1::int[]) and "lineId" like 'q:%'`,
  [[...new Set(quests.map((submission) => Number(submission.meta.quest)))]],
);
const momentOf = (lineId: string) => lineId.replace(/:[mf]$/, "");
const englishLines = new Set(questRows.filter((row) => row.lang === "enUS").map((row) => momentOf(row.lineId)));
// Every variant's text, either gender's included: the scrape shows one of them.
const corpusTexts = new Map<string, Set<string>>();
for (const row of questRows) {
  if (!row.text) continue;
  const key = `${momentOf(row.lineId)}\u0000${row.lang}`;
  if (!corpusTexts.has(key)) corpusTexts.set(key, new Set());
  corpusTexts.get(key)!.add(loose(row.text));
}

const bookLocales = [...new Set(submissions.filter((s) => s.source === "books").map((s) => s.locale))];
const { rows: bookRows } = await db().query<{ lang: string; text: string }>(
  `select "lang", "text" from "book_line" where "isCurrent" and "lang" = any($1::text[])`,
  [bookLocales],
);
const findable = new Set(bookRows.map((row) => `${row.lang}\u0000${pageChecksum(row.text)}`));

// Language and checksum to page id, from the contributor's map, and the pages the corpus has.
type BookMap = { books: { page_ids: number[]; texts: Record<string, { status: string; pages?: string[] }> }[] };
const pageIds = new Map<string, number>();
if (bookPages) {
  for (const book of (JSON.parse(readFileSync(bookPages, "utf8")) as BookMap).books) {
    for (const [locale, entry] of Object.entries(book.texts)) {
      entry.pages?.forEach((page, at) => {
        if (book.page_ids[at] !== undefined) pageIds.set(`${locale}\u0000${pageChecksum(page)}`, book.page_ids[at]);
      });
    }
  }
}
const { rows: pageRows } = await db().query<{ lang: string; pageId: number }>(
  `select "lang", "pageId" from "book_line" where "isCurrent" and "lang" = any($1::text[])`,
  [bookLocales],
);
const pagesInCorpus = new Set(pageRows.map((row) => `${row.lang}\u0000${row.pageId}`));

// English, to tell an untranslated line from a translation: the corpus's, and the batch's own
// enUS pages, which are retail's text where it has revised a book since 1.12.
const english = new Set(
  [
    ...questRows.filter((row) => row.lang === "enUS").map((row) => row.text ?? ""),
    ...(await db().query<{ text: string }>(`select "text" from "book_line" where "isCurrent" and "lang" = 'enUS'`)).rows.map(
      (row) => row.text,
    ),
    ...submissions.filter((submission) => submission.locale === "enUS").map((submission) => submission.text ?? ""),
  ].map(loose),
);

const ignored = new Set(
  (
    JSON.parse(
      readFileSync(fileURLToPath(new URL("../../../pipelines/quests/corpus/ignored.json", import.meta.url)), "utf8"),
    ) as { ignored: { lineId: string }[] }
  ).ignored.map((entry) => momentOf(entry.lineId)),
);

const { rows: storedRows } = await db().query<{ dedup: string }>(
  `select "dedup" from "contribution" where "dedup" = any($1::text[])`,
  [submissions.map((submission) => submission.dedup)],
);
const stored = new Set(storedRows.map((row) => row.dedup));

// 3. Sort each line into what happens to it.
const toStore: Submission[] = [];
for (const submission of submissions) {
  let outcome: Outcome;
  if (stored.has(submission.dedup)) {
    outcome = "already stored";
  } else if (submission.locale !== "enUS" && english.has(loose(submission.text ?? ""))) {
    outcome = "english";
  } else if (submission.source === "quests" && submission.meta.quest) {
    const lineId = questLineId(submission);
    const texts = corpusTexts.get(`${lineId}\u0000${submission.locale}`);
    if (!englishLines.has(lineId)) outcome = "unknown line";
    else if (ignored.has(lineId)) outcome = "ignored line";
    else if (texts?.has(loose(submission.text ?? ""))) outcome = "same as corpus";
    else outcome = texts ? "differs" : "new";
  } else if (submission.source === "books") {
    if (String(pageChecksum(submission.text ?? "")) !== submission.key) outcome = "bad checksum";
    else if (findable.has(`${submission.locale}\u0000${submission.key}`)) outcome = "already findable";
    else if (bookPages) {
      const pageId = pageIds.get(`${submission.locale}\u0000${submission.key}`);
      if (pageId === undefined) outcome = "unmapped page";
      else if (pagesInCorpus.has(`${submission.locale}\u0000${pageId}`)) outcome = "page in corpus";
      else outcome = "new";
    } else outcome = "new";
  } else {
    // A gossip line: there is no corpus line to compare it with, so triage decides.
    outcome = "new";
  }
  count(outcome, submission);
  if (STORED.includes(outcome)) toStore.push(submission);
}

// 4. Store, in one statement. importContributions re-checks each dedup, so a row a player sent
// between the lookup and here is left alone and simply not counted.
let inserted = toStore.length;
if (!dryRun) {
  console.error(`storing ${toStore.length} lines…`);
  inserted = (await importContributions(toStore, { name, email })).length;

  // Speakers, as storeSubmission resolves them, once per distinct observation. A scrape
  // usually names none -- the corpus already knows who speaks an old quest's lines -- and then
  // this does nothing.
  const observations = new Map<string, ReturnType<typeof observedFrom>>();
  for (const submission of toStore) {
    if (!submission.meta.npc) continue;
    const observed = observedFrom({ ...submission.meta, build: submission.build });
    observations.set(JSON.stringify(observed), observed);
  }
  for (const observed of observations.values()) {
    try {
      await resolveNpc(observed);
    } catch (error) {
      console.error(`could not resolve ${observed.npcKind} ${observed.npcId}:`, error);
    }
  }
}

if (listed.length) console.error(listed.join("\n"));

console.log(dryRun ? "dry run -- nothing written" : "done");
const groups = [...new Set([...tally.keys()].map((key) => key.split("\t")[0]))].sort();
for (const group of groups) {
  const outcomes = [...tally]
    .filter(([key]) => key.startsWith(`${group}\t`))
    .map(([key, value]) => `${key.split("\t")[1]} ${value}`);
  console.log(`  ${group.padEnd(14)} ${outcomes.join(", ")}`);
}
console.log(`  ${(dryRun ? "would store" : "stored").padEnd(14)} ${inserted} of ${submissions.length} distinct lines`);

await closeDb();
