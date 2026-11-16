import * as THREE from 'three';
import { LDrawLoader } from 'three/addons/loaders/LDrawLoader.js';
import { LDrawConditionalLineMaterial } from 'three/addons/materials/LDrawConditionalLineMaterial.js';
import { OrbitControls } from 'three/addons/controls/OrbitControls.js';

const manifest = await fetch('./manifest.json').then(r => r.json());
const examples = manifest.examples;
const canvas = document.getElementById('view');
const status = document.getElementById('status');
const picker = document.getElementById('parts');
const renderer = new THREE.WebGLRenderer({canvas, antialias: true, alpha: true, preserveDrawingBuffer: true});
renderer.setSize(800, 600, false);
renderer.setPixelRatio(1);
renderer.outputColorSpace = THREE.SRGBColorSpace;
renderer.toneMapping = THREE.NeutralToneMapping;
renderer.setClearColor(0xffffff, 0);
const scene = new THREE.Scene();
scene.add(new THREE.HemisphereLight(0xffffff, 0xadb5c1, 2.0));
const key = new THREE.DirectionalLight(0xffffff, 2.4);
key.position.set(-100, 180, 120);
scene.add(key);
const fill = new THREE.DirectionalLight(0xffffff, 0.6);
fill.position.set(100, 40, -100);
scene.add(fill);
const camera = new THREE.OrthographicCamera(-80, 80, 60, -60, 0.1, 5000);
const controls = new OrbitControls(camera, canvas);
controls.enablePan = false;
controls.addEventListener('change', () => renderer.render(scene, camera));
const loader = new LDrawLoader();
loader.setConditionalLineMaterial(LDrawConditionalLineMaterial);
// Packed subfile names are complete; avoid rewriting s/ into parts/s/.
loader.setFileMap(Object.fromEntries(manifest.files.map(file => [file.name, file.name])));
await loader.preloadMaterials('./library/LDConfig.ldr');

let current, currentExample, currentStats, busy = false;
const cache = new Map();
for (const entry of examples) {
  const option = document.createElement('option');
  option.value = entry.id;
  option.textContent = `${entry.label} · ${entry.colorLabel} · ${entry.part}`;
  picker.append(option);
}

function inspect(model) {
  const bounds = new THREE.Box3().setFromObject(model);
  const size = bounds.getSize(new THREE.Vector3());
  let triangles = 0, meshes = 0;
  const materials = new Map();
  model.traverse(object => {
    if (!object.isMesh) return;
    meshes++;
    triangles += (object.geometry.index?.count ?? object.geometry.attributes.position.count) / 3;
    for (const material of Array.isArray(object.material) ? object.material : [object.material]) {
      materials.set(material.uuid, {name: material.name.trim(), color: material.color?.getHexString(),
        opacity: material.opacity, transparent: material.transparent});
    }
  });
  return {boundsLDU: size.toArray().map(v => Math.round(v * 1000) / 1000), triangles, meshes, materials: [...materials.values()]};
}

function setAngle(angle) {
  const bounds = new THREE.Box3().setFromObject(current);
  const radius = bounds.getBoundingSphere(new THREE.Sphere()).radius;
  const halfHeight = radius * 0.95;
  camera.left = -halfHeight * 4 / 3;
  camera.right = halfHeight * 4 / 3;
  camera.top = halfHeight;
  camera.bottom = -halfHeight;
  camera.zoom = 1;
  camera.position.copy(angle === 'under' ? new THREE.Vector3(1, -0.9, 1.3) : new THREE.Vector3(1, 0.85, 1.3)).normalize().multiplyScalar(radius * 5);
  camera.up.set(0, 1, 0);
  camera.lookAt(0, 0, 0);
  camera.updateProjectionMatrix();
  controls.target.set(0, 0, 0);
  controls.update();
  renderer.render(scene, camera);
}

async function selectExample(id) {
  const example = examples.find(entry => entry.id === id);
  if (!example) throw new Error(`Unknown example ${id}`);
  const started = performance.now();
  if (!cache.has(id)) {
    const model = await loader.loadAsync(`./packed/${id}.mpd`);
    model.rotation.x = Math.PI; // LDraw uses negative Y as up.
    model.updateMatrixWorld(true);
    const bounds = new THREE.Box3().setFromObject(model);
    model.position.sub(bounds.getCenter(new THREE.Vector3()));
    model.updateMatrixWorld(true);
    cache.set(id, model);
  }
  if (current) scene.remove(current);
  current = cache.get(id);
  currentExample = example;
  scene.add(current);
  currentStats = inspect(current);
  setAngle('front');
  picker.value = id;
  status.textContent = `${example.sourceTitle}\n${example.part} · LDraw color ${example.color} · ${example.dependencyFiles} geometry files\n${currentStats.triangles.toLocaleString()} triangles · bounds ${currentStats.boundsLDU.join(' × ')} LDU`;
  return {...currentStats, loadAndRenderMs: Math.round((performance.now() - started) * 10) / 10};
}

window.selectExample = selectExample;
window.capture = angle => {
  const started = performance.now();
  setAngle(angle);
  const png = canvas.toDataURL('image/png');
  return {png, renderAndEncodeMs: Math.round((performance.now() - started) * 10) / 10,
    part: currentExample.part, stats: currentStats};
};
picker.addEventListener('change', async () => {
  if (busy) return;
  busy = true; picker.disabled = true;
  try { await selectExample(picker.value); }
  catch (error) { status.textContent = error.message; }
  finally { busy = false; picker.disabled = false; }
});
document.getElementById('front').addEventListener('click', () => setAngle('front'));
document.getElementById('under').addEventListener('click', () => setAngle('under'));
await selectExample(examples[0].id);
window.ready = true;
