// Reproducible research render. Does not modify the native app.
import { chromium } from 'playwright';
import { createServer } from 'node:http';
import { readFile, writeFile, mkdir } from 'node:fs/promises';
import { dirname, resolve, extname, sep } from 'node:path';
import { fileURLToPath } from 'node:url';
import assert from 'node:assert/strict';

const root = dirname(fileURLToPath(import.meta.url));
const output = resolve(root, 'renders');
await mkdir(output, {recursive: true});
const manifest = JSON.parse(await readFile(resolve(root, 'manifest.json'), 'utf8'));
const types = {'.html':'text/html','.js':'text/javascript','.mjs':'text/javascript','.json':'application/json','.png':'image/png'};
const server = createServer(async (request, response) => {
  try {
    const name = decodeURIComponent(new URL(request.url, 'http://localhost').pathname);
    const path = resolve(root, '.' + (name === '/' ? '/index.html' : name));
    if (!path.startsWith(root + sep)) throw new Error('Outside experiment');
    const data = await readFile(path);
    response.writeHead(200, {'Content-Type': types[extname(path)] || 'text/plain'});
    response.end(data);
  } catch { response.writeHead(404); response.end('Not found'); }
});
await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
const url = `http://127.0.0.1:${server.address().port}`;
const browser = await chromium.launch({
  executablePath: process.env.BROWSER_EXECUTABLE || '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
  headless: true, args: ['--use-angle=swiftshader', '--enable-unsafe-swiftshader']
});
try {
  const page = await browser.newPage({viewport:{width:1280,height:1100},deviceScaleFactor:1});
  const errors = [], warnings = [];
  page.on('pageerror', error => errors.push(error.message));
  page.on('console', message => { if (message.type() === 'warning') warnings.push(message.text()); });
  page.on('response', response => { if(response.status() >= 400 && !response.url().endsWith('favicon.ico')) errors.push(`${response.status()} ${response.url()}`); });
  await page.route('**/*', route => new URL(route.request().url()).hostname === '127.0.0.1' ? route.continue() : route.abort());
  await page.goto(url);
  await page.waitForFunction(() => window.ready, {timeout: 30000});
  const results = [];
  for (const example of manifest.examples) {
    const metrics = await page.evaluate(id => window.selectExample(id), example.id);
    assert(metrics.triangles > 0 && metrics.boundsLDU.every(v => v > 0 && Number.isFinite(v)), JSON.stringify({example:example.id,metrics,errors,warnings}));
    const angles = {};
    for (const angle of ['front','under']) {
      const result = await page.evaluate(angle => window.capture(angle), angle);
      const bytes = Buffer.from(result.png.split(',')[1], 'base64');
      await writeFile(resolve(output, `${example.id}-${angle}.png`), bytes);
      angles[angle] = {pngBytes:bytes.length, renderAndEncodeMs:result.renderAndEncodeMs};
    }
    results.push({...example, ...metrics, angles});
    console.log(`${example.id}: ${metrics.triangles} triangles, ${angles.front.pngBytes} byte PNG`);
  }
  const byID = Object.fromEntries(results.map(r => [r.id,r]));
  const dimensions = entry => [...entry.boundsLDU].sort((a,b)=>a-b);
  assert.deepEqual(dimensions(byID['yellow-brick']), [28,40,80]);
  assert.deepEqual(dimensions(byID['white-brick']), [28,40,40]);
  assert.deepEqual(dimensions(byID['green-plate']), [12,40,80]);
  assert.deepEqual(dimensions(byID['blue-tile']), [8,20,40]);
  assert(byID['printed-brick'].materials.some(m=>m.name === 'Black') && byID['printed-brick'].materials.some(m=>m.name === 'Yellow'), 'Fixed black print and inherited yellow must both survive');
  assert(byID['clear-brick'].materials.some(m => m.transparent && m.opacity < 1), 'Transparency must survive');
  assert.equal(byID['yellow-brick'].triangles, byID['clear-brick'].triangles, 'Color must not change geometry');
  await page.selectOption('#parts', 'printed-brick');
  await page.waitForFunction(() => !document.getElementById('parts').disabled && document.getElementById('status').textContent.includes('3001p08.dat'));
  const frontImage = await page.locator('canvas').evaluate(canvas => canvas.toDataURL());
  await page.click('#under');
  const underImage = await page.locator('canvas').evaluate(canvas => canvas.toDataURL());
  assert.notEqual(frontImage, underImage, 'Underside control changes the visible model');
  const canvasBox = await page.locator('canvas').boundingBox();
  await page.mouse.move(canvasBox.x + 200, canvasBox.y + 200);
  await page.mouse.down();
  await page.mouse.move(canvasBox.x + 320, canvasBox.y + 220, {steps:10});
  await page.mouse.up();
  const rotatedImage = await page.locator('canvas').evaluate(canvas => canvas.toDataURL());
  assert.notEqual(underImage, rotatedImage, 'Drag rotates the actual geometry');
  assert.deepEqual(errors, [], 'No failed local geometry loads or runtime errors');
  assert.deepEqual(warnings.filter(w => /LDraw|material|subfile/i.test(w)), [], 'No silently substituted geometry/material');
  const report = {createdAt:new Date().toISOString(), browser:browser.version(), renderer:'three@0.181.0',
    backend:'Headless Chrome with SwiftShader; not an iPad benchmark', dimensions:[800,600],
    recipe:{camera:[1,0.85,1.3],projection:'orthographic',output:'sRGB',toneMapping:'neutral',hemisphereIntensity:2,keyIntensity:2.4,fillIntensity:0.6},
    checks:['Complete dependency closure','Finite nonempty geometry','Known brick/plate/tile dimensions','Fixed print colors retained','Transparent material retained','Same geometry across colors','No loader errors or material warnings','Interactive part selection, underside button, and drag rotation'],
    warnings,results};
  await writeFile(resolve(root,'results.json'),JSON.stringify(report,null,2)+'\n');
  const cards=results.map(r=>`<article><div class="images"><img src="renders/${r.id}-front.png" alt="${r.label}, three-quarter view"><img src="renders/${r.id}-under.png" alt="${r.label}, underside"></div><h2>${r.label}</h2><p>${r.colorLabel} · ${r.part}</p></article>`).join('');
  await writeFile(resolve(root,'gallery.html'),`<!doctype html><html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>LDraw render study</title><style>body{margin:0;background:#f7f5ef;color:#263c31;font:16px system-ui}main{padding:30px;max-width:1280px;margin:auto}h1{font-size:30px;margin:0 0 8px}header p{margin:0 0 22px;color:#59665c}.grid{display:grid;grid-template-columns:repeat(4,minmax(0,1fr));gap:16px}article{background:white;border-radius:20px;padding:14px}.images img:first-child{width:100%;display:block}.images img:nth-child(2){width:55%;display:block;margin:-10px auto 0;background:#f0f1ec;border-radius:12px}h2{font-size:16px;margin:16px 0 4px}article p{color:#656b62;font-size:13px;margin:0}footer{color:#59665c;margin-top:20px;font-size:13px;line-height:1.5}@media(max-width:700px){.grid{grid-template-columns:repeat(2,minmax(0,1fr))}}a{color:inherit}</style><main><header><h1>Real geometry. Two views of each part.</h1><p>Eight LDraw examples · top view + underside · standard LDraw materials</p></header><div class="grid">${cards}</div><footer>Geometry: LDraw Parts Library · Three.js r181 · Manually selected examples; Rebrickable mappings not yet validated.<br>Transparent plastic is an alpha-based approximation. This study verifies model rendering, not real-world color matching. <a href="index.html">Open rotatable viewer</a></footer></main></html>`);
  await page.goto(`${url}/gallery.html`);
  await page.waitForFunction(() => [...document.images].every(i=>i.complete&&i.naturalWidth>0));
  await page.screenshot({path:resolve(output,'comparison.png'),fullPage:true});
  console.log('Geometry/material checks passed; comparison.png and results.json saved.');
} finally {
  await browser.close();
  await new Promise(resolve=>server.close(resolve));
}
