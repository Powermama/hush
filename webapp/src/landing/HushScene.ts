import * as THREE from "three";
import { loadStudioEnvironment } from "./StudioEnvironment";

// Original procedural artwork. No downloaded model or texture is required.
export async function mountHushScene(host: HTMLElement, signal: AbortSignal) {
  const environmentMap = await loadStudioEnvironment();
  if (signal.aborted || !host.isConnected) { environmentMap.dispose(); return null; }
  const canvas = document.createElement("canvas");
  const context = canvas.getContext("webgl2", { alpha: true, antialias: true, powerPreference: "low-power" });
  if (!context) { environmentMap.dispose(); return null; }
  const renderer = new THREE.WebGLRenderer({ canvas, context, alpha: true, antialias: true });
  renderer.setPixelRatio(Math.min(window.devicePixelRatio, 1.5));
  renderer.setClearColor(0xffffff, 0);
  renderer.toneMapping = THREE.ACESFilmicToneMapping;
  renderer.toneMappingExposure = 1.15;
  canvas.setAttribute("aria-hidden", "true");
  const scene = new THREE.Scene();
  const camera = new THREE.PerspectiveCamera(30, 1, 0.1, 30);
  camera.position.set(0, 0, 8.5);
  scene.environment = environmentMap;
  scene.environmentIntensity = 0.7;
  scene.add(new THREE.HemisphereLight(0xf8fcff, 0x647b89, 1));
  const light = new THREE.DirectionalLight(0xffffff, 3);
  light.position.set(-3, 5, 6);
  scene.add(light);

  const body = new THREE.Group();
  scene.add(body);
  const geometries: THREE.BufferGeometry[] = [];
  const materials: THREE.Material[] = [];
  function material(options: THREE.MeshPhysicalMaterialParameters) {
    const result = new THREE.MeshPhysicalMaterial(options);
    materials.push(result);
    return result;
  }
  function plate(width: number, height: number, depth: number, radius: number, surface: THREE.Material) {
    const shape = new THREE.Shape();
    const x = -width / 2, y = -height / 2;
    shape.moveTo(x + radius, y);
    shape.lineTo(x + width - radius, y);
    shape.quadraticCurveTo(x + width, y, x + width, y + radius);
    shape.lineTo(x + width, y + height - radius);
    shape.quadraticCurveTo(x + width, y + height, x + width - radius, y + height);
    shape.lineTo(x + radius, y + height);
    shape.quadraticCurveTo(x, y + height, x, y + height - radius);
    shape.lineTo(x, y + radius);
    shape.quadraticCurveTo(x, y, x + radius, y);
    const geometry = new THREE.ExtrudeGeometry(shape, {
      depth, bevelEnabled: true, bevelSize: 0.035, bevelThickness: 0.035,
      bevelSegments: 3, steps: 1, curveSegments: 16,
    });
    geometries.push(geometry);
    return new THREE.Mesh(geometry, surface);
  }
  const glass = material({ color: 0x91d6d2, metalness: 0.25, roughness: 0.13,
    transparent: true, opacity: 0.62, clearcoat: 1, depthWrite: false });
  const silver = material({ color: 0xe5edf1, metalness: 0.85, roughness: 0.24 });
  const graphite = material({ color: 0x11171c, metalness: 0.32, roughness: 0.26, clearcoat: 1 });
  const ceramic = material({ color: 0xffffff, metalness: 0.25, roughness: 0.2, clearcoat: 1 });
  const layers: { object: THREE.Object3D; x: number; y: number; z: number }[] = [];
  function addLayer(object: THREE.Object3D, x: number, y: number, z: number) {
    object.position.set(x, y, z);
    body.add(object);
    layers.push({ object, x, y, z });
  }
  addLayer(plate(2.65, 2.65, 0.07, 0.5, glass), 0.27, 0.23, -0.58);
  addLayer(plate(2.54, 2.54, 0.08, 0.48, glass), 0.13, 0.12, -0.28);
  const core = new THREE.Group();
  core.add(plate(2.36, 2.36, 0.17, 0.46, silver));
  const face = plate(2.28, 2.28, 0.12, 0.43, graphite);
  face.position.z = 0.12;
  core.add(face);
  [0.44, 1.22, 0.83, 0.36].forEach((height, index) => {
    const bar = plate(0.14, height, 0.065, 0.07, ceramic);
    bar.position.set((index - 1.5) * 0.39, 0, 0.28);
    core.add(bar);
  });
  addLayer(core, 0, 0, 0);

  let frame = 0;
  let disposed = false;
  let visible = true;
  let ready = false;
  let targetX = -0.16, targetY = -0.42;
  const reducedMotion = matchMedia("(prefers-reduced-motion: reduce)");
  const entry = host.closest<HTMLElement>(".hush-landing");
  let started = performance.now();
  let opening = !reducedMotion.matches && !document.hidden && window.scrollY < 100 && entry?.dataset.opening === "pending";
  let dockY = 0;
  function begin() {
    if (reducedMotion.matches || document.hidden) return;
    started = performance.now();
    opening = true;
    const rect = host.getBoundingClientRect();
    dockY = Math.max(-100, Math.min(100, innerHeight * 0.46 - rect.top - rect.height / 2));
    schedule();
  }
  function finish() {
    opening = false;
    host.style.removeProperty("translate");
    schedule();
  }
  body.rotation.set(targetX, targetY, -0.09);
  function schedule() {
    if (!frame && visible && !document.hidden && !disposed) frame = requestAnimationFrame(render);
  }
  function render(now: number) {
    frame = 0;
    if (disposed || !visible || document.hidden) return;
    const progress = !opening || reducedMotion.matches ? 1 : Math.min(1, (now - started) / 3000);
    const ease = 1 - Math.pow(1 - progress, 4);
    for (const [index, layer] of layers.entries()) {
      layer.object.position.set(layer.x + (1 - ease) * (index - 1) * 0.35,
        layer.y + (1 - ease) * (index - 1) * 1.6,
        layer.z - (1 - ease) * (2 - index) * 2.4);
    }
    body.rotation.x += (targetX - body.rotation.x) * (reducedMotion.matches ? 1 : 0.12);
    body.rotation.y += (targetY - body.rotation.y) * (reducedMotion.matches ? 1 : 0.12);
    body.scale.setScalar(1 - (1 - ease) * 0.35 + Math.sin(progress * Math.PI) * 0.12);
    body.rotation.z = -0.09 + (1 - ease) * 0.28;
    host.style.translate = `0 ${dockY * (1 - ease)}px`;
    renderer.render(scene, camera);
    if (!ready) { ready = true; host.dataset.scene = "ready"; }
    if (opening && progress === 1) finish();
    if (progress < 1 || Math.abs(targetX - body.rotation.x) + Math.abs(targetY - body.rotation.y) > 0.001) schedule();
  }
  function resize() {
    const { width, height } = host.getBoundingClientRect();
    if (!width || !height) return;
    camera.aspect = width / height;
    camera.updateProjectionMatrix();
    renderer.setSize(width, height, false);
    schedule();
  }
  function move(event: PointerEvent) {
    if (event.pointerType !== "mouse" || reducedMotion.matches) return;
    const rect = host.getBoundingClientRect();
    targetY = -0.42 + ((event.clientX - rect.left) / rect.width - 0.5) * 0.4;
    targetX = -0.16 + ((event.clientY - rect.top) / rect.height - 0.5) * 0.2;
    schedule();
  }
  function reset() { targetX = -0.16; targetY = -0.42; if (reducedMotion.matches) finish(); schedule(); }
  function interrupt() { if (opening) finish(); }
  function visibility() {
    if (document.hidden) { cancelAnimationFrame(frame); frame = 0; }
    else schedule();
  }
  function contextLost(event: Event) {
    event.preventDefault();
    host.dataset.scene = "fallback";
    cancelAnimationFrame(frame);
    frame = 0;
    visible = false;
    finish();
  }
  const resizeObserver = new ResizeObserver(resize);
  const intersectionObserver = new IntersectionObserver(([entry]) => {
    visible = entry.isIntersecting;
    if (!visible) { cancelAnimationFrame(frame); frame = 0; }
    else schedule();
  });
  resizeObserver.observe(host);
  intersectionObserver.observe(host);
  host.append(canvas);
  host.addEventListener("pointermove", move);
  host.addEventListener("pointerleave", reset);
  canvas.addEventListener("webglcontextlost", contextLost);
  document.addEventListener("visibilitychange", visibility);
  reducedMotion.addEventListener("change", reset);
  window.addEventListener("wheel", interrupt, { passive: true });
  window.addEventListener("keydown", interrupt);
  window.addEventListener("touchstart", interrupt, { passive: true });
  window.addEventListener("pointerdown", interrupt, { passive: true });
  resize();
  if (opening) begin();
  return () => {
    disposed = true;
    cancelAnimationFrame(frame);
    resizeObserver.disconnect();
    intersectionObserver.disconnect();
    host.removeEventListener("pointermove", move);
    host.removeEventListener("pointerleave", reset);
    document.removeEventListener("visibilitychange", visibility);
    reducedMotion.removeEventListener("change", reset);
    window.removeEventListener("wheel", interrupt);
    window.removeEventListener("keydown", interrupt);
    window.removeEventListener("touchstart", interrupt);
    window.removeEventListener("pointerdown", interrupt);
    canvas.removeEventListener("webglcontextlost", contextLost);
    for (const geometry of geometries) geometry.dispose();
    for (const surface of materials) surface.dispose();
    environmentMap.dispose();
    renderer.dispose();
    canvas.remove();
    delete host.dataset.scene;
  };
}
