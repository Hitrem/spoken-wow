/**
 * Write the pages of books contributions accepted before accepting wrote anything.
 *
 *   cd apps/web
 *   DATABASE_URL=postgres://… npx tsx --conditions=react-server \
 *     scripts/backfill-book-contributions.mts [--dry-run]
 *
 * Until migration 0059, accepting a books contribution sent from a client in another language
 * only flipped its status, so its text reached no page. This writes it, for every accepted
 * books row outside English, through the same code accept now runs (accept.ts's
 * writeAcceptedBookTranslation): the page or pages book_page_match names, as that language's
 * first version, credited to whoever accepted the row. A row with no match is counted and
 * left as it is; one whose page is already written is a no-op, so running this twice is safe.
 *
 * DATABASE_URL is required and never read from .env: the point of this script is to be aimed
 * at a database on purpose. --dry-run reports what would be written and writes nothing.
 */
import { closeDb, db } from "@/lib/db";
import { BASE_LANG } from "@/lib/lang";
import { writeAcceptedBookTranslation } from "@/lib/contributions/accept";

if (!process.env.DATABASE_URL) {
  console.error("DATABASE_URL is unset -- say which database to write to.");
  process.exit(2);
}

const dryRun = process.argv.includes("--dry-run");

type Row = { id: number; locale: string; matched: boolean; written: boolean };

const { rows } = await db().query<Row>(
  `select c."id", c."locale",
          exists (select 1 from "book_page_match" m
                   where m."lang" = c."locale" and m."key" = c."key") as "matched",
          exists (select 1 from "book_line" b
                   where b."origin" = 'contributed' and b."note" = 'contribution #' || c."id") as "written"
     from "contribution" c
    where c."source" = 'books' and c."status" = 'accepted' and c."locale" <> $1
    order by c."id"`,
  [BASE_LANG],
);

const tally = new Map<string, { written: number; already: number; unmatched: number; refused: number }>();
const count = (locale: string) => {
  let entry = tally.get(locale);
  if (!entry) tally.set(locale, (entry = { written: 0, already: 0, unmatched: 0, refused: 0 }));
  return entry;
};

for (const row of rows) {
  const entry = count(row.locale);
  if (row.written) {
    entry.already++;
    continue;
  }
  if (!row.matched) {
    entry.unmatched++;
    continue;
  }
  if (dryRun) {
    entry.written++;
    continue;
  }
  const refused = await writeAcceptedBookTranslation(row.id);
  if (refused) {
    entry.refused++;
    console.error(`#${row.id}: ${"message" in refused ? refused.message : refused.reason}`);
  } else {
    entry.written++;
  }
}

for (const [locale, entry] of tally) {
  console.log(
    `${locale}: ${dryRun ? "would write" : "wrote"} ${entry.written}, already written ${entry.already}, ` +
      `no page matched ${entry.unmatched}, refused ${entry.refused}`,
  );
}
if (tally.size === 0) console.log("no accepted books contributions outside English");

await closeDb();
