import { test } from "node:test";
import assert from "node:assert/strict";

import { normaliseText, spokenText, isGeneratable, spokenWithTitle } from "./text.mjs";

test("CRLF becomes a newline", () => {
  assert.equal(normaliseText("Ola Morgan,\r\n\r\nOs negocios"), "Ola Morgan,\n\nOs negocios");
});

test("$B and $b are newlines, whatever their case", () => {
  assert.equal(normaliseText("Line one$BLine two$bLine three"), "Line one\nLine two\nLine three");
});

test("trailing whitespace on a line goes, blank runs collapse to one blank line", () => {
  assert.equal(normaliseText("One   \n\n\n\nTwo\n\n"), "One\n\nTwo");
});

test("spoken text drops the HTML the signed pages carry", () => {
  assert.equal(spokenText("<HTML><BODY><H1>Ledger</H1>Three crates.</BODY></HTML>"), "Ledger Three crates.");
});

test("spoken text keeps ordinary prose untouched apart from newlines", () => {
  assert.equal(spokenText("Dear sir,\n\nThe rains have come."), "Dear sir, The rains have come.");
});

test("an empty page is not generatable", () => {
  assert.deepEqual(isGeneratable(""), { generatable: false, skipReason: "empty" });
});

test("a placeholder page is not generatable", () => {
  assert.deepEqual(isGeneratable("Missing Text"), { generatable: false, skipReason: "placeholder" });
});

test("a page holding a substitution token is not generatable", () => {
  assert.deepEqual(isGeneratable("Greetings, $N."), { generatable: false, skipReason: "substitution" });
});

test("ordinary prose is generatable", () => {
  assert.deepEqual(isGeneratable("The rains have come."), { generatable: true, skipReason: null });
});

test("a title is read ahead of the page, closed with a full stop and a break", () => {
  assert.equal(spokenWithTitle("Letter to Ello", "The letters\n\nflicker."), "Letter to Ello.\nThe letters flicker.");
});

test("a title that already ends a sentence gets no second stop", () => {
  assert.equal(spokenWithTitle("For the Light!", "Brothers,"), "For the Light!\nBrothers,");
});

test("a page that opens with its own title is not given it twice", () => {
  assert.equal(spokenWithTitle("Fellari Swiftarrow", "Fellari Swiftarrow\n\nRanger Captain"), "Fellari Swiftarrow Ranger Captain");
  assert.equal(
    spokenWithTitle("A Treatise on Military Ranks", '<H1 align="center">A TREATISE ON MILITARY RANKS</H1>'),
    "A TREATISE ON MILITARY RANKS",
  );
});

test("the comparison is not limited to ASCII", () => {
  assert.equal(spokenWithTitle("Записка Зама", "Записка Зама\n\nАптекарь"), "Записка Зама Аптекарь");
});

test("no title, just the spoken page", () => {
  assert.equal(spokenWithTitle("", "Dear sir,\n\nHello."), "Dear sir, Hello.");
  assert.equal(spokenWithTitle("   ", "Dear sir,"), "Dear sir,");
});
