import { describe, expect, it } from "vitest";

import { corpus } from "@/lib/quests/catalogue";

import {
  answersQuestMoment,
  broadcastGossipStem,
  gossipFileName,
  gossipHash,
  gossipLineId,
  gossipStemRank,
  localizedGossipStem,
  questFileName,
  questLineId,
  voiceNameFor,
} from "./naming";

describe("questLineId / questFileName", () => {
  it("matches a real corpus id and file -- q:33:accept -> 33-accept", async () => {
    const line = (await corpus()).lines.find((l) => l.lineId === "q:33:accept");
    expect(line).toBeDefined();
    expect(questLineId(33, "accept")).toBe(line!.lineId);
    expect(questFileName(33, "accept")).toBe(line!.fileName);
  });

  it("carries the event through unchanged", () => {
    expect(questLineId(76156, "progress")).toBe("q:76156:progress");
    expect(questFileName(76156, "progress")).toBe("76156-progress");
  });
});

describe("gossipHash / gossipLineId / gossipFileName", () => {
  it("matches a real corpus gossip line: md5(originalText + race + gender)", async () => {
    const line = (await corpus()).lines.find((l) => l.source === "gossip" && l.playerGender === null);
    expect(line).toBeDefined();
    const hash = gossipHash(line!.originalText, line!.race, line!.gender);
    expect(gossipLineId(hash)).toBe(line!.lineId);
    expect(gossipFileName(hash)).toBe(line!.fileName);
  });

  it("changes with the race or the gender, not just the text", () => {
    const a = gossipHash("Halt!", "human", "male");
    const b = gossipHash("Halt!", "human", "female");
    const c = gossipHash("Halt!", "orc", "male");
    expect(new Set([a, b, c]).size).toBe(3);
  });
});

describe("voiceNameFor", () => {
  it("joins race-gender-flavor when there is a flavor", () => {
    expect(voiceNameFor("tauren", "male", "warrior")).toBe("tauren-male-warrior");
  });

  it("drops the flavor segment when there is none", () => {
    expect(voiceNameFor("bloodelf", "female", null)).toBe("bloodelf-female");
  });
});

describe("answersQuestMoment", () => {
  it("matches the bare id and its player-gender variants, and nothing else", () => {
    expect(answersQuestMoment("q:166:complete", "q:166:complete")).toBe(true);
    expect(answersQuestMoment("q:166:complete:m", "q:166:complete")).toBe(true);
    expect(answersQuestMoment("q:166:complete:f", "q:166:complete")).toBe(true);
    expect(answersQuestMoment("q:1666:complete", "q:166:complete")).toBe(false);
    expect(answersQuestMoment("q:166:accept", "q:166:complete")).toBe(false);
  });
});

describe("upgradeable gossip stems", () => {
  // Pinned to tests/test_naming.py's test_broadcast_and_localized_gossip_stems.
  it("names a broadcast line after its id and voice, and a localized one after its language", () => {
    expect(broadcastGossipStem(6029, "orc-female-standard")).toBe("b6029-orc-female-standard");
    expect(localizedGossipStem("deDE", "0".repeat(32))).toBe(`deDE-${"0".repeat(32)}`);
  });

  it("ranks broadcast, then English, then localized", () => {
    expect(gossipStemRank("b6029-orc-female-standard")).toBe(0);
    expect(gossipStemRank(`bad0c0ffee${"0".repeat(22)}`)).toBe(1);
    expect(gossipStemRank(`deDE-${"0".repeat(32)}`)).toBe(2);
  });
});
