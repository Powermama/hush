import * as THREE from "three";

/** Ameca photo by Willy Jackson; photo adaptation under CC BY-SA 4.0. See /art/CREDITS.md. */
export async function mountPortraitScene(host: HTMLElement): Promise<(() => void) | null> {
  const picture = new Image();
  picture.src = "/art/robot-portrait.webp";
  try { await picture.decode(); } catch { return null; }
  if (!host.isConnected) return null;
  const canvas = document.createElement("canvas");
  const context = canvas.getContext("webgl2", { alpha: true, antialias: true, powerPreference: "low-power" });
  if (!context) return null;
  let renderer: THREE.WebGLRenderer;
  try { renderer = new THREE.WebGLRenderer({ canvas, context, alpha: true }); } catch { return null; }
  renderer.setPixelRatio(Math.min(devicePixelRatio, 1.5));
  renderer.setClearColor(0x111827, 0);
  canvas.setAttribute("aria-hidden", "true");
  const scene = new THREE.Scene();
  const camera = new THREE.OrthographicCamera(-2.8, 2.8, 3.2, -3.2, .1, 30);
  camera.position.set(0, 0, 9);
  scene.add(new THREE.HemisphereLight(0xe7ffff, 0x263e5c, 3));
  const key = new THREE.DirectionalLight(0xffffff, 3);
  key.position.set(-3, 4, 7);
  scene.add(key);
  const group = new THREE.Group();
  group.rotation.set(.035, -.19, -.06);
  scene.add(group);
  const geometries: THREE.BufferGeometry[] = [];
  const materials: THREE.Material[] = [];
  const textures: THREE.Texture[] = [];
  const backMaterial = new THREE.MeshStandardMaterial({ color: 0x70908f, metalness: .65, roughness: .4 });
  materials.push(backMaterial);
  const seams = [0, .17, .33, .48, .64, .79, 1];
  const offsets = [-.04, .17, -.23, .07, -.11, .03];
  try {
    for (let i = 0; i < seams.length - 1; i++) {
      const from = seams[i], to = seams[i + 1], height = (to - from) * 4.8;
      const strip = document.createElement("canvas");
      strip.width = 720;
      strip.height = Math.round(900 * (to - from));
      const paint = strip.getContext("2d");
      if (!paint) throw new Error("No 2D canvas");
      paint.drawImage(picture, 0, from * picture.height, picture.width, (to - from) * picture.height, 0, 0, strip.width, strip.height);
      const pixels = paint.getImageData(0, 0, strip.width, strip.height);
      for (let p = 0; p < pixels.data.length; p += 4) {
        const light = (.2126 * pixels.data[p] + .7152 * pixels.data[p + 1] + .0722 * pixels.data[p + 2]) / 255;
        pixels.data[p] = 39 + light * (i === 2 ? 188 : 169);
        pixels.data[p + 1] = 52 + light * (i === 2 ? 138 : 172);
        pixels.data[p + 2] = 78 + light * (i === 2 ? 137 : 158);
      }
      paint.putImageData(pixels, 0, 0);
      const texture = new THREE.CanvasTexture(strip);
      texture.colorSpace = THREE.SRGBColorSpace;
      textures.push(texture);
      const material = new THREE.MeshBasicMaterial({ map: texture });
      materials.push(material);
      const plane = new THREE.PlaneGeometry(3.84, height);
      const depth = new THREE.BoxGeometry(3.84, height, .08);
      geometries.push(plane, depth);
      const panel = new THREE.Group();
      panel.position.set(offsets[i], 2.4 - (from + to) / 2 * 4.8 + (2.5 - i) * .035, i === 2 ? .22 : 0);
      panel.rotation.y = i === 2 ? -.05 : .025;
      const edge = new THREE.Mesh(depth, backMaterial);
      const face = new THREE.Mesh(plane, material);
      face.position.z = .045;
      panel.add(edge, face);
      group.add(panel);
    }
  } catch {
    geometries.forEach(g => g.dispose()); materials.forEach(m => m.dispose()); textures.forEach(t => t.dispose()); renderer.dispose();
    return null;
  }
  host.append(canvas);
  let disposed = false, lost = false, visible = true, frame = 0;
  let x = 0, y = 0, targetX = 0, targetY = 0;
  const reduced = matchMedia("(prefers-reduced-motion: reduce)");
  const fine = matchMedia("(hover: hover) and (pointer: fine)");
  const request = () => { if (!disposed && !lost && visible && !document.hidden && !frame) frame = requestAnimationFrame(render); };
  function render() {
    frame = 0;
    if (disposed || lost || !visible || document.hidden) return;
    x += (targetX - x) * .12; y += (targetY - y) * .12;
    group.rotation.y = -.19 + x * .16;
    group.rotation.x = .035 - y * .09;
    try { renderer.render(scene, camera); host.dataset.scene = "ready"; }
    catch { lost = true; host.dataset.scene = "fallback"; return; }
    if (Math.abs(targetX - x) + Math.abs(targetY - y) > .001) request();
  }
  function resize() {
    const { width, height } = host.getBoundingClientRect();
    if (!width || !height) return;
    const aspect = width / height;
    camera.left = -3.2 * aspect; camera.right = 3.2 * aspect; camera.updateProjectionMatrix();
    renderer.setSize(width, height, false); request();
  }
  function move(event: PointerEvent) {
    if (reduced.matches || !fine.matches) return;
    const r = host.getBoundingClientRect();
    targetX = Math.max(-1, Math.min(1, (event.clientX - r.left) / r.width * 2 - 1));
    targetY = Math.max(-1, Math.min(1, (event.clientY - r.top) / r.height * 2 - 1)); request();
  }
  function reset() { targetX = targetY = 0; if (reduced.matches) x = y = 0; request(); }
  function visibility() { if (document.hidden) { cancelAnimationFrame(frame); frame = 0; } else request(); }
  function contextLost(event: Event) { event.preventDefault(); lost = true; cancelAnimationFrame(frame); frame = 0; host.dataset.scene = "fallback"; }
  const size = new ResizeObserver(resize);
  size.observe(host);
  const viewport = new IntersectionObserver(([entry]) => { visible = entry.isIntersecting; if (visible) request(); else { cancelAnimationFrame(frame); frame = 0; } });
  viewport.observe(host);
  host.addEventListener("pointermove", move, { passive: true });
  host.addEventListener("pointerleave", reset);
  reduced.addEventListener("change", reset);
  fine.addEventListener("change", reset);
  document.addEventListener("visibilitychange", visibility);
  canvas.addEventListener("webglcontextlost", contextLost);
  resize();
  return () => {
    disposed = true; cancelAnimationFrame(frame); size.disconnect(); viewport.disconnect();
    host.removeEventListener("pointermove", move); host.removeEventListener("pointerleave", reset);
    reduced.removeEventListener("change", reset); fine.removeEventListener("change", reset);
    document.removeEventListener("visibilitychange", visibility); canvas.removeEventListener("webglcontextlost", contextLost);
    geometries.forEach(g => g.dispose()); materials.forEach(m => m.dispose()); textures.forEach(t => t.dispose());
    renderer.dispose(); canvas.remove(); delete host.dataset.scene;
  };
}
