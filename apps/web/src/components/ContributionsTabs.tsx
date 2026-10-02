import Link from "next/link";

import { localeHref, type Lang } from "@/lib/lang";
import { cn } from "@/lib/utils";

const TABS = [
  { key: "contributions", label: "Contributions", href: "/contributions" },
  { key: "corrections", label: "Corrections", href: "/contributions/corrections" },
  { key: "npcs", label: "NPCs", href: "/contributions/npcs" },
] as const;

/**
 * The views of /contributions: the triage queue of missing lines, the corrections to lines the
 * corpus already has, and every NPC they have named. Links, not
 * client state -- each is its own page with its own gate, and the NPC tab is left out for
 * somebody that page would 404 for. Styled as VoicesTabs's own tab strip.
 */
export default function ContributionsTabs({
  lang,
  active,
  showNpcs,
}: {
  lang: Lang;
  active: (typeof TABS)[number]["key"];
  showNpcs: boolean;
}) {
  const tabs = TABS.filter((tab) => tab.key !== "npcs" || showNpcs);
  if (tabs.length < 2) return null;

  return (
    <nav aria-label="Contributions" className="mb-4 flex gap-1 border-b">
      {tabs.map((tab) => (
        <Link
          key={tab.key}
          href={localeHref(lang, tab.href)}
          aria-current={tab.key === active ? "page" : undefined}
          className={cn(
            "-mb-px border-b-2 px-3 py-2 text-sm",
            tab.key === active
              ? "border-foreground font-medium"
              : "text-muted-foreground hover:text-foreground border-transparent",
          )}
        >
          {tab.label}
        </Link>
      ))}
    </nav>
  );
}
