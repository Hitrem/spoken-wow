import type { Metadata } from "next";
import { headers } from "next/headers";
import { notFound } from "next/navigation";

import ContributionsTabs from "@/components/ContributionsTabs";
import NpcEditor from "@/components/NpcEditor";
import { auth } from "@/lib/auth";
import { summaryFromResolution } from "@/lib/contributions/speaker";
import { facets } from "@/lib/facets";
import { viewerOf } from "@/lib/grants/store";
import { BASE_LANG } from "@/lib/lang";
import { pageLang } from "@/lib/lang-server";
import { listResolutions } from "@/lib/npc/store";
import { can } from "@/lib/permissions";
import { Contained, Wide } from "@/components/Width";

export const metadata: Metadata = { title: "NPCs · Spoken" };

// Other people answer these NPCs too, from here and from the triage queue.
export const dynamic = "force-dynamic";

/**
 * Every NPC the contributions have named, and who voices each.
 *
 * The same answers the triage queue's NPC column gives, one row per NPC rather than per
 * contribution, so an NPC can be found and corrected without the row that named it being in
 * whatever the queue is filtered to. Gated as api/contributions/npc is, which it writes through:
 * an NPC's voice is the same in every language.
 */
export default async function Page({ params }: { params: Promise<{ lang: string }> }) {
  const lang = await pageLang(params);
  const session = await auth.api.getSession({ headers: await headers() });
  if (!session || !can(await viewerOf(session), "regenerate", BASE_LANG)) notFound();

  const { flavorScopes } = await facets();
  const npcs = (await listResolutions()).map((row) => summaryFromResolution(row, flavorScopes));

  return (
    <main className="pt-6 pb-24">
      <Contained>
        <h1 className="text-xl font-semibold">Contributions</h1>
        <p className="text-muted-foreground mt-1 mb-5 text-sm">
          Every NPC a contribution has named, and who voices them. An answer here settles every
          line that NPC speaks.
        </p>
        <ContributionsTabs lang={lang} active="npcs" showNpcs />
      </Contained>
      <Wide>
        <NpcEditor initial={npcs} flavorScopes={flavorScopes} />
      </Wide>
    </main>
  );
}
