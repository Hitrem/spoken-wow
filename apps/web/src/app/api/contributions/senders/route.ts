/**
 * Who sent a contribution, for the count on its row.
 *
 * Asked for when the count is pressed rather than sent with every row: most rows are never
 * opened, and a sender's name has no business in the page payload of rows nobody looked at.
 * Gated as resolve is, by the language the contribution was sent in, and checked for existence
 * only after the permission, so a member learns nothing about which ids exist.
 */
import { requireCapability } from "@/lib/generation/authz";
import { contributionLocale, contributionSenders } from "@/lib/contributions/store";
import { BASE_LANG, isLang } from "@/lib/lang";

export const dynamic = "force-dynamic";

export async function GET(request: Request) {
  const id = Number(new URL(request.url).searchParams.get("id"));
  if (!Number.isInteger(id) || id <= 0) {
    return Response.json({ error: "unknown contribution" }, { status: 404 });
  }

  const locale = await contributionLocale(id);
  const { denied } = await requireCapability("edit", isLang(locale) ? locale : BASE_LANG);
  if (denied) return denied;

  const senders = locale === null ? null : await contributionSenders(id);
  if (!senders) return Response.json({ error: "unknown contribution" }, { status: 404 });
  return Response.json(senders);
}
