// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2026 Clemens Kressmann
//
// The editor's smaller behaviours: what changes are reported to the screen,
// pasting Markdown and links, dropping images, the language of a code block
// and a table's rows and columns.
import { readArticle, type Block } from "@hush/article/blocks";
import { $isCodeNode } from "@lexical/code";
import { TOGGLE_LINK_COMMAND } from "@lexical/link";
import { useLexicalComposerContext } from "@lexical/react/LexicalComposerContext";
import { DRAG_DROP_PASTE } from "@lexical/rich-text";
import {
  $deleteTableColumnAtSelection, $deleteTableRowAtSelection, $findCellNode, $findTableNode, $insertTableColumnAtSelection,
  $insertTableRowAtSelection, $isTableSelection,
} from "@lexical/table";
import { $insertNodeToNearestRoot, mergeRegister } from "@lexical/utils";
import {
  $createParagraphNode, $getRoot, $getSelection, $insertNodes, $isParagraphNode, $isRangeSelection, $nodesOfType, COMMAND_PRIORITY_LOW,
  KEY_ARROW_UP_COMMAND, KEY_DOWN_COMMAND, PASTE_COMMAND, RootNode, SELECTION_CHANGE_COMMAND,
} from "lexical";
import { ChevronDown } from "lucide-react";
import { useCallback, useEffect, useImperativeHandle, useState, type Ref, type RefObject } from "react";
import { toast } from "sonner";
import {
  DropdownMenu, DropdownMenuContent, DropdownMenuItem, DropdownMenuSeparator, DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";
import { $createBlockNodes, $getBlocks } from "./blocks";
import { imageTypes, useEditorHost } from "./host";
import { $createImageNode, ImageNode } from "./nodes";
import { linkTarget } from "./toolbar";

export type ArticleEditorHandle = {
  /** The article's body as it stands. */
  blocks(): Block[];
  focus(): void;
  /** Images follow the post's slug: "media/<slug>/<name>". */
  moveImages(from: string, to: string): void;
};

/** Changes made by the system, not the author: they are not something to save. */
const quiet = "history-merge";

export function Reporting({ handle, onChange, onWords, onTyping, onLeaveUp }: {
  handle: Ref<ArticleEditorHandle>;
  onChange: () => void;
  onWords: (words: number, selected: number) => void;
  onTyping: () => void;
  onLeaveUp: () => void;
}) {
  const [editor] = useLexicalComposerContext();

  useImperativeHandle(handle, () => ({
    blocks: () => editor.getEditorState().read($getBlocks),
    focus: () => editor.focus(() => {}, { defaultSelection: "rootStart" }),
    moveImages: (from, to) => editor.update(() => {
      for (const node of $nodesOfType(ImageNode)) {
        const { src } = node.getImage();
        if (src.startsWith(`media/${from}/`)) node.setImage({ src: `media/${to}/${src.slice(`media/${from}/`.length)}` });
      }
    }, { tag: quiet }),
  }), [editor]);

  useEffect(() => {
    const words = (text: string) => text.split(/\s+/).filter(Boolean).length;
    const count = () => editor.getEditorState().read(() => {
      const selection = $getSelection();
      onWords(words($getRoot().getTextContent()), $isRangeSelection(selection) && !selection.isCollapsed() ? words(selection.getTextContent()) : 0);
    });
    count();
    return mergeRegister(
      editor.registerUpdateListener(({ dirtyElements, dirtyLeaves, tags }) => {
        count();
        if (!tags.has(quiet) && (dirtyElements.size || dirtyLeaves.size)) onChange();
      }),
      editor.registerCommand(KEY_DOWN_COMMAND, (event) => {
        // Writing, not a shortcut or moving about.
        if (event.key.length === 1 && !event.metaKey && !event.ctrlKey) onTyping();
        return false;
      }, COMMAND_PRIORITY_LOW),
      editor.registerCommand(KEY_ARROW_UP_COMMAND, (event) => {
        const selection = $getSelection();
        if (!$isRangeSelection(selection) || !selection.isCollapsed() || selection.anchor.offset !== 0) return false;
        const first = $getRoot().getFirstChild();
        const node = selection.anchor.getNode();
        if (node !== first && node !== $getRoot().getFirstDescendant()) return false;
        event.preventDefault();
        onLeaveUp();
        return true;
      }, COMMAND_PRIORITY_LOW),
      // There is always a line to write on after the last block.
      editor.registerNodeTransform(RootNode, (root) => {
        if (!$isParagraphNode(root.getLastChild())) root.append($createParagraphNode());
      }),
    );
  }, [editor, onChange, onWords, onTyping, onLeaveUp]);

  return null;
}

const plain = (blocks: Block[]) => blocks.length === 1 && blocks[0]!.type === "paragraph"
  && blocks[0]!.content.every((inline) => "text" in inline && Object.keys(inline).length === 1);

/** Pasted text that is Markdown arrives as blocks; a pasted address over selected text links it; dropped images are stored. */
export function Pasting() {
  const [editor] = useLexicalComposerContext();
  const host = useEditorHost();

  useEffect(() => mergeRegister(
    editor.registerCommand(PASTE_COMMAND, (event) => {
      const data = "clipboardData" in event ? event.clipboardData : null;
      const text = data?.getData("text/plain") ?? "";
      const selection = $getSelection();
      if (!text || data?.getData("text/html") || data?.files.length || !$isRangeSelection(selection)) return false;
      if ($isCodeNode(selection.anchor.getNode().getTopLevelElement())) return false;
      if (!selection.isCollapsed() && /^(https?:\/\/|mailto:)\S+$/.test(text.trim())) {
        event.preventDefault();
        editor.dispatchCommand(TOGGLE_LINK_COMMAND, linkTarget(text));
        return true;
      }
      const { article } = readArticle(text);
      if (!article) return false;
      // A pasted H1 is a section here: the article has its title already.
      const blocks: Block[] = [...(article.title ? [{ type: "heading" as const, level: 2 as const, content: [{ text: article.title }] }] : []), ...article.blocks];
      if (!blocks.length || plain(blocks)) return false;
      event.preventDefault();
      $insertNodes($createBlockNodes(blocks));
      return true;
    }, COMMAND_PRIORITY_LOW),
    editor.registerCommand(DRAG_DROP_PASTE, (files) => {
      const images = files.filter((file) => imageTypes.includes(file.type));
      if (!images.length) return false;
      void (async () => {
        for (const file of images) {
          const src = await host.upload(file);
          if (src) editor.update(() => { $insertNodeToNearestRoot($createImageNode({ src, alt: "", caption: "" })); });
        }
      })().catch(() => toast.error("The image could not be added."));
      return true;
    }, COMMAND_PRIORITY_LOW),
  ), [editor, host]);

  return null;
}

type Place = { top: number; left: number };

/** Where an element sits inside the editor's frame, while the cursor is in a block of some kind. */
function usePlace(anchor: RefObject<HTMLElement | null>, find: () => { element: HTMLElement | null; key: string } | null) {
  const [editor] = useLexicalComposerContext();
  const [place, setPlace] = useState<(Place & { right: number; key: string }) | null>(null);
  const refresh = useCallback(() => {
    const frame = anchor.current?.getBoundingClientRect();
    const found = editor.getEditorState().read(find);
    const rect = found?.element?.getBoundingClientRect();
    setPlace(frame && found && rect ? { key: found.key, top: rect.top - frame.top, left: rect.left - frame.left, right: rect.right - frame.left } : null);
    // find reads the editor; it is the same question every time.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [editor, anchor]);
  useEffect(() => mergeRegister(
    editor.registerUpdateListener(refresh),
    editor.registerCommand(SELECTION_CHANGE_COMMAND, () => { refresh(); return false; }, COMMAND_PRIORITY_LOW),
  ), [editor, refresh]);
  return place;
}

/** The language of the code block the cursor is in, in its top right corner. */
export function CodeLanguage({ anchor }: { anchor: RefObject<HTMLElement | null> }) {
  const [editor] = useLexicalComposerContext();
  const [language, setLanguage] = useState("");
  const place = usePlace(anchor, () => {
    const selection = $getSelection();
    const block = $isRangeSelection(selection) ? selection.anchor.getNode().getTopLevelElement() : null;
    if (!$isCodeNode(block)) return null;
    setLanguage(block.getLanguage() ?? "");
    return { element: editor.getElementByKey(block.getKey()), key: block.getKey() };
  });
  if (!place) return null;
  return (
    <input
      aria-label="Code language" value={language} placeholder="Language..." autoComplete="off" spellCheck={false}
      onKeyDown={(event) => { event.stopPropagation(); if (event.key === "Enter" || event.key === "Escape") { event.preventDefault(); editor.focus(); } }}
      onChange={(event) => {
        const value = event.target.value.trim().toLowerCase();
        setLanguage(value);
        editor.update(() => {
          const selection = $getSelection();
          const block = $isRangeSelection(selection) ? selection.anchor.getNode().getTopLevelElement() : null;
          if ($isCodeNode(block)) block.setLanguage(value || null);
        });
      }}
      className="not-kg-prose absolute z-10 h-[2.4rem] w-[10rem] -translate-x-full rounded border border-(--grey-300) bg-white px-2 font-sans text-[1.2rem] leading-normal text-(--grey-900) outline-none placeholder:text-(--grey-500) focus:border-(--grey-500) in-[.dark]:border-(--grey-800) in-[.dark]:bg-(--grey-950) in-[.dark]:text-(--grey-300)"
      style={{ top: place.top + 5, left: place.right - 6 }}
    />
  );
}

/** Rows and columns of the table the cursor is in, from a handle on the current cell. */
export function TableMenu({ anchor }: { anchor: RefObject<HTMLElement | null> }) {
  const [editor] = useLexicalComposerContext();
  const place = usePlace(anchor, () => {
    const selection = $getSelection();
    if (!$isRangeSelection(selection) && !$isTableSelection(selection)) return null;
    const cell = $findCellNode(selection.anchor.getNode());
    return cell ? { element: editor.getElementByKey(cell.getKey()), key: cell.getKey() } : null;
  });
  if (!place) return null;
  const act = (change: () => void) => () => editor.update(change);
  return (
    <div className="not-kg-prose absolute z-10 font-sans leading-normal" style={{ top: place.top + 5, left: place.right - 25 }}>
      <DropdownMenu>
        <DropdownMenuTrigger asChild>
          <button type="button" aria-label="Table options" onMouseDown={(event) => event.preventDefault()} className="flex size-5 cursor-pointer items-center justify-center rounded border border-(--grey-300) bg-white text-(--grey-700) hover:text-(--grey-900) in-[.dark]:border-(--grey-800) in-[.dark]:bg-(--grey-950)">
            <ChevronDown className="size-3 stroke-2" />
          </button>
        </DropdownMenuTrigger>
        <DropdownMenuContent align="end" onCloseAutoFocus={(event) => { event.preventDefault(); editor.focus(); }}>
          <DropdownMenuItem onSelect={act(() => { $insertTableRowAtSelection(false); })}>Insert row above</DropdownMenuItem>
          <DropdownMenuItem onSelect={act(() => { $insertTableRowAtSelection(true); })}>Insert row below</DropdownMenuItem>
          <DropdownMenuItem onSelect={act(() => { $insertTableColumnAtSelection(false); })}>Insert column left</DropdownMenuItem>
          <DropdownMenuItem onSelect={act(() => { $insertTableColumnAtSelection(true); })}>Insert column right</DropdownMenuItem>
          <DropdownMenuSeparator />
          <DropdownMenuItem onSelect={act(() => { $deleteTableRowAtSelection(); })}>Delete row</DropdownMenuItem>
          <DropdownMenuItem onSelect={act(() => { $deleteTableColumnAtSelection(); })}>Delete column</DropdownMenuItem>
          <DropdownMenuItem onSelect={act(() => {
            const selection = $getSelection();
            if ($isRangeSelection(selection) || $isTableSelection(selection)) $findTableNode(selection.anchor.getNode())?.remove();
          })}>Delete table</DropdownMenuItem>
        </DropdownMenuContent>
      </DropdownMenu>
    </div>
  );
}
