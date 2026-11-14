// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2026 Clemens Kressmann
//
// An article as blocks: its title and a list of paragraphs, headings, lists,
// tables, images and the other kinds below. Markdown stays what is stored and
// what agents write; blocks are how an editor shows and changes it.
//
// readArticle only returns blocks for Markdown it can write back unchanged in
// meaning, so an editor working on blocks never alters what it did not touch.
// Free of Node-only code (see AGENTS.md).
import { formatMarkdown, isTldr, parseMarkdown, tldrMarker, type MdNode } from "./markdown.ts";

/** A stretch of text with one formatting, or a line break. */
export type Inline =
  | { text: string; bold?: true; italic?: true; strike?: true; code?: true; link?: { url: string; title?: string } }
  | { break: true };

export type ListItem = { content: Inline[]; checked?: boolean; lists?: ListBlock[] };
export type ListBlock = {
  type: "list";
  style: "bullet" | "number" | "check";
  /** The first number of a numbered list, when it is not 1. */
  start?: number;
  /** Items stand apart as paragraphs (blank lines between them in Markdown). */
  loose?: true;
  items: ListItem[];
};
export type ParagraphBlock = { type: "paragraph"; content: Inline[] };

export type Block =
  | ParagraphBlock
  | { type: "heading"; level: 2 | 3 | 4 | 5 | 6; content: Inline[] }
  | { type: "quote"; content: Inline[] }
  /** The summary box at the start of an article ("> [!TLDR]"). */
  | { type: "summary"; blocks: Array<ParagraphBlock | ListBlock> }
  | ListBlock
  | { type: "code"; language?: string; code: string }
  /** The first row holds the column headings. */
  | { type: "table"; align?: Array<"left" | "right" | "center" | null>; rows: Inline[][][] }
  | { type: "image"; src: string; alt: string; caption?: string }
  | { type: "divider" };

export type Article = { title: string; blocks: Block[] };

class Unsupported extends Error {}
const unsupported = (what: string): never => { throw new Unsupported(what); };

type Marks = { bold?: true; italic?: true; strike?: true; link?: { url: string; title?: string } };
type Text = Extract<Inline, { text: string }>;
const isText = (inline: Inline | undefined): inline is Text => inline !== undefined && "text" in inline;
const sameFormat = (a: Text, b: Text) => a.bold === b.bold && a.italic === b.italic && a.strike === b.strike && a.code === b.code
  && a.link?.url === b.link?.url && a.link?.title === b.link?.title;

/**
 * One spelling for inline content: neighbours with the same formatting are one
 * stretch, and spaces carry no bold, italic or strike (it cannot be seen).
 */
export function tidyInline(content: Inline[]): Inline[] {
  const pieces: Inline[] = [];
  for (const inline of content) {
    if (!isText(inline)) { pieces.push(inline); continue; }
    if (inline.code) { if (inline.text) pieces.push(inline); continue; }
    for (const part of inline.text.split(/(\s+)/)) {
      if (!part) continue;
      const { bold: _bold, italic: _italic, strike: _strike, ...plain } = inline;
      pieces.push(/^\s+$/.test(part) ? { ...plain, text: part } : { ...inline, text: part });
    }
  }
  const tidy: Inline[] = [];
  for (const piece of pieces) {
    const last = tidy.at(-1);
    if (isText(piece) && isText(last) && sameFormat(last, piece)) tidy[tidy.length - 1] = { ...last, text: last.text + piece.text };
    else tidy.push(piece);
  }
  return tidy;
}

function readInline(nodes: MdNode[], marks: Marks = {}): Inline[] {
  return nodes.flatMap((node): Inline[] => {
    switch (node.type) {
      // A line ending inside a paragraph reads as a space.
      case "text": return [{ ...marks, text: (node.value ?? "").replace(/[ \t]*\n[ \t]*/g, " ") }];
      case "inlineCode": return [{ ...marks, text: node.value ?? "", code: true }];
      case "strong": return readInline(node.children ?? [], { ...marks, bold: true });
      case "emphasis": return readInline(node.children ?? [], { ...marks, italic: true });
      case "delete": return readInline(node.children ?? [], { ...marks, strike: true });
      case "link": return readInline(node.children ?? [], { ...marks, link: { url: node.url ?? "", ...(node.title ? { title: node.title } : {}) } });
      case "break": return [{ break: true }];
      default: return unsupported(node.type === "html" ? "raw HTML" : node.type === "image" ? "an image inside a line of text" : `"${node.type}" in text`);
    }
  });
}

const inlineOf = (node: MdNode) => tidyInline(readInline(node.children ?? []));

function readList(node: MdNode): ListBlock {
  const items = node.children ?? [];
  const checks = items.filter((item) => typeof item.checked === "boolean").length;
  if (checks && checks !== items.length) unsupported("a list mixing checkboxes and plain items");
  const loose = Boolean(node.spread) || items.some((item) => item.spread);
  return {
    type: "list",
    style: checks ? "check" : node.ordered ? "number" : "bullet",
    ...(node.ordered && typeof node.start === "number" && node.start !== 1 ? { start: node.start } : {}),
    ...(loose ? { loose: true as const } : {}),
    items: items.map((item): ListItem => {
      const [first, ...rest] = item.children ?? [];
      const lists = first?.type === "paragraph" ? rest : item.children ?? [];
      if (lists.some((child) => child.type !== "list")) unsupported("a list item with more than one paragraph or another block");
      return {
        content: first?.type === "paragraph" ? inlineOf(first) : [],
        ...(typeof item.checked === "boolean" ? { checked: item.checked } : {}),
        ...(lists.length ? { lists: lists.map(readList) } : {}),
      };
    }),
  };
}

function readSummary(node: MdNode): Block {
  const [first, ...rest] = (node.children ?? []).map((child) => ({ ...child }));
  // The marker opens the first paragraph; what follows it there is the summary's first text.
  const [marker, ...following] = first!.children!;
  const text = (marker!.value ?? "").trimStart().slice(tldrMarker.length).replace(/^\s+/, "");
  const opening = { ...first!, children: [...(text ? [{ ...marker!, value: text }] : []), ...following] };
  const blocks = [...(opening.children.length ? [opening] : []), ...rest].map((child): ParagraphBlock | ListBlock => {
    if (child.type === "paragraph") return { type: "paragraph", content: inlineOf(child) };
    if (child.type === "list") return readList(child);
    return unsupported(`"${child.type}" inside the summary`);
  });
  return { type: "summary", blocks };
}

function readBlock(node: MdNode): Block {
  switch (node.type) {
    case "paragraph": {
      const [only, ...others] = node.children ?? [];
      if (only?.type === "image" && !others.length) {
        return { type: "image", src: only.url ?? "", alt: only.alt ?? "", ...(only.title ? { caption: only.title } : {}) };
      }
      return { type: "paragraph", content: inlineOf(node) };
    }
    case "heading":
      if (node.depth === 1) unsupported("a second H1, or an H1 that is not the first line");
      return { type: "heading", level: node.depth as 2 | 3 | 4 | 5 | 6, content: inlineOf(node) };
    case "blockquote": {
      if (isTldr(node as never)) return readSummary(node);
      const [only, ...others] = node.children ?? [];
      if (only?.type !== "paragraph" || others.length) unsupported("a quote holding more than one paragraph");
      return { type: "quote", content: inlineOf(only!) };
    }
    case "list": return readList(node);
    case "code":
      if (node.meta) unsupported("a code block with options after its language");
      return { type: "code", ...(node.lang ? { language: node.lang } : {}), code: node.value ?? "" };
    case "table": {
      const align = node.align ?? [];
      return {
        type: "table",
        ...(align.some(Boolean) ? { align } : {}),
        rows: (node.children ?? []).map((row) => (row.children ?? []).map(inlineOf)),
      };
    }
    case "thematicBreak": return { type: "divider" };
    default: return unsupported(node.type === "html" ? "raw HTML" : `"${node.type}"`);
  }
}

function read(markdown: string): Article {
  const [first, ...rest] = parseMarkdown(markdown).children ?? [];
  if (first?.type !== "heading" || first.depth !== 1) return { title: "", blocks: [...(first ? [first] : []), ...rest].map(readBlock) };
  if (first.children?.some((child) => child.type !== "text")) unsupported("formatting in the H1");
  return { title: inlineOf(first).map((inline) => (isText(inline) ? inline.text : " ")).join("").trim(), blocks: rest.map(readBlock) };
}

const marks = [["strong", "bold"], ["emphasis", "italic"], ["delete", "strike"]] as const;

/** Nests stretches of text in links and marks; a space between two stretches of a mark stays inside it. */
function writeInline(content: Inline[], depth = -1): MdNode[] {
  if (depth === marks.length) {
    return content.map((inline): MdNode => (!isText(inline) ? { type: "break" }
      : inline.code ? { type: "inlineCode", value: inline.text } : { type: "text", value: inline.text }));
  }
  const key = (inline: Inline | undefined): unknown => {
    if (!isText(inline)) return undefined;
    return depth === -1 ? (inline.link ? `${inline.link.url}\n${inline.link.title ?? ""}` : undefined) : inline[marks[depth]![1]];
  };
  const isSpace = (inline: Inline | undefined) => isText(inline) && !inline.code && /^\s+$/.test(inline.text);
  const out: MdNode[] = [];
  for (let start = 0; start < content.length;) {
    const group = key(content[start]);
    let end = start + 1;
    if (!group) {
      while (end < content.length && !key(content[end])) end++;
      out.push(...writeInline(content.slice(start, end), depth + 1));
    } else {
      // The group runs on over spaces as long as more of it follows them.
      for (let next = end; next < content.length; next++) {
        if (key(content[next]) === group) end = next + 1;
        else if (depth === -1 || !isSpace(content[next])) break;
      }
      const children = writeInline(content.slice(start, end), depth + 1);
      const link = depth === -1 ? (content[start] as Text).link! : undefined;
      out.push(link ? { type: "link", url: link.url, title: link.title ?? null, children } : { type: marks[depth]![0], children });
    }
    start = end;
  }
  return out;
}

function writeList(list: ListBlock): MdNode {
  return {
    type: "list", ordered: list.style === "number", start: list.style === "number" ? list.start ?? 1 : null, spread: Boolean(list.loose),
    children: list.items.map((item): MdNode => ({
      type: "listItem", spread: Boolean(list.loose), checked: list.style === "check" ? Boolean(item.checked) : null,
      children: [
        ...(item.content.length ? [{ type: "paragraph", children: writeInline(item.content) }] : []),
        ...(item.lists ?? []).map(writeList),
      ],
    })),
  };
}

const paragraph = (content: Inline[]): MdNode => ({ type: "paragraph", children: writeInline(content) });

function writeBlock(block: Block): MdNode {
  switch (block.type) {
    case "paragraph": return paragraph(block.content);
    case "heading": return { type: "heading", depth: block.level, children: writeInline(block.content) };
    case "quote": return { type: "blockquote", children: [paragraph(block.content)] };
    case "summary": {
      // Written as is ("html"), so the marker keeps its brackets unescaped, as GitHub alerts are written.
      const marker: MdNode = { type: "html", value: tldrMarker };
      const [first, ...rest] = block.blocks;
      const opening: MdNode = first?.type === "paragraph"
        ? { type: "paragraph", children: [marker, { type: "text", value: "\n" }, ...writeInline(first.content)] }
        : { type: "paragraph", children: [marker] };
      return { type: "blockquote", children: [opening, ...(first?.type === "paragraph" ? rest : block.blocks).map(writeBlock)] };
    }
    case "list": return writeList(block);
    case "code": return { type: "code", lang: block.language ?? null, meta: null, value: block.code };
    case "table": return {
      type: "table", align: block.align ?? block.rows[0]?.map(() => null) ?? [],
      children: block.rows.map((row) => ({ type: "tableRow", children: row.map((cell) => ({ type: "tableCell", children: writeInline(cell) })) })),
    };
    case "image": return { type: "paragraph", children: [{ type: "image", url: block.src, alt: block.alt, title: block.caption ?? null }] };
    case "divider": return { type: "thematicBreak" };
  }
}

/** Writes an article as Markdown: its title as the H1, then its blocks. */
export function writeArticle(article: Article): string {
  const title = article.title.trim();
  return formatMarkdown({
    type: "root",
    children: [...(title ? [{ type: "heading", depth: 1, children: [{ type: "text", value: title }] }] : []), ...article.blocks.map(writeBlock)],
  });
}

/**
 * Reads Markdown as blocks. Markdown that blocks cannot hold exactly (raw HTML,
 * footnotes, a quote of several paragraphs and the like) is reported instead,
 * with what stands in the way, and is then edited as Markdown.
 */
export function readArticle(markdown: string): { article: Article; unsupported?: undefined } | { article?: undefined; unsupported: string } {
  try {
    const article = read(markdown);
    // Proof that writing loses nothing: the Markdown written from the blocks reads as the same blocks.
    if (JSON.stringify(read(writeArticle(article))) !== JSON.stringify(article)) return { unsupported: "formatting that would change when saved" };
    return { article };
  } catch (error) {
    if (error instanceof Unsupported) return { unsupported: error.message };
    throw error;
  }
}
