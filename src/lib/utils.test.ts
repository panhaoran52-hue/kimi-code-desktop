import { describe, expect, it } from "vitest";
import { cn, shortenTitle, stripThinkMarkup } from "./utils";

describe("cn", () => {
  it("merges class names with tailwind-merge", () => {
    expect(cn("px-2 py-1", "px-4")).toBe("py-1 px-4");
  });

  it("handles conditional classes", () => {
    expect(cn("base", false && "hidden", true && "block")).toBe("base block");
  });

  it("handles undefined and null", () => {
    expect(cn("base", undefined, null)).toBe("base");
  });
});

describe("stripThinkMarkup", () => {
  it("removes <think>...</think> blocks", () => {
    const input = "Hello <think>some reasoning</think> world";
    expect(stripThinkMarkup(input)).toBe("Hello   world");
  });

  it("removes unclosed <think> blocks", () => {
    const input = "Hello <think>unfinished";
    expect(stripThinkMarkup(input)).toBe("Hello  ");
  });

  it("handles multiple think blocks", () => {
    const input = "<think>a</think> middle <think>b</think>";
    expect(stripThinkMarkup(input)).toBe("  middle  ");
  });

  it("returns empty string for null/undefined", () => {
    expect(stripThinkMarkup(null)).toBe("");
    expect(stripThinkMarkup(undefined)).toBe("");
  });
});

describe("shortenTitle", () => {
  it("returns empty string for null/undefined", () => {
    expect(shortenTitle(null)).toBe("");
    expect(shortenTitle(undefined)).toBe("");
  });

  it("normalizes whitespace", () => {
    expect(shortenTitle("  hello   world  ")).toBe("hello world");
  });

  it("strips think markup before shortening", () => {
    expect(shortenTitle("<think>reasoning</think> title")).toBe("title");
  });

  it("does not shorten if within maxLength", () => {
    expect(shortenTitle("short title", 50)).toBe("short title");
  });

  it("shortens with ellipsis when exceeding maxLength", () => {
    const long = "a".repeat(60);
    expect(shortenTitle(long, 50)).toBe("a".repeat(49) + "…");
  });
});
