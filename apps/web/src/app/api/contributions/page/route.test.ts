/**
 * Which English page a books contribution from another language's client is, answered by
 * whoever edits its language.
 *
 * Needs DATABASE_URL, migrations applied (0059) and the books corpus imported.
 */
import { afterAll, afterEach, beforeAll, describe, expect, it, vi } from "vitest";

import { closeDb, db } from "@/lib/db";

/** Every language the mocked viewer may edit; the route's gate asks about exactly one. */
const editable = new Set<string>();

vi.mock("@/lib/generation/authz", () => ({
  requireCapability: async (capability: string, lang: string) =>
    capability === "edit" && editable.has(lang)
      ? { session: { user: { id: "test" } }, denied: null }
      : { session: null, denied: Response.json({ error: "not allowed" }, { status: 403 }) },
}));

// The session's "test" user does not exist, so a real insert would only log a foreign-key error.
const { recordActivity } = vi.hoisted(() => ({ recordActivity: vi.fn() }));
vi.mock("@/lib/activity/store", () => ({ recordActivity }));

import { POST } from "./route";

/** A bucket no other run shares, so a concurrent run's cleanup can't race this one's rows. */
const ip = `test-${Math.random().toString(36).slice(2, 10)}`;

afterEach(async () => {
  editable.clear();
  recordActivity.mockClear();
  await db().query(`delete from "contribution" where "ip" = $1`, [ip]);
});

afterAll(async () => {
  await db().query(`delete from "book_line" where "bookId" = $1`, [bookId]);
  // The English name book_line's trigger gave the owner (0036).
  await db().query(`delete from "entity_name" where "kind" = 'item' and "entityId" = $1`, [String(bookId)]);
  await closeDb();
});

async function contribution(source = "books"): Promise<number> {
  const { rows } = await db().query<{ id: number }>(
    `insert into "contribution" ("source", "key", "locale", "build", "meta", "raw", "dedup", "text", "ip")
     values ($3, '123456', 'ptBR', '1.15.7/1', '{"book": "Livro", "number": "2"}', 'raw', $2, 'Palavras.', $1)
     returning "id"`,
    [ip, `${ip}-${Math.random()}`, source],
  );
  return rows[0].id;
}

/**
 * A two-page English book of this run's own, so the test needs no imported corpus. Ids far
 * outside vmangos's, and the run's own, so a concurrent run never shares them.
 */
const bookId = 900_000_000 + Math.floor(Math.random() * 90_000_000);

beforeAll(async () => {
  for (const pageNumber of [1, 2]) {
    await db().query(
      `insert into "book_line"
         ("lineId", "lang", "version", "isCurrent", "origin", "pageId", "bookId",
          "pageNumber", "pageCount", "title", "ownerKind", "ownerIds", "text")
       values ($1, 'enUS', 1, true, 'extracted', $2, $3, $4, 2, 'A Test Tome', 'item', $5, 'Words.')`,
      [`b:${bookId + pageNumber - 1}`, bookId + pageNumber - 1, bookId, pageNumber, [bookId]],
    );
  }
});

async function secondPage(): Promise<{ bookId: number; pageId: number }> {
  return { bookId, pageId: bookId + 1 };
}

async function pageIdOf(id: number): Promise<number | null> {
  const { rows } = await db().query<{ pageId: number | null }>(`select "pageId" from "contribution" where "id" = $1`, [id]);
  return rows[0].pageId;
}

function post(body: unknown): Request {
  return new Request("https://example.com/api/contributions/page", {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify(body),
  });
}

describe("POST /api/contributions/page", () => {
  it("records the page a book and a page number name, and clears it", async () => {
    const id = await contribution();
    const { bookId, pageId } = await secondPage();
    editable.add("ptBR");

    const response = await POST(post({ id, bookId, pageNumber: 2 }));
    expect(response.status).toBe(200);
    expect(await response.json()).toMatchObject({ match: { pageId, bookId, pageNumber: 2 } });
    expect(await pageIdOf(id)).toBe(pageId);
    expect(recordActivity).toHaveBeenCalledWith(
      expect.objectContaining({ kind: "contribution.edited", subject: String(id), detail: { field: "pageId", value: pageId } }),
    );

    expect((await POST(post({ id, pageId: null }))).status).toBe(200);
    expect(await pageIdOf(id)).toBeNull();
  });

  it("refuses a page the book does not have", async () => {
    const id = await contribution();
    const { bookId } = await secondPage();
    editable.add("ptBR");
    expect((await POST(post({ id, bookId, pageNumber: 999 }))).status).toBe(400);
    expect((await POST(post({ id, bookId: "x", pageNumber: 2 }))).status).toBe(400);
    expect(await pageIdOf(id)).toBeNull();
  });

  it("leaves a row that is not a book's alone", async () => {
    const id = await contribution("zones");
    const { bookId } = await secondPage();
    editable.add("ptBR");
    expect((await POST(post({ id, bookId, pageNumber: 2 }))).status).toBe(409);
  });

  it("refuses somebody who edits another language only", async () => {
    const id = await contribution();
    const { bookId } = await secondPage();
    editable.add("enUS");
    expect((await POST(post({ id, bookId, pageNumber: 2 }))).status).toBe(403);
  });
});
