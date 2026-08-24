import { describe, expect, it } from "vitest";
import { normalizePrimaryAttachments } from "../src/util/attachment-primary.js";

describe("attachment primary invariant", () => {
  it("marks the first attachment primary when none are marked", () => {
    expect(normalizePrimaryAttachments([{ url: "a" }, { url: "b" }])).toEqual([
      { url: "a", isPrimary: true },
      { url: "b", isPrimary: false },
    ]);
  });

  it("preserves the first marked primary and clears duplicates", () => {
    expect(normalizePrimaryAttachments([
      { url: "a", isPrimary: true },
      { url: "b", isPrimary: true },
      { url: "c", isPrimary: false },
    ])).toEqual([
      { url: "a", isPrimary: true },
      { url: "b", isPrimary: false },
      { url: "c", isPrimary: false },
    ]);
  });

  it("preserves a single selected primary", () => {
    expect(normalizePrimaryAttachments([
      { url: "a", isPrimary: false },
      { url: "b", isPrimary: true },
    ])).toEqual([
      { url: "a", isPrimary: false },
      { url: "b", isPrimary: true },
    ]);
  });
});
