// Run after: flutter test tool/screens_test.dart --plain-name QR
// Uses the same local Playwright install as browser_smoke.cjs.
const assert = require('node:assert/strict');
const fs = require('node:fs/promises');
const path = require('node:path');
const { chromium } = require('../.dart_tool/browser-check/node_modules/playwright');

(async () => {
  const folder = process.env.SCREENS_DIR || 'build/screens';
  const names = ['qr-static', 'qr-enlarged'];
  for (const width of [390, 320, 1440]) {
    for (const look of ['day', 'night']) {
      names.push(`qr-${width}-${look}`, `qr-${width}-${look}-next`, `qr-${width}-${look}-enlarged`);
    }
  }
  const browser = await chromium.launch({ channel: 'chrome', headless: true });
  const results = [];
  try {
    const page = await browser.newPage();
    await page.addScriptTag({ path: 'web/assets/zxing.min.js' });
    for (const name of names) {
      const metadata = JSON.parse(await fs.readFile(path.join(folder, `${name}.json`), 'utf8'));
      const png = await fs.readFile(path.join(folder, `${name}.png`));
      // This bundled ZXing version can choose false finder patterns when even
      // an exact QR matrix is rendered at large cell sizes. Normalize the crop
      // to a camera-sized image before checking the payload; do not mistake
      // this check for verification of real camera focus or capture speed.
      const width = Math.min(320, Math.floor(metadata.width));
      const decoded = await page.evaluate(async ({ metadata, png, width }) => {
        const img = new Image();
        img.src = `data:image/png;base64,${png}`;
        await img.decode();
        const canvas = document.createElement('canvas');
        canvas.width = width;
        canvas.height = width;
        canvas.getContext('2d').drawImage(img,
          metadata.x, metadata.y, metadata.width, metadata.height,
          0, 0, canvas.width, canvas.height);
        const source = new ZXing.HTMLCanvasElementLuminanceSource(canvas);
        const bitmap = new ZXing.BinaryBitmap(new ZXing.HybridBinarizer(source));
        const hints = new Map([[ZXing.DecodeHintType.TRY_HARDER, true]]);
        return new ZXing.QRCodeReader().decode(bitmap, hints).getText();
      }, { metadata, png: png.toString('base64'), width });
      assert.equal(decoded, metadata.data, name);
      results.push({ name, width, decoded: true, characters: decoded.length });
    }
    await fs.mkdir('artifacts', { recursive: true });
    await fs.writeFile('artifacts/qr-image-verification.json', JSON.stringify({
      passed: true,
      note: 'Rendered QR crops normalized to at most 320 pixels for the bundled decoder; physical-camera testing remains separate.',
      results,
    }, null, 2));
    console.log(`PASS: ${results.length} rendered QR decodes match the displayed payloads.`);
  } finally {
    await browser.close();
  }
})().catch(error => { console.error(error); process.exitCode = 1; });
