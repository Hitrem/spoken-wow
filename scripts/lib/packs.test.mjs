import { mkdtempSync, mkdirSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import assert from "node:assert/strict";

import {
  changelogSection, findPack, isLanguageHeading, loadPacks, packsFor,
} from "./packs.mjs";

// A publishers/ tree in a temp directory, one page per entry: [group, file, frontmatter].
function tree(pages) {
  const dir = mkdtempSync(join(tmpdir(), "packs-"));
  for (const [group, file, fields] of pages) {
    mkdirSync(join(dir, group), { recursive: true });
    const lines = Object.entries(fields).map(([k, v]) => `${k}: ${v}`);
    writeFileSync(join(dir, group, file), `---\n${lines.join("\n")}\n---\n\nBody.\n`);
  }
  return dir;
}

const zonesEn = ["zones", "a.md", { section: "zones", lang: "enUS", curseforge: "1636532",
  wago: "b6mvD9KP", release: "zones-audio", slug: "spoken-zones-audio", name: "Spoken Zones Audio" }];
const zonesMx = ["zones", "b.md", { section: "zones", lang: "esMX", version: "1.0.0",
  curseforge: "1711067", release: "zones-audio-esMX", slug: "spoken-zones-audio-esmx",
  name: "Spoken Zones Audio: Spanish (AL)" }];
const hordeEn = ["quests", "h.md", { section: "quests", lang: "enUS", pack: "horde",
  curseforge: "1660198", wago: "vNAg3OKo", release: "quests-audio-horde",
  slug: "spoken-quests-audio-horde", name: "Spoken Quests Audio: Horde" }];
const addonPage = ["zones", "addon.md", { curseforge: "1636521", slug: "spoken-zones",
  name: "Spoken Zones" }];

test("English packs keep today's folders and carry no version, zip or tag", () => {
  const packs = loadPacks(tree([zonesEn, hordeEn, addonPage]));
  assert.equal(findPack("zones", "enUS", null, packs).folder, "SpokenZonesAudio");
  const horde = findPack("quests", "enUS", "horde", packs);
  assert.equal(horde.folder, "SpokenQuestsAudioHorde");
  assert.equal(horde.version, null);
  assert.equal(horde.zip, null);
  assert.equal(horde.tag, null);
});

test("a language pack gets English's folder plus its code, and a zip and tag from its version", () => {
  const mx = findPack("zones", "esMX", null, loadPacks(tree([zonesEn, zonesMx])));
  assert.equal(mx.folder, "SpokenZonesAudio_esMX");
  assert.equal(mx.zip, "SpokenZonesAudio_esMX-1.0.0.zip");
  assert.equal(mx.tag, "zones-audio-esMX/v1.0.0");
  assert.equal(mx.wago, null);
});

test("pages without a section are addons, not packs", () => {
  assert.deepEqual(packsFor("zones", "enUS", loadPacks(tree([addonPage]))), []);
});

test("packsFor lists only that section and language", () => {
  const packs = loadPacks(tree([zonesEn, zonesMx, hordeEn]));
  assert.deepEqual(packsFor("zones", "esMX", packs).map((p) => p.folder), ["SpokenZonesAudio_esMX"]);
  assert.deepEqual(packsFor("quests", "esMX", packs), []);
});

test("findPack names what it could not find", () => {
  assert.throws(() => findPack("books", "deDE", null, loadPacks(tree([zonesEn]))),
    /no books pack registered for deDE/);
});

for (const [why, page, message] of [
  ["a language pack without a version", ["zones", "x.md", { ...zonesMx[2], version: undefined }], /version/],
  ["a code that is not a language", ["zones", "x.md", { ...zonesMx[2], lang: "esXX" }], /esXX/],
  ["a quests pack without a pack key", ["quests", "x.md", { ...hordeEn[2], pack: undefined }], /pack/],
  ["a zones page with a pack key", ["zones", "x.md", { ...zonesEn[2], pack: "horde" }], /pack/],
  ["a release tag off the rule", ["zones", "x.md", { ...zonesMx[2], release: "zones-esMX" }], /zones-audio-esMX/],
  ["an unknown section", ["zones", "x.md", { ...zonesEn[2], section: "maps" }], /maps/],
]) {
  test(`rejects ${why}`, () => {
    const fields = Object.fromEntries(Object.entries(page[2]).filter(([, v]) => v !== undefined));
    assert.throws(() => loadPacks(tree([[page[0], page[1], fields]])), message);
  });
}

test("rejects two pages for one pack", () => {
  assert.throws(() => loadPacks(tree([zonesMx, ["zones", "c.md", zonesMx[2]]])), /two pages/);
});

test("a language heading is told from an English one", () => {
  assert.equal(isLanguageHeading("## 1.0.0 — zones-audio-esMX — 2026-09-30"), true);
  assert.equal(isLanguageHeading("## 2.0.0 — quests-audio-horde-deDE"), true);
  assert.equal(isLanguageHeading("## 2.1.0 — audio — 2026-09-18"), false);
  assert.equal(isLanguageHeading("## 2.1.0 — 2026-09-21"), false);
  assert.equal(isLanguageHeading("## 0.3.3 — 2026-08-19 (sound packs)"), false);
});

const CHANGELOG = `# Changelog

## 2.1.0 — books-audio-esMX — 2026-10-01

- Spanish.

## 2.1.0 — 2026-09-21

- English.
`;

test("changelogSection takes exactly the language pack's section", () => {
  assert.equal(changelogSection(CHANGELOG, "2.1.0", "books-audio-esMX"),
    "## 2.1.0 — books-audio-esMX — 2026-10-01\n\n- Spanish.");
  assert.throws(() => changelogSection(CHANGELOG, "2.1.0", "books-audio-deDE"), /no "## 2.1.0 — books-audio-deDE"/);
  assert.throws(() => changelogSection(CHANGELOG + "\n## 2.1.0 — books-audio-esMX\n", "2.1.0", "books-audio-esMX"), /two/);
});

test("a language may ship its quests as one All pack, and English may not", () => {
  const allFr = ["quests", "fr.md", { section: "quests", lang: "frFR", pack: "all",
    version: "2.0.0", release: "quests-audio-all-frFR", slug: "spoken-quests-audio-all-frfr",
    name: "Spoken Quests Audio: French" }];
  const fr = findPack("quests", "frFR", "all", loadPacks(tree([allFr])));
  assert.equal(fr.folder, "SpokenQuestsAudioAll_frFR");
  assert.equal(fr.tag, "quests-audio-all-frFR/v2.0.0");
  assert.equal(fr.curseforge, null);

  const allEn = ["quests", "en.md", { section: "quests", lang: "enUS", pack: "all",
    curseforge: "1", release: "quests-audio-all", slug: "s", name: "n" }];
  assert.throws(() => loadPacks(tree([allEn])), /enUS quests pack needs pack/);
});
