// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2026 Clemens Kressmann
//
// Renders the raster icons from public/favicon.svg. The outputs are committed;
// run again after changing the SVG:  bun scripts/generate-favicons.ts
//   public/favicon.ico           16, 32 and 48 px (browsers, Google's /favicon.ico lookup)
//   public/favicon-96x96.png     a multiple of 48 px, as Google Search asks
//   public/apple-touch-icon.png  180 px, full bleed: iOS rounds the corners itself
//   public/logo.png              512 px, the publisher logo in structured data
import sharp from "sharp";

const svg = await Bun.file("public/favicon.svg").text();
const fullBleed = svg.replace(/ rx="[^"]*" ry="[^"]*"/, "");
const png = (source: string, size: number) =>
  sharp(Buffer.from(source), { density: 72 * size / 64 }).resize(size, size).png({ compressionLevel: 9 }).toBuffer();

/** An ICO file holding PNG images (supported by every current browser). */
function ico(images: Array<{ size: number; data: Buffer }>) {
  const header = Buffer.alloc(6 + 16 * images.length);
  header.writeUInt16LE(1, 2); // type: icon
  header.writeUInt16LE(images.length, 4);
  let offset = header.length;
  images.forEach(({ size, data }, index) => {
    const entry = 6 + 16 * index;
    header.writeUInt8(size % 256, entry); // 0 means 256
    header.writeUInt8(size % 256, entry + 1);
    header.writeUInt16LE(1, entry + 4); // colour planes
    header.writeUInt16LE(32, entry + 6); // bits per pixel
    header.writeUInt32LE(data.length, entry + 8);
    header.writeUInt32LE(offset, entry + 12);
    offset += data.length;
  });
  return Buffer.concat([header, ...images.map((image) => image.data)]);
}

const icoSizes = [16, 32, 48];
await Bun.write("public/favicon.ico", ico(await Promise.all(icoSizes.map(async (size) => ({ size, data: await png(svg, size) })))));
await Bun.write("public/favicon-96x96.png", await png(svg, 96));
await Bun.write("public/apple-touch-icon.png", await png(fullBleed, 180));
await Bun.write("public/logo.png", await png(svg, 512));
console.info("Wrote favicon.ico, favicon-96x96.png, apple-touch-icon.png and logo.png");
