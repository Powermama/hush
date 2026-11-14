// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2026 Clemens Kressmann
//
// Koenig's card menu: the "+" beside an empty line and "/" typed at its start
// open the same list of blocks to insert.
import { $createCodeNode } from "@lexical/code";
import { INSERT_ORDERED_LIST_COMMAND, INSERT_UNORDERED_LIST_COMMAND, $createListItemNode, $createListNode } from "@lexical/list";
import { useLexicalComposerContext } from "@lexical/react/LexicalComposerContext";
import { $createHorizontalRuleNode } from "@lexical/react/LexicalHorizontalRuleNode";
import { LexicalTypeaheadMenuPlugin, MenuOption } from "@lexical/react/LexicalTypeaheadMenuPlugin";
import { $createHeadingNode, $createQuoteNode } from "@lexical/rich-text";
import { $setBlocksType } from "@lexical/selection";
import { $createTableNodeWithDimensions } from "@lexical/table";
import { mergeRegister } from "@lexical/utils";
import {
  $createParagraphNode, $getSelection, $isParagraphNode, $isRangeSelection, $isRootNode, $isTextNode, COMMAND_PRIORITY_HIGH, COMMAND_PRIORITY_LOW, KEY_ENTER_COMMAND, KEY_ESCAPE_COMMAND,
  SELECTION_CHANGE_COMMAND, type ElementNode, type LexicalEditor, type LexicalNode,
} from "lexical";
import { Code, Heading2, Heading3, ImageIcon, List, ListOrdered, Minus, Plus, Quote, Sparkles, Table, type LucideIcon } from "lucide-react";
import { useCallback, useEffect, useMemo, useRef, useState, type RefObject } from "react";
import { createPortal } from "react-dom";
import { cn } from "@/lib/utils";
import { ShadeScope } from "@/shade-scope";
import { $createImageNode, $createSummaryNode } from "./nodes";

/** Puts a block where the cursor is: in place of an empty line, else after the current block. */
function $insertBlock(node: LexicalNode) {
  const selection = $getSelection();
  if (!$isRangeSelection(selection)) return;
  const block = selection.anchor.getNode().getTopLevelElementOrThrow();
  if ($isParagraphNode(block) && !block.getTextContent()) block.replace(node);
  else block.insertAfter(node);
  // A line to go on writing after a block the cursor cannot leave by typing.
  if (!node.getNextSibling()) node.insertAfter($createParagraphNode());
}

const $setBlock = (create: () => ElementNode) => {
  const selection = $getSelection();
  if ($isRangeSelection(selection)) $setBlocksType(selection, create);
};

type Item = { key: string; section: "Primary" | "Text"; label: string; description: string; shortcut: string; keywords: string; icon: LucideIcon; run: (editor: LexicalEditor) => void };

const items: Item[] = [
  {
    key: "image", section: "Primary", label: "Image", description: "Upload a screenshot or picture", shortcut: "/image", keywords: "image picture photo screenshot", icon: ImageIcon,
    run: (editor) => editor.update(() => $insertBlock($createImageNode({ src: "", alt: "", caption: "" }))),
  },
  {
    key: "divider", section: "Primary", label: "Divider", description: "Insert a dividing line", shortcut: "/hr", keywords: "divider hr line rule", icon: Minus,
    run: (editor) => editor.update(() => {
      const rule = $createHorizontalRuleNode();
      $insertBlock(rule);
      rule.getNextSibling()?.selectStart();
    }),
  },
  {
    key: "summary", section: "Primary", label: "Summary", description: "The short answer box that opens an article", shortcut: "/summary", keywords: "summary tldr short callout", icon: Sparkles,
    run: (editor) => editor.update(() => {
      const item = $createListItemNode();
      $insertBlock($createSummaryNode().append($createListNode("bullet").append(item)));
      item.select();
    }),
  },
  {
    key: "table", section: "Primary", label: "Table", description: "Compare things in rows and columns", shortcut: "/table", keywords: "table grid compare", icon: Table,
    run: (editor) => editor.update(() => {
      const table = $createTableNodeWithDimensions(3, 3, { rows: true, columns: false });
      $insertBlock(table);
      table.selectStart();
    }),
  },
  {
    key: "code", section: "Primary", label: "Code", description: "A command or a piece of code", shortcut: "/code", keywords: "code snippet command terminal", icon: Code,
    run: (editor) => editor.update(() => $setBlock(() => $createCodeNode())),
  },
  { key: "h2", section: "Text", label: "Heading 2", description: "A section of the article", shortcut: "/h2", keywords: "heading h2 section title", icon: Heading2, run: (editor) => editor.update(() => $setBlock(() => $createHeadingNode("h2"))) },
  { key: "h3", section: "Text", label: "Heading 3", description: "A part of a section, or a question", shortcut: "/h3", keywords: "heading h3 subsection question", icon: Heading3, run: (editor) => editor.update(() => $setBlock(() => $createHeadingNode("h3"))) },
  { key: "quote", section: "Text", label: "Quote", description: "Words someone else said", shortcut: "/quote", keywords: "quote blockquote citation", icon: Quote, run: (editor) => editor.update(() => $setBlock(() => $createQuoteNode())) },
  { key: "bullets", section: "Text", label: "Bulleted list", description: "Points in no particular order", shortcut: "/ul", keywords: "list bullets unordered ul", icon: List, run: (editor) => { editor.dispatchCommand(INSERT_UNORDERED_LIST_COMMAND, undefined); } },
  { key: "numbers", section: "Text", label: "Numbered list", description: "Steps to follow in order", shortcut: "/ol", keywords: "list numbers ordered steps ol", icon: ListOrdered, run: (editor) => { editor.dispatchCommand(INSERT_ORDERED_LIST_COMMAND, undefined); } },
];

const matching = (query: string) => {
  const wanted = query.toLowerCase();
  return items.filter((item) => !wanted || item.shortcut.slice(1).startsWith(wanted) || item.keywords.split(" ").some((word) => word.startsWith(wanted)) || item.label.toLowerCase().includes(wanted));
};

function MenuList({ shown, selected, onHover, onPick }: { shown: Item[]; selected?: number; onHover?: (index: number) => void; onPick: (item: Item) => void }) {
  return (
    <ul role="listbox" aria-label="Insert a block" className="not-kg-prose m-0 max-h-[420px] w-[348px] list-none overflow-y-auto rounded-lg bg-white p-0 py-2 font-sans leading-normal shadow-md dark:bg-gray-950 dark:ring-1 dark:ring-gray-900">
      {shown.length === 0 && <li className="m-0 px-4 py-2 text-[1.3rem] text-gray-700">No block matches</li>}
      {shown.map((item, index) => (
        <li key={item.key} className="m-0 p-0">
          {item.section !== shown[index - 1]?.section && <p className="m-0 px-4 pt-3 pb-1 text-[1.1rem] font-semibold tracking-wide text-gray-600 uppercase">{item.section}</p>}
          <button
            type="button" role="option" aria-selected={selected === index}
            ref={(element) => { if (selected === index) element?.scrollIntoView({ block: "nearest" }); }}
            onMouseDown={(event) => event.preventDefault()} onMouseEnter={() => onHover?.(index)} onClick={() => onPick(item)}
            className={cn("group flex w-full cursor-pointer items-center gap-3 px-4 py-2 text-left hover:bg-gray-100 dark:hover:bg-gray-900", selected === index && "bg-gray-100 dark:bg-gray-900")}
          >
            <span className="flex size-7 shrink-0 items-center justify-center text-foreground"><item.icon className="size-[1.8rem] stroke-[1.5]" /></span>
            <span className="min-w-0 flex-1">
              <span className="block truncate text-[1.35rem] leading-snug font-medium text-foreground">{item.label}</span>
              <span className="block truncate text-[1.25rem] leading-snug text-gray-700">{item.description}</span>
            </span>
            <span className={cn("shrink-0 text-[1.2rem] text-gray-600 opacity-0 group-hover:opacity-100", selected === index && "opacity-100")}>{item.shortcut}</span>
          </button>
        </li>
      ))}
    </ul>
  );
}

class BlockOption extends MenuOption {
  constructor(readonly item: Item) { super(item.key); }
}

/** "/" at the start of an empty line, narrowed by what is typed after it. */
export function SlashMenu() {
  const [editor] = useLexicalComposerContext();
  const [query, setQuery] = useState("");
  const options = useMemo(() => matching(query).map((item) => new BlockOption(item)), [query]);
  // The block highlighted in the menu, as last drawn.
  const highlighted = useRef<string | null>(null);

  // Enter on a line that is just "/name" decides from the text itself: the menu's own options can lag behind fast
  // typing, or not be open yet. The highlighted block wins while it still matches, else the first match.
  useEffect(() => editor.registerCommand(KEY_ENTER_COMMAND, (event) => {
    const selection = $getSelection();
    const block = $isRangeSelection(selection) && selection.isCollapsed() ? selection.anchor.getNode().getTopLevelElement() : null;
    const typed = $isParagraphNode(block) ? /^\/(\w*)$/.exec(block.getTextContent()) : null;
    if (!typed) return false;
    const found = matching(typed[1]!);
    const item = found.find((candidate) => candidate.key === highlighted.current) ?? found[0];
    if (!item) return false;
    event?.preventDefault();
    block!.clear();
    block!.select();
    item.run(editor);
    return true;
  }, COMMAND_PRIORITY_HIGH), [editor]);

  return (
    <LexicalTypeaheadMenuPlugin<BlockOption>
      onClose={() => { highlighted.current = null; }}
      options={options}
      onQueryChange={(text) => setQuery(text ?? "")}
      triggerFn={(text) => {
        const match = /^\/(\w*)$/.exec(text);
        return match ? { leadOffset: 0, matchingString: match[1]!, replaceableString: match[0] } : null;
      }}
      onSelectOption={(option, _typed, close) => {
        // The menu's own record of the query can lag behind fast typing, and the "/" may sit in a text node of its
        // own, so the typed "/…" is found in the line's text up to the cursor and removed there.
        editor.update(() => {
          const selection = $getSelection();
          const anchor = $isRangeSelection(selection) ? selection.anchor.getNode() : null;
          if (!$isRangeSelection(selection) || !$isTextNode(anchor)) return;
          const nodes = [...anchor.getPreviousSiblings().filter($isTextNode), anchor];
          const before = nodes.map((node) => (node === anchor ? node.getTextContent().slice(0, selection.anchor.offset) : node.getTextContent())).join("");
          const query = /\/\w*$/.exec(before);
          if (!query) return;
          // From the cursor backwards, so that earlier offsets stay valid; the cursor ends where the "/" was.
          let end = before.length;
          let caret: { node: typeof anchor; offset: number } | null = null;
          for (const node of nodes.reverse()) {
            const length = node === anchor ? selection.anchor.offset : node.getTextContentSize();
            const start = end - length;
            const from = Math.max(query.index - start, 0);
            if (from < length) {
              node.spliceText(from, length - from, "", false);
              caret = { node, offset: from };
            }
            end = start;
          }
          if (caret) caret.node.select(caret.offset, caret.offset);
          for (const node of nodes) if (node.isAttached() && !node.getTextContent()) node.remove();
        });
        option.item.run(editor);
        close();
      }}
      menuRenderFn={(anchor, { selectedIndex, selectOptionAndCleanUp, setHighlightedIndex }) => {
        highlighted.current = selectedIndex === null ? null : options[selectedIndex]?.item.key ?? null;
        return anchor.current ? createPortal(
        <ShadeScope className="mt-8">
          <MenuList
            shown={options.map((option) => option.item)} selected={selectedIndex ?? undefined} onHover={setHighlightedIndex}
            onPick={(item) => selectOptionAndCleanUp(options.find((option) => option.item === item)!)}
          />
        </ShadeScope>,
        anchor.current,
      ) : null;
      }}
    />
  );
}

/** The "+" beside the empty line the cursor is on. */
export function PlusMenu({ anchor }: { anchor: RefObject<HTMLElement | null> }) {
  const [editor] = useLexicalComposerContext();
  const [top, setTop] = useState<number | null>(null);
  const [open, setOpen] = useState(false);

  const refresh = useCallback(() => {
    const frame = anchor.current;
    if (!frame) return;
    setTop(editor.getEditorState().read(() => {
      const selection = $getSelection();
      if (!$isRangeSelection(selection) || !selection.isCollapsed()) return null;
      const node = selection.anchor.getNode();
      if (!$isParagraphNode(node) || !$isRootNode(node.getParent()) || node.getTextContent()) return null;
      const element = editor.getElementByKey(node.getKey());
      return element ? element.getBoundingClientRect().top - frame.getBoundingClientRect().top : null;
    }));
  }, [editor, anchor]);

  useEffect(() => mergeRegister(
    editor.registerUpdateListener(refresh),
    editor.registerCommand(SELECTION_CHANGE_COMMAND, () => { refresh(); return false; }, COMMAND_PRIORITY_LOW),
    editor.registerCommand(KEY_ESCAPE_COMMAND, () => { setOpen(false); return false; }, COMMAND_PRIORITY_LOW),
  ), [editor, refresh]);

  useEffect(() => {
    if (top === null) setOpen(false);
  }, [top]);

  useEffect(() => {
    if (!open) return;
    const close = (event: MouseEvent) => { if (!(event.target as HTMLElement).closest("[data-plus-menu]")) setOpen(false); };
    document.addEventListener("mousedown", close);
    return () => document.removeEventListener("mousedown", close);
  }, [open]);

  if (top === null) return null;
  return (
    <div data-plus-menu className="not-kg-prose absolute left-[-32px] z-20 font-sans leading-normal min-[500px]:left-[-66px]" style={{ top }}>
      <button
        type="button" aria-label="Add a card" aria-expanded={open}
        onMouseDown={(event) => event.preventDefault()} onClick={() => setOpen((value) => !value)}
        className="group mt-[-2px] flex size-7 cursor-pointer items-center justify-center rounded-full border border-gray-300 bg-white text-gray-800 transition-all ease-linear hover:border-gray-500 md:size-9 dark:border-gray-800 dark:bg-gray-950 dark:text-gray-500 dark:hover:border-gray-700"
      >
        <Plus className={cn("size-4 stroke-[1.5] transition-transform md:size-[1.8rem]", open && "rotate-45")} />
      </button>
      {open && (
        <div className="absolute top-12 left-0">
          <MenuList shown={items} onPick={(item) => { setOpen(false); editor.focus(); item.run(editor); }} />
        </div>
      )}
    </div>
  );
}
