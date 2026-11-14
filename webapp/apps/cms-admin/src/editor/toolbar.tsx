// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2026 Clemens Kressmann
//
// Koenig's floating toolbar: it appears above selected text with bold, italic,
// the two headings, quote and link. Link turns it into a field for the address;
// with the cursor inside a link it shows where the link goes.
import { $isCodeNode } from "@lexical/code";
import { $isLinkNode, TOGGLE_LINK_COMMAND, type LinkNode } from "@lexical/link";
import { useLexicalComposerContext } from "@lexical/react/LexicalComposerContext";
import { $createHeadingNode, $createQuoteNode, $isHeadingNode, $isQuoteNode } from "@lexical/rich-text";
import { $setBlocksType } from "@lexical/selection";
import { $findMatchingParent, mergeRegister } from "@lexical/utils";
import {
  $createParagraphNode, $getSelection, $isRangeSelection, $setSelection, COMMAND_PRIORITY_LOW, COMMAND_PRIORITY_NORMAL, FORMAT_TEXT_COMMAND,
  KEY_DOWN_COMMAND, KEY_ESCAPE_COMMAND, SELECTION_CHANGE_COMMAND, type BaseSelection,
} from "lexical";
import { Bold, Heading2, Heading3, Italic, Link2, Pencil, Quote, Unlink } from "lucide-react";
import { useCallback, useEffect, useRef, useState, type ReactNode, type RefObject } from "react";
import { Tooltip, TooltipContent, TooltipTrigger } from "@/components/ui/tooltip";
import { cn } from "@/lib/utils";

type Active = { bold: boolean; italic: boolean; h2: boolean; h3: boolean; quote: boolean; link: boolean };
type View =
  | { mode: "format"; left: number; top: number; active: Active }
  | { mode: "link"; left: number; top: number; url: string }
  | { mode: "linkInfo"; left: number; top: number; url: string };

const mac = typeof navigator !== "undefined" && /Mac|iPhone|iPad/.test(navigator.platform);
const mod = mac ? "⌘" : "Ctrl+";
const ctrlAlt = mac ? "⌃⌥" : "Ctrl+Alt+";

/** A typed address as a link target: site paths, anchors and schemes stay, a bare domain gets https. */
export function linkTarget(text: string) {
  const url = text.trim();
  return !url || /^([a-z][a-z0-9+.-]*:|\/|#)/i.test(url) ? url : `https://${url}`;
}

function ToolbarButton({ label, shortcut, active, onClick, children }: { label: string; shortcut?: string; active?: boolean; onClick: () => void; children: ReactNode }) {
  return (
    <li className="m-0 flex p-0 first:ml-0">
      <Tooltip>
        <TooltipTrigger asChild>
          <button
            type="button" aria-label={label} aria-pressed={active}
            // The selection stays in the text while the toolbar is used.
            onMouseDown={(event) => event.preventDefault()} onClick={onClick}
            className={cn("my-1 flex h-8 w-9 cursor-pointer items-center justify-center rounded-md transition-colors hover:bg-gray-200/80 dark:hover:bg-gray-900", active ? "text-green-600" : "text-foreground")}
          >
            {children}
          </button>
        </TooltipTrigger>
        <TooltipContent side="top" sideOffset={8}>{label}{shortcut && <span className="ml-2 opacity-60">{shortcut}</span>}</TooltipContent>
      </Tooltip>
    </li>
  );
}

export function FloatingToolbar({ anchor }: { anchor: RefObject<HTMLElement | null> }) {
  const [editor] = useLexicalComposerContext();
  const [view, setView] = useState<View | null>(null);
  const mouseDown = useRef(false);
  // The text selection the link field works on, while the field has the focus.
  const linkSelection = useRef<BaseSelection | null>(null);

  const place = useCallback((rect: DOMRect) => {
    const frame = anchor.current!.getBoundingClientRect();
    const center = rect.left + rect.width / 2 - frame.left;
    return { left: Math.min(Math.max(center, 130), Math.max(frame.width - 130, 130)), top: rect.top - frame.top };
  }, [anchor]);

  const refresh = useCallback(() => {
    if (mouseDown.current || !anchor.current) return;
    setView((current) => {
      if (current?.mode === "link") return current;
      return editor.getEditorState().read((): View | null => {
        const selection = $getSelection();
        const range = window.getSelection();
        if (!$isRangeSelection(selection) || !range?.rangeCount || !editor.getRootElement()?.contains(range.anchorNode)) return null;
        const node = selection.anchor.getNode();
        const block = node.getTopLevelElement();
        if ($isCodeNode(block)) return null;
        const link = $findMatchingParent(node, $isLinkNode) ?? $findMatchingParent(selection.focus.getNode(), $isLinkNode);
        if (selection.isCollapsed()) {
          const element = link && editor.getElementByKey(link.getKey());
          return element ? { mode: "linkInfo", ...place(element.getBoundingClientRect()), url: link.getURL() } : null;
        }
        if (!selection.getTextContent().trim()) return null;
        return {
          mode: "format", ...place(range.getRangeAt(0).getBoundingClientRect()),
          active: {
            bold: selection.hasFormat("bold"), italic: selection.hasFormat("italic"),
            h2: $isHeadingNode(block) && block.getTag() === "h2", h3: $isHeadingNode(block) && block.getTag() === "h3",
            quote: $isQuoteNode(block), link: Boolean(link),
          },
        };
      });
    });
  }, [editor, anchor, place]);

  const openLink = useCallback(() => {
    editor.update(() => {
      const selection = $getSelection();
      if (!$isRangeSelection(selection)) return;
      const link = $findMatchingParent(selection.anchor.getNode(), $isLinkNode) as LinkNode | null;
      // With the cursor in a link, the whole link is what gets edited.
      if (link && selection.isCollapsed()) link.select(0, link.getChildrenSize());
      else if (selection.isCollapsed()) return;
      linkSelection.current = $getSelection()!.clone();
      const element = link && editor.getElementByKey(link.getKey());
      const rect = element?.getBoundingClientRect() ?? window.getSelection()!.getRangeAt(0).getBoundingClientRect();
      setView({ mode: "link", ...place(rect), url: link?.getURL() ?? "" });
    });
  }, [editor, place]);

  const closeLink = useCallback((url?: string) => {
    const selection = linkSelection.current;
    linkSelection.current = null;
    setView(null);
    editor.update(() => { if (selection) $setSelection(selection.clone()); });
    if (url !== undefined) editor.dispatchCommand(TOGGLE_LINK_COMMAND, linkTarget(url) || null);
    editor.focus();
  }, [editor]);

  const setBlock = useCallback((kind: "h2" | "h3" | "quote", active: boolean) => editor.update(() => {
    const selection = $getSelection();
    if (!$isRangeSelection(selection)) return;
    $setBlocksType(selection, () => (active ? $createParagraphNode() : kind === "quote" ? $createQuoteNode() : $createHeadingNode(kind)));
  }), [editor]);

  useEffect(() => {
    const down = () => { mouseDown.current = true; };
    const up = () => { mouseDown.current = false; setTimeout(refresh); };
    document.addEventListener("mousedown", down);
    document.addEventListener("mouseup", up);
    window.addEventListener("resize", refresh);
    const unregister = mergeRegister(
      editor.registerUpdateListener(refresh),
      editor.registerCommand(SELECTION_CHANGE_COMMAND, () => { refresh(); return false; }, COMMAND_PRIORITY_LOW),
      editor.registerCommand(KEY_ESCAPE_COMMAND, () => { setView(null); return false; }, COMMAND_PRIORITY_LOW),
      editor.registerCommand(KEY_DOWN_COMMAND, (event) => {
        const command = mac ? event.metaKey : event.ctrlKey;
        const key = event.key.toLowerCase();
        if (command && !event.shiftKey && !event.altKey && key === "k") { event.preventDefault(); openLink(); return true; }
        if (event.ctrlKey && event.altKey && (event.code === "Digit2" || event.code === "Digit3")) {
          event.preventDefault();
          const kind = event.code === "Digit2" ? "h2" : "h3";
          const active = editor.getEditorState().read(() => {
            const selection = $getSelection();
            const block = $isRangeSelection(selection) ? selection.anchor.getNode().getTopLevelElement() : null;
            return $isHeadingNode(block) && block.getTag() === kind;
          });
          setBlock(kind, active);
          return true;
        }
        if (event.ctrlKey && !event.altKey && !event.metaKey && key === "q") {
          event.preventDefault();
          const active = editor.getEditorState().read(() => {
            const selection = $getSelection();
            return $isRangeSelection(selection) && $isQuoteNode(selection.anchor.getNode().getTopLevelElement());
          });
          setBlock("quote", active);
          return true;
        }
        return false;
      }, COMMAND_PRIORITY_NORMAL),
    );
    return () => {
      document.removeEventListener("mousedown", down);
      document.removeEventListener("mouseup", up);
      window.removeEventListener("resize", refresh);
      unregister();
    };
  }, [editor, refresh, openLink, setBlock]);

  if (!view) return null;
  const bar = "flex items-center rounded-lg bg-white font-sans text-[1.3rem] font-medium shadow-md dark:bg-gray-950 dark:shadow-none dark:ring-1 dark:ring-gray-900";
  return (
    <div
      data-editor-toolbar={view.mode}
      className={cn("not-kg-prose absolute z-30 -translate-x-1/2 leading-normal motion-safe:animate-in motion-safe:fade-in motion-safe:duration-100", view.mode === "linkInfo" ? "translate-y-2" : "-translate-y-full")}
      style={{ left: view.left, top: view.mode === "linkInfo" ? view.top + 28 : view.top - 10 }}
    >
      {view.mode === "format" && (
        <ul className={cn(bar, "m-0 list-none gap-1 px-1")}>
          <ToolbarButton label="Bold" shortcut={`${mod}B`} active={view.active.bold} onClick={() => editor.dispatchCommand(FORMAT_TEXT_COMMAND, "bold")}><Bold className="size-4 stroke-[2.5]" /></ToolbarButton>
          <ToolbarButton label="Italic" shortcut={`${mod}I`} active={view.active.italic} onClick={() => editor.dispatchCommand(FORMAT_TEXT_COMMAND, "italic")}><Italic className="size-4 stroke-[2.5]" /></ToolbarButton>
          <ToolbarButton label="Heading 2" shortcut={`${ctrlAlt}2`} active={view.active.h2} onClick={() => setBlock("h2", view.active.h2)}><Heading2 className="size-[1.8rem] stroke-[2.25]" /></ToolbarButton>
          <ToolbarButton label="Heading 3" shortcut={`${ctrlAlt}3`} active={view.active.h3} onClick={() => setBlock("h3", view.active.h3)}><Heading3 className="size-[1.8rem] stroke-[2.25]" /></ToolbarButton>
          <li aria-hidden className="m-0 w-px self-stretch bg-gray-300/80 p-0 dark:bg-gray-900" />
          <ToolbarButton label="Quote" shortcut={mac ? "⌃Q" : "Ctrl+Q"} active={view.active.quote} onClick={() => setBlock("quote", view.active.quote)}><Quote className="size-4 stroke-[2.5]" /></ToolbarButton>
          <ToolbarButton label="Link" shortcut={`${mod}K`} active={view.active.link} onClick={openLink}><Link2 className="size-4 stroke-[2.5]" /></ToolbarButton>
        </ul>
      )}
      {view.mode === "link" && (
        <form className={cn(bar, "w-[32rem] px-3")} onSubmit={(event) => { event.preventDefault(); closeLink(new FormData(event.currentTarget).get("url") as string); }}>
          <input
            name="url" aria-label="Link address" autoFocus defaultValue={view.url} placeholder="Enter url" autoComplete="off" spellCheck={false}
            onKeyDown={(event) => { event.stopPropagation(); if (event.key === "Escape") { event.preventDefault(); closeLink(); } }}
            onBlur={() => { if (linkSelection.current) closeLink(); }}
            className="h-10 w-full border-0 bg-transparent p-0 text-[1.4rem] font-normal text-foreground outline-none placeholder:text-gray-500"
          />
        </form>
      )}
      {view.mode === "linkInfo" && (
        <div className={cn(bar, "max-w-[36rem] gap-1 py-1 pr-1 pl-3")}>
          <a href={view.url} target="_blank" rel="noreferrer" className="min-w-0 truncate text-[1.3rem] font-normal text-foreground underline-offset-2 hover:underline" onMouseDown={(event) => event.preventDefault()}>{view.url}</a>
          <button type="button" aria-label="Edit link" onMouseDown={(event) => event.preventDefault()} onClick={openLink} className="flex size-8 shrink-0 cursor-pointer items-center justify-center rounded-md hover:bg-gray-200/80 dark:hover:bg-gray-900"><Pencil className="size-[1.4rem]" /></button>
          <button type="button" aria-label="Remove link" onMouseDown={(event) => event.preventDefault()} onClick={() => { editor.dispatchCommand(TOGGLE_LINK_COMMAND, null); setView(null); }} className="flex size-8 shrink-0 cursor-pointer items-center justify-center rounded-md hover:bg-gray-200/80 dark:hover:bg-gray-900"><Unlink className="size-[1.4rem]" /></button>
        </div>
      )}
    </div>
  );
}
