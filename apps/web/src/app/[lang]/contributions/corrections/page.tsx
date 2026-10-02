import type { Metadata } from "next";
import { headers } from "next/headers";
import { notFound } from "next/navigation";

import ContributionsTabs from "@/components/ContributionsTabs";
import CorrectionTable, { type CorrectionRow } from "@/components/CorrectionTable";
import { auth } from "@/lib/auth";
import { clientOf } from "@/lib/contributions/client";
import { readable } from "@/lib/contributions/compare";
import { isStatus, type ContributionStatus } from "@/lib/contributions/contributions";
import { lineStates, tabOf } from "@/lib/contributions/known";
import { listContributions } from "@/lib/contributions/store";
import { questFor } from "@/lib/contributions/triage";
import { viewerOf } from "@/lib/grants/store";
import { BASE_LANG } from "@/lib/lang";
import { pageLang } from "@/lib/lang-server";
import { can } from "@/lib/permissions";
import { Contained, Wide } from "@/components/Width";

export const metadata: Metadata = { title: "Corrections · Spoken" };

// Read against a queue other people are resolving rows in, as the triage page is.
export const dynamic = "force-dynamic";

/**
 * Contributions for a quest moment the corpus already has, whose text says something else: the
 * line as the corpus has it and as the player's client showed it, side by side.
 *
 * Gated as the triage page is -- the rows are the same table's. Accept is not offered: accepting
 * a quests row only ever writes a line that is missing (accept.ts), so here it would change
 * nothing. Taking a correction is the explorer's text edit on the line, linked from each row;
 * dismissing one is the same reject the triage page sends.
 */
export default async function Page({
  params,
  searchParams,
}: {
  params: Promise<{ lang: string }>;
  searchParams: Promise<{ status?: string }>;
}) {
  const lang = await pageLang(params);
  const session = await auth.api.getSession({ headers: await headers() });
  const viewer = await viewerOf(session);
  if (!session || !can(viewer, "edit", lang)) notFound();

  const { status: rawStatus } = await searchParams;
  const status: ContributionStatus | "all" = isStatus(rawStatus)
    ? rawStatus
    : rawStatus === "all"
      ? "all"
      : "new";

  const listed = (await listContributions(status, lang)).filter((row) => row.source === "quests");
  const states = await lineStates(listed);

  // Only what crosses into the client component, as page.tsx's ContributionRow projection says.
  const rows: CorrectionRow[] = listed.flatMap((row, index) => {
    const state = states[index];
    if (state.kind !== "changed" || tabOf(row.status, state) !== "corrections") return [];
    const quest = questFor(row);
    return [
      {
        id: row.id,
        lineId: state.lineId,
        quest: quest === "gossip" ? null : quest,
        client: clientOf(row.build),
        locale: row.locale,
        count: row.count,
        createdAt: row.createdAt,
        status: row.status,
        before: readable(state.current),
        after: row.text ?? "",
        body: row.body,
      },
    ];
  });

  return (
    <main className="pt-6 pb-24">
      <Contained>
        <h1 className="text-xl font-semibold">Contributions</h1>
        <p className="text-muted-foreground mt-1 mb-5 text-sm">
          Lines the corpus already has, sent back with different text -- usually the game
          rewording a quest since the corpus was extracted. Take a correction by editing the line
          in the explorer; dismiss one that is wrong.
        </p>
        <ContributionsTabs
          lang={lang}
          active="corrections"
          showNpcs={can(viewer, "regenerate", BASE_LANG)}
        />
      </Contained>
      <Wide>
        <CorrectionTable initial={rows} status={status} />
      </Wide>
    </main>
  );
}
