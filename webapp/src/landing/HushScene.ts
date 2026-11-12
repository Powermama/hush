import * as THREE from "three";
import { loadStudioEnvironment } from "./StudioEnvironment";
import { createHeroScene } from "./hero/createHeroScene";
import { startLandingEntrance } from "./entrance/landingEntrance";

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
  const { scene, camera, body, layers, dispose: disposeScene } = createHeroScene(environmentMap);
  let disposed = false;
  function releaseResources() {
    if (disposed) return;
    disposed = true;
    disposeScene();
    environmentMap.dispose();
    renderer.dispose();
  }
  // Prepare the final material variants before playback. Three.js polls shader
  // completion without blocking where KHR_parallel_shader_compile is available.
  // Dispose immediately on navigation, including while compilation is pending.
  signal.addEventListener("abort", releaseResources, { once: true });
  try {
    await renderer.compileAsync(scene, camera);
    if (signal.aborted || !host.isConnected || context.isContextLost()) {
      releaseResources();
      return null;
    }
  } catch (error) {
    releaseResources();
    throw error;
  } finally {
    signal.removeEventListener("abort", releaseResources);
  }

  let frame = 0;
  let visible = true;
  let ready = false;
  let targetX = -0.16, targetY = -0.42;
  const reducedMotion = matchMedia("(prefers-reduced-motion: reduce)");
  const entry = host.closest<HTMLElement>(".hush-landing");
  let started: number | undefined;
  let opening = !reducedMotion.matches && !document.hidden && window.scrollY < 100 && entry?.dataset.opening === "pending";
  let dockY = 0;
  let renderedWidth = 0, renderedHeight = 0;
  function begin() {
    if (reducedMotion.matches || document.hidden) return;
    started = undefined;
    opening = true;
    const rect = host.getBoundingClientRect();
    dockY = Math.max(-100, Math.min(100, innerHeight * 0.46 - rect.top - rect.height / 2));
    schedule();
  }
  function finish() {
    opening = false;
    host.style.removeProperty("translate");
    if (entry?.dataset.opening === "playing") entry.dataset.opening = "complete";
    schedule();
  }
  body.rotation.set(targetX, targetY, -0.09);
  function schedule() {
    if (!frame && visible && !document.hidden && !disposed) frame = requestAnimationFrame(render);
  }
  function render(now: number) {
    frame = 0;
    if (disposed || !visible || document.hidden) return;
    // GPU preparation is not part of the visible three-second assembly.
    if (started === undefined) {
      started = now;
      if (opening) opening = startLandingEntrance(entry);
    }
    const progress = !opening || reducedMotion.matches ? 1 : Math.max(0, Math.min(1, (now - started) / 3000));
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
    if (!width || !height || (width === renderedWidth && height === renderedHeight)) return;
    renderedWidth = width;
    renderedHeight = height;
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
    releaseResources();
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
    canvas.remove();
    delete host.dataset.scene;
  };
}
