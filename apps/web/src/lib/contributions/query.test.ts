import { describe, expect, it } from "vitest";

import { DEFAULT_SORT, MISSING, NEEDS_DECISION, contributionsHref, nextSort, sortOf, matchesSpeaker, matchesStage, nextContributionFilters, pageOf } from "./query";

describe("nextContributionFilters", () => {
  const current = { status: "new", provenance: "all", client: "all", source: "all", stage: "all", sort: DEFAULT_SORT } as const;

  it("changes the dimension named in `next` and keeps the other", () => {
    expect(nextContributionFilters(current, { provenance: "corpus" })).toEqual({
      status: "new",
      provenance: "corpus",
      client: "all",
      source: "all",
      stage: "all",
      sort: DEFAULT_SORT,
    });
  });

  it("resets a dimension to 'all' when `next` names it with no value", () => {
    // FilterChip's reset button calls onChange(undefined) -- the key is present, the value
    // isn't, and that must read as "clear this filter", not "leave it alone".
    expect(nextContributionFilters({ status: "accepted", provenance: "moderator", client: "forever", source: "books", stage: "all", sort: DEFAULT_SORT }, { provenance: undefined })).toEqual(
      { status: "accepted", provenance: "all", client: "forever", source: "books", stage: "all", sort: DEFAULT_SORT },
    );
  });

  it("changes the client dimension alone", () => {
    expect(nextContributionFilters(current, { client: "legacy" })).toEqual({ ...current, client: "legacy" });
  });

  it("changes the source dimension alone", () => {
    expect(nextContributionFilters(current, { source: "zones" })).toEqual({ ...current, source: "zones" });
  });

  it("leaves every dimension alone when `next` names none", () => {
    expect(nextContributionFilters(current, {})).toEqual(current);
  });
});

describe("contributionsHref", () => {
  it("builds a query string carrying every dimension", () => {
    expect(contributionsHref({ status: "new", provenance: "all", client: "era", source: "all", stage: "all", sort: DEFAULT_SORT }, { status: "rejected" })).toBe(
      "/contributions?status=rejected&provenance=all&client=era&source=all&stage=all",
    );
  });

  // The sentinel round-trips through the URL like any other provenance value -- no special
  // encoding, just the same string page.tsx's own parsing compares rawProvenance against.
  it("round-trips the NEEDS_DECISION sentinel through the href", () => {
    expect(
      contributionsHref({ status: "all", provenance: "all", client: "all", source: "all", stage: "all", sort: DEFAULT_SORT }, { provenance: NEEDS_DECISION }),
    ).toBe(`/contributions?status=all&provenance=${NEEDS_DECISION}&client=all&source=all&stage=all`);
  });
});

describe("sort", () => {
  const filters = { status: "new", provenance: "all", client: "all", source: "all", stage: "all", sort: DEFAULT_SORT } as const;

  it("starts a newly clicked column in its own direction, and flips the one in force", () => {
    expect(nextSort(DEFAULT_SORT, "filed")).toEqual({ column: "filed", direction: "desc" });
    expect(nextSort(DEFAULT_SORT, "source")).toEqual({ column: "source", direction: "asc" });
    expect(nextSort(DEFAULT_SORT, "count")).toEqual({ column: "count", direction: "asc" });
    expect(nextSort({ column: "count", direction: "asc" }, "count")).toEqual({ column: "count", direction: "desc" });
  });

  it("reads the query string, falling back to most sent first", () => {
    expect(sortOf("filed", "asc")).toEqual({ column: "filed", direction: "asc" });
    expect(sortOf("filed", undefined)).toEqual({ column: "filed", direction: "desc" });
    expect(sortOf("filed", "sideways")).toEqual({ column: "filed", direction: "desc" });
    for (const column of [undefined, "", "npc", "createdAt; drop table"]) expect(sortOf(column, "asc")).toEqual(DEFAULT_SORT);
  });

  it("carries a sort in the href and leaves the default out", () => {
    expect(contributionsHref(filters, { sort: { column: "filed", direction: "asc" } })).toBe(
      "/contributions?status=new&provenance=all&client=all&source=all&stage=all&sort=filed&dir=asc",
    );
    expect(contributionsHref({ ...filters, sort: { column: "filed", direction: "asc" } }, { sort: DEFAULT_SORT })).toBe(
      "/contributions?status=new&provenance=all&client=all&source=all&stage=all",
    );
  });

  it("keeps the sort across a filter change", () => {
    const sort = { column: "status", direction: "desc" } as const;
    expect(nextContributionFilters({ ...filters, sort }, { status: "accepted" }).sort).toEqual(sort);
  });
});

describe("paging", () => {
  it("carries a page past the first, and leaves the first page bare", () => {
    const filters = { status: "new", provenance: "all", client: "all", source: "all", stage: "all", sort: DEFAULT_SORT } as const;
    expect(contributionsHref(filters, {}, 3)).toBe("/contributions?status=new&provenance=all&client=all&source=all&stage=all&page=3");
    expect(contributionsHref(filters, {}, 1)).toBe("/contributions?status=new&provenance=all&client=all&source=all&stage=all");
    // A filter change starts again from the first page.
    expect(contributionsHref(filters, { status: "accepted" })).toBe("/contributions?status=accepted&provenance=all&client=all&source=all&stage=all");
  });

  it("reads anything that is not a positive integer as the first page", () => {
    expect(pageOf("4")).toBe(4);
    for (const value of [undefined, "", "0", "-2", "1.5", "abc"]) expect(pageOf(value)).toBe(1);
  });
});

describe("matchesSpeaker", () => {
  it("matches only 'client' and 'none' for the NEEDS_DECISION sentinel, and nothing else", () => {
    // Bite-check: if the special case in matchesSpeaker were ever deleted or short-circuited to
    // `provenance === filter` like the plain-provenance branch, "corpus" and "moderator" would
    // start passing here too -- this pins that they must not.
    expect(matchesSpeaker("client", NEEDS_DECISION, "quests")).toBe(true);
    expect(matchesSpeaker("none", NEEDS_DECISION, "quests")).toBe(true);
    expect(matchesSpeaker("corpus", NEEDS_DECISION, "quests")).toBe(false);
    expect(matchesSpeaker("moderator", NEEDS_DECISION, "quests")).toBe(false);
  });

  it("still matches a single provenance exactly when the filter names one", () => {
    expect(matchesSpeaker("corpus", "corpus", "quests")).toBe(true);
    expect(matchesSpeaker("client", "corpus", "quests")).toBe(false);
  });

  it("matches everything when the filter is 'all', including a row with no npc", () => {
    expect(matchesSpeaker(undefined, "all", "quests")).toBe(true);
  });

  it("matches MISSING only for a quests row with no npc", () => {
    expect(matchesSpeaker(undefined, MISSING, "quests")).toBe(true);
    // Zones and books never name an NPC; they are not missing one.
    expect(matchesSpeaker(undefined, MISSING, "zones")).toBe(false);
    expect(matchesSpeaker("none", MISSING, "quests")).toBe(false);
  });

  it("never matches a row with no npc for a real filter, sentinel included", () => {
    expect(matchesSpeaker(undefined, NEEDS_DECISION, "quests")).toBe(false);
    expect(matchesSpeaker(undefined, "client", "quests")).toBe(false);
  });
});

describe("matchesStage", () => {
  const quest = (stage: "accept" | "progress" | "complete" | null) => ({ title: "Stalk With The Earthmother", questId: 76156, stage });

  it("lets everything through when no stage is picked", () => {
    expect(matchesStage(null, "all")).toBe(true);
    expect(matchesStage("gossip", "all")).toBe(true);
    expect(matchesStage(quest(null), "all")).toBe(true);
  });

  it("matches a quest row on its own stage only", () => {
    expect(matchesStage(quest("progress"), "progress")).toBe(true);
    expect(matchesStage(quest("progress"), "complete")).toBe(false);
    expect(matchesStage(quest(null), "accept")).toBe(false);
    expect(matchesStage(quest("accept"), "gossip")).toBe(false);
  });

  it("matches gossip only to gossip, and a row with no quest concept to nothing narrowed", () => {
    expect(matchesStage("gossip", "gossip")).toBe(true);
    expect(matchesStage("gossip", "accept")).toBe(false);
    expect(matchesStage(null, "gossip")).toBe(false);
    expect(matchesStage(null, "complete")).toBe(false);
  });
});
