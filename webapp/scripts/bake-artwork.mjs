// Bake editorial colour treatments into image files so pages run no CSS or SVG
// filters at runtime. WebKit renders those filters on the CPU in its GPU
// process, which stalls WebGL frame delivery on the same page.
// Rebuild after changing a treatment or a source image.
// Run from webapp: node scripts/bake-artwork.mjs
import { readFile, writeFile } from "node:fs/promises";
import { chromium } from "playwright";

const art = "src/media/art";

// Each duotone first removes colour, then maps dark/light values to two inks.
const duotones = {
  blue: { r: "0.055 0.79", g: "0.20 0.94", b: "0.37 0.93" },
  coral: { r: "0.06 1", g: "0.12 0.73", b: "0.22 0.66" },
  print: { r: "0.10 0.90", g: "0.19 0.94", b: "0.38 0.99" },
};

// Source files stay untreated. Outputs are imported through Vite for hashing.
const treatments = [
  { output: "aristotle-blue", sources: ["aristotle", "aristotle-small"], filter: "url(#blue) saturate(.55) hue-rotate(20deg)" },
  { output: "liberty-coral", sources: ["liberty", "liberty-small"], filter: "url(#coral) saturate(.7)" },
  { output: "liberty-coral-echo", sources: ["liberty"], filter: "url(#coral)" },
  { output: "geographer-muted", sources: ["geographer", "geographer-small"], filter: "saturate(.62)" },
  { output: "printing-press-print", sources: ["printing-press", "printing-press-small"], filter: "url(#print)" },
  { output: "printing-press-print-echo", sources: ["printing-press", "printing-press-small"], filter: "url(#print) hue-rotate(85deg)" },
  { output: "twittering-machine-muted", sources: ["twittering-machine", "twittering-machine-small"], filter: "saturate(.4) hue-rotate(350deg) contrast(.92)" },
  { output: "robot-portrait-teal", sources: ["robot-portrait", "robot-portrait-small"], filter: "grayscale(1) sepia(.35) hue-rotate(150deg)" },
  { output: "robot-portrait-violet", sources: ["robot-portrait"], filter: "grayscale(1) sepia(.5) hue-rotate(280deg)" },
];

// Hero app icons: 96 px sources shown at 48 CSS px. The 2 px CSS drop shadow is
// baked at source scale into a 1/12 padding on every side, so the icon stays put.
const icons = ["chrome", "figma", "mail", "messages", "notes", "notion", "slack"];
const iconShadow = { padding: 8, filter: "drop-shadow(0 4px 4px #0001)" };

const svg = `<svg width="0" height="0"><defs>${Object.entries(duotones).map(([id, ink]) =>
  `<filter id="${id}" color-interpolation-filters="sRGB"><feColorMatrix type="saturate" values="0"/>` +
  `<feComponentTransfer><feFuncR type="table" tableValues="${ink.r}"/><feFuncG type="table" tableValues="${ink.g}"/>` +
  `<feFuncB type="table" tableValues="${ink.b}"/></feComponentTransfer></filter>`).join("")}</defs></svg>`;

const browser = await chromium.launch();
try {
  const page = await browser.newPage();
  await page.setContent(`<!doctype html><body>${svg}</body>`);
  for (const { output, sources, filter } of treatments) {
    for (const source of sources) {
      const input = (await readFile(`${art}/${source}.webp`)).toString("base64");
      const target = source.replace(source.replace(/-small$/, ""), output);
      const result = await page.evaluate(async ({ input, filter }) => {
        const image = new Image();
        image.src = `data:image/webp;base64,${input}`;
        await image.decode();
        const canvas = document.createElement("canvas");
        canvas.width = image.naturalWidth;
        canvas.height = image.naturalHeight;
        const context = canvas.getContext("2d", { colorSpace: "srgb" });
        context.filter = filter;
        context.drawImage(image, 0, 0);
        // Reject a silently ignored filter: an unknown url() draws the source unchanged.
        const probe = document.createElement("canvas").getContext("2d");
        probe.canvas.width = canvas.width; probe.canvas.height = canvas.height;
        probe.drawImage(image, 0, 0);
        const a = context.getImageData(0, 0, canvas.width, canvas.height).data;
        const b = probe.getImageData(0, 0, canvas.width, canvas.height).data;
        let changed = 0;
        for (let i = 0; i < a.length; i += 4) if (a[i] !== b[i] || a[i + 1] !== b[i + 1] || a[i + 2] !== b[i + 2]) changed++;
        const blob = await new Promise(resolve => canvas.toBlob(resolve, "image/webp", 0.85));
        const bytes = new Uint8Array(await blob.arrayBuffer());
        let binary = "";
        for (let i = 0; i < bytes.length; i += 0x8000) binary += String.fromCharCode(...bytes.subarray(i, i + 0x8000));
        return { data: btoa(binary), changed: changed / (a.length / 4), type: blob.type };
      }, { input, filter });
      if (result.type !== "image/webp") throw new Error(`${target}: browser did not encode WebP`);
      if (result.changed < 0.5) throw new Error(`${target}: filter "${filter}" left the image unchanged`);
      await writeFile(`${art}/${target}.webp`, Buffer.from(result.data, "base64"));
      console.log(`${target}.webp`);
    }
  }
  for (const icon of icons) {
    const path = `src/media/app-icons/${icon}.png`;
    const input = (await readFile(path)).toString("base64");
    const data = await page.evaluate(async ({ input, padding, filter }) => {
      const image = new Image();
      image.src = `data:image/png;base64,${input}`;
      await image.decode();
      const canvas = document.createElement("canvas");
      canvas.width = image.naturalWidth + padding * 2;
      canvas.height = image.naturalHeight + padding * 2;
      const context = canvas.getContext("2d", { colorSpace: "srgb" });
      context.filter = filter;
      context.drawImage(image, padding, padding);
      return canvas.toDataURL("image/webp", 0.9).split(",")[1];
    }, { input, ...iconShadow });
    await writeFile(path.replace(/\.png$/, "-shadow.webp"), Buffer.from(data, "base64"));
    console.log(`${icon}-shadow.webp`);
  }
} finally {
  await browser.close();
}
