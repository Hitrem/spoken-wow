"use client";

import Link from "next/link";

import type { ContributionStatus } from "@/lib/contributions/contributions";
import { cn } from "@/lib/utils";

const TABS: { status: ContributionStatus; label: string }[] = [
  { status: "new", label: "New" },
  { status: "accepted", label: "Accepted" },
  { status: "rejected", label: "Rejected" },
];

/**
 * Which rows of a contributions table are shown: the ones still to triage, or those already
 * accepted or rejected. Tabs rather than a filter, since every row is in exactly one and the
 * new ones are the only queue anybody works down; links, so the tab survives a reload.
 */
export default function StatusTabs({
  active,
  hrefFor,
  onGo,
}: {
  active: ContributionStatus;
  /** The href of each tab, already localised, keeping whatever else the page is filtered to. */
  hrefFor: (status: ContributionStatus) => string;
  /**
   * The table's own pending push, so its rows dim while the tab loads: a plain link to the
   * route already open gets no loading.tsx and looked like it had done nothing.
   */
  onGo: (href: string) => void;
}) {
  return (
    <nav aria-label="Status" className="mb-3 flex gap-1">
      {TABS.map((tab) => (
        <Link
          key={tab.status}
          href={hrefFor(tab.status)}
          onClick={(event) => {
            // A modified click opens a tab or a window, which is the link's to do.
            if (event.metaKey || event.ctrlKey || event.shiftKey || event.button !== 0) return;
            event.preventDefault();
            onGo(hrefFor(tab.status));
          }}
          aria-current={tab.status === active ? "page" : undefined}
          className={cn(
            "rounded-md px-2.5 py-1 text-sm",
            tab.status === active ? "bg-muted font-medium" : "text-muted-foreground hover:text-foreground",
          )}
        >
          {tab.label}
        </Link>
      ))}
    </nav>
  );
}
