// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2026 Clemens Kressmann
//
// The article body in CodeMirror 6: Markdown with soft wrapping, undo history
// and Mod-s to save. Uncontrolled after mount; changes flow out via onChange.
import { defaultKeymap, history, historyKeymap } from "@codemirror/commands";
import { markdown } from "@codemirror/lang-markdown";
import { EditorState } from "@codemirror/state";
import { EditorView, keymap, placeholder } from "@codemirror/view";
import { useEffect, useRef } from "react";

const theme = EditorView.theme({
  "&": { fontSize: "17px", backgroundColor: "transparent" },
  "&.cm-focused": { outline: "none" },
  ".cm-scroller": { fontFamily: "var(--font-sans)" },
  ".cm-content": { lineHeight: "1.75", padding: "8px 0 160px", caretColor: "var(--color-black)", color: "#2b2c29" },
  ".cm-line": { padding: "0" },
  ".cm-placeholder": { color: "var(--color-gray-700)" },
  ".cm-selectionBackground, &.cm-focused .cm-selectionBackground": { backgroundColor: "var(--color-gray-200)" },
});

export function MarkdownEditor({ value, onChange, onSave, label }: {
  value: string; onChange: (value: string) => void; onSave: () => void; label: string;
}) {
  const host = useRef<HTMLDivElement>(null);
  const callbacks = useRef({ onChange, onSave });
  callbacks.current = { onChange, onSave };

  useEffect(() => {
    const view = new EditorView({
      parent: host.current!,
      state: EditorState.create({
        doc: value,
        extensions: [
          history(),
          keymap.of([{ key: "Mod-s", preventDefault: true, run: () => { callbacks.current.onSave(); return true; } }, ...defaultKeymap, ...historyKeymap]),
          markdown(),
          EditorView.lineWrapping,
          EditorView.contentAttributes.of({ "aria-label": label, "aria-multiline": "true" }),
          placeholder("Start with the article's H1: # …"),
          EditorView.updateListener.of((update) => { if (update.docChanged) callbacks.current.onChange(update.state.doc.toString()); }),
          theme,
        ],
      }),
    });
    return () => view.destroy();
    // The document is set once; later values come from the editor itself.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  return <div ref={host} className="min-h-[60vh]" />;
}
