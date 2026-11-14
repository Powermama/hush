// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2026 Clemens Kressmann
//
// The post's images. An upload is named for the Markdown that references it,
// media/<slug>/<name>; the CMS converts it to WebP when the post renders.
import { useQueryClient } from "@tanstack/react-query";
import { CopyIcon, ImageUpIcon } from "lucide-react";
import { useRef, useState } from "react";
import { toast } from "sonner";
import { getListMediaQueryKey, uploadMedia, useListMedia, type Media } from "@/api/cms.generated";
import { CmsError } from "@/api/fetcher";
import { Button } from "@/components/ui/button";

/** A lowercase, dash-separated name the CMS accepts, keeping the extension. */
function mediaName(file: File) {
  const extension = file.type === "image/jpeg" ? "jpg" : file.type === "image/webp" ? "webp" : "png";
  const base = file.name.replace(/\.[^.]+$/, "").toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-+|-+$/g, "") || "image";
  return `${base}.${extension}`;
}

export function PostMedia({ postId, slug }: { postId: string; slug: string }) {
  const queryClient = useQueryClient();
  const media = useListMedia(postId);
  const input = useRef<HTMLInputElement>(null);
  const [uploading, setUploading] = useState(false);
  const items: Media[] = media.data?.data && "media" in media.data.data ? media.data.data.media : [];

  const upload = async (files: FileList | null) => {
    if (!files?.length) return;
    setUploading(true);
    try {
      for (const file of files) {
        await uploadMedia(postId, mediaName(file), file, { headers: { "Content-Type": file.type } });
      }
      await queryClient.invalidateQueries({ queryKey: getListMediaQueryKey(postId) });
      toast.success(files.length === 1 ? "Image uploaded" : `${files.length} images uploaded`);
    } catch (error) {
      toast.error(error instanceof CmsError ? error.message : "The upload failed.");
    } finally {
      setUploading(false);
      if (input.current) input.current.value = "";
    }
  };

  const markdownFor = (name: string) => `![Describe the image](media/${slug}/${name})`;

  return (
    <section className="grid gap-3">
      <div className="flex items-center justify-between">
        <h3 className="text-sm font-semibold">Images</h3>
        <Button variant="outline" size="sm" disabled={uploading} onClick={() => input.current?.click()}><ImageUpIcon />{uploading ? "Uploading…" : "Upload"}</Button>
        <input ref={input} type="file" accept="image/png,image/jpeg,image/webp" multiple hidden onChange={(event) => void upload(event.target.files)} />
      </div>
      <p className="text-xs text-muted-foreground">PNG, JPEG or WebP up to 10 MB, at least 680 px wide. Paste the Markdown into the article on a line of its own.</p>
      {items.length === 0 && <p className="text-xs text-muted-foreground">No images yet.</p>}
      <ul className="grid gap-2">
        {items.map((item) => (
          <li key={item.id} className="flex items-center gap-2 rounded-md border border-border px-3 py-2 text-xs">
            <span className="min-w-0 flex-1 truncate font-mono">{item.name}</span>
            <span className="text-muted-foreground tabular-nums">{item.width}×{item.height}</span>
            <Button variant="ghost" size="icon-sm" aria-label={`Copy Markdown for ${item.name}`} onClick={() => { void navigator.clipboard.writeText(markdownFor(item.name)); toast.success("Markdown copied"); }}><CopyIcon /></Button>
          </li>
        ))}
      </ul>
    </section>
  );
}
