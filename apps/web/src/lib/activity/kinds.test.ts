import { describe, expect, it } from "vitest";

import { categoryOf } from "./kinds";

describe("categoryOf", () => {
  it("files pausing and resuming the queue under audio, with the batches they hold", () => {
    expect(categoryOf("queue.paused")).toBe("audio");
    expect(categoryOf("queue.resumed")).toBe("audio");
  });
});
