"use client";

import { useState } from "react";

import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Popover, PopoverContent, PopoverTrigger } from "@/components/ui/popover";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import type { GrantRow } from "@/lib/grants/store";
import { CODES, isLang, langName, type Lang } from "@/lib/lang";
import { CAPABILITIES, canGrant, capabilityLabel, type Capability, type Viewer } from "@/lib/permissions";

/**
 * One person's languages: what they hold in each, every capability removable, and a way to
 * add another.
 *
 * Offers only what `viewer` may hand out (lib/permissions.ts `canGrant`), so a language
 * admin sees edit and regenerate in their own languages and nothing else. The server
 * refuses anything else whatever this offers.
 */
export default function GrantCell({
  grants,
  viewer,
  busy,
  onGrant,
  onRevoke,
}: {
  /** This person's grants, as far as the viewer may see them. */
  grants: readonly GrantRow[];
  viewer: Viewer;
  busy: boolean;
  onGrant: (lang: Lang, capability: Capability) => Promise<boolean>;
  onRevoke: (lang: Lang, capability: Capability) => void;
}) {
  const [open, setOpen] = useState(false);
  const byLang = new Map<Lang, Capability[]>();
  for (const grant of grants) {
    if (!isLang(grant.lang)) continue;
    const held = byLang.get(grant.lang);
    if (held) held.push(grant.capability);
    else byLang.set(grant.lang, [grant.capability]);
  }
  const offer = (lang: Lang) =>
    CAPABILITIES.filter((cap) => canGrant(viewer, cap, lang) && !byLang.get(lang)?.includes(cap));

  return (
    <div className="flex flex-wrap items-center gap-x-3 gap-y-1">
      {[...byLang].map(([lang, capabilities]) => (
        <span key={lang} className="flex items-center gap-1">
          <span className="text-muted-foreground text-xs">{langName(lang)}</span>
          {capabilities.map((capability) => {
            const removable = canGrant(viewer, capability, lang);
            return (
              <Badge key={capability} variant="outline" className={removable ? "pr-0.5" : undefined}>
                {capabilityLabel(capability)}
                {removable ? (
                  <button
                    type="button"
                    disabled={busy}
                    aria-label={`Remove ${capabilityLabel(capability)} in ${langName(lang)}`}
                    className="text-muted-foreground hover:text-foreground rounded-full px-1 disabled:opacity-50"
                    onClick={() => onRevoke(lang, capability)}
                  >
                    ×
                  </button>
                ) : null}
              </Badge>
            );
          })}
        </span>
      ))}
      {CODES.some((lang) => offer(lang).length > 0) ? (
        <Popover open={open} onOpenChange={setOpen}>
          <PopoverTrigger asChild>
            <Button variant="ghost" size="xs" disabled={busy}>
              + Grant
            </Button>
          </PopoverTrigger>
          {/* Mounted only while open, so the choice starts fresh each time. */}
          <PopoverContent align="start" className="w-auto">
            <GrantPicker
              offer={offer}
              busy={busy}
              onPick={(lang, capability) =>
                void onGrant(lang, capability).then((ok) => {
                  if (ok) setOpen(false);
                })
              }
            />
          </PopoverContent>
        </Popover>
      ) : null}
    </div>
  );
}

/**
 * A language, a capability in it, and a button: what every grant is made from.
 *
 * `offer` says what may be granted in each language; languages it offers nothing in are
 * left out, and changing the language picks the first thing offered there.
 */
export function GrantPicker({
  offer,
  busy,
  onPick,
  children,
}: {
  offer: (lang: Lang) => readonly Capability[];
  busy: boolean;
  onPick: (lang: Lang, capability: Capability) => void;
  /** Anything to put before the selects, such as an email field; the whole is one form. */
  children?: React.ReactNode;
}) {
  const langs = CODES.filter((code) => offer(code).length > 0);
  const [lang, setLang] = useState(langs[0]);
  const [capability, setCapability] = useState(lang && offer(lang)[0]);

  return (
    <form
      className="flex flex-wrap items-center gap-2"
      onSubmit={(event) => {
        event.preventDefault();
        if (lang && capability) onPick(lang, capability);
      }}
    >
      {children}
      <Select
        value={lang}
        onValueChange={(value) => {
          setLang(value as Lang);
          setCapability(offer(value as Lang)[0]);
        }}
      >
        <SelectTrigger className="w-40" aria-label="Language">
          <SelectValue />
        </SelectTrigger>
        <SelectContent>
          {langs.map((code) => (
            <SelectItem key={code} value={code}>
              {langName(code)}
            </SelectItem>
          ))}
        </SelectContent>
      </Select>
      <Select value={capability} onValueChange={(value) => setCapability(value as Capability)}>
        <SelectTrigger className="w-36" aria-label="Capability">
          <SelectValue />
        </SelectTrigger>
        <SelectContent>
          {(lang ? offer(lang) : []).map((cap) => (
            <SelectItem key={cap} value={cap}>
              {capabilityLabel(cap)}
            </SelectItem>
          ))}
        </SelectContent>
      </Select>
      <Button type="submit" size="sm" disabled={busy || !lang || !capability}>
        Grant
      </Button>
    </form>
  );
}
