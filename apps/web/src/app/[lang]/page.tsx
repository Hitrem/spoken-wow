import type { Metadata } from "next";
import NextLink from "next/link";
import { Fragment } from "react";

import Link from "@/components/LocaleLink";
import { LOCALES, localeHref, type Lang } from "@/lib/lang";
import { pageLang } from "@/lib/lang-server";
import { languageStates } from "@/lib/languages/store";
import { packFor, PACKS, type Section } from "@/lib/packs";
import { cn } from "@/lib/utils";

export const metadata: Metadata = { title: "Spoken" };

const CURSEFORGE = "https://www.curseforge.com/wow/addons";
const WAGO = "https://addons.wago.io/addons";
const GITHUB_RELEASES = "https://github.com/rusty-key/spoken-wow/releases?q=";
const DISCORD = "https://discord.gg/HEGUgn6Yf";

/**
 * Discord's mark, from Simple Icons (CC0). Inline rather than from lucide-react, which
 * carries no brand icons. Filled with Discord's own blurple (#5865F2) from its brand kit.
 */
function DiscordIcon({ className }: { className?: string }) {
  return (
    <svg viewBox="0 0 24 24" fill="#5865F2" aria-hidden="true" className={className}>
      <path d="M20.317 4.3698a19.7913 19.7913 0 00-4.8851-1.5152.0741.0741 0 00-.0785.0371c-.211.3753-.4447.8648-.6083 1.2495-1.8447-.2762-3.68-.2762-5.4868 0-.1636-.3933-.4058-.8742-.6177-1.2495a.077.077 0 00-.0785-.037 19.7363 19.7363 0 00-4.8852 1.515.0699.0699 0 00-.0321.0277C.5334 9.0458-.319 13.5799.0992 18.0578a.0824.0824 0 00.0312.0561c2.0528 1.5076 4.0413 2.4228 5.9929 3.0294a.0777.0777 0 00.0842-.0276c.4616-.6304.8731-1.2952 1.226-1.9942a.076.076 0 00-.0416-.1057c-.6528-.2476-1.2743-.5495-1.8722-.8923a.077.077 0 01-.0076-.1277c.1258-.0943.2517-.1923.3718-.2914a.0743.0743 0 01.0776-.0105c3.9278 1.7933 8.18 1.7933 12.0614 0a.0739.0739 0 01.0785.0095c.1202.099.246.1981.3728.2924a.077.077 0 01-.0066.1276 12.2986 12.2986 0 01-1.873.8914.0766.0766 0 00-.0407.1067c.3604.698.7719 1.3628 1.225 1.9932a.076.076 0 00.0842.0286c1.961-.6067 3.9495-1.5219 6.0023-3.0294a.077.077 0 00.0313-.0552c.5004-5.177-.8382-9.6739-3.5485-13.6604a.061.061 0 00-.0312-.0286zM8.02 15.3312c-1.1825 0-2.1569-1.0857-2.1569-2.419 0-1.3332.9555-2.4189 2.157-2.4189 1.2108 0 2.1757 1.0952 2.1568 2.419 0 1.3332-.9555 2.4189-2.1569 2.4189zm7.9748 0c-1.1825 0-2.1569-1.0857-2.1569-2.419 0-1.3332.9554-2.4189 2.1569-2.4189 1.2108 0 2.1757 1.0952 2.1568 2.419 0 1.3332-.946 2.4189-2.1568 2.4189Z" />
    </svg>
  );
}

/**
 * The front door.
 *
 * Three sections, named by what they voice rather than by which project they came from: a
 * visitor does not know that one of these used to be at voiceover.rusty.one and another at
 * lore.rusty.one, and should not have to. Under them, every sound pack by language, and above
 * them the site itself in every language that is switched on.
 *
 * Each card carries the addon's own icon, the same art CurseForge and the in-game addon
 * list show, so somebody arriving from either recognises what they came for. They are the
 * exported SVGs from pipelines/*, copied into public/icons/ -- see the note there.
 *
 * The store links sit BELOW the card rather than inside it, and that is structural
 * rather than aesthetic: the card is one big anchor, and an anchor inside an anchor is
 * invalid HTML that browsers resolve by closing the outer one early.
 *
 * THREE CHANNELS, AND NOT EVERYTHING IS ON ALL OF THEM. The slugs are identical on CurseForge
 * and Wago, so one slug addresses both -- but a sound pack is hundreds of megabytes and Wago's
 * upload endpoint refuses a file that size, and most languages' packs have no CurseForge
 * project yet. Every addon and every pack has a GitHub release, so GitHub is the one link
 * every row carries. The link is the releases query rather than a tag, so it does not go
 * stale the next time the audio is built.
 */
/** An addon as it is offered: CurseForge always, Wago when it is there, GitHub by tag prefix. */
type Addon = { slug: string; label: string; wago?: boolean; release?: string };

/** The one-click install and the library every addon needs, above the three sections. */
const CORE: Addon[] = [
  // A meta addon of dependencies, which only an addon manager resolves: no GitHub release.
  { slug: "spoken", label: "Spoken Everything" },
  { slug: "spoken-player", label: "Spoken Player", wago: true, release: "spoken/" },
];

const SECTIONS: {
  key: Section;
  href: string;
  icon: string;
  title: string;
  blurb: string;
  detail: string;
  addon: Addon;
}[] = [
  {
    key: "quests",
    href: "/quests",
    icon: "/icons/quests.svg",
    title: "Quest dialogue",
    blurb:
      "Every line an NPC speaks when you take, hand in or ask about a quest, and the gossip " +
      "in between. Extracted from the game, voiced per race, gender and flavour.",
    detail: "17,507 lines · 54 voices",
    addon: { slug: "spoken-quests", label: "Spoken Quests", wago: true, release: "quests/" },
  },
  {
    key: "zones",
    href: "/zones",
    icon: "/icons/zones.svg",
    title: "Zone lore",
    blurb:
      "The prose the addon reads when you walk into a place, for every zone and subzone. " +
      "Written rather than extracted: scraped from the wiki, and correctable here.",
    detail: "1,353 lines · one narrator",
    addon: { slug: "spoken-zones", label: "Spoken Zones", wago: true, release: "zones/" },
  },
  {
    key: "books",
    href: "/books",
    icon: "/icons/books.svg",
    title: "Books and notes",
    blurb:
      "Every book, letter, note and plaque the game will show you, page by page. " +
      "Blizzard's words again, read by the narrator rather than by the NPC who hands them over.",
    detail: "1,191 pages · 404 books",
    addon: { slug: "spoken-books", label: "Spoken Books", wago: true, release: "books/" },
  },
];

/** The languages with at least one pack, in the site's order. */
const PACK_LANGS: Lang[] = LOCALES.map((locale) => locale.code).filter((code) =>
  PACKS.some((pack) => pack.lang === code),
);

const linkClass = "hover:text-foreground underline underline-offset-2";

function Dot() {
  return <span className="px-1.5">·</span>;
}

function External({ href, children }: { href: string; children: React.ReactNode }) {
  return (
    <a href={href} target="_blank" rel="noreferrer" className={linkClass}>
      {children}
    </a>
  );
}

/** One addon's name and its stores, on one line. */
function AddonRow({ addon }: { addon: Addon }) {
  return (
    <p className="text-muted-foreground">
      {addon.label}
      <Dot />
      <External href={`${CURSEFORGE}/${addon.slug}`}>CurseForge</External>
      {addon.wago && (
        <>
          <Dot />
          <External href={`${WAGO}/${addon.slug}`}>Wago</External>
        </>
      )}
      {addon.release && (
        <>
          <Dot />
          <External href={`${GITHUB_RELEASES}${encodeURIComponent(addon.release)}`}>GitHub</External>
        </>
      )}
    </p>
  );
}

export default async function Page({ params }: { params: Promise<{ lang: string }> }) {
  const lang = await pageLang(params);
  // One small query, and the only one this page makes. The header's switcher asks the same of
  // /api/languages in the browser; this list is for somebody who has not found the header yet,
  // so it shows only what is switched on, admin or not.
  const siteLangs = (await languageStates()).filter((state) => state.enabled).map((state) => state.code);

  return (
    <main className="mx-auto max-w-6xl px-5 pt-10 pb-24">
      <h1 className="text-2xl font-semibold">Spoken</h1>
      <p className="text-muted-foreground mt-2 max-w-2xl text-sm">
        Voiced dialogue, lore and text for World of Warcraft Classic. Browse and play every
        line the addons ship, search for the one you heard, and tell us when one is wrong.
      </p>
      <a
        href={DISCORD}
        target="_blank"
        rel="noreferrer"
        className="text-muted-foreground hover:text-foreground mt-3 inline-flex items-center gap-2 text-base font-medium transition-colors"
      >
        <DiscordIcon className="h-6 w-6" />
        Join us on Discord
      </a>

      {siteLangs.length > 1 && (
        <p className="text-muted-foreground mt-3 text-xs">
          Browse in
          {siteLangs.map((code, index) => (
            <Fragment key={code}>
              {index === 0 ? <span className="px-1.5" /> : <Dot />}
              {code === lang ? (
                <span className="text-foreground whitespace-nowrap">{LOCALES.find((l) => l.code === code)?.name}</span>
              ) : (
                // Plain next/link: LocaleLink would put the href in the page's language, and
                // these are the one set of links that leave it.
                <NextLink href={localeHref(code, "/")} className={cn(linkClass, "whitespace-nowrap")}>
                  {LOCALES.find((l) => l.code === code)?.name}
                </NextLink>
              )}
            </Fragment>
          ))}
        </p>
      )}

      <div className="mt-6 mb-8 text-xs">
        {CORE.map((addon) => (
          <AddonRow key={addon.slug} addon={addon} />
        ))}
        <p className="text-muted-foreground/70 mt-1">
          Spoken Everything installs every addon and the English audio in one go. Spoken Player
          is what each of them runs on; an addon manager fetches it for you, a manual install
          needs it alongside.
        </p>
      </div>

      {/* Three columns once there is room, so the third card does not sit alone on a row
          of its own. Two below that, one on a phone.

          items-start, so a cell whose links wrap to a second line does not stretch its
          neighbours: the cards stay the same height as each other and the link rows below
          them are free to differ. */}
      <div className="grid items-start gap-4 sm:grid-cols-2 lg:grid-cols-3">
        {SECTIONS.map((section) => (
          <div key={section.href}>
            <Link
              href={section.href}
              className="hover:bg-accent block h-full rounded-lg border p-5 transition-colors"
            >
              {/* Plain img, not next/image: these are fixed-size SVGs, which the image
                  optimiser passes through untouched, and the standalone server would want
                  sharp installed to do even that. */}
              <img
                src={section.icon}
                alt=""
                width={40}
                height={40}
                className="mb-3 h-10 w-10"
              />
              <h2 className="font-medium">{section.title}</h2>
              <p className="text-muted-foreground mt-1 text-sm">{section.blurb}</p>
              <p className="text-muted-foreground mt-3 text-xs">{section.detail}</p>
            </Link>

            <div className="mt-2 px-1 text-xs">
              <AddonRow addon={section.addon} />
            </div>
          </div>
        ))}
      </div>

      <h2 className="mt-12 font-medium">Audio packs</h2>
      <p className="text-muted-foreground mt-1 mb-4 max-w-2xl text-sm">
        Each addon speaks only with its sound pack installed beside it, one per language. The
        English quest pack on CurseForge pulls in four smaller ones (Alliance, Horde, Shared
        and Gossip), listed on its page; GitHub has it as one download.
      </p>

      {/* A table on a wide screen; on a phone each language becomes a block of its own with
          the section named beside each cell, so the page never scrolls sideways. The column
          headings are the only thing hidden on a phone, and the inline ones the only thing
          hidden above it. */}
      <div className="text-xs">
        <div className="text-muted-foreground hidden border-b pb-2 sm:grid sm:grid-cols-[10rem_repeat(3,1fr)]">
          <span>Language</span>
          {SECTIONS.map((section) => (
            <span key={section.key}>{section.title}</span>
          ))}
        </div>
        {PACK_LANGS.map((code) => (
          <div
            key={code}
            className={cn(
              "grid gap-1 border-b py-2 sm:grid-cols-[10rem_repeat(3,1fr)] sm:gap-0",
              code === lang && "bg-accent/50 -mx-2 rounded px-2",
            )}
          >
            <span className="font-medium">{LOCALES.find((l) => l.code === code)?.name}</span>
            {SECTIONS.map((section) => {
              const pack = packFor(section.key, code);
              return (
                <span key={section.key} className="text-muted-foreground">
                  <span className="sm:hidden">{section.title}: </span>
                  {pack ? (
                    <>
                      {pack.curseforge && (
                        <>
                          <External href={`${CURSEFORGE}/${pack.curseforge}`}>CurseForge</External>
                          <Dot />
                        </>
                      )}
                      <External href={`${GITHUB_RELEASES}${encodeURIComponent(pack.release)}`}>
                        GitHub
                      </External>
                    </>
                  ) : (
                    <span className="text-muted-foreground/50">not yet</span>
                  )}
                </span>
              );
            })}
          </div>
        ))}
      </div>
    </main>
  );
}
