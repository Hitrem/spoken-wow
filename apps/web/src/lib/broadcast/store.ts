/**
 * The broadcast_text tables (migration 0066): BroadcastText rows per language, and which NPC
 * showed which row.
 */
import { db, query } from "@/lib/db";
import { BASE_LANG, type Lang } from "@/lib/lang";

export type BroadcastSource = "cache" | "eglink";
export type BroadcastRow = { id: number; text: string; text1: string };
export type BroadcastSpeaker = {
  entityKind: "npc" | "object";
  entityId: number;
  broadcastTextId: number;
  window: "gossip" | "greeting";
};

export type RecordedTexts = { texts: number; added: number; changed: number };

/**
 * Write one source's rows for a language.
 *
 * A row's text is replaced only by one from the same or a newer build: a hotfix rewrites a
 * row in place, and an upload of an old cache must not undo it. Every copy counts as an
 * observation, whichever text it carried.
 */
export async function recordTexts(
  lang: Lang,
  build: number | null,
  source: BroadcastSource,
  rows: BroadcastRow[],
): Promise<RecordedTexts> {
  // One row per id, the last copy winning: Postgres refuses an upsert that touches a row twice.
  const byId = new Map(rows.map((row) => [row.id, row]));
  const unique = [...byId.values()];
  if (unique.length === 0) return { texts: 0, added: 0, changed: 0 };

  const client = await db().connect();
  try {
    await client.query("begin");
    const prior = await client.query<{ id: number; text: string; text1: string; build: number | null }>(
      `select "broadcastTextId" as "id", "text", "text1", "build" from "broadcast_text"
        where "lang" = $1 and "broadcastTextId" = any($2::int[])
        for update`,
      [lang, unique.map((row) => row.id)],
    );
    const before = new Map(prior.rows.map((row) => [row.id, row]));

    await client.query(
      `insert into "broadcast_text" ("lang", "broadcastTextId", "text", "text1", "build", "source")
       select $1, t."id", t."text", t."text1", $2, $3
         from unnest($4::int[], $5::text[], $6::text[]) as t("id", "text", "text1")
       on conflict ("lang", "broadcastTextId") do update set
         "observations" = "broadcast_text"."observations" + 1,
         "text"   = case when ${NEWER} then excluded."text"   else "broadcast_text"."text"   end,
         "text1"  = case when ${NEWER} then excluded."text1"  else "broadcast_text"."text1"  end,
         "source" = case when ${NEWER} then excluded."source" else "broadcast_text"."source" end,
         "build"  = case when ${NEWER} then excluded."build"  else "broadcast_text"."build"  end,
         "updatedAt" = now()`,
      [lang, build, source, unique.map((r) => r.id), unique.map((r) => r.text), unique.map((r) => r.text1)],
    );
    await client.query("commit");

    let added = 0;
    let changed = 0;
    for (const row of unique) {
      const old = before.get(row.id);
      if (!old) added += 1;
      else if (isNewer(build, old.build) && (old.text !== row.text || old.text1 !== row.text1)) changed += 1;
    }
    return { texts: unique.length, added, changed };
  } catch (error) {
    await client.query("rollback");
    throw error;
  } finally {
    client.release();
  }
}

const NEWER = `(excluded."build" is not null and ("broadcast_text"."build" is null or excluded."build" >= "broadcast_text"."build"))`;

function isNewer(build: number | null, old: number | null): boolean {
  return build !== null && (old === null || build >= old);
}

export async function recordUpload(
  userId: string,
  lang: Lang,
  build: number | null,
  counts: RecordedTexts,
): Promise<void> {
  await query(
    `insert into "broadcast_text_upload" ("userId", "lang", "build", "texts", "added", "changed")
     values ($1, $2, $3, $4, $5, $6)`,
    [userId, lang, build, counts.texts, counts.added, counts.changed],
  );
}

export async function recordSpeakers(source: "eglink", speakers: BroadcastSpeaker[]): Promise<number> {
  if (speakers.length === 0) return 0;
  const result = await db().query(
    `insert into "broadcast_text_speaker" ("entityKind", "entityId", "broadcastTextId", "window", "source")
     select t."kind", t."entity", t."id", t."window", $1
       from unnest($2::text[], $3::int[], $4::int[], $5::text[]) as t("kind", "entity", "id", "window")
     on conflict do nothing`,
    [
      source,
      speakers.map((s) => s.entityKind),
      speakers.map((s) => s.entityId),
      speakers.map((s) => s.broadcastTextId),
      speakers.map((s) => s.window),
    ],
  );
  return result.rowCount ?? 0;
}

/**
 * How many of these rows say exactly what English says under the same id.
 *
 * A cache is per client language, and the folder it sits in is the only sign of which; an
 * English cache sent as German would file English text as German's. Rows that read
 * identically in both languages are rare outside names and punctuation.
 */
export async function sameAsEnglish(rows: BroadcastRow[]): Promise<{ compared: number; same: number }> {
  const found = await query<{ compared: number; same: number }>(
    `select count(*)::int as "compared",
            count(*) filter (where e."text" = t."text" and e."text1" = t."text1")::int as "same"
       from unnest($1::int[], $2::text[], $3::text[]) as t("id", "text", "text1")
       join "broadcast_text" e on e."lang" = $4 and e."broadcastTextId" = t."id"`,
    [rows.map((r) => r.id), rows.map((r) => r.text), rows.map((r) => r.text1), BASE_LANG],
  );
  return found[0] ?? { compared: 0, same: 0 };
}
