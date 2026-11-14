// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2026 Clemens Kressmann
//
// The Markdown of a hush article: how it is parsed and written, and the blocks
// an article is made of beyond plain Markdown. Free of Node-only code, so the
// renderer (article.ts) and the CMS editor read and write articles the same way.
import type { Table } from "mdast";
import type { Handle } from "mdast-util-to-markdown";
import remarkGfm from "remark-gfm";
import remarkParse from "remark-parse";
import remarkStringify from "remark-stringify";
import { unified } from "unified";
import type { BlogLanguage } from "./taxonomy.ts";

/** A node of the Markdown syntax tree (mdast), as far as articles use it. */
export type MdNode = {
  type: string;
  depth?: number;
  url?: string;
  alt?: string | null;
  title?: string | null;
  value?: string;
  lang?: string | null;
  meta?: string | null;
  ordered?: boolean | null;
  start?: number | null;
  spread?: boolean | null;
  checked?: boolean | null;
  align?: Array<"left" | "right" | "center" | null> | null;
  children?: MdNode[];
};

/** Parses GitHub-flavoured Markdown, as every reader of an article does. */
export function parseMarkdown(source: string): MdNode {
  return unified().use(remarkParse).use(remarkGfm).parse(source) as unknown as MdNode;
}

/** A blockquote starting with [!TLDR] (GitHub alert syntax) is the summary box. */
export const tldrMarker = "[!TLDR]";
export const tldrTitles: Record<BlogLanguage, string> = { en: "In short", de: "Kurz gesagt" };

const delimiters = { left: ":---", center: ":---:", right: "---:" };

/** A table without column padding and with "---" delimiters, as articles are written by hand and by agents. */
const writeTable: Handle = (node: Table, _parent, state, info) => {
  const exit = state.enter("table");
  const rows = node.children.map((row) => row.children.map((cell) => {
    const exitCell = state.enter("tableCell");
    const exitPhrasing = state.enter("phrasing");
    const value = state.containerPhrasing(cell, { ...info, before: "|", after: "|" });
    exitPhrasing();
    exitCell();
    return value;
  }));
  exit();
  const columns = Math.max(...rows.map((row) => row.length), node.align?.length ?? 0);
  const line = (cells: string[]) => `| ${Array.from({ length: columns }, (_cell, index) => cells[index] ?? "").join(" | ")} |`;
  const [head = [], ...body] = rows;
  return [line(head), line(Array.from({ length: columns }, (_cell, index) => delimiters[node.align?.[index] ?? "none" as "left"] ?? "---")), ...body.map(line)].join("\n");
};

/** Writes a syntax tree as Markdown in the style of the hush-seo skill: "-" bullets, "*" emphasis, fenced code, plain tables. */
export function formatMarkdown(tree: MdNode): string {
  return unified().use(remarkGfm).use(remarkStringify, {
    bullet: "-", emphasis: "*", strong: "*", fences: true, rule: "-", listItemIndent: "one", incrementListMarker: true,
    handlers: { table: writeTable },
    // A summary's list follows its marker on the next line, as GitHub alerts are written.
    join: [(left, right, parent) => (parent.type === "blockquote" && right.type === "list" && left.type === "paragraph"
      && left.children.length === 1 && left.children[0]!.type === "html" && left.children[0]!.value === tldrMarker ? 0 : undefined)],
  }).stringify(tree as never);
}

/** Whether a blockquote (of the Markdown tree or the HTML tree made from it) is the summary box. */
export function isTldr(node: { children?: Array<{ type: string; tagName?: string; children?: Array<{ type: string; value?: string }> }> }) {
  const first = node.children?.find((child) => child.type === "paragraph" || child.tagName === "p");
  const text = first?.children?.[0];
  return text?.type === "text" && (text.value ?? "").trimStart().startsWith(tldrMarker);
}

/** The questions section every article has. */
export const faqHeadings: Record<BlogLanguage, string> = {
  en: "Frequently asked questions",
  de: "Häufige Fragen",
};
/** The FAQ and the sources section close the article; the page sets them apart from the body. */
export const sourcesHeadings: Record<BlogLanguage, string> = {
  en: "Sources and how we tested",
  de: "Quellen und Testaufbau",
};
