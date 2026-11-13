import * as THREE from "three";
import { RoomEnvironment } from "three/addons/environments/RoomEnvironment.js";
import type { MascotState } from "./HushMascot";

// Small original character scenes, rendered only while responding to the visitor.
export function mountMascotScene(host: HTMLElement, state: MascotState) {
  const canvas = document.createElement("canvas");
  const context = canvas.getContext("webgl2", { alpha: true, antialias: true, powerPreference: "low-power" });
  if (!context) return null;
  const geometry: THREE.BufferGeometry[] = [];
  const materials: THREE.Material[] = [];
  let environmentMap: THREE.WebGLRenderTarget | undefined;
  let renderer: THREE.WebGLRenderer;
  try {
    renderer = new THREE.WebGLRenderer({ canvas, context, alpha: true, antialias: true });
  } catch { return null; }
  function releaseResources() {
    geometry.forEach(item => item.dispose());
    materials.forEach(item => item.dispose());
    environmentMap?.dispose();
    renderer.dispose();
    canvas.remove();
  }
  try {
    renderer.setPixelRatio(Math.min(devicePixelRatio, 1.75));
    renderer.setClearColor(0xffffff, 0);
    renderer.toneMapping = THREE.ACESFilmicToneMapping;
    renderer.toneMappingExposure = 1.3;
    canvas.setAttribute("aria-hidden", "true");
    const scene = new THREE.Scene();
    const camera = new THREE.OrthographicCamera(-1.7, 1.7, 1.6, -1.6, .1, 20);
    camera.position.set(0, .08, 7);
    const environment = new RoomEnvironment();
    const pmrem = new THREE.PMREMGenerator(renderer);
    try { environmentMap = pmrem.fromScene(environment, .05); }
    finally { environment.dispose(); pmrem.dispose(); }
    scene.environment = environmentMap.texture;
    scene.environmentIntensity = .75;
    scene.add(new THREE.HemisphereLight(0xf9ffff, 0x6b8a9c, 2));
    const key = new THREE.DirectionalLight(0xffffff, 3.5);
    key.position.set(-3, 5, 5);
    scene.add(key);
    const rim = new THREE.DirectionalLight(0xa5e6f4, 2);
    rim.position.set(3, 2, -2);
    scene.add(rim);

    function surface(options: THREE.MeshPhysicalMaterialParameters) {
      const material = new THREE.MeshPhysicalMaterial(options);
      materials.push(material);
      return material;
    }
    function mesh(shape: THREE.BufferGeometry, material: THREE.Material, parent: THREE.Object3D, x = 0, y = 0, z = 0) {
      geometry.push(shape);
      const object = new THREE.Mesh(shape, material);
      object.position.set(x, y, z);
      parent.add(object);
      return object;
    }
    function plate(w: number, h: number, d: number, r: number, material: THREE.Material, parent: THREE.Object3D, x = 0, y = 0, z = 0) {
      const outline = new THREE.Shape();
      const l = -w / 2, b = -h / 2;
      outline.moveTo(l + r, b);
      outline.lineTo(l + w - r, b);
      outline.quadraticCurveTo(l + w, b, l + w, b + r);
      outline.lineTo(l + w, b + h - r);
      outline.quadraticCurveTo(l + w, b + h, l + w - r, b + h);
      outline.lineTo(l + r, b + h);
      outline.quadraticCurveTo(l, b + h, l, b + h - r);
      outline.lineTo(l, b + r);
      outline.quadraticCurveTo(l, b, l + r, b);
      return mesh(new THREE.ExtrudeGeometry(outline, { depth: d, bevelEnabled: true, bevelSize: .025, bevelThickness: .025, bevelSegments: 3, curveSegments: 12, steps: 1 }), material, parent, x, y, z);
    }
    function sphere(r: number, material: THREE.Material, parent: THREE.Object3D, x: number, y: number, z: number) {
      return mesh(new THREE.SphereGeometry(r, 20, 12), material, parent, x, y, z);
    }
    function curve(points: number[][], radius: number, material: THREE.Material, parent: THREE.Object3D) {
      return mesh(new THREE.TubeGeometry(new THREE.CatmullRomCurve3(points.map(p => new THREE.Vector3(...p))), 20, radius, 8, false), material, parent);
    }

    const graphite = surface({ color: 0x17222c, metalness: .35, roughness: .22, clearcoat: 1 });
    const silver = surface({ color: 0xd3e1e9, metalness: .72, roughness: .23 });
    const ceramic = surface({ color: 0xffffff, roughness: .15, clearcoat: 1 });
    const mint = surface({ color: 0xb4e4d9, metalness: .12, roughness: .25, clearcoat: 1 });
    const glass = surface({ color: 0x9adfdc, transparent: true, opacity: .65, metalness: .2, roughness: .14, clearcoat: 1, depthWrite: false });
    const iris = surface({ color: 0x367d99, metalness: .3, roughness: .13 });
    const pupil = surface({ color: 0x071725, roughness: .1, clearcoat: 1 });
    const blush = surface({ color: 0xf3a2a1, roughness: .35 });
    const glow = surface({ color: 0xffe0b5, emissive: 0xffce87, emissiveIntensity: .25, roughness: .3 });
    const shadowMaterial = new THREE.MeshBasicMaterial({ color: 0x183747, transparent: true, opacity: .11, depthWrite: false });
    materials.push(shadowMaterial);
    const shadow = mesh(new THREE.CircleGeometry(.7, 32), shadowMaterial, scene, 0, -1.08, -.3);
    shadow.scale.y = .12;

    const character = new THREE.Group();
    scene.add(character);
    const face = new THREE.Group();
    character.add(face);
    face.position.y = .12;
    plate(1.35, 1.25, .06, .32, glass, face, .10, .08, -.2);
    plate(1.28, 1.22, .14, .30, silver, face, 0, 0, -.08);
    plate(1.23, 1.17, .12, .29, graphite, face, 0, 0, .04);

    const eyes = new THREE.Group();
    face.add(eyes);
    eyes.position.y = .20;
    const pupils: THREE.Group[] = [];
    for (const x of [-.27, .27]) {
      const eye = sphere(.22, ceramic, eyes, x, 0, .20);
      eye.scale.set(.8, 1.16, .45);
      const gaze = new THREE.Group();
      gaze.position.set(x, .015, .292);
      eyes.add(gaze);
      const colour = sphere(.105, iris, gaze, 0, 0, 0);
      colour.scale.set(.82, 1.12, .35);
      const centre = sphere(.067, pupil, gaze, 0, 0, .033);
      centre.scale.set(.86, 1.15, .35);
      sphere(.028, ceramic, gaze, -.024, .036, .058);
      sphere(.013, ceramic, gaze, .026, -.036, .058);
      pupils.push(gaze);
    }
    for (const x of [-.46, .46]) {
      const cheek = sphere(.068, blush, face, x, -.05, .19);
      cheek.scale.set(1.25, .55, .25);
    }
    const sad = state === "sad";
    // Sad: a frown, worried brows, a tear and resting dots where the voice bars usually move.
    const smile = curve(sad ? [[-.1, -.03, 0], [0, .035, .02], [.1, -.03, 0]] : [[-.1, 0, 0], [0, -.06, .02], [.1, 0, 0]], .018, ceramic, face);
    smile.position.set(0, -.11, .22);
    if (sad) {
      for (const side of [-1, 1]) {
        curve([[side * .15, .61, .25], [side * .26, .60, .26], [side * .38, .55, .25]], .016, ceramic, face);
      }
      const tear = sphere(.045, glass, face, .33, -.10, .27);
      tear.scale.set(.8, 1.3, .6);
      for (let i = 0; i < 4; i++) plate(.036, .036, .018, .018, silver, face, (i - 1.5) * .13, -.36, .18);
    } else {
      [.12, .25, .19, .10].forEach((h, i) => plate(.036, h, .018, .018, silver, face, (i - 1.5) * .13, -.36, .18));
    }

    for (const x of [-.38, .38]) {
      curve([[x * .85, -.46, 0], [x, -.80, .06], [x * 1.15, -.91, .16]], .055, graphite, character);
      const foot = sphere(.14, silver, character, x * 1.15, -.96, .20);
      foot.scale.set(1.3, .65, 1.4);
    }
    const leftShoulder = new THREE.Group();
    const rightShoulder = new THREE.Group();
    let ropeHand: THREE.Mesh | undefined;
    function arm(points: number[][], parent: THREE.Object3D) {
      curve(points, .054, silver, parent);
      const end = points[2];
      const hand = sphere(.11, mint, parent, end[0], end[1], end[2]);
      hand.scale.set(.85, 1.15, .8);
      sphere(.052, mint, parent, end[0] - .065, end[1] + .035, end[2] + .03);
      return hand;
    }
    const leftArm = state === "recording"
      ? [[-.58, -.12, 0], [-.85, -.41, .12], [-.98, -.08, .23]]
      : state === "sad"
        ? [[-.58, -.12, 0], [-.74, -.44, .06], [-.70, -.72, .14]]
        : [[-.58, -.12, 0], [-.87, -.29, .05], [-.86, -.53, .16]];
    const rightArm = state === "listening"
      ? [[.58, -.1, 0], [.9, .05, .08], [.82, .44, .16]]
      : state === "thinking"
        ? [[.58, -.1, 0], [.88, -.39, .10], [.40, -.20, .31]]
        : state === "sad"
          ? [[.58, -.1, 0], [.74, -.42, .06], [.70, -.70, .14]]
          : [[.58, -.1, 0], [.85, -.30, .08], [1.0, -.08, .18]];
    if (state === "listening") {
      character.add(leftShoulder, rightShoulder);
      leftShoulder.position.set(-.58, -.1, 0);
      rightShoulder.position.set(.58, -.1, 0);
      arm([[0, 0, 0], [-.24, .09, .10], [-.52, .18, .22]], leftShoulder);
      curve([[-.54, .20, .22], [-.68, .22, .24]], .035, mint, leftShoulder);
      ropeHand = arm([[0, 0, 0], [.31, .16, .08], [.24, .54, .16]], rightShoulder);
    } else {
      arm(leftArm, character);
      arm(rightArm, character);
    }

    const accessory = new THREE.Group();
    character.add(accessory);
    if (state === "listening") {
      curve([[-.72, .12, -.03], [-.72, .68, -.03], [0, .91, -.04], [.72, .68, -.03], [.72, .12, -.03]], .042, silver, accessory);
      for (const x of [-.69, .69]) {
        const pad = sphere(.17, mint, accessory, x, .20, .02);
        pad.scale.set(.55, 1.2, .95);
      }
    } else if (state === "thinking") {
      sphere(.045, glass, accessory, .78, .85, 0);
      sphere(.07, glass, accessory, .97, 1.04, 0);
      const idea = mesh(new THREE.OctahedronGeometry(.17, 0), glow, accessory, 1.12, 1.30, 0);
      idea.scale.set(.75, 1.2, .6);
    } else if (state === "recording") {
      const mic = new THREE.Group();
      accessory.add(mic);
      mic.position.set(-.98, .07, .25);
      mic.rotation.z = -.18;
      mesh(new THREE.CylinderGeometry(.036, .045, .29, 16), silver, mic, 0, -.11, 0);
      const head = sphere(.105, graphite, mic, 0, .11, 0);
      head.scale.y = 1.4;
      for (const y of [.045, .095, .145]) {
        const ring = mesh(new THREE.TorusGeometry(.101, .009, 6, 20), silver, mic, 0, y, 0);
        ring.rotation.x = Math.PI / 2;
      }
    }

    const reduced = matchMedia("(prefers-reduced-motion: reduce)");
    const art = host.closest<HTMLElement>(".thought-art, .intelligence-art") ?? host;
    const rope = state === "listening" ? art.querySelector<SVGSVGElement>(".thought-descent-line") : null;
    const ropePath = rope?.querySelector("path");
    const ropeAnchor = rope?.querySelector("circle");
    const grip = new THREE.Vector3();
    // Sad looks down with its head slightly tilted.
    const base = { x: sad ? .14 : -.06, y: state === "thinking" ? -.18 : .15, z: state === "listening" ? .14 : sad ? .1 : -.08 };
    let targetX = base.x, targetY = base.y;
    let frame = 0, visible = false, disposed = false, lost = false;
    let gestureStarted = -Infinity;
    let descent = 1, targetDescent = 1, sway = 0;
    let firstMeasurement = true, grounded = true, landedAt = -Infinity;
    let anchorX: number | undefined;
    character.rotation.set(base.x, base.y, base.z);
    const schedule = () => {
      if (!frame && visible && !document.hidden && !disposed && !lost) frame = requestAnimationFrame(render);
    };
    function render(now: number) {
      frame = 0;
      if (disposed || lost || !visible || document.hidden) return;
      const t = reduced.matches ? 1 : Math.min(1, (now - gestureStarted) / 1100);
      const gesture = Math.sin(t * Math.PI);
      const ease = reduced.matches ? 1 : .15;
      const descentVelocity = targetDescent - descent;
      descent += descentVelocity * (reduced.matches ? 1 : .18);
      if (Math.abs(targetDescent - descent) < .0005) descent = targetDescent;
      const isGrounded = descent >= .9995;
      if (isGrounded && !grounded) landedAt = now;
      if (!isGrounded) landedAt = -Infinity;
      grounded = isGrounded;
      const landing = reduced.matches ? 1 : Math.min(1, (now - landedAt) / 750);
      const swayTarget = reduced.matches ? 0 : THREE.MathUtils.clamp(descentVelocity * 4, -.16, .16)
        + (Math.abs(descentVelocity) > .0008 ? Math.sin(descent * Math.PI * 5) * .05 : 0);
      sway += (swayTarget - sway) * (reduced.matches ? 1 : .14);
      character.rotation.x += (targetX - character.rotation.x) * ease;
      character.rotation.y += (targetY - character.rotation.y) * ease;
      character.rotation.z = base.z + gesture * (state === "listening" ? .08 : -.035) + sway;
      character.position.y = gesture * .045;
      // A brief blink within the finite greeting, never a perpetual render loop.
      eyes.scale.y = t > .38 && t < .52 ? Math.max(.14, Math.abs(t - .45) / .07) : 1;
      accessory.rotation.z = state === "thinking" ? gesture * .04 : 0;
      let shiftX = 0;
      if (state === "listening") {
        const release = THREE.MathUtils.smoothstep(descent, .86, 1);
        shadowMaterial.opacity = .11 * release;
        const pointTowardHeading = innerWidth <= 760 ? -Math.PI / 3 : 0;
        leftShoulder.rotation.z = THREE.MathUtils.lerp(pointTowardHeading, .95, release);
        rightShoulder.rotation.z = -.10 * (1 - release);
        smile.scale.y = .2 + release * .8;
        if (landing > .16 && landing < .40) eyes.scale.y = Math.max(.15, Math.abs(landing - .28) / .12);
        const drop = Math.max(0, art.clientHeight - host.clientHeight * .5 - 58);
        const bounce = Math.sin(landing * Math.PI * 2) * 4 * (1 - landing);
        shiftX = sway * 65;
        host.style.translate = isGrounded && landing === 1 && Math.abs(sway) < .001
          ? "" : `${shiftX}px ${-drop * (1 - descent) + bounce}px`;
        host.dataset.arrival = isGrounded ? landing < 1 ? "landing" : "settled" : "sliding";
      }
      for (const [index, gaze] of pupils.entries()) {
        gaze.position.x = (index ? .27 : -.27) + (state === "thinking" ? .035 : -.015) + (character.rotation.y - base.y) * .13;
        gaze.position.y = state === "thinking" ? .065 : sad ? -.05 : .015;
      }
      try { renderer.render(scene, camera); host.dataset.scene = "ready"; }
      catch { lost = true; showFallback(); return; }
      if (rope && ropePath && ropeHand) {
        const rect = host.getBoundingClientRect();
        const artRect = art.getBoundingClientRect();
        ropeHand.getWorldPosition(grip).project(camera);
        const handX = rect.left - artRect.left + (grip.x * .5 + .5) * rect.width;
        const handY = rect.top - artRect.top + (-grip.y * .5 + .5) * rect.height;
        anchorX ??= handX - shiftX;
        const retract = THREE.MathUtils.smoothstep(descent, .94, 1);
        const endX = THREE.MathUtils.lerp(handX, anchorX, retract);
        const endY = THREE.MathUtils.lerp(handY, 3, retract);
        ropePath.setAttribute("d", `M${anchorX} 3 Q${anchorX + shiftX * .3} ${endY * .45} ${endX} ${endY}`);
        ropeAnchor?.setAttribute("cx", String(anchorX));
        rope.style.opacity = String(1 - retract);
      }
      if (t < 1 || landing < 1 || Math.abs(targetDescent - descent) > .0005 || Math.abs(sway) > .001
        || Math.abs(targetX - character.rotation.x) + Math.abs(targetY - character.rotation.y) > .001) schedule();
    }
    function updateScroll() {
      if (state !== "listening" || lost) return;
      const rect = art.getBoundingClientRect();
      const start = innerHeight * .85;
      const end = Math.max(24, (innerHeight - rect.height) * .35);
      targetDescent = reduced.matches ? 1 : THREE.MathUtils.clamp((start - rect.top) / Math.max(1, start - end), 0, 1);
      if (firstMeasurement) {
        descent = targetDescent;
        grounded = descent >= .9995;
        firstMeasurement = false;
      }
      schedule();
    }
    function resize() {
      const { width, height } = host.getBoundingClientRect();
      if (!width || !height) return;
      camera.left = -1.6 * width / height;
      camera.right = 1.6 * width / height;
      camera.updateProjectionMatrix();
      renderer.setSize(width, height, false);
      anchorX = undefined;
      updateScroll();
      schedule();
    }
    function move(event: PointerEvent) {
      if (event.pointerType !== "mouse" || reduced.matches || !grounded) return;
      const rect = art.getBoundingClientRect();
      targetY = base.y + ((event.clientX - rect.left) / rect.width - .5) * .35;
      targetX = base.x + ((event.clientY - rect.top) / rect.height - .5) * .15;
      schedule();
    }
    function greet(event: PointerEvent) {
      if (event.pointerType !== "mouse" || reduced.matches || !grounded) return;
      gestureStarted = performance.now();
      schedule();
    }
    function reset() { targetX = base.x; targetY = base.y; gestureStarted = -Infinity; updateScroll(); schedule(); }
    function visibility() {
      if (document.hidden) { cancelAnimationFrame(frame); frame = 0; }
      else schedule();
    }
    function contextLost(event: Event) {
      event.preventDefault(); lost = true;
      cancelAnimationFrame(frame); frame = 0;
      showFallback();
    }
    function showFallback() {
      host.dataset.scene = "fallback";
      host.dataset.arrival = "settled";
      host.style.removeProperty("translate");
      if (rope) rope.style.opacity = "0";
    }
    const resizes = new ResizeObserver(resize);
    const intersections = new IntersectionObserver(([entry]) => {
      visible = entry.isIntersecting;
      if (visible) { updateScroll(); schedule(); }
      else { cancelAnimationFrame(frame); frame = 0; gestureStarted = -Infinity; }
    });
    host.append(canvas);
    resizes.observe(host);
    intersections.observe(state === "listening" ? art : host);
    if (state === "listening") window.addEventListener("scroll", updateScroll, { passive: true });
    art.addEventListener("pointermove", move);
    art.addEventListener("pointerenter", greet);
    art.addEventListener("pointerleave", reset);
    document.addEventListener("visibilitychange", visibility);
    reduced.addEventListener("change", reset);
    canvas.addEventListener("webglcontextlost", contextLost);
    resize();
    return () => {
      disposed = true;
      cancelAnimationFrame(frame);
      resizes.disconnect(); intersections.disconnect();
      art.removeEventListener("pointermove", move);
      art.removeEventListener("pointerenter", greet);
      art.removeEventListener("pointerleave", reset);
      document.removeEventListener("visibilitychange", visibility);
      reduced.removeEventListener("change", reset);
      window.removeEventListener("scroll", updateScroll);
      canvas.removeEventListener("webglcontextlost", contextLost);
      releaseResources();
      delete host.dataset.scene;
      delete host.dataset.arrival;
      host.style.removeProperty("translate");
      if (rope) rope.style.opacity = "0";
    };
  } catch {
    releaseResources();
    return null;
  }
}
