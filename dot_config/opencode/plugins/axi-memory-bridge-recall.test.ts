import { describe, expect, test } from "bun:test";

// Extracted from axi-memory-bridge.ts for isolated testing
function keywordJaccard(a: string[], b: string[]): number {
  if (a.length === 0 && b.length === 0) return 1;
  if (a.length === 0 || b.length === 0) return 0;
  const setA = new Set(a);
  const setB = new Set(b);
  let intersection = 0;
  for (const w of setA) if (setB.has(w)) intersection++;
  const union = setA.size + setB.size - intersection;
  return union === 0 ? 0 : intersection / union;
}

function avgJaccardAgainstHistory(current: string[], history: string[][]): number {
  if (history.length === 0) return 0;
  let total = 0;
  for (const prev of history) total += keywordJaccard(current, prev);
  return total / history.length;
}

function extractKeywords(text: string, maxWords = 5): string {
  const stopWords = new Set(["the", "a", "an", "is", "are", "was", "were", "be", "been", "being", "have", "has", "had", "do", "does", "did", "will", "would", "could", "should", "may", "might", "must", "shall", "can", "need", "dare", "ought", "used", "to", "of", "in", "for", "on", "with", "at", "by", "from", "as", "into", "through", "during", "before", "after", "above", "below", "between", "under", "and", "but", "or", "yet", "so", "if", "because", "although", "though", "while", "where", "when", "that", "which", "who", "whom", "whose", "what", "this", "these", "those", "i", "you", "he", "she", "it", "we", "they", "me", "him", "her", "us", "them", "my", "your", "his", "its", "our", "their", "mine", "yours", "hers", "ours", "theirs", "myself", "yourself", "himself", "herself", "itself", "ourselves", "yourselves", "themselves"]);
  const words = text
    .toLowerCase()
    .replace(/[^a-z0-9\s]/g, " ")
    .split(/\s+/)
    .filter((w) => w.length > 2 && !stopWords.has(w))
    .slice(0, maxWords);
  return words.join(" ");
}

function hasResults(output: string): boolean {
  return output.trim().length > 0 && !output.includes("count: 0 of 0");
}

describe("topic-shift auto-recall", () => {
  test("keywordJaccard: identical arrays = 1.0", () => {
    expect(keywordJaccard(["deploy", "friday", "bad"], ["deploy", "friday", "bad"])).toBe(1);
  });

  test("keywordJaccard: no overlap = 0.0", () => {
    expect(keywordJaccard(["deploy", "friday"], ["database", "migration"])).toBe(0);
  });

  test("keywordJaccard: partial overlap", () => {
    // {deploy, friday} ∩ {deploy, sunday} = {deploy} = 1
    // {deploy, friday} ∪ {deploy, sunday} = {deploy, friday, sunday} = 3
    expect(keywordJaccard(["deploy", "friday"], ["deploy", "sunday"])).toBeCloseTo(1 / 3);
  });

  test("avgJaccardAgainstHistory: empty history = 0", () => {
    expect(avgJaccardAgainstHistory(["deploy"], [])).toBe(0);
  });

  test("avgJaccardAgainstHistory: on-topic messages score high", () => {
    const history = [["deploy", "friday", "bad"], ["deploy", "friday", "idea"]];
    const current = ["deploy", "friday", "policy"];
    // Jaccard with each: ~0.5, ~0.5 → avg ~0.5
    expect(avgJaccardAgainstHistory(current, history)).toBeGreaterThan(0.3);
  });

  test("avgJaccardAgainstHistory: topic-shift scores low", () => {
    const history = [["deploy", "friday", "bad"], ["deploy", "friday", "idea"]];
    const current = ["database", "migration", "schema"];
    expect(avgJaccardAgainstHistory(current, history)).toBeLessThan(0.3);
  });

  test("extractKeywords: filters stop words and short words", () => {
    const kw = extractKeywords("the quick brown fox jumps over the lazy dog", 5);
    expect(kw).toBe("quick brown fox jumps over");
  });

  test("extractKeywords: returns empty for stop-word-only input", () => {
    const kw = extractKeywords("the a an is are was", 5);
    expect(kw).toBe("");
  });
});

describe("hasResults guard", () => {
  test("hasResults: true for non-empty results", () => {
    expect(hasResults("d-2026-08-20-test decision Test — abstract")).toBe(true);
  });

  test("hasResults: false for count: 0 of 0", () => {
    expect(hasResults("count: 0 of 0 total\nhelp[1]:\n  Run mem add...")).toBe(false);
  });

  test("hasResults: false for empty string", () => {
    expect(hasResults("")).toBe(false);
  });

  test("hasResults: false for whitespace-only", () => {
    expect(hasResults("   \n  ")).toBe(false);
  });

  test("hasResults: true for inject output with results", () => {
    expect(hasResults("d-2026-08-20-test decision Test — abstract\n")).toBe(true);
  });
});
