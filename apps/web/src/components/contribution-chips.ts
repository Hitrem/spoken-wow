/** The filter chips both contributions tables offer. */
import type { ChipOption } from "@/components/FilterChip";
import { CLIENT_FAMILIES, CLIENT_FAMILY_LABELS } from "@/lib/contributions/client";

/** Where the search box is matched, as the explorer's own "search in"; "any" is the idle state. */
export const SEARCH_IN_OPTIONS: ChipOption[] = [
  { value: "npc", label: "NPC only" },
  { value: "quest", label: "Quest only" },
  { value: "text", label: "Text only" },
];

export const CLIENT_CHIP_OPTIONS: ChipOption[] = CLIENT_FAMILIES.map((option) => ({
  value: option,
  label: CLIENT_FAMILY_LABELS[option],
}));
