/**
 * correction.ts, against a real Postgres.
 *
 * Needs DATABASE_URL and migrations applied. The quest lines are made by the test itself, under
 * a quest id far past any real one, and torn down after with everything accepting wrote.
 */
import { afterAll, beforeAll, describe, expect, it } from "vitest";

import { closeDb, db } from "@/lib/db";

import { acceptCorrection, correctionNote } from "./correction";
import { lineStates } from "./known";

const ACCEPTER = "test-contributions-correction";
const quest = 2_000_000_000 - Math.floor(Math.random() * 1_000_000);
const lineId = `q:${quest}:accept`;
const file = `quests/${quest}-accept.mp3`;
const ip = `test-${Math.random().toString(36).slice(2, 10)}`;

async function contribution(locale: string, text: string, event = "accept"): Promise<number> {
  const { rows } = await db().query<{ id: number }>(
    `insert into "contribution" ("source", "key", "locale", "raw", "dedup", "text", "ip", "meta")
     values ('quests', $1, $2, 'raw', $3, $4, $5, $6::jsonb) returning "id"`,
    [
      `${quest}:${event}`,
      locale,
      `${ip}-${Math.random().toString(36).slice(2, 10)}`,
      text,
      ip,
      JSON.stringify({ quest: String(quest), event, title: "Test" }),
    ],
  );
  return rows[0].id;
}

beforeAll(async () => {
  await db().query(
    `insert into "user" ("id", "name", "email", "emailVerified")
     values ($1, 'Test Accepter', $2, false)
     on conflict ("id") do nothing`,
    [ACCEPTER, `${ACCEPTER}@example.invalid`],
  );
  await db().query(
    `insert into "quest_line"
       ("lineId", "variant", "lang", "version", "isCurrent", "origin", "source", "fileName",
        "text", "originalText", "localeText")
     values ($1, 0, 'enUS', 1, true, 'extracted', 'accept', $2, 'Hello, adventurer.', 'Hello, $n.', null),
            ($1, 0, 'deDE', 1, true, 'extracted', 'accept', $2, 'Hallo, $N.', 'Hello, $n.', 'Hallo, $N.')`,
    [lineId, `${quest}-accept`],
  );
});

afterAll(async () => {
  await db().query(
    `delete from "activity" where "lineId" = $1
        or ("kind" = 'contribution.resolved'
            and "subject" in (select "id"::text from "contribution" where "ip" = $2))`,
    [lineId, ip],
  );
  await db().query(`delete from "contribution" where "ip" = $1`, [ip]);
  await db().query(`delete from "line_override" where "file" = $1`, [file]);
  await db().query(`delete from "quest_line" where "lineId" = $1`, [lineId]);
  await db().query(`delete from "user" where "id" = $1`, [ACCEPTER]);
  await closeDb();
});

describe("acceptCorrection", () => {
  it("writes an English correction as the line's spoken override and accepts it", async () => {
    const id = await contribution("enUS", "Greetings, $N.");
    const outcome = await acceptCorrection(id, ACCEPTER);
    expect(outcome.ok && outcome.contribution.status).toBe("accepted");

    const { rows } = await db().query(`select "lineId", "text" from "line_override" where "file" = $1`, [file]);
    expect(rows).toEqual([{ lineId, text: "Greetings, Adventurer." }]);

    const { rows: logged } = await db().query(
      `select "detail" from "activity" where "kind" = 'override.set' and "subject" = $1`,
      [file],
    );
    expect(logged[0].detail.contribution).toBe(id);

    // The printed text is untouched, so the row is still a correction.
    const [state] = await lineStates([{ source: "quests", locale: "enUS", text: "Greetings, $N.", meta: { quest: String(quest), event: "accept" } }]);
    expect(state.kind).toBe("changed");
  });

  it("writes a translation's correction as a new version, noted as one", async () => {
    const id = await contribution("deDE", "Guten Tag, $N.");
    const outcome = await acceptCorrection(id, ACCEPTER);
    expect(outcome.ok && outcome.contribution.status).toBe("accepted");

    const { rows } = await db().query(
      `select "version", "text", "localeText", "note" from "quest_line"
        where "lineId" = $1 and "lang" = 'deDE' and "isCurrent"`,
      [lineId],
    );
    expect(rows).toEqual([{ version: 2, text: "Guten Tag, $N.", localeText: "Hallo, $N.", note: correctionNote(id) }]);
  });

  it("refuses a contribution the corpus does not differ from", async () => {
    const id = await contribution("enUS", "Hello, $N.");
    const outcome = await acceptCorrection(id, ACCEPTER);
    expect(outcome.ok).toBe(false);
    expect(!outcome.ok && outcome.reason).toBe("not-a-correction");
    const { rows } = await db().query(`select "status" from "contribution" where "id" = $1`, [id]);
    expect(rows[0].status).toBe("new");
  });

  it("answers not-found for an id that is not there", async () => {
    expect(await acceptCorrection(999_999_999, ACCEPTER)).toEqual({ ok: false, reason: "not-found" });
  });
});
