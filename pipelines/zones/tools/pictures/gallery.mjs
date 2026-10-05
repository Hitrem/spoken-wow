#!/usr/bin/env node
// Downloads every picture on each zone's and area's warcraft.wiki.gg page into a folder per
// place, to choose from by eye: <out>/<Zone>/<Place>/<wiki file name>. The picture fetch.mjs chose
// is prefixed "[picked] ". Only icons, animations and pictures under MIN_WIDTH wide are left out.
// A choice goes into choices.json as { "<manifest id>": "File:<wiki file name>" }.
//
// Usage: node tools/pictures/gallery.mjs [out]   (default: ~/Desktop/Zone picture choices)

import { readFile, writeFile, mkdir, copyFile } from "node:fs/promises";
import { existsSync } from "node:fs";
import { homedir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

import { CACHE, ROOT, USER_AGENT, THROTTLE_MS, sleep, readJson } from "../lib/wiki.mjs";
import { entries, pageImages, imageInfo } from "./fetch.mjs";

const HERE = dirname(fileURLToPath(import.meta.url));
const OUT = process.argv[2] || join(homedir(), "Desktop", "Zone picture choices");
const STORE = join(CACHE, "pictures", "gallery");
const MIN_WIDTH = 300;

const safe = (s) => s.replace(/[<>:"/\\|?*]/g, "").replace(/\s+/g, " ").trim();

async function main() {
  const all = await entries();
  const manifest = (await readJson(join(HERE, "manifest.json"))).pictures;
  const zones = await readFile(join(ROOT, "addons/Spoken_Zones/Data/enUS/Zones.lua"), "utf8");
  const zoneName = new Map([...zones.matchAll(/\[(\d+)\] = \{\s*\n\s*name = "([^"]+)"/g)].map((m) => [Number(m[1]), m[2]]));

  const pages = await pageImages([...new Set(all.map((e) => e.title))]);
  const pictureFile = (f) => /\.(jpe?g|png|webp)$/i.test(f) && !/(^File:.*_\d\d\.png$|icon)/i.test(f);
  const files = [...new Set([...pages.values()].flatMap((p) => p.images.filter(pictureFile)))];
  console.log(`${files.length} pictures on ${pages.size} pages`);
  const info = await imageInfo(files);

  await mkdir(STORE, { recursive: true });
  let fetched = 0, placed = 0;
  for (const e of all) {
    const page = pages.get(e.title);
    if (!page) continue;
    const zone = safe(zoneName.get(e.parent) || String(e.parent));
    const place = e.id.startsWith("zone-") ? `${zone} (the zone)` : safe(e.title.replace(/ \(Classic\)$/, ""));
    const dir = join(OUT, zone, place);
    const picked = manifest[e.id]?.file;
    for (const file of page.images.filter(pictureFile)) {
      const i = info.get(file);
      if (!i || i.width < MIN_WIDTH) continue;
      const name = safe(file.replace(/^File:/, ""));
      const stored = join(STORE, name);
      if (!existsSync(stored)) {
        const res = await fetch(i.url, { headers: { "User-Agent": USER_AGENT } });
        await sleep(THROTTLE_MS);
        if (!res.ok) { console.warn(`\n  ${res.status} ${i.url}`); continue; }
        await writeFile(stored, Buffer.from(await res.arrayBuffer()));
        fetched++;
      }
      await mkdir(dir, { recursive: true });
      await copyFile(stored, join(dir, (file === picked ? "[picked] " : "") + name));
      placed++;
      process.stdout.write(`\r  downloaded ${fetched}, placed ${placed}`);
    }
  }
  process.stdout.write("\n");
  console.log(`done: ${OUT}`);
}

main().catch((err) => { console.error(err); process.exit(1); });
