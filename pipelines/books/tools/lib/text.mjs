// Page text as it comes out of vmangos, and as it goes to a narrator.
//
// Two forms, deliberately: `normaliseText` is stored and shown, so it keeps the shape of
// the page -- a letter's paragraphs are part of reading it. `spokenText` is what would be
// sent to ElevenLabs, where a newline buys nothing and the markup on the signed pages
// would be read aloud as tag names.
//
// No dependencies, so `node tools/extract.mjs` runs on a clone with nothing installed.

/** Pages whose text is a maintenance placeholder rather than anything a player reads. */
const PLACEHOLDERS = new Set(["missing text", "texto ausente", "test", "placeholder"]);

/** What the game substitutes at runtime and a recording cannot: $N, $C, $R, $Gx:y;. */
const SUBSTITUTION = /\$[a-zA-Z]/;

/**
 * Storage form: real newlines, no trailing spaces, no runs of blank lines.
 *
 * `$B` is WoW's newline token and appears in both cases in the same table, so matching
 * only the documented upper case leaves a literal "$b" in the middle of a sentence.
 */
export function normaliseText(raw) {
  return String(raw ?? "")
    .replace(/\r\n?/g, "\n")
    .replace(/\$[Bb]/g, "\n")
    .split("\n")
    .map((line) => line.replace(/[ \t]+$/, ""))
    .join("\n")
    .replace(/\n{3,}/g, "\n\n")
    .trim();
}

/**
 * Narration form: one flowing paragraph, markup gone.
 *
 * Tags become a space rather than nothing, because "<H1>Ledger</H1>Three crates." has no
 * space of its own and deleting the tags would leave "LedgerThree".
 */
export function spokenText(text) {
  return normaliseText(text)
    .replace(/<[^>]+>/g, " ")
    .replace(/\s+/g, " ")
    .trim();
}

/**
 * Whether this page can be voiced, and if not, why.
 *
 * Mirrors the quests corpus's `generatable`/`skipReason` pair: a page that cannot be
 * spoken is kept and labelled rather than dropped, so the explorer can show that the game
 * has a page and say why it is silent.
 */
export function isGeneratable(text) {
  const spoken = spokenText(text);
  if (spoken === "") return { generatable: false, skipReason: "empty" };
  if (PLACEHOLDERS.has(spoken.toLowerCase())) return { generatable: false, skipReason: "placeholder" };
  if (SUBSTITUTION.test(spoken)) return { generatable: false, skipReason: "substitution" };
  return { generatable: true, skipReason: null };
}

/** Where a title already closes a sentence, and a second stop would be read as a pause. */
const SENTENCE_END = /[.!?…。！？]$/;

/** Letters and digits only, for asking whether a page opens with its own title. */
function wordsOf(text) {
  return spokenText(text).toLowerCase().replace(/[^\p{L}\p{N}]/gu, "");
}

/**
 * A book's first page as a narrator reads it: the title, a full stop and a line break, then
 * the page -- in spoken form, so the result is what is sent and not something to flatten.
 *
 * The client shows the title above every page and never says it, so a book that does not
 * name itself in its own words starts mid-thought. Only the narration takes it -- the page's
 * stored text, and the checksum the addon finds it by, are of the words on the page alone.
 *
 * The break is the one newline spoken text keeps. A full stop alone runs the title into the
 * first sentence; the newline is a longer pause on ElevenLabs, and on fish.audio a silence of
 * its own, because SHAPE.fish splits the line there rather than sending the break.
 *
 * A page that already opens with its title (a gravestone's name, a treatise's <H1>) is left
 * as it is: prepending would read the same words twice in a row.
 */
export function spokenWithTitle(title, text) {
  const heading = spokenText(title);
  const page = spokenText(text);
  if (wordsOf(page).startsWith(wordsOf(heading))) return page;
  return `${heading}${SENTENCE_END.test(heading) ? "" : "."}\n${page}`;
}
