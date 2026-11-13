// Rebuild after changing Three.js's PMREM representation or RoomEnvironment.
// Run from webapp/apps/web: node scripts/bake-studio-environment.mjs
import { createServer } from "node:http";
import { readFile, writeFile } from "node:fs/promises";
import { resolve, sep } from "node:path";
import { gzipSync } from "node:zlib";
import { chromium } from "playwright";

const root = resolve("node_modules/three");
const server = createServer(async (request, response) => {
  if (request.url === "/") {
    response.setHeader("content-type", "text/html");
    response.end('<script type="importmap">{"imports":{"three":"/build/three.module.js"}}</script>');
    return;
  }
  const path = resolve(root, "." + new URL(request.url, "http://localhost").pathname);
  if (!path.startsWith(root + sep) || !path.endsWith(".js")) { response.writeHead(404).end(); return; }
  try { response.setHeader("content-type", "text/javascript"); response.end(await readFile(path)); }
  catch { response.writeHead(404).end(); }
});
await new Promise(resolve => server.listen(0, "127.0.0.1", resolve));
let browser;
try {
  browser = await chromium.launch();
  const page = await browser.newPage();
  await page.goto(`http://127.0.0.1:${server.address().port}/`);
  const encoded = await page.evaluate(async () => {
    const THREE = await import("/build/three.module.js");
    const { RoomEnvironment } = await import("/examples/jsm/environments/RoomEnvironment.js");
    const { KTX2Exporter } = await import("/examples/jsm/exporters/KTX2Exporter.js");
    const { read, write } = await import("/examples/jsm/libs/ktx-parse.module.js");
    const renderer = new THREE.WebGLRenderer();
    const room = new RoomEnvironment();
    const generator = new THREE.PMREMGenerator(renderer);
    const target = generator.fromScene(room, .04);
    // Let the standard exporter create the half-float/linear-sRGB descriptor.
    const template = new THREE.DataTexture(new Uint16Array(4), 1, 1, THREE.RGBAFormat, THREE.HalfFloatType);
    template.colorSpace = THREE.LinearSRGBColorSpace;
    const container = read(await new KTX2Exporter().parse(template));
    // Downsample every prefiltered level, retaining its original roughness.
    // Broad studio highlights need no 256px faces in the delivered asset.
    container.pixelWidth = container.pixelHeight = target.width / 2;
    container.faceCount = 6;
    container.levelCount = target.texture.mipmaps.length;
    container.levels = [];
    container.keyValue.hushEnvironment = `RoomEnvironment; three ${THREE.REVISION}; sigma 0.04; PMREM; 2x area downsample`;
    const gl = renderer.getContext();
    for (let lod = 0; lod < container.levelCount; lod++) {
      const sourceSize = target.width >> lod;
      const size = sourceSize / 2;
      const values = new Uint16Array(size * size * 4 * 6);
      for (let face = 0; face < 6; face++) {
        renderer.setRenderTarget(target, face, lod);
        const pixels = new Float32Array(sourceSize * sourceSize * 4);
        gl.readPixels(0, 0, sourceSize, sourceSize, gl.RGBA, gl.FLOAT, pixels);
        if (gl.getError() !== gl.NO_ERROR) throw new Error("Unable to read the environment mip");
        const offset = face * size * size * 4;
        for (let y = 0; y < size; y++) for (let x = 0; x < size; x++) for (let channel = 0; channel < 4; channel++) {
          const index = (y * 2 * sourceSize + x * 2) * 4 + channel;
          const value = (pixels[index] + pixels[index + 4] + pixels[index + sourceSize * 4] + pixels[index + sourceSize * 4 + 4]) / 4;
          values[offset + (y * size + x) * 4 + channel] = THREE.DataUtils.toHalfFloat(value);
        }
      }
      container.levels.push({ levelData: new Uint8Array(values.buffer), uncompressedByteLength: values.byteLength });
    }
    const bytes = write(container);
    let binary = "";
    for (let i = 0; i < bytes.length; i += 8192) binary += String.fromCharCode(...bytes.subarray(i, i + 8192));
    template.dispose(); target.dispose(); generator.dispose(); room.dispose(); renderer.dispose();
    return btoa(binary);
  });
  const bytes = gzipSync(Buffer.from(encoded, "base64"), { level: 9 });
  await writeFile("src/landing/assets/studio-lighting.ktx2.gz", bytes);
  console.log(`Baked studio environment: ${bytes.length} bytes`);
} finally {
  await browser?.close();
  await new Promise(resolve => server.close(resolve));
}
