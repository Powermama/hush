import { CompressedCubeTexture, HalfFloatType, LinearSRGBColorSpace } from "three";
import { read, VK_FORMAT_R16G16B16A16_SFLOAT } from "ktx-parse";
import environmentURL from "./assets/studio-lighting.ktx2.gz?url";

let data: Promise<ReturnType<typeof read>> | undefined;

/** Shared download, independently owned GPU textures. No runtime PMREM filtering. */
export async function loadStudioEnvironment() {
  data ??= (async () => {
    const response = await fetch(environmentURL, { signal: AbortSignal.timeout(8000) });
    if (!response.ok || !response.body) throw new Error("Studio lighting unavailable");
    const buffer = await response.arrayBuffer();
    let decoded = new Uint8Array(buffer);
    // Vite can deliver decoded KTX2; static hosts deliver our gzip archive.
    // WebKit can also expose an edge gzip wrapper around that archive. Decode
    // only those two known layers, then require the exact KTX2 format below.
    // Do not trust Content-Encoding as a description of Fetch's decoded body.
    for (let layer = 0; layer < 2 && decoded[0] === 0x1f && decoded[1] === 0x8b; layer++) {
      decoded = new Uint8Array(await new Response(
        new Blob([decoded]).stream().pipeThrough(new DecompressionStream("gzip")),
      ).arrayBuffer());
    }
    const container = read(decoded);
    if (container.vkFormat !== VK_FORMAT_R16G16B16A16_SFLOAT || container.faceCount !== 6 ||
        container.pixelWidth !== 128 || container.pixelHeight !== 128 || container.levels.length !== 6) {
      throw new Error("Unexpected studio lighting format");
    }
    return container;
  })().catch(error => { data = undefined; throw error; });
  const container = await data;
  const faces = Array.from({ length: 6 }, (_, face) => ({
    width: container.pixelWidth,
    height: container.pixelHeight,
    mipmaps: container.levels.map((level, lod) => {
      const size = container.pixelWidth >> lod;
      const length = size * size * 4;
      if (level.levelData.byteLength !== length * 2 * 6) throw new Error("Invalid studio lighting mip");
      return { width: size, height: size, data: new Uint16Array(level.levelData.buffer, level.levelData.byteOffset + face * length * 2, length) };
    }),
  }));
  const texture = new CompressedCubeTexture(faces, undefined, HalfFloatType);
  texture.colorSpace = LinearSRGBColorSpace;
  texture.isPMREMTexture = true;
  texture.needsUpdate = true;
  return texture;
}
