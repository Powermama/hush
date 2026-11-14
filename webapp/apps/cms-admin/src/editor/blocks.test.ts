// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2026 Clemens Kressmann
//
// The editor shows an article as nodes and hands it back as the same blocks,
// so opening an article in the editor and saving it changes nothing.
import { expect, test } from "bun:test";
import { readArticle, writeArticle, type Block } from "@hush/article/blocks";
import { createHeadlessEditor } from "@lexical/headless";
import { $createParagraphNode, $createTextNode, $getRoot } from "lexical";
import { $getBlocks, $setBlocks } from "./blocks";
import { articleNodes } from "./nodes";

const article = `# How to dictate on a Mac without the cloud

> [!TLDR]
> Short and clear.
>
> - Local dictation keeps **your voice** on the Mac.
> - It needs the internet *once*, for the model.

Local dictation keeps your voice on your Mac. Read more on [the *home* page](/ "hush") with \`code\`, ~~old~~ and a\\
hard break.

## How does it work?

1. Open **System Settings**.
2. Choose *Keyboard*.
   - Turn on dictation.
   - Pick a [shortcut](https://support.apple.com/guide/mac-help/mh40584/mac).
     1. Deeper still.
3. Speak.

Later steps:

5. A list that starts at five.

Notes:

- A loose list.

- With space between its items.

Checks:

- [x] Model downloaded
- [ ] Microphone allowed

![The dictation settings on a Mac](media/dictate-without-cloud/settings.png "Where the setting lives")

![No caption here](media/dictate-without-cloud/plain.png)

| Tool | Runs locally | Price |
| :--- | :---: | ---: |
| hush | **yes** | free |
| Other | no, see [why](/) | 10 $ |

\`\`\`sh
defaults read com.apple.speech

  indented --flag
\`\`\`

\`\`\`
no language
\`\`\`

> Speech stays on the *device*.

---

## Frequently asked questions

### Does it need the internet?

Only to download the model once.
`;

function editor() {
  return createHeadlessEditor({ namespace: "test", nodes: articleNodes, onError: (error) => { throw error; } });
}

/** Blocks through the editor: set, then read back. */
test("the sample is an article blocks can hold", () => {
  expect(readArticle(article).unsupported).toBeUndefined();
});

function through(blocks: Block[]) {
  const lexical = editor();
  lexical.update(() => $setBlocks(blocks), { discrete: true });
  return lexical.read(() => $getBlocks());
}

test("every kind of block survives the editor unchanged", () => {
  const { blocks } = readArticle(article).article!;
  expect(new Set(blocks.map((block) => block.type))).toEqual(new Set(["summary", "paragraph", "heading", "list", "image", "table", "code", "quote", "divider"]));
  expect(through(blocks)).toEqual(blocks);
  expect(writeArticle({ title: "How to dictate on a Mac without the cloud", blocks: through(blocks) })).toBe(writeArticle(readArticle(article).article!));
});

test("the editor's state survives being stored and loaded", () => {
  const { blocks } = readArticle(article).article!;
  const first = editor();
  first.update(() => $setBlocks(blocks), { discrete: true });
  const second = editor();
  second.setEditorState(second.parseEditorState(JSON.stringify(first.getEditorState())));
  expect(second.read(() => $getBlocks())).toEqual(blocks);
});

test("an empty article is one empty paragraph to write in, and reads as no blocks", () => {
  const lexical = editor();
  lexical.update(() => $setBlocks([]), { discrete: true });
  expect(lexical.read(() => $getRoot().getChildrenSize())).toBe(1);
  expect(lexical.read(() => $getBlocks())).toEqual([]);
});

test("what an author types into the nodes comes back as blocks", () => {
  const lexical = editor();
  lexical.update(() => $setBlocks(readArticle("- First\n- Second").article!.blocks), { discrete: true });
  lexical.update(() => {
    const bold = $createTextNode("bold start ");
    bold.toggleFormat("bold");
    $getRoot().append($createParagraphNode().append(bold, $createTextNode("and plain.")), $createParagraphNode());
  }, { discrete: true });
  const blocks = lexical.read(() => $getBlocks());
  expect(blocks.at(-1)).toEqual({ type: "paragraph", content: [{ text: "bold", bold: true }, { text: " " }, { text: "start", bold: true }, { text: " and plain." }] });
  expect(writeArticle({ title: "", blocks: [blocks.at(-1)!] })).toBe("**bold start** and plain.\n");
});
