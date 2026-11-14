// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2026 Clemens Kressmann
//
// The article's body as blocks, edited the way Ghost's editor (Koenig) is:
// rich text with Markdown shortcuts, a floating toolbar, the card menu and
// cards for images, the summary, code, tables and dividers.
import type { Block } from "@hush/article/blocks";
import { CheckListPlugin } from "@lexical/react/LexicalCheckListPlugin";
import { LexicalComposer, type InitialConfigType } from "@lexical/react/LexicalComposer";
import { ContentEditable } from "@lexical/react/LexicalContentEditable";
import { LexicalErrorBoundary } from "@lexical/react/LexicalErrorBoundary";
import { HistoryPlugin } from "@lexical/react/LexicalHistoryPlugin";
import { $createHorizontalRuleNode, $isHorizontalRuleNode, HorizontalRuleNode } from "@lexical/react/LexicalHorizontalRuleNode";
import { LinkPlugin } from "@lexical/react/LexicalLinkPlugin";
import { ListPlugin } from "@lexical/react/LexicalListPlugin";
import { MarkdownShortcutPlugin } from "@lexical/react/LexicalMarkdownShortcutPlugin";
import { RichTextPlugin } from "@lexical/react/LexicalRichTextPlugin";
import { TabIndentationPlugin } from "@lexical/react/LexicalTabIndentationPlugin";
import { TablePlugin } from "@lexical/react/LexicalTablePlugin";
import {
  BOLD_ITALIC_STAR, BOLD_STAR, BOLD_UNDERSCORE, CHECK_LIST, CODE, INLINE_CODE, ITALIC_STAR, ITALIC_UNDERSCORE, LINK, ORDERED_LIST, QUOTE,
  STRIKETHROUGH, UNORDERED_LIST, type ElementTransformer, type Transformer,
} from "@lexical/markdown";
import { $createHeadingNode, HeadingNode } from "@lexical/rich-text";
import { useMemo, useRef, type Ref } from "react";
import { PlusMenu, SlashMenu } from "./block-menu";
import { $setBlocks } from "./blocks";
import { articleNodes } from "./nodes";
import { CodeLanguage, Pasting, Reporting, TableMenu, type ArticleEditorHandle } from "./plugins";
import { FloatingToolbar } from "./toolbar";
import { cn } from "@/lib/utils";

/** "# " to "###### " start a heading; the article's H1 is its title, so the body's largest is H2. */
const heading: ElementTransformer = {
  dependencies: [HeadingNode],
  export: () => null,
  regExp: /^(#{1,6})\s/,
  replace: (parent, children, match) => {
    const node = $createHeadingNode(`h${Math.max(2, match[1]!.length)}` as "h2");
    node.append(...children);
    parent.replace(node);
    node.select(0, 0);
  },
  type: "element",
};

/** "---", "***" or "___" and a space is a divider. */
const divider: ElementTransformer = {
  dependencies: [HorizontalRuleNode],
  export: (node) => ($isHorizontalRuleNode(node) ? "---" : null),
  regExp: /^(---|\*\*\*|___)\s?$/,
  replace: (parent, _children, _match, isImport) => {
    const rule = $createHorizontalRuleNode();
    if (isImport || parent.getNextSibling()) parent.replace(rule);
    else parent.insertBefore(rule);
    rule.selectNext();
  },
  type: "element",
};

const shortcuts: Transformer[] = [
  heading, divider, QUOTE, UNORDERED_LIST, ORDERED_LIST, CHECK_LIST, CODE,
  INLINE_CODE, BOLD_ITALIC_STAR, BOLD_STAR, BOLD_UNDERSCORE, ITALIC_STAR, ITALIC_UNDERSCORE, STRIKETHROUGH, LINK,
];

export function ArticleEditor({ handle, initialBlocks, summaryTitle, dark, onChange, onWords, onTyping, onLeaveUp }: {
  handle: Ref<ArticleEditorHandle>;
  /** The body when the editor opens; it keeps its own text after that. */
  initialBlocks: Block[];
  /** The summary box's heading in the article's language. */
  summaryTitle: string;
  dark: boolean;
  onChange: () => void;
  onWords: (words: number, selected: number) => void;
  onTyping: () => void;
  onLeaveUp: () => void;
}) {
  const frame = useRef<HTMLDivElement>(null);
  const config = useMemo((): InitialConfigType => ({
    namespace: "hush-article",
    nodes: articleNodes,
    editorState: () => $setBlocks(initialBlocks),
    onError: (error) => { throw error; },
    theme: {
      text: { italic: "italic", strikethrough: "line-through", underline: "underline" },
      list: { nested: { listitem: "editor-nested-item" }, listitemChecked: "editor-check", listitemUnchecked: "editor-check" },
      code: "editor-code",
      table: "editor-table",
      tableCellSelected: "editor-cell-selected",
      hrSelected: "editor-selected",
      summaryTitle,
    },
    // Set once: the editor owns its content from here on.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }), []);

  return (
    <LexicalComposer initialConfig={config}>
      <div ref={frame} className={cn("koenig-lexical", dark && "dark")}>
        <RichTextPlugin
          contentEditable={<ContentEditable className="kg-prose" aria-label="Article" aria-placeholder="Begin writing your post..." placeholder={<div className="editor-placeholder">Begin writing your post...</div>} />}
          ErrorBoundary={LexicalErrorBoundary}
        />
        <FloatingToolbar anchor={frame} />
        <PlusMenu anchor={frame} />
        <CodeLanguage anchor={frame} />
        <TableMenu anchor={frame} />
      </div>
      <SlashMenu />
      <HistoryPlugin />
      <ListPlugin />
      <CheckListPlugin />
      <LinkPlugin />
      <TablePlugin hasCellMerge={false} hasCellBackgroundColor={false} />
      <TabIndentationPlugin />
      <MarkdownShortcutPlugin transformers={shortcuts} />
      <Pasting />
      <Reporting handle={handle} onChange={onChange} onWords={onWords} onTyping={onTyping} onLeaveUp={onLeaveUp} />
    </LexicalComposer>
  );
}
