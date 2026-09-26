/**
 * An NPC's voice answer in the shape the speaker controls render, built without the corpus.
 *
 * Node-free, like query.ts: SpeakerCell and ContributionTable are client components and call
 * these on every save, and /contributions/npcs calls them on the server for every NPC on file.
 * triage.ts's npcSummaryFrom is the server-side twin that asks the corpus (flavorsFor) instead of
 * facets().flavorScopes -- the same answer, from the corpus's own roster.
 */
import type { NpcResolution } from "../npc/store";
import type { NpcSummary } from "./triage";

/** A race-gender-flavor triple the corpus actually has: facets().flavorScopes. */
export type FlavorScope = { race: string; gender: string; flavor: string };

/** The flavors a race-gender is voiced in, or [] while either is unknown. */
export function flavorOptionsFor(race: string | null, gender: string | null, scopes: FlavorScope[]): string[] {
  if (!race || !gender) return [];
  return scopes.filter((scope) => scope.race === race && scope.gender === gender).map((scope) => scope.flavor);
}

/** A stored resolution, as SpeakerCell renders it. */
export function summaryFromResolution(resolution: NpcResolution, flavorScopes: FlavorScope[]): NpcSummary {
  return {
    npcKind: resolution.npcKind,
    npcId: resolution.npcId,
    npcName: resolution.npcName,
    race: resolution.race,
    gender: resolution.gender,
    flavor: resolution.flavor,
    provenance: resolution.provenance,
    confirmed: resolution.confirmed,
    doubtful: resolution.doubtful,
    flavorOptions: flavorOptionsFor(resolution.race, resolution.gender, flavorScopes),
    conflict: [],
  };
}
