"use client";

/**
 * The triage list for pasted envelopes.
 *
 * A table for the same reason ReportTable is one: triage is a scan down a column, and the
 * submitted text -- which can run to a full quest's worth of dialogue -- sits behind a
 * `<details>` so a long paste does not push every row after it off the screen (the reasoning
 * CATEGORY_COLUMN gives in lib/reports/reports.ts for the same shape of problem).
 *
 * Never renders `ip`, `name` or `email`: reports/ReportTable shows a reporter's own name
 * because they gave it to have their report followed up on, but a contribution's identifying
 * fields exist only for abuse response, not for triage to read. `body` -- the optional
 * complaint -- is different: it's the one field a player filled in specifically to be read,
 * so it is rendered below, deliberately included in the Row this component accepts.
 *
 * `initial` is typed as `ContributionRow`, not the full `Contribution`, and page.tsx must
 * project down to it before passing rows here: this is a "use client" component, so whatever
 * shape its props carry crosses into the RSC flight payload and is readable in devtools
 * regardless of what this file goes on to render. `ip`, `name`, `email` and `raw` have no
 * reason to make that crossing at all.
 */
import { useLang } from "@/components/LangProvider";
import { localeHref } from "@/lib/lang";
import { useRouter } from "next/navigation";
import { useCallback, useState } from "react";

import FilterChip, { type ChipOption } from "@/components/FilterChip";
import SpeakerCell, { ProvenanceBadge, type SpeakerAnswer } from "@/components/SpeakerCell";
import { Refreshing } from "@/components/Loading";
import { usePendingPush } from "@/components/usePendingPush";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Checkbox } from "@/components/ui/checkbox";
import type { ContributionStatus } from "@/lib/contributions/contributions";
import { CLIENT_FAMILIES, CLIENT_FAMILY_LABELS, type ClientSummary } from "@/lib/contributions/client";
import { flavorOptionsFor, summaryFromResolution, type FlavorScope } from "@/lib/contributions/speaker";
import { contributionsHref, MISSING, NEEDS_DECISION, type ClientFilter, type SpeakerFilter } from "@/lib/contributions/query";
import type { Contribution } from "@/lib/contributions/store";
// Both are computed server-side (npcSummaryFrom pulls in corpus.ts's flavorsFor) -- `import
// type` erases the whole thing at compile time, so none of that follows the type in here. The
// same split existing.ts's `existing` prop already draws.
import type { NpcConflictOption, NpcSummary, QuestSummary } from "@/lib/contributions/triage";
// From npc.ts, not npc/store.ts: store.ts imports @/lib/db, and pulling NPC_KINDS/PROVENANCES
// (values, not just types) out of it would drag Postgres's own node built-ins into this bundle.
import { NPC_KINDS, PROVENANCES, type NpcKind, type Provenance } from "@/lib/npc/npc";
import type { NpcResolution } from "@/lib/npc/store";
import { cn } from "@/lib/utils";
import { wowheadEntityUrl, wowheadForeverUrl, wowheadQuestUrl } from "@/lib/wowhead";

export type { NpcSummary };

/** The fields this table reads. page.tsx projects full Contribution rows down to this shape. */
export type ContributionRow = Pick<
  Contribution,
  "id" | "source" | "key" | "locale" | "count" | "text" | "status" | "createdAt" | "body"
> & {
  /** The game client the text came from, classified from the envelope's `build`. */
  client: ClientSummary;
  /** Null when the envelope never named an NPC at all -- zones and books, or a quest keyed on quest+event. */
  npc: NpcSummary | null;
  /** Null when the source has no quest concept at all. See lib/contributions/triage.ts. */
  quest: QuestSummary | null;
  /**
   * Whether this contribution's line is already in the explorer (accept.ts's lineIsInExplorer).
   * Only meaningful for an accepted quests row -- it is what decides whether "Add to explorer"
   * is offered: a row accepted before this feature existed has none yet.
   */
  hasLine: boolean;
};

const SOURCE_LABELS: Record<Contribution["source"], string> = {
  quests: "Quests",
  zones: "Zones",
  books: "Books",
};

const STATUS_LABELS: Record<ContributionStatus, string> = {
  new: "New",
  accepted: "Accepted",
  rejected: "Rejected",
};

const STATUS_OPTIONS: readonly ContributionStatus[] = ["new", "accepted", "rejected"];
const STATUS_CHIP_OPTIONS: ChipOption[] = STATUS_OPTIONS.map((option) => ({
  value: option,
  label: STATUS_LABELS[option],
}));

const PROVENANCE_LABELS: Record<Provenance, string> = {
  corpus: "Corpus",
  display: "Game data",
  client: "Guessed",
  moderator: "Moderated",
  none: "Unknown",
};


// The Speaker dropdown's options: NEEDS_DECISION first -- it's the view this queue exists for,
// "everything nobody has settled yet" -- then PROVENANCES's own four, then MISSING: a quest row
// that names no NPC at all, which the NPC column's own form fills in. "Confirmed"
// (the union nobody triages: settled rows) is deliberately not here; see NEEDS_DECISION's own
// docstring in lib/contributions/query.ts for why that one dropped out while this one didn't.
const SPEAKER_CHIP_OPTIONS: ChipOption[] = [
  { value: NEEDS_DECISION, label: "Needs a decision" },
  ...PROVENANCES.map((option) => ({ value: option, label: PROVENANCE_LABELS[option] })),
  { value: MISSING, label: "Missing" },
];

const CLIENT_CHIP_OPTIONS: ChipOption[] = CLIENT_FAMILIES.map((option) => ({
  value: option,
  label: CLIENT_FAMILY_LABELS[option],
}));

/** The day and the clock time, short enough to sit in a column, matching ReportTable's `when`. */
function when(at: string): string {
  return new Date(at).toLocaleString(undefined, {
    month: "short",
    day: "numeric",
    hour: "2-digit",
    minute: "2-digit",
  });
}


export default function ContributionTable({
  initial,
  status,
  provenance,
  client,
  existing,
  flavorScopes,
  canAnswerNpc,
}: {
  initial: ContributionRow[];
  status: ContributionStatus | "all";
  provenance: SpeakerFilter;
  client: ClientFilter;
  /** id -> corpus text, present only where the row's key resolves to something on file. */
  existing: Record<number, string>;
  /** facets().flavorScopes -- what lets that state's flavor select narrow to whatever race-gender was just chosen, without a round trip. */
  flavorScopes: FlavorScope[];
  /** Whether the viewer may set an NPC's race, gender and flavor; if not, they are shown only. */
  canAnswerNpc: boolean;
}) {
  const { pending, push } = usePendingPush();
  const router = useRouter();
  const lang = useLang();

  /**
   * What this session resolved, overlaid on the server's rows -- the same shape ReportTable
   * uses and for the same reason: the status dropdown below is a navigation, so seeding state
   * from `initial` once would leave a resolved row sitting in a queue it no longer belongs to
   * until the next reload.
   */
  const [resolved, setResolved] = useState<Record<number, Contribution["status"]>>({});
  const [busy, setBusy] = useState<number | null>(null);
  /** Same overlay idea as `resolved`, for "Add to explorer" succeeding on an already-accepted row. */
  const [lineCreated, setLineCreated] = useState<Set<number>>(new Set());
  /** A refused resolve, in the words the route already gives -- cleared by the next attempt. */
  const [refusals, setRefusals] = useState<Record<number, string>>({});

  /**
   * The npc column, overlaid on the server's rows for the same reason `resolved` is: the
   * override writes through to the NPC, not this contribution, so nothing here navigates away
   * on save and a reload would be the only other way to see it land.
   *
   * Keyed by NPC (overrideKey), not by contribution, for the same reason the write goes to the
   * NPC: one answer settles every row that NPC speaks, and the page should show that at once.
   * A kind-less row has no NPC key yet, so its own answer is kept under its contribution id.
   */
  const [npcOverrides, setNpcOverrides] = useState<Record<string, NpcSummary>>({});
  const [npcBusy, setNpcBusy] = useState<number | null>(null);

  const overrideNpc = useCallback(
    async (
      contributionId: number,
      npc: NpcSummary,
      // Partial on purpose -- a key left out entirely (not sent as "") tells the route to keep
      // whatever is already on the row, which is what lets the "client" state save just a
      // flavor and the "nothing known" state save just a race and gender. See the route's own
      // orExisting for the other half of this. `npcKind` is only ever in here for a kind-less
      // row (npc.npcKind === null): the moderator's own select is the only source for it then,
      // since there is no existing row (or envelope) to fall back on the way race/gender/flavor
      // can.
      answer: SpeakerAnswer,
    ) => {
      setNpcBusy(contributionId);
      const response = await fetch("/api/contributions/npc", {
        method: "POST",
        headers: { "content-type": "application/json" },
        // A kind-less row's moderator-chosen kind wins over the row's own null. `??` rather than
        // spreading `answer` over the default: SpeakerCell sends `npcKind: undefined` for a row
        // that already has a kind, and a spread would overwrite that kind with undefined, which
        // JSON then drops -- the route answered every such save "unknown kind".
        body: JSON.stringify({ ...answer, npcId: npc.npcId, npcKind: answer.npcKind ?? npc.npcKind }),
      }).catch(() => null);
      setNpcBusy(null);

      if (!response?.ok) return;
      const { resolution } = (await response.json()) as { resolution: NpcResolution };
      // A kind-less row's moderator just said which kind it is: record that on the contribution
      // too, so a later answer for the other kind under the same id can never turn this row
      // into a conflict.
      if (npc.npcKind === null && answer.npcKind) {
        await recordKind(contributionId, answer.npcKind);
      }
      // A saved answer is always "settled" (provenance "moderator" is always confirmed --
      // migration 0031), so nothing here ever renders the flavor select again to need
      // flavorOptions -- computed anyway so the type stays honest rather than lying with `[]`.
      const summary = summaryFromResolution(resolution, flavorScopes);
      setNpcOverrides((current) => ({
        ...current,
        [contributionKey(contributionId)]: summary,
        [overrideKey(resolution.npcKind, resolution.npcId)]: summary,
      }));
    },
    [flavorScopes],
  );

  /**
   * A conflict settled: the moderator picked which of the answers on file this contribution's
   * NPC is. Recorded on the contribution (api/contributions/kind), then shown as that answer.
   */
  const pickConflict = useCallback(
    async (contributionId: number, npc: NpcSummary, option: NpcConflictOption) => {
      setNpcBusy(contributionId);
      const ok = await recordKind(contributionId, option.npcKind);
      setNpcBusy(null);
      if (!ok) {
        setRefusals(withRefusal(contributionId));
        return;
      }
      setNpcOverrides((current) => ({
        ...current,
        [contributionKey(contributionId)]: {
          ...npc,
          npcKind: option.npcKind,
          race: option.race,
          gender: option.gender,
          flavor: option.flavor,
          provenance: option.provenance,
          confirmed: option.provenance === "corpus" || option.provenance === "display" || option.provenance === "moderator",
          doubtful: option.doubtful,
          flavorOptions: flavorOptionsFor(option.race, option.gender, flavorScopes),
          conflict: [],
        },
      }));
    },
    [flavorScopes],
  );

  /**
   * A quest row whose envelope named no NPC, given one by hand (api/contributions/npc-identity).
   * Shown under the contribution's own key, with resolveNpc's answer for it. When resolving
   * failed the answer is still recorded, and a refresh is what resolves it (page.tsx's npcFor).
   * The error, when there is one, is the route's own words.
   */
  const nameNpc = useCallback(
    async (contributionId: number, answer: { npcKind: NpcKind; npcId: number; npcName: string }) => {
      setNpcBusy(contributionId);
      const response = await fetch("/api/contributions/npc-identity", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ id: contributionId, ...answer }),
      }).catch(() => null);
      setNpcBusy(null);

      const body = (await response?.json().catch(() => null)) as
        | { resolution?: NpcResolution | null; error?: unknown }
        | null;
      if (!response?.ok) {
        setRefusals(withRefusal(contributionId, body?.error));
        return;
      }
      setRefusals(withoutRefusal(contributionId));
      if (!body?.resolution) {
        router.refresh();
        return;
      }
      const summary = summaryFromResolution(body.resolution, flavorScopes);
      setNpcOverrides((current) => ({ ...current, [contributionKey(contributionId)]: summary }));
    },
    [flavorScopes, router],
  );

  /** One row's status change, shared by its own buttons and the bulk ones. True when it landed. */
  const send = useCallback(async (id: number, next: ContributionStatus): Promise<boolean> => {
    const response = await fetch("/api/contributions/resolve", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ id, status: next }),
    }).catch(() => null);

    if (!response?.ok) {
      // The route already gives a plain-words reason for needs-speaker and one-way (accept.ts);
      // anything else (bad status, unknown row) degrades the same way this always has.
      const body = await response?.json().catch(() => null);
      setRefusals(withRefusal(id, body?.error));
      return false;
    }
    setRefusals(withoutRefusal(id));
    setResolved((current) => ({ ...current, [id]: next }));
    // "Add to explorer" is the same POST as Accept, re-sent for a row already accepted -- this
    // is what hides the button once it has worked, without waiting for a reload.
    if (next === "accepted") setLineCreated((current) => new Set(current).add(id));
    return true;
  }, []);

  const resolve = useCallback(
    async (id: number, next: ContributionStatus) => {
      setBusy(id);
      await send(id, next);
      setBusy(null);
    },
    [send],
  );

  /** Rows ticked for "Accept selected" / "Reject selected". */
  const [selected, setSelected] = useState<Set<number>>(new Set());
  /** A bulk run in flight, for its progress line and to hold every other button still meanwhile. */
  const [bulk, setBulk] = useState<{ next: ContributionStatus; done: number; total: number } | null>(null);
  /** What the last bulk run came to, until the next one starts. */
  const [bulkOutcome, setBulkOutcome] = useState<string | null>(null);
  /** "Accept all shown" asks twice: accepting writes quest lines, and a quests row can't be reopened after. */
  const [confirmAll, setConfirmAll] = useState(false);

  /**
   * The same POST as a row's own button, once per row, one at a time: each accept is its own
   * transaction writing quest lines (accept.ts), and running them in parallel is how two rows
   * for the same line would race each other's collision check. A row that is refused keeps its
   * refusal under it, exactly as if its own button had been pressed, and the rest carry on.
   */
  const resolveMany = useCallback(
    async (ids: number[], next: ContributionStatus) => {
      setBulkOutcome(null);
      setBulk({ next, done: 0, total: ids.length });
      const refused: number[] = [];
      for (const [index, id] of ids.entries()) {
        if (!(await send(id, next))) refused.push(id);
        setBulk({ next, done: index + 1, total: ids.length });
      }
      setBulk(null);
      // The refused rows stay ticked, so fixing their speakers and pressing the same button again
      // is the whole retry.
      setSelected(new Set(refused));
      setBulkOutcome(
        `${STATUS_LABELS[next]}: ${ids.length - refused.length} of ${ids.length}` +
          (refused.length > 0 ? ` -- ${refused.length} refused and left selected.` : "."),
      );
    },
    [send],
  );

  const rows = initial.filter((row) => {
    const current = resolved[row.id] ?? row.status;
    return status === "all" || current === status;
  });

  // Only rows still on screen count: a selected row a bulk reject just moved out of this view
  // must not be accepted by the next click on a button that no longer shows it.
  const selectedRows = rows.filter((row) => selected.has(row.id));
  /** The ids among `from` a bulk change to `next` would actually change. */
  const changeable = (from: ContributionRow[], next: ContributionStatus) =>
    from.filter((row) => (resolved[row.id] ?? row.status) !== next).map((row) => row.id);
  const shownToAccept = changeable(rows, "accepted");
  const selectedToAccept = changeable(selectedRows, "accepted");
  const selectedToReject = changeable(selectedRows, "rejected");
  const allTicked = rows.length > 0 && selectedRows.length === rows.length;

  const toggle = (id: number, on: boolean) =>
    setSelected((current) => {
      const next = new Set(current);
      if (on) next.add(id);
      else next.delete(id);
      return next;
    });

  /**
   * Move one dropdown and keep the other, then push it -- a soft navigation, not a state
   * change, so the filter still lives in the URL and survives a refresh. Follows
   * ReportTable.tsx's own `go`; the mapping itself is contributionsHref, pulled out to
   * lib/contributions/query.ts so it can be tested without rendering FilterChip or this table.
   */
  function go(next: { status?: ContributionStatus | "all"; provenance?: SpeakerFilter; client?: ClientFilter }) {
    push(localeHref(lang, contributionsHref({ status, provenance, client }, next)));
  }

  return (
    <>
      {/* Dropdowns, the same control the explorers filter with -- matching ReportTable.
          Status/Speaker being one dropdown each, rather than a row of link pills, is what makes
          "New / Accepted / Rejected / All" and the six speaker pills fit without crowding. */}
      <nav className="mb-4 flex flex-wrap items-center gap-2">
        <FilterChip
          label="status"
          value={status === "all" ? undefined : status}
          options={STATUS_CHIP_OPTIONS}
          onChange={(next) => go({ status: next as ContributionStatus | undefined })}
        />
        <FilterChip
          label="speaker"
          value={provenance === "all" ? undefined : provenance}
          options={SPEAKER_CHIP_OPTIONS}
          onChange={(next) => go({ provenance: next as SpeakerFilter | undefined })}
        />
        <FilterChip
          label="client"
          value={client === "all" ? undefined : client}
          options={CLIENT_CHIP_OPTIONS}
          onChange={(next) => go({ client: next as ClientFilter | undefined })}
        />
        {pending && <Refreshing />}
      </nav>

      {rows.length > 0 ? (
        <div className="mb-3 flex flex-wrap items-center gap-2 text-xs">
          {bulk ? (
            <span className="text-muted-foreground">
              {STATUS_LABELS[bulk.next]}: {bulk.done} of {bulk.total}…
            </span>
          ) : (
            <>
              {confirmAll ? (
                <>
                  <span>Accept all {shownToAccept.length} shown? A quests line can&apos;t be reopened after.</span>
                  <Button
                    size="sm"
                    onClick={() => {
                      setConfirmAll(false);
                      void resolveMany(shownToAccept, "accepted");
                    }}
                  >
                    Accept {shownToAccept.length}
                  </Button>
                  <Button size="sm" variant="ghost" onClick={() => setConfirmAll(false)}>
                    Cancel
                  </Button>
                </>
              ) : (
                <Button
                  size="sm"
                  variant="outline"
                  disabled={shownToAccept.length === 0}
                  onClick={() => setConfirmAll(true)}
                >
                  Accept all shown ({shownToAccept.length})
                </Button>
              )}
              {selectedRows.length > 0 ? (
                <>
                  <span className="text-muted-foreground ml-2">{selectedRows.length} selected</span>
                  <Button
                    size="sm"
                    variant="outline"
                    disabled={selectedToAccept.length === 0}
                    onClick={() => void resolveMany(selectedToAccept, "accepted")}
                  >
                    Accept selected ({selectedToAccept.length})
                  </Button>
                  <Button
                    size="sm"
                    variant="outline"
                    disabled={selectedToReject.length === 0}
                    onClick={() => void resolveMany(selectedToReject, "rejected")}
                  >
                    Reject selected ({selectedToReject.length})
                  </Button>
                  <Button size="sm" variant="ghost" onClick={() => setSelected(new Set())}>
                    Clear
                  </Button>
                </>
              ) : null}
              {bulkOutcome ? <span className="text-muted-foreground ml-2">{bulkOutcome}</span> : null}
            </>
          )}
        </div>
      ) : null}

      {rows.length === 0 ? (
        <p className="text-muted-foreground text-sm">Nothing here.</p>
      ) : (
        <table
          aria-busy={pending}
          className={cn("w-full border-separate border-spacing-0 text-sm transition-opacity", pending && "opacity-60")}
        >
          <thead className="text-muted-foreground text-left text-xs">
            <tr>
              <th className="border-b py-2 pr-2 font-normal">
                <Checkbox
                  aria-label="Select every row shown"
                  checked={allTicked ? true : selectedRows.length > 0 ? "indeterminate" : false}
                  disabled={bulk !== null}
                  onCheckedChange={(on) => setSelected(on === true ? new Set(rows.map((row) => row.id)) : new Set())}
                />
              </th>
              <th className="border-b py-2 pr-3 font-normal">Filed</th>
              <th className="border-b py-2 pr-3 font-normal">Source</th>
              <th className="border-b py-2 pr-3 font-normal">NPC</th>
              <th className="border-b py-2 pr-3 font-normal">Quest</th>
              <th className="border-b py-2 pr-3 font-normal">Client</th>
              <th className="border-b py-2 pr-3 font-normal">Count</th>
              <th className="border-b py-2 pr-3 font-normal">What they sent</th>
              <th className="border-b py-2 pr-3 font-normal">Status</th>
              <th className="border-b py-2 font-normal" />
            </tr>
          </thead>

          <tbody>
            {rows.map((row) => {
              const current = resolved[row.id] ?? row.status;
              const found = existing[row.id];
              const npc =
                (row.npc?.npcKind ? npcOverrides[overrideKey(row.npc.npcKind, row.npc.npcId)] : undefined) ??
                npcOverrides[contributionKey(row.id)] ??
                row.npc;

              return (
                // Top-aligned, not middle: the NPC/Speaker cell below can grow to a whole form's
                // height (race/gender/flavor selects), and centring every other
                // cell against that made the short ones float to mid-row instead of sitting on
                // a scannable line.
                <tr
                  key={row.id}
                  // Anchor, not just a key: an accepted quests row's line carries a link back
                  // here (LineRow.tsx's "contributed" badge), and this is what it jumps to.
                  id={`contribution-${row.id}`}
                  className="align-top [&>td]:border-b [&>td]:py-2 [&>td]:leading-5"
                >
                  <td className="pr-2">
                    <Checkbox
                      aria-label={`Select contribution ${row.id}`}
                      checked={selected.has(row.id)}
                      disabled={bulk !== null}
                      onCheckedChange={(on) => toggle(row.id, on === true)}
                    />
                  </td>

                  <td className="text-muted-foreground pr-3 text-xs whitespace-nowrap">
                    {when(row.createdAt)}
                  </td>

                  <td className="pr-3 text-xs whitespace-nowrap">
                    {/* The raw triage key moved here, as a hover title -- the NPC and Quest
                        columns are what a moderator scans now (finding 1), but the key is still
                        worth having for a zones/books row, where neither column applies. */}
                    <Badge variant="outline" className="py-0 leading-5" title={row.key}>
                      {SOURCE_LABELS[row.source]}
                    </Badge>
                  </td>

                  {/* NPC and Speaker, merged: who the NPC is and who voices their lines are the
                      same question, and showing them as two columns meant scanning across the
                      row to connect an id in one cell with a form three cells later. Name/id/
                      links stay on their own line; the voice -- settled text for a corpus NPC,
                      the override form for one that isn't -- sits right beneath it. */}
                  <td className="max-w-[20rem] pr-3 text-xs">
                    {npc ? (
                      <div className="flex flex-col gap-1">
                        <div className="flex items-center gap-1 whitespace-nowrap">
                          <a
                            href={localeHref(lang, `/quests?q=${npc.npcId}&filter=npc`)}
                            className="truncate hover:underline"
                            title={npc.npcName ?? undefined}
                          >
                            {npc.npcName ?? "unnamed"}{" "}
                            <span className="text-muted-foreground">#{npc.npcId}</span>
                          </a>
                          <a
                            href={
                              // The corpus's own exact answer means it has this NPC on the branch
                              // the corpus is built from; anything else -- including a post-vanilla
                              // NPC like 205729 -- is only ever on the client's own branch. See
                              // wowhead.ts for why two branches exist rather than one.
                              //
                              // A kind-less row (npc.npcKind === null) has no real kind to link
                              // with yet -- "creature" is a convenience guess for this link only,
                              // never stored, and every quest/gossip npc field this table has ever
                              // seen has in fact named one.
                              npc.provenance === "corpus"
                                ? wowheadEntityUrl(npc.npcKind ?? "creature", npc.npcId)
                                : wowheadForeverUrl(npc.npcKind ?? "creature", npc.npcId)
                            }
                            target="_blank"
                            rel="noreferrer"
                            className="text-muted-foreground shrink-0 hover:underline"
                          >
                            wh↗
                          </a>
                        </div>
                        {npc.conflict.length > 0 ? (
                          <NpcConflict
                            npc={npc}
                            busy={npcBusy === row.id}
                            onPick={(option) => void pickConflict(row.id, npc, option)}
                          />
                        ) : (
                          <SpeakerCell
                            npc={npc}
                            flavorScopes={flavorScopes}
                            readOnly={!canAnswerNpc}
                            busy={npcBusy === row.id}
                            onSave={(answer) => void overrideNpc(row.id, npc, answer)}
                          />
                        )}
                      </div>
                    ) : row.source === "quests" ? (
                      // No NPC named at all: whoever triages it can say who speaks it.
                      <MissingNpcForm busy={npcBusy === row.id} onSave={(answer) => void nameNpc(row.id, answer)} />
                    ) : (
                      <span className="text-muted-foreground">—</span>
                    )}
                  </td>

                  <td className="max-w-[14rem] pr-3 text-xs whitespace-nowrap">
                    {row.quest === null ? (
                      <span className="text-muted-foreground">—</span>
                    ) : row.quest === "gossip" ? (
                      "Gossip"
                    ) : (
                      <>
                        <span className="truncate">{row.quest.title}</span>{" "}
                        <a
                          href={wowheadQuestUrl(row.quest.questId)}
                          target="_blank"
                          rel="noreferrer"
                          className="text-muted-foreground hover:underline"
                        >
                          #{row.quest.questId}
                        </a>
                      </>
                    )}
                  </td>

                  {/* Which game, then the locale and the exact build underneath: the version is
                      in the label, and the build number is what tells a beta's builds apart. */}
                  <td className="pr-3 text-xs whitespace-nowrap">
                    <div>{row.client.label}</div>
                    <div className="text-muted-foreground">
                      {row.locale}
                      {row.client.buildNumber ? ` · ${row.client.buildNumber}` : null}
                    </div>
                  </td>

                  <td className="pr-3 text-xs whitespace-nowrap">{row.count}</td>

                  <td className="max-w-md pr-3">
                    {/* Collapsed by default: a full quest's dialogue in an open cell is the
                        "table stops being a scan" failure this markup exists to avoid. */}
                    <details>
                      <summary className="text-muted-foreground cursor-pointer text-xs">
                        {row.text ? `${row.text.length} chars` : "no text"}
                        {found !== undefined ? " · corpus already has this key" : ""}
                        {row.body ? " · note attached" : ""}
                      </summary>
                      <p className="mt-1 whitespace-pre-wrap">{row.text ?? "(no text sent)"}</p>
                      {row.body ? (
                        // The optional complaint: collected on the form, stored as `body`, and
                        // until now rendered nowhere -- a player who explained what was wrong
                        // had that reach no one. Shown here rather than its own column because
                        // most rows won't have one and a column that's usually empty is a scan
                        // slower than the details cell it would sit next to.
                        <div className="mt-2 rounded border p-2">
                          <p className="text-muted-foreground text-xs font-medium">
                            What they said was wrong:
                          </p>
                          <p className="mt-1 whitespace-pre-wrap">{row.body}</p>
                        </div>
                      ) : null}
                      {found !== undefined ? (
                        // A "missing" key the corpus already answers to is a corpus bug, not
                        // an absent line -- shown beside the submitted text so that reading is
                        // a glance, not a second lookup.
                        <div className="bg-muted/40 mt-2 rounded p-2">
                          <p className="text-muted-foreground text-xs font-medium">
                            Already on file:
                          </p>
                          <p className="mt-1 whitespace-pre-wrap">{found}</p>
                        </div>
                      ) : null}
                    </details>
                  </td>

                  <td className="pr-3 text-xs whitespace-nowrap">{STATUS_LABELS[current]}</td>

                  <td>
                    <div className="flex items-center justify-end gap-1">
                      {current !== "accepted" ? (
                        <Button
                          size="sm"
                          variant="outline"
                          disabled={busy === row.id || bulk !== null}
                          onClick={() => void resolve(row.id, "accepted")}
                        >
                          Accept
                        </Button>
                      ) : row.source === "quests" && !(row.hasLine || lineCreated.has(row.id)) ? (
                        // A quests row accepted before this feature existed (or reopened and
                        // re-accepted since) has no line in the quest tables yet -- Accept itself is
                        // hidden once `current` is already "accepted", so this is the only way
                        // back to the same POST, still gated by resolveContribution's own rules
                        // (needs-speaker, collision, one-way).
                        <Button
                          size="sm"
                          variant="outline"
                          disabled={busy === row.id || bulk !== null}
                          onClick={() => void resolve(row.id, "accepted")}
                        >
                          Add to explorer
                        </Button>
                      ) : null}
                      {current !== "rejected" ? (
                        <Button
                          size="sm"
                          variant="outline"
                          disabled={busy === row.id || bulk !== null}
                          onClick={() => void resolve(row.id, "rejected")}
                        >
                          Reject
                        </Button>
                      ) : null}
                      {current !== "new" ? (
                        <Button
                          size="sm"
                          variant="ghost"
                          disabled={busy === row.id || bulk !== null}
                          onClick={() => void resolve(row.id, "new")}
                        >
                          Reopen
                        </Button>
                      ) : null}
                    </div>
                    {refusals[row.id] ? (
                      // Plain words, straight from resolveContribution's own refusal message --
                      // silence here used to be the whole failure mode ("Degrade per row on a
                      // failed resolve"), and a moderator staring at a button that visibly did
                      // nothing has no way to tell "try again" from "fix something first".
                      <p className="text-destructive mt-1 text-right text-xs">{refusals[row.id]}</p>
                    ) : null}
                  </td>
                </tr>
              );
            })}
          </tbody>
        </table>
      )}
    </>
  );
}

type Refusals = Record<number, string>;

/** A row's refusal, in the route's own words where it gave some. A setRefusals updater. */
function withRefusal(id: number, error?: unknown): (current: Refusals) => Refusals {
  const message = typeof error === "string" ? error : "That didn't go through -- try again.";
  return (current) => ({ ...current, [id]: message });
}

/** A row's refusal cleared by the next attempt succeeding. A setRefusals updater. */
function withoutRefusal(id: number): (current: Refusals) => Refusals {
  return (current) => {
    if (!(id in current)) return current;
    const { [id]: _dropped, ...rest } = current;
    return rest;
  };
}

/** Record a kind-less contribution's NPC kind (api/contributions/kind). True when it landed. */
async function recordKind(contributionId: number, npcKind: NpcKind): Promise<boolean> {
  const response = await fetch("/api/contributions/kind", {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ id: contributionId, npcKind }),
  }).catch(() => null);
  return Boolean(response?.ok);
}

/**
 * The NPC column of a quest row that names no NPC: kind, id and name, the last two required --
 * an id with no name, or a name with no id, is not an answer (migration 0048's check).
 */
function MissingNpcForm({
  busy,
  onSave,
}: {
  busy: boolean;
  onSave: (answer: { npcKind: NpcKind; npcId: number; npcName: string }) => void;
}) {
  const [npcKind, setNpcKind] = useState<NpcKind>("creature");
  const [npcId, setNpcId] = useState("");
  const [npcName, setNpcName] = useState("");
  const valid = /^\d+$/.test(npcId.trim()) && npcName.trim() !== "";

  return (
    <form
      className="flex flex-wrap items-center gap-1"
      onSubmit={(event) => {
        event.preventDefault();
        if (valid) onSave({ npcKind, npcId: Number(npcId.trim()), npcName });
      }}
    >
      <select
        value={npcKind}
        onChange={(event) => setNpcKind(event.target.value as NpcKind)}
        className="h-7 rounded border bg-transparent text-xs"
      >
        {NPC_KINDS.map((option) => (
          <option key={option} value={option}>
            {option}
          </option>
        ))}
      </select>
      <input
        required
        inputMode="numeric"
        pattern="\d+"
        placeholder="id"
        value={npcId}
        onChange={(event) => setNpcId(event.target.value)}
        className="h-7 w-20 rounded border bg-transparent px-1.5 text-xs"
      />
      <input
        required
        placeholder="name"
        value={npcName}
        onChange={(event) => setNpcName(event.target.value)}
        className="h-7 w-32 rounded border bg-transparent px-1.5 text-xs"
      />
      <Button type="submit" size="sm" variant="outline" className="h-7 px-2 text-xs" disabled={busy || !valid}>
        Add
      </Button>
    </form>
  );
}

/**
 * A kind-less row whose id has disagreeing answers on file -- one as a creature, another as a
 * gameobject. Each is shown with where it came from; the moderator picks the one this
 * contribution meant, and nothing is used until they do (triage.ts's idOnlyResolution).
 */
function NpcConflict({
  npc,
  busy,
  onPick,
}: {
  npc: NpcSummary;
  busy: boolean;
  onPick: (option: NpcConflictOption) => void;
}) {
  return (
    <div className="flex flex-col gap-1">
      <p className="text-destructive">Conflicting answers for #{npc.npcId} -- which is it?</p>
      {npc.conflict.map((option) => (
        <div key={option.npcKind} className="flex items-center gap-2">
          <span>
            {option.npcKind}: {[option.race, option.gender, option.flavor].filter(Boolean).join("-") || "no race"}
          </span>
          <ProvenanceBadge provenance={option.provenance} />
          <Button
            size="sm"
            variant="outline"
            className="h-6 px-2 text-xs"
            disabled={busy}
            onClick={() => onPick(option)}
          >
            This one
          </Button>
        </div>
      ))}
    </div>
  );
}

/** npcOverrides' key for an NPC's own answer, shared by every row that NPC speaks. */
function overrideKey(npcKind: NpcKind, npcId: number): string {
  return `npc:${npcKind}:${npcId}`;
}

/** npcOverrides' key for one contribution's own answer, for a row with no NPC key yet. */
function contributionKey(contributionId: number): string {
  return `contribution:${contributionId}`;
}
