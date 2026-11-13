// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2026 Clemens Kressmann
import * as THREE from "three";

/** Original hero geometry and materials. The caller owns the environment texture. */
export function createHeroScene(environmentMap: THREE.CompressedCubeTexture) {
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

  return {
    scene, camera, body, layers,
    dispose() {
      for (const geometry of geometries) geometry.dispose();
      for (const surface of materials) surface.dispose();
    },
  };
}
