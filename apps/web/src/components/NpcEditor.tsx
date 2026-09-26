"use client";

/**
 * /contributions/npcs: every NPC on file, one row each, with the triage table's own speaker
 * controls. `initial` is NpcSummary, built server-side (npcSummaryFrom), so nothing from
 * npc_resolution beyond what is rendered crosses into the client.
 */
import { SearchIcon } from "lucide-react";
import { usePathname, useSearchParams } from "next/navigation";
import { useCallback, useMemo, useState } from "react";

import FilterChip, { type ChipOption } from "@/components/FilterChip";
import { useLang } from "@/components/LangProvider";
import SpeakerCell, { type SpeakerAnswer } from "@/components/SpeakerCell";
import { Input } from "@/components/ui/input";
import { summaryFromResolution, type FlavorScope } from "@/lib/contributions/speaker";
import type { NpcSummary } from "@/lib/contributions/triage";
import { localeHref } from "@/lib/lang";
import { isProvenance, PROVENANCES, type NpcKind, type Provenance } from "@/lib/npc/npc";
import type { NpcResolution } from "@/lib/npc/store";
import { wowheadEntityUrl, wowheadForeverUrl } from "@/lib/wowhead";

function key(npcKind: NpcKind | null, npcId: number): string {
  return `${npcKind}:${npcId}`;
}

// ContributionTable's own words for the same four, so a speaker reads the same on both tabs.
const PROVENANCE_LABELS: Record<Provenance, string> = {
  corpus: "Corpus",
  client: "Guessed",
  moderator: "Moderated",
  none: "Unknown",
};

const SPEAKER_CHIP_OPTIONS: ChipOption[] = PROVENANCES.map((option) => ({
  value: option,
  label: PROVENANCE_LABELS[option],
}));

const PROGRESSES = ["unfinished", "doubtful", "finished"] as const;
type Progress = (typeof PROGRESSES)[number];

function isProgress(value: unknown): value is Progress {
  return (PROGRESSES as readonly unknown[]).includes(value);
}

const PROGRESS_CHIP_OPTIONS: ChipOption[] = [
  { value: "unfinished", label: "Unfinished" },
  { value: "doubtful", label: "Doubtful" },
  { value: "finished", label: "Finished" },
];

/**
 * Whether this NPC's voice still has a blank to fill: race, gender, or a flavor its race and
 * gender offer. A confirmed row with every field null is settled rather than blank -- someone
 * decided it has no race (see SpeakerCell's speakerNote) -- so it counts as finished.
 */
function unfinished(npc: NpcSummary): boolean {
  if (npc.confirmed && !npc.race && !npc.gender && !npc.flavor) return false;
  return !npc.race || !npc.gender || (npc.flavorOptions.length > 0 && !npc.flavor);
}

/**
 * Where an NPC stands for the progress filter. A blank outranks a doubt, being the more
 * pressing thing to fill, and "finished" means neither.
 */
function progressOf(npc: NpcSummary): Progress {
  if (unfinished(npc)) return "unfinished";
  return npc.doubtful ? "doubtful" : "finished";
}

export default function NpcEditor({
  initial,
  flavorScopes,
}: {
  initial: NpcSummary[];
  /** facets().flavorScopes, for SpeakerCell's flavor select. */
  flavorScopes: FlavorScope[];
}) {
  const lang = useLang();
  const pathname = usePathname();
  const params = useSearchParams();
  // The filters live in the URL, so a reload or a shared link keeps the view. Written with
  // history.replaceState rather than router.replace, for zones/Explorer.tsx's reason: the rows
  // are all here already, and Next re-renders useSearchParams() from a native history call.
  const query = params.get("q") ?? "";
  const speakerParam = params.get("speaker");
  const provenance = isProvenance(speakerParam) ? speakerParam : undefined;
  const progressParam = params.get("progress");
  const progress = isProgress(progressParam) ? progressParam : undefined;
  const setParam = useCallback(
    (name: string, value: string | undefined) => {
      const search = new URLSearchParams(params.toString());
      if (value) search.set(name, value);
      else search.delete(name);
      const next = search.toString();
      window.history.replaceState(null, "", next ? `${pathname}?${next}` : pathname);
    },
    [params, pathname],
  );
  /** What this session saved, over the server's rows, keyed by NPC. */
  const [saved, setSaved] = useState<Record<string, NpcSummary>>({});
  const [busy, setBusy] = useState<string | null>(null);
  const [failed, setFailed] = useState<string | null>(null);

  const save = useCallback(
    async (npc: NpcSummary, answer: SpeakerAnswer) => {
      const k = key(npc.npcKind, npc.npcId);
      setBusy(k);
      setFailed(null);
      // Every row here came from npc_resolution, so npcKind is never null and the route's
      // required kind is always the row's own.
      const response = await fetch("/api/contributions/npc", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ ...answer, npcKind: npc.npcKind, npcId: npc.npcId }),
      }).catch(() => null);
      setBusy(null);
      if (!response?.ok) {
        setFailed(k);
        return;
      }
      const { resolution } = (await response.json()) as { resolution: NpcResolution };
      setSaved((current) => ({ ...current, [k]: summaryFromResolution(resolution, flavorScopes) }));
    },
    [flavorScopes],
  );

  // Not rebuilt when only `busy` or `failed` changes.
  const rows = useMemo(() => {
    const needle = query.trim().toLowerCase();
    return initial
      .map((npc) => saved[key(npc.npcKind, npc.npcId)] ?? npc)
      .filter(
        (npc) =>
          !needle || String(npc.npcId).includes(needle) || (npc.npcName ?? "").toLowerCase().includes(needle),
      )
      .filter((npc) => !provenance || npc.provenance === provenance)
      .filter((npc) => !progress || progressOf(npc) === progress);
  }, [initial, saved, query, provenance, progress]);

  return (
    <>
      <div className="mb-4 flex items-center gap-3">
        <Input
          type="search"
          placeholder="Filter by id or name"
          value={query}
          onChange={(event) => setParam("q", event.target.value)}
          className="h-8 max-w-xs text-sm"
        />
        <FilterChip
          label="speaker"
          value={provenance}
          options={SPEAKER_CHIP_OPTIONS}
          onChange={(next) => setParam("speaker", next)}
        />
        <FilterChip
          label="progress"
          value={progress}
          options={PROGRESS_CHIP_OPTIONS}
          onChange={(next) => setParam("progress", next)}
        />
        <span className="text-muted-foreground text-xs">
          {rows.length} of {initial.length}
        </span>
      </div>

      {rows.length === 0 ? (
        <p className="text-muted-foreground text-sm">Nothing here.</p>
      ) : (
        <table className="w-full border-separate border-spacing-0 text-sm">
          <thead className="text-muted-foreground text-left text-xs">
            <tr>
              <th className="border-b py-2 pr-3 font-normal">ID</th>
              <th className="border-b py-2 pr-3 font-normal">Name</th>
              <th className="border-b py-2 pr-3 font-normal">Race / gender / flavor</th>
              <th className="border-b py-2 font-normal" />
            </tr>
          </thead>
          <tbody>
            {rows.map((npc) => {
              const k = key(npc.npcKind, npc.npcId);
              return (
                <tr key={k} className="align-top [&>td]:border-b [&>td]:py-2 [&>td]:leading-5">
                  <td className="pr-3 text-xs whitespace-nowrap">
                    <span className="font-mono">{npc.npcId}</span>
                    {npc.npcKind === "gameobject" ? (
                      <span className="text-muted-foreground"> · object</span>
                    ) : null}{" "}
                    {/* Both branches: a vanilla NPC is on each, a post-vanilla one only on
                        /forever/ -- see wowhead.ts. */}
                    <a
                      href={wowheadEntityUrl(npc.npcKind ?? "creature", npc.npcId)}
                      target="_blank"
                      rel="noreferrer"
                      title="Wowhead Classic"
                      className="text-muted-foreground hover:underline"
                    >
                      wc↗
                    </a>{" "}
                    <a
                      href={wowheadForeverUrl(npc.npcKind ?? "creature", npc.npcId)}
                      target="_blank"
                      rel="noreferrer"
                      title="Wowhead Anniversary"
                      className="text-muted-foreground hover:underline"
                    >
                      wf↗
                    </a>
                  </td>
                  <td className="pr-3 text-xs">{npc.npcName ?? <span className="text-muted-foreground">unnamed</span>}</td>
                  <td className="pr-3 text-xs">
                    <SpeakerCell
                      // Remount on a save, so the form's own state starts from the new answer.
                      key={`${npc.provenance}:${npc.race}:${npc.gender}:${npc.flavor}:${npc.doubtful}`}
                      npc={npc}
                      flavorScopes={flavorScopes}
                      readOnly={false}
                      busy={busy === k}
                      onSave={(answer) => void save(npc, answer)}
                    />
                    {failed === k ? (
                      <p className="text-destructive mt-1">That didn&apos;t go through -- try again.</p>
                    ) : null}
                  </td>
                  <td className="text-right">
                    <a
                      href={localeHref(lang, `/quests?q=${npc.npcId}&filter=npc`)}
                      title="Find this NPC's lines in the quests explorer"
                      aria-label={`Find ${npc.npcName ?? npc.npcId} in the quests explorer`}
                      className="text-muted-foreground hover:text-foreground inline-flex p-1"
                    >
                      <SearchIcon className="size-4" />
                    </a>
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
