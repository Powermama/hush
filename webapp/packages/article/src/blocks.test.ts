// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2026 Clemens Kressmann
import { expect, test } from "bun:test";
import rehypeStringify from "rehype-stringify";
import remarkGfm from "remark-gfm";
import remarkParse from "remark-parse";
import remarkRehype from "remark-rehype";
import { unified } from "unified";
import { readArticle, tidyInline, writeArticle, type Article } from "./blocks.ts";

const html = (markdown: string) => String(unified().use(remarkParse).use(remarkGfm).use(remarkRehype).use(rehypeStringify).processSync(markdown));

const article = `# How to dictate on a Mac without the cloud

> [!TLDR]
> - Local dictation keeps **your voice** on the Mac.
> - It needs the internet *once*, for the model.

Local dictation keeps your voice on your Mac. Read more on [the home page](/ "hush") or in
the [editorial policy](/blog/editorial-policy), with \`code\`, ~~old~~ and a\\
hard break. Stars like 2 * 3 and under_scores stay as typed.

## How does it work?

1. Open **System Settings**.
2. Choose *Keyboard*.
   - Turn on dictation.
   - Pick a [shortcut](https://support.apple.com/guide/mac-help/mh40584/mac).
3. Speak.

- [x] Model downloaded
- [ ] Microphone allowed

![The dictation settings on a Mac](media/dictate-without-cloud/settings.png "Where the setting lives")

| Tool | Runs locally | Price |
| :--- | :---: | ---: |
| hush | **yes** | free |
| Other | no | 10 $ |

\`\`\`sh
defaults read com.apple.speech
\`\`\`

> Speech stays on the device.

---

## Frequently asked questions

### Does it need the internet?

Only to download the model once.
`;

test("an article reads as blocks and is written back with the same meaning", () => {
  const { article: blocks, unsupported } = readArticle(article);
  expect(unsupported).toBeUndefined();
  expect(blocks!.title).toBe("How to dictate on a Mac without the cloud");
  expect(blocks!.blocks.map((block) => block.type)).toEqual([
    "summary", "paragraph", "heading", "list", "list", "image", "table", "code", "quote", "divider", "heading", "heading", "paragraph",
  ]);
  const written = writeArticle(blocks!);
  expect(readArticle(written).article).toEqual(blocks!);
  // The page a reader gets is the same, apart from line endings inside paragraphs.
  expect(html(written)).toBe(html(article).replace("or in\nthe", "or in the"));
  expect(written).toContain("| Tool | Runs locally | Price |\n| :--- | :---: | ---: |\n| hush | **yes** | free |");
  // Written once, it stays as it is.
  expect(writeArticle(readArticle(written).article!)).toBe(written);
});

test("blocks are written the way the hush-seo skill writes Markdown", () => {
  const blocks: Article = {
    title: "A title",
    blocks: [
      { type: "summary", blocks: [{ type: "paragraph", content: [{ text: "Short and clear." }] }] },
      { type: "summary", blocks: [{ type: "list", style: "bullet", items: [{ content: [{ text: "One point" }] }] }] },
      // As an editor hands it over; reading gives the tidy spelling of the same text.
      { type: "paragraph", content: tidyInline([{ text: "Two words", bold: true }, { text: " and " }, { text: "a link", link: { url: "/" }, italic: true }, { text: "." }]) },
      { type: "list", style: "number", start: 3, items: [{ content: [{ text: "Third" }], lists: [{ type: "list", style: "bullet", items: [{ content: [{ text: "Below" }] }] }] }] },
    ],
  };
  expect(writeArticle(blocks)).toBe([
    "# A title", "", "> [!TLDR]", "> Short and clear.", "", "> [!TLDR]", "> - One point", "",
    "**Two words** and [*a link*](/).", "", "3. Third", "   - Below", "",
  ].join("\n"));
  expect(readArticle(writeArticle(blocks)).article).toEqual(blocks);
});

test("text that looks like Markdown is written so that it stays text", () => {
  const blocks: Article = {
    title: "1. Not a list * not emphasis",
    blocks: [
      { type: "paragraph", content: [{ text: "# not a heading, [not](a link), *not* bold, <b>not html</b> and a_b_c." }] },
      { type: "paragraph", content: [{ text: "- not a list" }] },
      { type: "table", rows: [[[{ text: "a | b" }], [{ text: "x | y", code: true }]], [[{ text: "1" }], [{ text: "2" }]]] },
      { type: "code", code: "```\nfences inside\n```" },
    ],
  };
  expect(readArticle(writeArticle(blocks)).article).toEqual(blocks);
});

test("spaces carry no formatting and equal neighbours join", () => {
  expect(tidyInline([{ text: "a ", bold: true }, { text: "b", bold: true }, { text: " c" }, { text: "", italic: true }]))
    .toEqual([{ text: "a", bold: true }, { text: " " }, { text: "b", bold: true }, { text: " c" }]);
});

test("an article without a heading, or with none of anything, is still an article", () => {
  expect(readArticle("").article).toEqual({ title: "", blocks: [] });
  expect(writeArticle({ title: "", blocks: [] })).toBe("");
  expect(readArticle("Just a thought.").article).toEqual({ title: "", blocks: [{ type: "paragraph", content: [{ text: "Just a thought." }] }] });
  expect(writeArticle({ title: "  Only a title ", blocks: [] })).toBe("# Only a title\n");
});

test("Markdown that blocks cannot hold exactly is reported, not changed", () => {
  const cases: Array<[string, string]> = [
    ["# Title\n\n<div>raw</div>", "raw HTML"],
    ["# Title\n\nText with <b>raw</b> inside.", "raw HTML"],
    ["# Title\n\n> One paragraph.\n>\n> Another.", "a quote holding more than one paragraph"],
    ["# Title\n\n- An item\n\n  with a second paragraph", "a list item with more than one paragraph or another block"],
    ["# Title\n\nA note.[^1]\n\n[^1]: The note.", '"footnoteReference" in text'],
    ["# Title\n\nSee [the docs][docs].\n\n[docs]: https://example.com", '"linkReference" in text'],
    ["# Title\n\nText ![inline](media/a/b.png) image.", "an image inside a line of text"],
    ["# A *styled* title", "formatting in the H1"],
    ["Intro first.\n\n# Title", "a second H1, or an H1 that is not the first line"],
    ["# Title\n\n```js {1,2}\ncode\n```", "a code block with options after its language"],
    ["# Title\n\n> [!TLDR]\n> ```\n> code\n> ```", '"code" inside the summary'],
  ];
  for (const [markdown, reason] of cases) expect(readArticle(markdown)).toEqual({ unsupported: reason });
});
