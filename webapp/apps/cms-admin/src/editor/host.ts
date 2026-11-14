// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2026 Clemens Kressmann
//
// What the editor needs from the screen around it: the post its images belong to.
import { createContext, useContext } from "react";

export type EditorHost = {
  /** Stores an image with the post (saving a new post first) and returns how the article refers to it. */
  upload(file: File): Promise<string | undefined>;
  /** Where the browser loads an article image ("media/<slug>/<name>") from, once it is stored. */
  imageUrl(src: string): string | undefined;
  /** Whether the post's stored images are known yet; until then a missing one may still be on its way. */
  mediaLoaded: boolean;
};

export const EditorHostContext = createContext<EditorHost | null>(null);

export function useEditorHost() {
  const host = useContext(EditorHostContext);
  if (!host) throw new Error("The editor needs an EditorHostContext.");
  return host;
}

export const imageTypes = ["image/png", "image/jpeg", "image/webp"];
