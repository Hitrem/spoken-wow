import { mkdtempSync, mkdirSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import assert from "node:assert/strict";

import { announcement } from "./announce.mjs";

// A repo in a temp directory: publishers/ pages as [group, file, frontmatter], and one
// docs/<section>/CHANGELOG.md per entry of `changelogs`.
function repo(pages, changelogs) {
  const dir = mkdtempSync(join(tmpdir(), "announce-"));
  for (const [group, file, fields] of pages) {
    mkdirSync(join(dir, "publishers", group), { recursive: true });
    const lines = Object.entries(fields).map(([k, v]) => `${k}: ${v}`);
    writeFileSync(join(dir, "publishers", group, file), `---\n${lines.join("\n")}\n---\n\nBody.\n`);
  }
  for (const [section, text] of Object.entries(changelogs)) {
    mkdirSync(join(dir, "docs", section), { recursive: true });
    writeFileSync(join(dir, "docs", section, "CHANGELOG.md"), text);
  }
  const dirs = { publishersDir: join(dir, "publishers"), docsDir: join(dir, "docs") };
  return (tag) => announcement(tag, dirs);
}

const pages = [
  ["zones", "addon.md", { slug: "spoken-zones", name: "Spoken Zones" }],
  ["zones", "a.md", { section: "zones", lang: "enUS", release: "zones-audio",
    slug: "spoken-zones-audio", name: "Spoken Zones Audio" }],
  ["zones", "b.md", { section: "zones", lang: "frFR", version: "2.0.0", release: "zones-audio-frFR",
    slug: "spoken-zones-audio-frfr", name: "Spoken Zones Audio: French" }],
  ["quests", "player.md", { slug: "spoken-quests", name: "Spoken Quests" }],
  ["quests", "h.md", { section: "quests", lang: "enUS", pack: "horde", release: "quests-audio-horde",
    slug: "spoken-quests-audio-horde", name: "Spoken Quests Audio: Horde" }],
];

const zones = `# Changelog

## 2.0.1 — audio — 2026-09-18

- Audio notes.

## 2.0.1 — 2026-09-18

- Addon notes.

## 2.0.0 — zones-audio-frFR — 2026-09-26

- French notes.
`;

const quests = `## 2.1.0 — sound packs

Pack notes.

## 2.1.0 — player

Player notes.
`;

const run = repo(pages, { zones, quests });

test("an addon takes the store page's name and its own heading, not its audio's", () => {
  assert.deepEqual(run("zones/v2.0.1"), { name: "Spoken Zones", version: "2.0.1", notes: "- Addon notes." });
});

test("English audio takes the heading its kind word marks", () => {
  assert.equal(run("zones-audio/v2.0.1").notes, "- Audio notes.");
  assert.equal(run("quests-audio-horde/v2.1.0").notes, "Pack notes.");
  assert.equal(run("quests/v2.1.0").notes, "Player notes.");
});

test("a language pack takes its tag's heading, and the heading line is dropped", () => {
  assert.deepEqual(run("zones-audio-frFR/v2.0.0"),
    { name: "Spoken Zones Audio: French", version: "2.0.0", notes: "- French notes." });
});

test("a version with no changelog section still announces, without notes", () => {
  assert.deepEqual(run("zones/v9.9.9"), { name: "Spoken Zones", version: "9.9.9", notes: null });
});

test("a tag with no store page behind it is skipped", () => {
  assert.ok(run("legacy/quests/v1.0.0").skip);
  assert.ok(run("not-a-release").skip);
});
