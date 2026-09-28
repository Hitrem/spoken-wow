import { test } from "node:test";
import assert from "node:assert/strict";

import { localeEntries, lookupPath, packLua } from "./lookup.mjs";
import { pageChecksum } from "./naming.mjs";

test("English's lookup stays in the pack folder", () => {
  assert.match(lookupPath("enUS"), /addons\/SpokenBooksAudio\/Data\/Sounds\.lua$/);
});

test("a voiced page carries caption text from its current language row", () => {
  const lua = packLua("esMX", [{ pageId: 15, file: "15", durationSec: 2.5,
    text: "<H1>Registro</H1>Hola.$BAdiós." }]);
  assert.match(lua, /text = "Registro Hola\. Adiós\."/);
});

test("another language's is build output, never in English's folder", () => {
  const path = lookupPath("esMX");
  assert.match(path, /build\/books\/esMX\/Data\/Sounds\.lua$/);
  assert.doesNotMatch(path, /addons\//);
});

const CLIPS = [{ pageId: 15, file: "15", durationSec: 2.5 }];
const PAGES = [
  { pageId: 15, bookId: 15, pageNumber: 1, ownerKind: "object", ownerIds: [7, 8], text: "Hola." },
  { pageId: 16, bookId: 15, pageNumber: 2, ownerKind: "item", ownerIds: [9], text: "Adiós." },
];
const NAMES = [
  { kind: "gameobject", entityId: "7", name: "Registro" },
  { kind: "gameobject", entityId: "8", name: "Registro del pueblo" },
  { kind: "item", entityId: "7", name: "Not this one" },
];

test("a translated page is listed under each name its owners have in that language", () => {
  const [first, second] = localeEntries(PAGES, NAMES);
  assert.deepEqual(first.titles, ["Registro", "Registro del pueblo"]);
  assert.deepEqual(second.titles, []);
});

test("a language's pack carries its index, keyed on its own titles and words", () => {
  const lua = packLua("esMX", CLIPS, localeEntries(PAGES, NAMES));
  assert.match(lua, /language = "esMX"/);
  assert.ok(lua.includes(`["Registro del pueblo"] = {`));
  assert.ok(lua.includes(`[1] = { [${pageChecksum("Hola.")}] = 15 }`));
});

test("a page whose owners have no name there is still found by its words", () => {
  const lua = packLua("esMX", CLIPS, localeEntries(PAGES, NAMES));
  const loose = lua.slice(lua.indexOf("loose = {"));
  assert.ok(loose.includes(`[${pageChecksum("Adiós.")}] = 16`));
});

test("a page listed under two names is not ambiguous with itself", () => {
  const lua = packLua("esMX", CLIPS, localeEntries(PAGES, NAMES));
  const loose = lua.slice(lua.indexOf("loose = {"));
  assert.ok(loose.includes(`[${pageChecksum("Hola.")}] = 15`));
});

test("English's pack carries no index: the addon's own is English", () => {
  const lua = packLua("enUS", CLIPS);
  assert.doesNotMatch(lua, /index = \{|loose = \{/);
  assert.match(lua, /\[15\] = \{ file = "15", len = 2\.5 \},\n\t\},\n\}\n/);
});
