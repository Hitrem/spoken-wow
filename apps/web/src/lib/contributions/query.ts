/**
 * The query string /contributions's filter dropdowns write to, and the Speaker dropdown's
 * one sentinel value.
 *
 * A free function, not inlined in ContributionTable's click handler, so the mapping -- combine
 * whichever dimension just changed with the other as it stands, the same rule ReportTable's own
 * `go` follows -- can be pinned by a test without rendering FilterChip or a page. Node-free, like
 * contributions.ts and npc.ts, whose types this one only composes: ContributionTable is a client
 * component and calls this directly on every dropdown change.
 */
import type { ClientFamily } from "./client";
import type { ContributionStatus } from "./contributions";
import type { EnvelopeSource } from "./envelope";
import type { Provenance } from "../npc/npc";

/**
 * "Everything a moderator still owes a decision" -- not a fifth provenance, a sentinel over the
 * four real ones. `client` (a guess nobody has looked at) and `none` (nothing known at all) are
 * exactly the two provenances `confirmed` can never be true for, which is the whole reason this
 * queue exists: the brief's own words for it are "tweak unconfirmed NPCs later".
 *
 * A single-select Speaker dropdown of the four provenances alone cannot express that union --
 * picking "Client guess" or "No race" narrows to one of the two, never both in one click -- so
 * dropping the old Confirmed/Unconfirmed axis entirely (both of which were themselves unions of
 * two provenances, not renamed single ones) would have quietly removed a real view rather than
 * a duplicate one. This sentinel restores the "unconfirmed" half of that view without bringing
 * back a second dropdown or the "confirmed" half: nobody triages the settled rows, so there is
 * no queue that ever wants "corpus or moderator" as one filter.
 *
 * Kept off `isProvenance`'s own union on purpose: a value it doesn't recognise must fall back to
 * "all" (page.tsx's own parsing already does this for any unrecognised string), not silently
 * mean "needs a decision" -- the two are handled by two separate checks in matchesSpeaker so a
 * typo in the query string can never masquerade as this filter.
 */
export const NEEDS_DECISION = "needs-decision" as const;

/**
 * "A quest row whose envelope never named an NPC at all" -- the one speaker state with no
 * provenance, because there is no npc_resolution row to have one. What the manual NPC form in
 * the triage table exists for. Zones and books never name an NPC, so they are never missing one.
 */
export const MISSING = "missing" as const;

export type SpeakerFilter = Provenance | "all" | typeof NEEDS_DECISION | typeof MISSING;

/** The Speaker dropdown's two sentinels, for page.tsx's parsing of the query string. */
export function isSpeakerSentinel(value: unknown): value is typeof NEEDS_DECISION | typeof MISSING {
  return value === NEEDS_DECISION || value === MISSING;
}

export type ClientFilter = ClientFamily | "all";

export type SourceFilter = EnvelopeSource | "all";

export type ContributionFilters = {
  status: ContributionStatus | "all";
  provenance: SpeakerFilter;
  client: ClientFilter;
  source: SourceFilter;
};

export type FilterChange = {
  status?: ContributionStatus | "all";
  provenance?: SpeakerFilter;
  client?: ClientFilter;
  source?: SourceFilter;
};

/**
 * The next filter state after one dropdown changes, keeping the others where they stood.
 *
 * A key present in `next` always wins, even set to `undefined` -- FilterChip's own way of
 * saying "reset to any", which this maps back to "all". A key simply absent from `next` (the
 * dimensions that did not change) is the only case that falls back to `current`.
 */
export function nextContributionFilters(
  current: ContributionFilters,
  next: FilterChange,
): ContributionFilters {
  return {
    status: "status" in next ? (next.status ?? "all") : current.status,
    provenance: "provenance" in next ? (next.provenance ?? "all") : current.provenance,
    client: "client" in next ? (next.client ?? "all") : current.client,
    source: "source" in next ? (next.source ?? "all") : current.source,
  };
}

/** How many rows one page of /contributions shows. */
export const PAGE_SIZE = 100;

/** The `page` query parameter as a page number: 1 for anything that is not a positive integer. */
export function pageOf(value: unknown): number {
  const page = Number(value);
  return Number.isInteger(page) && page > 0 ? page : 1;
}

/**
 * nextContributionFilters, turned into the href /contributions's own rows read back.
 *
 * `page` only when asked for: a filter change starts again from the first page, since the
 * page it was on may not exist in the new view.
 */
export function contributionsHref(current: ContributionFilters, next: FilterChange, page = 1): string {
  const filters = nextContributionFilters(current, next);
  const params = new URLSearchParams({
    status: filters.status,
    provenance: filters.provenance,
    client: filters.client,
    source: filters.source,
  });
  if (page > 1) params.set("page", String(page));
  return `/contributions?${params}`;
}

/**
 * Whether one row's NPC provenance satisfies a Speaker dropdown selection -- the server-side
 * half of the filter, called from page.tsx's own row projection, not just the UI's idea of what
 * is selected.
 *
 * `undefined` (a row with no npc at all) matches MISSING when it is a quests row, and no other
 * real filter.
 */
export function matchesSpeaker(provenance: Provenance | undefined, filter: SpeakerFilter, source: EnvelopeSource): boolean {
  if (filter === "all") return true;
  if (filter === MISSING) return provenance === undefined && source === "quests";
  if (provenance === undefined) return false;
  if (filter === NEEDS_DECISION) return provenance === "client" || provenance === "none";
  return provenance === filter;
}
