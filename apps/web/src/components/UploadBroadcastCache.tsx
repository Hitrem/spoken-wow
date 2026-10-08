"use client";

/**
 * Sending the game's text cache: the BroadcastText rows in Cache/ADB/<locale>/DBCache.bin.
 *
 * Read in the browser (lib/broadcast/cache.ts); only the rows are sent. Several files at once,
 * because each one holds only the texts of a session or two: the client keeps a
 * DBCache.bin<n>.tmp per session beside the main file.
 *
 * The language is asked for rather than guessed: nothing in the file says which it is, only
 * the folder it came from.
 */
import Link from "next/link";
import { useRef, useState } from "react";

import { Button } from "@/components/ui/button";
import { parseBroadcastCache, type BroadcastCache } from "@/lib/broadcast/cache";
import { LOCALES, type Lang } from "@/lib/lang";

const CLIENT_LOCALES = LOCALES.filter((locale) => !("client" in locale && locale.client === false));

type Loaded = { name: string; cache: BroadcastCache }[];
type Sent = { texts: number; added: number; changed: number };

export default function UploadBroadcastCache({ signedIn, lang }: { signedIn: boolean; lang: Lang }) {
  const [locale, setLocale] = useState<Lang>(lang);
  const [loaded, setLoaded] = useState<Loaded>([]);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [sent, setSent] = useState<Sent | null>(null);
  const [dragging, setDragging] = useState(false);
  const input = useRef<HTMLInputElement>(null);

  if (!signedIn) {
    return (
      <p className="text-sm">
        <Link href="/login" className="underline">
          Sign in
        </Link>{" "}
        to send a cache.
      </p>
    );
  }

  async function read(files: FileList | null) {
    setError(null);
    setSent(null);
    if (!files?.length) return;
    const next: Loaded = [];
    const unreadable: string[] = [];
    for (const file of [...files]) {
      try {
        next.push({ name: file.name, cache: parseBroadcastCache(await file.arrayBuffer()) });
      } catch {
        unreadable.push(file.name);
      }
    }
    setLoaded(next.filter((file) => file.cache.texts.length > 0));
    if (unreadable.length) setError(`Not a DBCache file: ${unreadable.join(", ")}`);
    else if (next.every((file) => file.cache.texts.length === 0)) {
      setError("Those files hold no NPC text. Talk to a few NPCs, log out, and pick them again.");
    }
  }

  async function send() {
    setBusy(true);
    setError(null);
    const total: Sent = { texts: 0, added: 0, changed: 0 };
    // One request per file: each carries its own client build, which decides whose text wins.
    for (const { cache } of loaded) {
      const response = await fetch("/api/broadcast-text", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ lang: locale, build: cache.build, texts: cache.texts }),
      }).catch(() => null);
      const body = await response?.json().catch(() => null);
      if (!response?.ok) {
        setError(body?.error ?? "That did not go through. Try again in a minute.");
        setBusy(false);
        return;
      }
      total.texts += body.texts;
      total.added += body.added;
      total.changed += body.changed;
    }
    setBusy(false);
    setLoaded([]);
    setSent(total);
  }

  const count = new Set(loaded.flatMap((file) => file.cache.texts.map((text) => text.id))).size;

  return (
    <div className="flex max-w-xl flex-col gap-4">
      <label className="flex items-center gap-2 text-sm">
        Game language
        <select
          value={locale}
          onChange={(event) => setLocale(event.target.value as Lang)}
          className="bg-background rounded border px-2 py-1"
        >
          {CLIENT_LOCALES.map((option) => (
            <option key={option.code} value={option.code}>
              {option.name} ({option.code})
            </option>
          ))}
        </select>
      </label>

      <div
        role="button"
        tabIndex={0}
        onClick={() => input.current?.click()}
        onKeyDown={(event) => {
          if (event.key === "Enter" || event.key === " ") {
            event.preventDefault();
            input.current?.click();
          }
        }}
        onDragOver={(event) => {
          event.preventDefault();
          setDragging(true);
        }}
        onDragLeave={() => setDragging(false)}
        onDrop={(event) => {
          event.preventDefault();
          setDragging(false);
          void read(event.dataTransfer.files);
        }}
        className={
          "flex cursor-pointer flex-col items-center gap-2 rounded-lg border-2 border-dashed px-6 py-8 text-center text-sm transition-colors outline-none focus-visible:ring-3 " +
          (dragging ? "border-primary bg-muted" : "border-muted-foreground/40 hover:border-muted-foreground hover:bg-muted/50")
        }
      >
        <strong>{loaded.length ? `${loaded.length} files, ${count} texts` : "Drop the DBCache files here"}</strong>
        <span className="text-muted-foreground">or click to choose them</span>
        <input
          ref={input}
          type="file"
          multiple
          onChange={(event) => void read(event.target.files)}
          className="hidden"
        />
      </div>

      {error ? (
        <p role="alert" className="text-sm text-red-400">
          {error}
        </p>
      ) : null}

      {sent ? (
        <p role="status" className="rounded border p-4 text-sm">
          Got {sent.texts} texts — {sent.added} new, {sent.changed} updated. Thank you.
        </p>
      ) : null}

      {loaded.length ? (
        <div>
          <Button onClick={() => void send()} disabled={busy}>
            {busy ? "Sending…" : `Send ${count} texts as ${locale}`}
          </Button>
        </div>
      ) : null}
    </div>
  );
}
