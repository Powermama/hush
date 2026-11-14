// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2026 Clemens Kressmann
//
// Between an article's blocks (@hush/article/blocks) and the editor's nodes:
// $setBlocks fills the editor from blocks, $getBlocks reads them back. Both
// run inside editor.update() or editor.read().
import { $createCodeNode, $isCodeNode } from "@lexical/code";
import { $createLinkNode, $isLinkNode } from "@lexical/link";
import { $createListItemNode, $createListNode, $isListItemNode, $isListNode, type ListNode } from "@lexical/list";
import { $createHorizontalRuleNode, $isHorizontalRuleNode } from "@lexical/react/LexicalHorizontalRuleNode";
import { $createHeadingNode, $createQuoteNode, $isHeadingNode, $isQuoteNode } from "@lexical/rich-text";
import {
  $createTableCellNode, $createTableNode, $createTableRowNode, $isTableCellNode, $isTableNode, $isTableRowNode, TableCellHeaderStates,
} from "@lexical/table";
import { tidyInline, type Block, type Inline, type ListBlock, type ListItem, type ParagraphBlock } from "@hush/article/blocks";
import {
  $createLineBreakNode, $createParagraphNode, $createTextNode, $getRoot, $getState, $isElementNode, $isLineBreakNode, $isParagraphNode,
  $isTextNode, $setState, type ElementNode, type LexicalNode,
} from "lexical";
import { $createImageNode, $createSummaryNode, $isImageNode, $isSummaryNode, looseListState, tableAlignState } from "./nodes";

type Text = Extract<Inline, { text: string }>;
const formats = [["bold", "bold"], ["italic", "italic"], ["strike", "strikethrough"], ["code", "code"]] as const;

function $inlineNodes(content: Inline[]): LexicalNode[] {
  const nodes: LexicalNode[] = [];
  for (let index = 0; index < content.length; index++) {
    const inline = content[index]!;
    if (!("text" in inline)) { nodes.push($createLineBreakNode()); continue; }
    const text = $createTextNode(inline.text);
    for (const [mark, format] of formats) if (inline[mark]) text.toggleFormat(format);
    if (!inline.link) { nodes.push(text); continue; }
    // One link node for every stretch of the same link.
    const link = $createLinkNode(inline.link.url, { title: inline.link.title ?? null }).append(text);
    for (let next = content[index + 1]; next && "text" in next && next.link?.url === inline.link.url && next.link.title === inline.link.title; next = content[index + 1]) {
      index++;
      const more = $createTextNode(next.text);
      for (const [mark, format] of formats) if (next[mark]) more.toggleFormat(format);
      link.append(more);
    }
    nodes.push(link);
  }
  return nodes;
}

function $listNode(list: ListBlock): ListNode {
  const node = $createListNode(list.style, list.start ?? 1);
  if (list.loose) $setState(node, looseListState, true);
  for (const item of list.items) {
    node.append($createListItemNode(list.style === "check" ? Boolean(item.checked) : undefined).append(...$inlineNodes(item.content)));
    // Lexical keeps a nested list in an item of its own, after the item it belongs to.
    for (const nested of item.lists ?? []) node.append($createListItemNode().append($listNode(nested)));
  }
  return node;
}

function $blockNode(block: Block): LexicalNode {
  switch (block.type) {
    case "paragraph": return $createParagraphNode().append(...$inlineNodes(block.content));
    case "heading": return $createHeadingNode(`h${block.level}`).append(...$inlineNodes(block.content));
    case "quote": return $createQuoteNode().append(...$inlineNodes(block.content));
    case "summary": return $createSummaryNode().append(...(block.blocks.length ? block.blocks : [{ type: "paragraph" as const, content: [] }]).map($blockNode));
    case "list": return $listNode(block);
    case "code": {
      const lines = block.code.split("\n");
      return $createCodeNode(block.language).append(...lines.flatMap((line, index) => [
        ...(index ? [$createLineBreakNode()] : []), ...(line ? [$createTextNode(line)] : []),
      ]));
    }
    case "table": {
      const table = $createTableNode();
      if (block.align) $setState(table, tableAlignState, block.align);
      block.rows.forEach((row, index) => table.append($createTableRowNode().append(...row.map((cell) => (
        $createTableCellNode(index ? TableCellHeaderStates.NO_STATUS : TableCellHeaderStates.ROW).append($createParagraphNode().append(...$inlineNodes(cell)))
      )))));
      return table;
    }
    case "image": return $createImageNode({ src: block.src, alt: block.alt, caption: block.caption ?? "" });
    case "divider": return $createHorizontalRuleNode();
  }
}

/** Replaces the editor's content with the blocks. */
export function $setBlocks(blocks: Block[]) {
  const root = $getRoot().clear();
  root.append(...(blocks.length ? blocks.map($blockNode) : [$createParagraphNode()]));
}

function $inline(node: ElementNode, link?: Text["link"]): Inline[] {
  return node.getChildren().flatMap((child): Inline[] => {
    if ($isLineBreakNode(child)) return [{ break: true }];
    if ($isLinkNode(child)) {
      const title = child.getTitle();
      return $inline(child, { url: child.getURL(), ...(title ? { title } : {}) });
    }
    if ($isTextNode(child)) {
      const text: Text = { text: child.getTextContent() };
      for (const [mark, format] of formats) if (child.hasFormat(format)) text[mark] = true;
      if (link) text.link = link;
      return [text];
    }
    return $isElementNode(child) ? $inline(child, link) : [{ text: child.getTextContent() }];
  });
}

const $content = (node: ElementNode) => tidyInline($inline(node));

function $list(node: ListNode): ListBlock {
  const style = node.getListType();
  const items: ListItem[] = [];
  for (const child of node.getChildren()) {
    if (!$isListItemNode(child)) continue;
    const nested = child.getChildren().filter($isListNode);
    if (nested.length && nested.length === child.getChildrenSize()) {
      // An item holding only lists: they belong to the item before it.
      const owner = items.at(-1) ?? items[items.push({ content: [] }) - 1]!;
      owner.lists = [...(owner.lists ?? []), ...nested.map($list)];
    } else {
      items.push({ content: $content(child), ...(style === "check" ? { checked: Boolean(child.getChecked()) } : {}) });
    }
  }
  const start = node.getStart();
  return {
    type: "list", style,
    ...(style === "number" && start !== 1 ? { start } : {}),
    ...($getState(node, looseListState) ? { loose: true as const } : {}),
    items,
  };
}

function $block(node: LexicalNode): Block[] {
  if ($isHeadingNode(node)) {
    // The article's H1 is its title, edited apart from the body; the body starts at H2.
    const level = Math.max(2, Number(node.getTag().slice(1))) as 2 | 3 | 4 | 5 | 6;
    return [{ type: "heading", level, content: $content(node) }];
  }
  if ($isQuoteNode(node)) return [{ type: "quote", content: $content(node) }];
  if ($isSummaryNode(node)) {
    const blocks = node.getChildren().flatMap($block).filter((block): block is ParagraphBlock | ListBlock => block.type === "paragraph" || block.type === "list");
    return [{ type: "summary", blocks }];
  }
  if ($isListNode(node)) return [$list(node)];
  if ($isCodeNode(node)) {
    const language = node.getLanguage();
    return [{ type: "code", ...(language ? { language } : {}), code: node.getTextContent() }];
  }
  if ($isTableNode(node)) {
    const rows = node.getChildren().filter($isTableRowNode).map((row) => row.getChildren().filter($isTableCellNode).map((cell) => {
      // A cell is one line of text in Markdown: its paragraphs become line breaks.
      const paragraphs = cell.getChildren().filter($isElementNode).map((paragraph) => $inline(paragraph)).filter((content) => content.length);
      return tidyInline(paragraphs.flatMap((content, index) => (index ? [{ break: true as const }, ...content] : content)));
    }));
    const align = $getState(node, tableAlignState);
    return rows.length ? [{ type: "table", ...(align?.some(Boolean) ? { align } : {}), rows }] : [];
  }
  if ($isImageNode(node)) {
    const { src, alt, caption } = node.getImage();
    return [{ type: "image", src, alt, ...(caption ? { caption } : {}) }];
  }
  if ($isHorizontalRuleNode(node)) return [{ type: "divider" }];
  if ($isParagraphNode(node) || $isElementNode(node)) {
    // An empty paragraph is only where the cursor rests; Markdown has no such thing.
    const content = $content(node);
    return content.length ? [{ type: "paragraph", content }] : [];
  }
  const text = node.getTextContent();
  return text ? [{ type: "paragraph", content: [{ text }] }] : [];
}

/** The editor's content as blocks. */
export function $getBlocks(): Block[] {
  return $getRoot().getChildren().flatMap($block);
}
