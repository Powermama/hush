// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2026 Clemens Kressmann
//
// The editor's own nodes, beside Lexical's: the two article blocks Lexical has
// no node for (an image with its caption, the summary box), and what Markdown
// records about a list and a table that Lexical's nodes do not.
import { CodeNode } from "@lexical/code";
import { LinkNode } from "@lexical/link";
import { ListItemNode, ListNode } from "@lexical/list";
import { HorizontalRuleNode } from "@lexical/react/LexicalHorizontalRuleNode";
import { HeadingNode, QuoteNode } from "@lexical/rich-text";
import { TableCellNode, TableNode, TableRowNode } from "@lexical/table";
import {
  $applyNodeReplacement, DecoratorNode, ElementNode, createState, type EditorConfig, type Klass, type LexicalNode, type NodeKey,
  type SerializedElementNode, type SerializedLexicalNode, type Spread,
} from "lexical";
import type { ReactNode } from "react";
import { ImageCard } from "./image-card";

/** A list whose items stand apart as paragraphs (blank lines between them in Markdown). */
export const looseListState = createState("loose", { parse: (value) => value === true });

type Align = Array<"left" | "right" | "center" | null>;
/** A table's column alignments, as its Markdown delimiter row gives them. */
export const tableAlignState = createState("align", { parse: (value): Align | null => (Array.isArray(value) ? value as Align : null) });

export type Image = { src: string; alt: string; caption: string };
type SerializedImageNode = Spread<Image, SerializedLexicalNode>;

/** An image on a line of its own, with its alt text and an optional caption. */
export class ImageNode extends DecoratorNode<ReactNode> {
  __src: string;
  __alt: string;
  __caption: string;

  static getType() { return "image"; }
  static clone(node: ImageNode) { return new ImageNode({ src: node.__src, alt: node.__alt, caption: node.__caption }, node.__key); }
  static importJSON(json: SerializedImageNode) { return $createImageNode(json).updateFromJSON(json); }

  constructor({ src, alt, caption }: Image, key?: NodeKey) {
    super(key);
    this.__src = src;
    this.__alt = alt;
    this.__caption = caption;
  }

  exportJSON(): SerializedImageNode { return { ...super.exportJSON(), ...this.getImage() }; }
  getImage(): Image {
    const latest = this.getLatest();
    return { src: latest.__src, alt: latest.__alt, caption: latest.__caption };
  }
  setImage(image: Partial<Image>) {
    const writable = this.getWritable();
    if (image.src !== undefined) writable.__src = image.src;
    if (image.alt !== undefined) writable.__alt = image.alt;
    if (image.caption !== undefined) writable.__caption = image.caption;
    return writable;
  }
  getTextContent() { return this.getLatest().__caption; }
  isInline() { return false; }
  createDOM(_config: EditorConfig) {
    const element = document.createElement("div");
    element.className = "editor-image";
    return element;
  }
  updateDOM() { return false; }
  decorate() { return <ImageCard nodeKey={this.__key} image={this.getImage()} />; }
}

export const $createImageNode = (image: Image) => $applyNodeReplacement(new ImageNode(image));
export const $isImageNode = (node: LexicalNode | null | undefined): node is ImageNode => node instanceof ImageNode;

/** The summary box at the start of an article: a frame around paragraphs and lists. */
export class SummaryNode extends ElementNode {
  static getType() { return "summary"; }
  static clone(node: SummaryNode) { return new SummaryNode(node.__key); }
  static importJSON(json: SerializedElementNode) { return $createSummaryNode().updateFromJSON(json); }

  createDOM(config: EditorConfig) {
    const element = document.createElement("div");
    element.className = "editor-summary";
    // The box's heading in the article's language ("In short"), as the page shows it.
    element.dataset.title = String(config.theme.summaryTitle ?? "In short");
    return element;
  }
  updateDOM() { return false; }
  // Like a table cell: its blocks are edited inside it, and the selection does not merge it with its neighbours.
  isShadowRoot() { return true; }
  canBeEmpty() { return false; }
}

export const $createSummaryNode = () => $applyNodeReplacement(new SummaryNode());
export const $isSummaryNode = (node: LexicalNode | null | undefined): node is SummaryNode => node instanceof SummaryNode;

/** Every node an article is made of. */
export const articleNodes: Array<Klass<LexicalNode>> = [
  HeadingNode, QuoteNode, ListNode, ListItemNode, LinkNode, CodeNode, TableNode, TableRowNode, TableCellNode,
  HorizontalRuleNode, ImageNode, SummaryNode,
];
