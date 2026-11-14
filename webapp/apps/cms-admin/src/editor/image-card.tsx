// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2026 Clemens Kressmann
//
// An image in the article, as Koenig's image card: the picture, a caption
// under it and an "Alt" switch that turns the caption field into the alt text.
// Without a picture yet it is a place to click or drop one.
import { useLexicalComposerContext } from "@lexical/react/LexicalComposerContext";
import { useLexicalNodeSelection } from "@lexical/react/useLexicalNodeSelection";
import { mergeRegister } from "@lexical/utils";
import {
  $createParagraphNode, $getNodeByKey, $getSelection, $isNodeSelection, CLICK_COMMAND, COMMAND_PRIORITY_LOW, KEY_BACKSPACE_COMMAND,
  KEY_DELETE_COMMAND, KEY_ENTER_COMMAND, type NodeKey,
} from "lexical";
import { ImageIcon } from "lucide-react";
import { useEffect, useRef, useState } from "react";
import { toast } from "sonner";
import { LoadingIndicator } from "@/components/ui/loading-indicator";
import { cn } from "@/lib/utils";
import { imageTypes, useEditorHost } from "./host";
import type { Image, ImageNode } from "./nodes";

export function ImageCard({ nodeKey, image }: { nodeKey: NodeKey; image: Image }) {
  const [editor] = useLexicalComposerContext();
  const host = useEditorHost();
  const [selected, setSelected, clearSelection] = useLexicalNodeSelection(nodeKey);
  const [editingAlt, setEditingAlt] = useState(false);
  const [uploading, setUploading] = useState(false);
  const [over, setOver] = useState(false);
  const card = useRef<HTMLElement>(null);
  const picker = useRef<HTMLInputElement>(null);
  const url = image.src ? host.imageUrl(image.src) : undefined;

  const change = (patch: Partial<Image>) => editor.update(() => { ($getNodeByKey(nodeKey) as ImageNode | null)?.setImage(patch); });

  const choose = async (file: File | undefined) => {
    if (!file) return;
    if (!imageTypes.includes(file.type)) { toast.error("Use a PNG, JPEG or WebP image."); return; }
    setUploading(true);
    try {
      const src = await host.upload(file);
      if (src) change({ src });
    } finally {
      setUploading(false);
    }
  };

  useEffect(() => mergeRegister(
    editor.registerCommand(CLICK_COMMAND, (event) => {
      if (!card.current?.contains(event.target as Node)) return false;
      // The fields keep their own cursor; a click anywhere else on the card selects it.
      if ((event.target as HTMLElement).closest("input")) return false;
      if (!event.shiftKey) clearSelection();
      setSelected(true);
      return true;
    }, COMMAND_PRIORITY_LOW),
    ...[KEY_BACKSPACE_COMMAND, KEY_DELETE_COMMAND].map((command) => editor.registerCommand(command, (event) => {
      if (!selected || !$isNodeSelection($getSelection())) return false;
      event.preventDefault();
      $getNodeByKey(nodeKey)?.remove();
      return true;
    }, COMMAND_PRIORITY_LOW)),
    editor.registerCommand(KEY_ENTER_COMMAND, (event) => {
      if (!selected || !$isNodeSelection($getSelection())) return false;
      event?.preventDefault();
      const paragraph = $createParagraphNode();
      $getNodeByKey(nodeKey)?.insertAfter(paragraph);
      paragraph.select();
      return true;
    }, COMMAND_PRIORITY_LOW),
  ), [editor, nodeKey, selected, setSelected, clearSelection]);

  const field = editingAlt
    ? { value: image.alt, placeholder: "Type alt text for image (optional)", label: "Alt text", set: (alt: string) => change({ alt }) }
    : { value: image.caption, placeholder: "Type caption for image (optional)", label: "Caption", set: (caption: string) => change({ caption }) };

  return (
    <figure
      ref={card}
      data-selected={selected || undefined}
      className={cn("not-kg-prose relative m-0 rounded-[3px] font-sans leading-normal transition-shadow", selected ? "shadow-[0_0_0_2px_var(--green)]" : "hover:shadow-[0_0_0_1px_var(--green)]")}
    >
      {url ? (
        <img src={url} alt={image.alt} draggable={false} className="mx-auto block h-auto max-w-full" />
      ) : image.src && !host.mediaLoaded ? (
        <div role="status" aria-label="Loading image" className="flex h-[22vh] min-h-[160px] w-full items-center justify-center bg-(--grey-50) in-[.dark]:bg-(--grey-950)">
          <LoadingIndicator size="md" />
        </div>
      ) : (
        <button
          type="button"
          aria-label="Select an image"
          disabled={uploading}
          onClick={() => picker.current?.click()}
          onDragOver={(event) => { event.preventDefault(); setOver(true); }}
          onDragLeave={() => setOver(false)}
          onDrop={(event) => { event.preventDefault(); event.stopPropagation(); setOver(false); void choose(event.dataTransfer.files[0]); }}
          className={cn(
            "flex h-[22vh] min-h-[160px] w-full cursor-pointer flex-col items-center justify-center gap-3 border border-(--grey-200) bg-(--grey-50) text-(--grey-800) transition-colors hover:text-(--grey-900) in-[.dark]:border-(--grey-900) in-[.dark]:bg-(--grey-950) in-[.dark]:text-(--grey-500)",
            over && "border-(--green) bg-(--grey-100)",
          )}
        >
          {uploading ? <LoadingIndicator size="md" /> : <ImageIcon className="size-8 stroke-[1.25]" />}
          <span className="text-[1.3rem] font-medium">
            {uploading ? "Uploading..." : image.src ? `${image.src.split("/").at(-1)} is not uploaded yet. Click to select it` : "Click to select an image"}
          </span>
        </button>
      )}
      <input ref={picker} type="file" accept={imageTypes.join(",")} hidden onChange={(event) => { void choose(event.target.files?.[0]); event.target.value = ""; }} />
      {(url || image.src) && (
        <figcaption className="relative flex min-h-[3.6rem] items-center px-14 py-2">
          <input
            aria-label={field.label}
            value={field.value}
            placeholder={field.placeholder}
            onChange={(event) => field.set(event.target.value)}
            // Typing here is the field's own business, not the editor's.
            onKeyDown={(event) => event.stopPropagation()}
            onFocus={() => clearSelection()}
            className="w-full border-0 bg-transparent p-0 text-center text-[1.4rem] tracking-[0.04rem] text-(--grey-900) outline-none placeholder:text-(--grey-500) in-[.dark]:text-(--grey-300)"
          />
          <button
            type="button"
            aria-pressed={editingAlt}
            onClick={() => setEditingAlt((value) => !value)}
            className={cn(
              "absolute right-0 bottom-2 cursor-pointer rounded border px-2 text-[1.3rem] leading-[2.2rem] font-normal tracking-[0.04rem] transition-colors",
              editingAlt ? "border-(--green) bg-(--green) text-white" : "border-(--grey-300) text-(--grey-600) hover:text-(--grey-900) in-[.dark]:border-(--grey-800)",
            )}
          >
            Alt
          </button>
        </figcaption>
      )}
    </figure>
  );
}
