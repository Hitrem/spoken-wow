#!/usr/bin/env node
// The sound packs, read off their store pages.
//
// A pack is a page under publishers/<group>/ whose frontmatter names a `section`. Every other
// page is an addon's. So the pages are the registry: which language has which pack, and which
// store project and GitHub tag it is released under. Adding a language is pages, not code --
// every build and release script asks this module rather than keeping a table of its own,
// which is what a case block per script per language turned into the moment there was a second
// language.
//
//   node scripts/lib/packs.mjs list <section> <lang>                     pack keys, or "-"
//   node scripts/lib/packs.mjs get <section> <lang> <pack|-> <field>     one field
//   node scripts/lib/packs.mjs changelog <file> <version> <release>      a pack's notes
//
// WHAT IS DERIVED AND WHAT IS WRITTEN. The folder and the release tag are rules, not fields:
// English's are the names players already have installed, and a language's are those plus its
// code. The page still writes `release:`, because descriptions.mjs links a Wago reader to it,
// and this checks the page agrees with the rule rather than trusting either.
import { readdirSync, readFileSync, statSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

import { BASE_LOCALE, CODES } from "../../pipelines/lib/locales.mjs";
import { parseFrontmatter } from "./frontmatter.mjs";

const ROOT = join(dirname(fileURLToPath(import.meta.url)), "../..");
export const PUBLISHERS_DIR = join(ROOT, "publishers");

export const SECTIONS = ["quests", "zones", "books"];

// tts_cli/factions.py PACK_SUFFIXES, for the four that ship. English's `all` is the meta addon,
// which is not a pack: its page carries no section.
const QUESTS_PACKS = { alliance: "Alliance", horde: "Horde", shared: "Shared", gossip: "Gossip" };
// A language may instead ship its quests as one pack holding every line: one folder is one answer
// to "which do I install", and a GitHub release takes a file up to 2 GB. CurseForge does not take
// one that size, so a language that goes there later is split into the four.
const LANGUAGE_QUESTS_PACKS = { ...QUESTS_PACKS, all: "All" };

function englishFolder(section, pack) {
  if (section === "zones") return "SpokenZonesAudio";
  if (section === "books") return "SpokenBooksAudio";
  return "SpokenQuestsAudio" + LANGUAGE_QUESTS_PACKS[pack];
}

function englishRelease(section, pack) {
  return section === "quests" ? `quests-audio-${pack}` : `${section}-audio`;
}

const NOT_A_PAGE = new Set(["README.md"]);

function pageFiles(dir) {
  const files = [];
  for (const group of readdirSync(dir).sort()) {
    const groupDir = join(dir, group);
    if (!statSync(groupDir).isDirectory()) continue;
    for (const file of readdirSync(groupDir).sort()) {
      if (file.endsWith(".md") && !NOT_A_PAGE.has(file)) files.push(join(group, file));
    }
  }
  return files;
}

function toPack(page, meta) {
  const fail = (why) => { throw new Error(`publishers/${page}: ${why}`); };
  const { section, lang } = meta;
  if (!SECTIONS.includes(section)) fail(`section '${section}' is not one of ${SECTIONS.join(", ")}`);
  if (!CODES.includes(lang)) fail(`lang '${lang}' is not one of ${CODES.join(", ")}`);

  const english = lang === BASE_LOCALE;
  const pack = meta.pack ?? null;
  const allowed = english ? QUESTS_PACKS : LANGUAGE_QUESTS_PACKS;
  if (section === "quests" && !(pack in allowed)) {
    fail(`a ${lang} quests pack needs pack: one of ${Object.keys(allowed).join(", ")}`);
  }
  if (section !== "quests" && pack !== null) fail(`only a quests pack has a pack key`);

  const version = meta.version ?? null;
  if (!english && !/^\d+\.\d+\.\d+$/.test(version ?? "")) {
    fail(`a ${lang} pack needs version: x.y.z (English's comes from its .toc)`);
  }
  if (english && version !== null) fail(`an English pack's version is its .toc's, not the page's`);

  const release = englishRelease(section, pack) + (english ? "" : `-${lang}`);
  if (meta.release !== release) fail(`release should be ${release}, not ${meta.release}`);

  // No `curseforge` until the project exists: a pack can go out on GitHub before it has one.
  for (const key of ["slug", "name"]) if (!meta[key]) fail(`missing '${key}'`);

  const folder = englishFolder(section, pack) + (english ? "" : `_${lang}`);
  return {
    page, section, lang, pack, version,
    curseforge: meta.curseforge ?? null, wago: meta.wago ?? null, release,
    slug: meta.slug, name: meta.name, folder,
    zip: english ? null : `${folder}-${version}.zip`,
    tag: english ? null : `${release}/v${version}`,
  };
}

export function loadPacks(dir = PUBLISHERS_DIR) {
  const packs = [];
  for (const page of pageFiles(dir)) {
    const { meta } = parseFrontmatter(readFileSync(join(dir, page), "utf8"), page);
    if (meta.section === undefined) continue;
    packs.push(toPack(page, meta));
  }
  const seen = new Map();
  for (const p of packs) {
    const key = `${p.section}/${p.lang}/${p.pack ?? "-"}`;
    if (seen.has(key)) throw new Error(`two pages for one pack (${key}): publishers/${seen.get(key)} and publishers/${p.page}`);
    seen.set(key, p.page);
  }
  return packs;
}

export function packsFor(section, lang, packs = loadPacks()) {
  return packs.filter((p) => p.section === section && p.lang === lang);
}

export function findPack(section, lang, pack, packs = loadPacks()) {
  const found = packsFor(section, lang, packs).find((p) => p.pack === (pack ?? null));
  if (!found) throw new Error(`no ${section} pack registered for ${lang}${pack ? ` (${pack})` : ""}`);
  return found;
}

// `## 1.0.0 — zones-audio-esMX`: a release tag ending in a language code. English headings
// name a kind (`— audio`, `— pack`) or nothing, never a tag, so this is how an English matcher
// steps over a language pack's notes that happen to share its version number.
const LANGUAGE_HEADING = /^## \S+ — [a-z]+(?:-[a-z]+)+-[a-z]{2}[A-Z]{2}(?:\s|$)/;

export function isLanguageHeading(line) {
  return LANGUAGE_HEADING.test(line);
}

export function changelogSection(text, version, release) {
  const lines = text.split("\n");
  const heading = new RegExp(`^## ${version.replace(/\./g, "\\.")} — ${release}(?:\\s|$)`);
  const starts = lines.flatMap((l, i) => (heading.test(l) ? [i] : []));
  if (starts.length === 0) throw new Error(`no "## ${version} — ${release}" section`);
  if (starts.length > 1) throw new Error(`two "## ${version} — ${release}" sections`);
  let end = lines.length;
  for (let i = starts[0] + 1; i < lines.length; i++) {
    if (lines[i].startsWith("## ")) { end = i; break; }
  }
  return lines.slice(starts[0], end).join("\n").trim();
}

function main([command, ...args]) {
  if (command === "list") {
    const [section, lang] = args;
    const packs = packsFor(section, lang);
    if (packs.length === 0) throw new Error(`no ${section} packs registered for ${lang}`);
    for (const p of packs) console.log(p.pack ?? "-");
  } else if (command === "get") {
    const [section, lang, pack, field] = args;
    const found = findPack(section, lang, pack === "-" ? null : pack);
    if (!(field in found)) throw new Error(`no field '${field}'`);
    console.log(found[field] ?? "");
  } else if (command === "changelog") {
    const [file, version, release] = args;
    process.stdout.write(changelogSection(readFileSync(file, "utf8"), version, release));
  } else {
    throw new Error("usage: packs.mjs list <section> <lang> | get <section> <lang> <pack|-> <field> | changelog <file> <version> <release>");
  }
}

if (process.argv[1] && fileURLToPath(import.meta.url) === process.argv[1]) {
  try {
    main(process.argv.slice(2));
  } catch (error) {
    console.error(`error: ${error.message}`);
    process.exit(1);
  }
}
