import { CompressedCubeTexture, HalfFloatType, LinearSRGBColorSpace } from "three";
import { read, VK_FORMAT_R16G16B16A16_SFLOAT } from "ktx-parse";
import environmentURL from "./assets/studio-environment.ktx2.gz?url";

let data: Promise<ReturnType<typeof read>> | undefined;

/** Shared download, independently owned GPU textures. No runtime PMREM filtering. */
export async function loadStudioEnvironment() {
  data ??= (async () => {
    const response = await fetch(environmentURL, { signal: AbortSignal.timeout(8000) });
    if (!response.ok || !response.body) throw new Error("Studio lighting unavailable");
    const buffer = await response.arrayBuffer();
    const bytes = new Uint8Array(buffer);
    // Fetch already decodes HTTP Content-Encoding (including Vite's .gz assets).
    // Static hosts may instead serve the gzip file as bytes. Inspect the payload
    // so both delivery paths decode exactly once, then validate the KTX below.
    const decoded = bytes[0] === 0x1f && bytes[1] === 0x8b
      ? new Uint8Array(await new Response(new Blob([buffer]).stream().pipeThrough(new DecompressionStream("gzip"))).arrayBuffer())
      : bytes;
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
