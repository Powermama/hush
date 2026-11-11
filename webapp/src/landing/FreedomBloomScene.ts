import * as THREE from "three";
import { GLTFLoader } from "three/addons/loaders/GLTFLoader.js";
import { loadStudioEnvironment } from "./StudioEnvironment";
import { mergeGeometries } from "three/addons/utils/BufferGeometryUtils.js";
import roseURL from "./assets/rose.glb?url";

/** CC0 Innerscene rose. Source, licence and preparation are recorded in public/art/CREDITS.md. */
export async function mountFreedomBloom(host: HTMLElement, signal: AbortSignal): Promise<(() => void) | null> {
  const response = await fetch(roseURL, { signal });
  if (!response.ok) throw new Error("Rose asset unavailable");
  const gltf = await new GLTFLoader().parseAsync(await response.arrayBuffer(), "");
  const sourceMeshes: THREE.Mesh[] = [];
  gltf.scene.traverse(node => { if (node instanceof THREE.Mesh) sourceMeshes.push(node); });
  const releaseSource = () => {
    sourceMeshes.forEach(mesh => mesh.geometry.dispose());
    new Set(sourceMeshes.flatMap(mesh => Array.isArray(mesh.material) ? mesh.material : [mesh.material])).forEach(material => material.dispose());
  };
  if (signal.aborted || !host.isConnected) { releaseSource(); return null; }
  let environmentMap: THREE.CompressedCubeTexture;
  try { environmentMap = await loadStudioEnvironment(); }
  catch (error) { releaseSource(); throw error; }
  if (signal.aborted || !host.isConnected) { releaseSource(); environmentMap.dispose(); return null; }
  const canvas = document.createElement("canvas");
  // Buffer dimensions cannot participate in layout or trigger a ResizeObserver growth loop.
  Object.assign(canvas.style, { position: "absolute", inset: "0", width: "100%", height: "100%", display: "block" });
  const context = canvas.getContext("webgl2", { alpha: true, antialias: true, powerPreference: "low-power" });
  if (!context) { releaseSource(); environmentMap.dispose(); return null; }
  const renderer = new THREE.WebGLRenderer({ canvas, context, alpha: true, antialias: true });
  renderer.setPixelRatio(Math.min(devicePixelRatio, 1.5));
  renderer.setClearColor(0, 0);
  renderer.toneMapping = THREE.ACESFilmicToneMapping;
  renderer.toneMappingExposure = 1.1;
  canvas.setAttribute("aria-hidden", "true");
  const scene = new THREE.Scene();
  const camera = new THREE.PerspectiveCamera(34, 1, .1, 40);
  camera.position.set(0, .15, 10.5);
  scene.environment = environmentMap;
  scene.environmentIntensity = .8;
  scene.add(new THREE.HemisphereLight(0xf4eefa, 0x555179, 1.8));
  const light = new THREE.DirectionalLight(0xfff6f2, 2.5);
  light.position.set(-3, 5, 6); scene.add(light);
  const rim = new THREE.DirectionalLight(0xc4bcff, 1.8);
  rim.position.set(4, -1, 2); scene.add(rim);
  const pearl = new THREE.MeshPhysicalMaterial({ color: 0xd7c7df, metalness: .25, roughness: .36, clearcoat: .45, clearcoatRoughness: .3, iridescence: .22, side: THREE.DoubleSide });
  const lilac = new THREE.MeshPhysicalMaterial({ color: 0xb4a0cb, metalness: .2, roughness: .4, clearcoat: .35, side: THREE.DoubleSide });
  const blush = new THREE.MeshPhysicalMaterial({ color: 0xe1c1cd, metalness: .18, roughness: .38, clearcoat: .4, side: THREE.DoubleSide });
  const stemMaterial = new THREE.MeshStandardMaterial({ color: 0x8498a6, metalness: .4, roughness: .4, side: THREE.DoubleSide });
  const flower = new THREE.Group();
  flower.rotation.set(-.14, -.25, -.16);
  scene.add(flower);
  const head = new THREE.Group();
  head.position.y = 1.05;
  head.rotation.x = .9;
  flower.add(head);
  const geometries: THREE.BufferGeometry[] = [];
  const stems: THREE.BufferGeometry[] = [];
  const petals: { hinge: THREE.Group; axis: THREE.Vector3; layer: number }[] = [];
  const sourceOrigin = new THREE.Vector3(.007574, .449, -.0025);
  for (const source of sourceMeshes) {
    const geometry = source.geometry.clone();
    geometry.translate(-sourceOrigin.x, -sourceOrigin.y, -sourceOrigin.z);
    // GLTFLoader sanitizes the source's spaces into underscores.
    const match = /layer[ _](\d+)[ _]curved[ _]petal/.exec(source.name);
    const isHead = /petal|bud|sepal|receptacle/i.test(source.name);
    geometry.scale(isHead ? 50 : 25, isHead ? 50 : 10, isHead ? 50 : 25);
    if (!isHead) { stems.push(geometry); continue; }
    geometries.push(geometry);
    const material = /sepal|receptacle/.test(source.name) ? stemMaterial : match && Number(match[1]) <= 2 ? (petals.length % 4 === 0 ? blush : pearl) : lilac;
    const mesh = new THREE.Mesh(geometry, material);
    if (match) {
      geometry.computeBoundingBox();
      const center = geometry.boundingBox!.getCenter(new THREE.Vector3());
      const radial = new THREE.Vector3(center.x, 0, center.z).normalize();
      const pivot = radial.clone().multiplyScalar(.16);
      geometry.translate(-pivot.x, 0, -pivot.z);
      const hinge = new THREE.Group();
      hinge.position.copy(pivot); hinge.add(mesh); head.add(hinge);
      petals.push({ hinge, axis: new THREE.Vector3(-radial.z, 0, radial.x), layer: Number(match[1]) });
    } else head.add(mesh);
  }
  const stemGeometry = mergeGeometries(stems);
  stems.forEach(geometry => geometry.dispose());
  if (stemGeometry) {
    geometries.push(stemGeometry);
    const stem = new THREE.Mesh(stemGeometry, stemMaterial);
    stem.position.y = 1.05; flower.add(stem);
  }
  releaseSource();

  const reduced = matchMedia("(prefers-reduced-motion: reduce)");
  let frame = 0, visible = false, disposed = false, lost = false;
  let lastFrameTime = 0;
  let lastWidth = 0, lastHeight = 0;
  let targetX = -.14, targetY = -.25;
  const clamp = (value: number) => Math.max(0, Math.min(1, value));
  function scrollProgress() {
    if (reduced.matches) return 1;
    const { top, height } = host.getBoundingClientRect();
    // Hold the bud until its centre is comfortably in view. Then unfold over
    // half a viewport of native scrolling, keeping the bloom visible throughout.
    const bloomCentre = top + height * .28;
    return clamp((innerHeight * .74 - bloomCentre) / (innerHeight * .52));
  }
  let targetBloom = scrollProgress(), bloom = targetBloom;
  function schedule() {
    if (!frame && visible && !disposed && !lost && !document.hidden) frame = requestAnimationFrame(render);
  }
  function render(now: number) {
    frame = 0;
    if (disposed || !visible || lost || document.hidden) return;
    // IntersectionObserver is asynchronous; never draw an extra frame after a fast scroll away.
    const bounds = host.getBoundingClientRect();
    if (bounds.bottom <= 0 || bounds.top >= innerHeight) { lastFrameTime = 0; return; }
    // Use elapsed time on slow renderers too. Reset the clock between animation
    // runs so returning from an idle or hidden scene cannot snap the petals.
    const elapsed = lastFrameTime ? now - lastFrameTime : 16.7;
    lastFrameTime = now;
    const easing = reduced.matches ? 1 : 1 - Math.exp(-elapsed / 230);
    bloom += (targetBloom - bloom) * easing;
    flower.rotation.x += (targetX - flower.rotation.x) * easing;
    flower.rotation.y += (targetY - flower.rotation.y) * easing;
    for (const { hinge, axis, layer } of petals) {
      const progress = clamp((bloom - (4 - layer) * .055) / .835);
      const smooth = progress * progress * (3 - 2 * progress);
      const closedAngle = .3 - layer * .055;
      const openAngle = 0;
      hinge.quaternion.setFromAxisAngle(axis, closedAngle + (openAngle - closedAngle) * smooth);
    }
    const fullness = bloom * bloom * (3 - 2 * bloom);
    // Keep the layers nested while closed instead of folding them through each other.
    head.scale.set(.46 + fullness * .54, 1, .46 + fullness * .54);
    renderer.render(scene, camera);
    host.dataset.scene = "ready";
    host.dataset.bloom = bloom.toFixed(3);
    if (Math.abs(targetBloom - bloom) + Math.abs(targetX - flower.rotation.x) + Math.abs(targetY - flower.rotation.y) > .001) schedule();
    else lastFrameTime = 0;
  }
  function scroll() {
    if (!visible) return;
    targetBloom = scrollProgress(); schedule();
  }
  function resize() {
    const { width, height } = host.getBoundingClientRect();
    if (!width || !height || (width === lastWidth && height === lastHeight)) return;
    lastWidth = width; lastHeight = height;
    camera.aspect = width / height; camera.updateProjectionMatrix();
    const scale = Math.min(1, 1000 / width, 1200 / height);
    renderer.setSize(Math.round(width * scale), Math.round(height * scale), false);
    targetBloom = scrollProgress(); schedule();
  }
  function move(event: PointerEvent) {
    if (reduced.matches || event.pointerType !== "mouse") return;
    const rect = host.getBoundingClientRect();
    targetX = -.14 + ((event.clientY - rect.top) / rect.height - .5) * .15;
    targetY = -.25 + ((event.clientX - rect.left) / rect.width - .5) * .3;
    schedule();
  }
  function reset() { targetX = -.14; targetY = -.25; targetBloom = scrollProgress(); schedule(); }
  function visibility() {
    if (document.hidden) { cancelAnimationFrame(frame); frame = 0; lastFrameTime = 0; }
    else { targetBloom = scrollProgress(); schedule(); }
  }
  function contextLost(event: Event) {
    event.preventDefault(); lost = true; cancelAnimationFrame(frame); frame = 0;
    host.dataset.scene = "fallback";
  }
  const intersection = new IntersectionObserver(([entry]) => {
    visible = entry.isIntersecting;
    if (visible) { targetBloom = scrollProgress(); schedule(); }
    else { cancelAnimationFrame(frame); frame = 0; lastFrameTime = 0; }
  });
  const observer = new ResizeObserver(resize);
  host.append(canvas); observer.observe(host); intersection.observe(host);
  host.addEventListener("pointermove", move);
  host.addEventListener("pointerleave", reset);
  canvas.addEventListener("webglcontextlost", contextLost);
  window.addEventListener("scroll", scroll, { passive: true });
  document.addEventListener("visibilitychange", visibility);
  reduced.addEventListener("change", reset);
  resize();
  return () => {
    disposed = true; cancelAnimationFrame(frame);
    observer.disconnect(); intersection.disconnect();
    host.removeEventListener("pointermove", move); host.removeEventListener("pointerleave", reset);
    canvas.removeEventListener("webglcontextlost", contextLost);
    window.removeEventListener("scroll", scroll);
    document.removeEventListener("visibilitychange", visibility); reduced.removeEventListener("change", reset);
    geometries.forEach(geometry => geometry.dispose());
    [pearl, lilac, blush, stemMaterial].forEach(material => material.dispose());
    environmentMap.dispose(); renderer.dispose(); canvas.remove();
  };
}
