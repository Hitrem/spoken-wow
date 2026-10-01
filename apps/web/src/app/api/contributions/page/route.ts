/**
 * A moderator's answer to "which English page is this?", for a books contribution from another
 * language's client.
 *
 * The envelope cannot say: its page is the checksum of the translated text (Contribute.lua), so
 * the match is recorded on the contribution (store.ts's setContributionPage), as ../npc-identity
 * records an NPC, and accept refuses a row without one. Sent as a book and a page number, which
 * is how a moderator reads a book; `pageId: null` clears it. Refused once the row's page is
 * written -- that is one-way (accept.ts).
 *
 * Gated as ../npc-identity is: whoever may edit the row's language.
 */
import { catalogue } from "@/lib/books/catalogue";
import { requireCapability } from "@/lib/generation/authz";
import { contributionLocale, setContributionPage } from "@/lib/contributions/store";
import type { BookMatch } from "@/lib/contributions/triage";
import { BASE_LANG, isLang } from "@/lib/lang";
import { INT32_MAX } from "@/lib/npc/npc";

export const dynamic = "force-dynamic";

export async function POST(request: Request) {
  const body = (await request.json().catch(() => ({}))) as Record<string, unknown>;

  const id = Number(body.id);
  if (!Number.isInteger(id) || id <= 0 || id > INT32_MAX) {
    return Response.json({ error: "unknown contribution" }, { status: 404 });
  }
  const clear = body.pageId === null;
  const bookId = body.bookId;
  const pageNumber = body.pageNumber;
  if (
    !clear &&
    !(typeof bookId === "number" && Number.isInteger(bookId) && typeof pageNumber === "number" && Number.isInteger(pageNumber))
  ) {
    return Response.json({ error: "a book and a page number are required" }, { status: 400 });
  }

  // Permission before existence, as ../npc-identity does, so a member learns nothing about which ids exist.
  const locale = await contributionLocale(id);
  const { session, denied } = await requireCapability("edit", isLang(locale) ? locale : BASE_LANG);
  if (denied) return denied;

  let match: BookMatch | null = null;
  if (!clear) {
    const page = (await catalogue(BASE_LANG)).find((p) => p.bookId === bookId && p.pageNumber === pageNumber);
    if (!page) return Response.json({ error: `book ${bookId} has no page ${pageNumber}` }, { status: 400 });
    match = {
      pageId: page.pageId,
      bookId: page.bookId,
      title: page.title,
      pageNumber: page.pageNumber,
      pageCount: page.pageCount,
    };
  }

  const recorded = await setContributionPage(id, match?.pageId ?? null, session.user.id);
  if (!recorded) {
    return Response.json(
      { error: "no such books contribution, or its page is already in the explorer" },
      { status: 409 },
    );
  }
  return Response.json({ ok: true, match });
}
