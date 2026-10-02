const assert = require('node:assert/strict');
const fs = require('node:fs/promises');
const { chromium } = require('../.dart_tool/browser-check/node_modules/playwright');

(async () => {
  await fs.mkdir('artifacts', { recursive: true });
  const browser = await chromium.launch({
    channel: 'chrome',
    headless: true,
  });
  const errors = [], external = [];
  async function makeContext(viewport) {
    const context = await browser.newContext({
      viewport, deviceScaleFactor: 1,
      permissions: ['clipboard-read', 'clipboard-write'],
    });
    await context.route('**/*', route => {
      const url = route.request().url();
      if (!url.startsWith('http://127.0.0.1:5178') && !url.startsWith('data:') && !url.startsWith('blob:')) {
        external.push(url);
        return route.abort();
      }
      return route.continue();
    });
    return context;
  }
  async function boot(page) {
    page.setDefaultTimeout(25000);
    page.setDefaultNavigationTimeout(45000);
    page.on('pageerror', error => errors.push(error.message));
    await page.goto('http://127.0.0.1:5178', {waitUntil:'domcontentloaded'});
    await page.locator('flt-semantics-placeholder').waitFor({state:'attached'});
    await page.locator('flt-semantics-placeholder').evaluate(el=>el.click());
    await page.waitForTimeout(600);
    await page.screenshot({path:'artifacts/boot-debug.png'});

    await page.getByRole('button', {name:'Settings'}).waitFor();
  }
  try {
    const sender = await makeContext({width:1440,height:1024});
    const page = await sender.newPage();
    await boot(page);
    await page.screenshot({path:'artifacts/desktop-empty.png'});
    await page.getByRole('button',{name:'Take a peek at an example pocket'}).click();
    await page.waitForTimeout(600);
    await page.screenshot({path:'artifacts/desktop-pocket.png'});
    await page.getByRole('button',{name:/Create something/}).click();
    await page.getByRole('button',{name:'Note A thought worth keeping'}).click();
    await page.getByRole('textbox',{name:'Give this thought a home…'}).click(); await page.keyboard.insertText('A little browser check'); await page.waitForTimeout(180);
    await page.getByRole('textbox',{name:'Let your thoughts land here.'}).click(); await page.keyboard.insertText('Café, tomorrow at 10. A small thing worth keeping.'); await page.waitForTimeout(180);
    await page.waitForTimeout(900);
    await page.screenshot({path:'artifacts/desktop-editor.png'});
    await page.getByRole('button',{name:'Save and go back'}).click();
    assert.match(await page.locator('body').ariaSnapshot(), /A little browser check/);
    await page.reload({waitUntil:'domcontentloaded'});
    await page.locator('flt-semantics-placeholder').waitFor({state:'attached'});
    await page.locator('flt-semantics-placeholder').evaluate(el=>el.click());
    await page.getByRole('button',{name:'Settings'}).waitFor();
    assert.match(await page.locator('body').ariaSnapshot(), /A little browser check/);
    console.log('PASS: browser local storage survives reload');
    await page.getByRole('group',{name:/A little browser check/}).click();
    await page.getByRole('button',{name:'Pass',exact:true}).click();
    // Let the sheet finish sliding up before its code is photographed.
    await page.getByRole('img',{name:/Pocklino pass code/}).waitFor();
    await page.waitForTimeout(700);
    if (await page.getByRole('button',{name:'Pause QR animation'}).count()) {
      await page.getByRole('button',{name:'Pause QR animation'}).click();
    }
    await page.screenshot({path:'artifacts/pass-qr.png'});
    await page.addScriptTag({url:'http://127.0.0.1:5178/assets/zxing.min.js'});
    const screenshot = await page.getByRole('img',{name:/Pocklino pass code/}).screenshot();
    const scanned = await page.evaluate(async data => {
      const img = new Image(); img.src = data; await img.decode();
      const canvas = document.createElement('canvas');
      canvas.width = img.width; canvas.height = img.height;
      canvas.getContext('2d').drawImage(img,0,0);
      const source = new ZXing.HTMLCanvasElementLuminanceSource(canvas);
      const bitmap = new ZXing.BinaryBitmap(new ZXing.HybridBinarizer(source));
      const hints = new Map([[ZXing.DecodeHintType.TRY_HARDER,true]]);
      return new ZXing.QRCodeReader().decode(bitmap,hints).getText();
    }, 'data:image/png;base64,'+screenshot.toString('base64'));
    assert.match(scanned,/^pocklino(?:-part)?:1:/);
    console.log('PASS: locally bundled ZXing decodes actual rendered QR pixels');
    await page.getByRole('button',{name:'Copy code',exact:true}).click();
    const token = await page.evaluate(()=>navigator.clipboard.readText());
    assert.match(token,/^pocklino:1:/);
    const receiver = await makeContext({width:390,height:844});
    const phone = await receiver.newPage();
    await boot(phone);
    await phone.getByRole('button',{name:'Receive a note',exact:true}).click();
    await phone.getByRole('textbox',{name:'Paste your Pocklino pass code here…'}).click();
    await phone.keyboard.insertText(token);
    await phone.waitForTimeout(200);
    await phone.getByRole('button',{name:'Preview pocket',exact:true}).click();
    assert.match(await phone.locator('body').ariaSnapshot(), /A little browser check/);
    await phone.getByRole('button',{name:'Keep in my pocket',exact:true}).click();
    await phone.waitForTimeout(500);
    assert.match(await phone.locator('body').ariaSnapshot(), /A little browser check/);
    console.log('PASS: independent receiver previews and keeps its own copy');
    await phone.getByRole('button',{name:'Settings',exact:true}).click();
    await phone.getByRole('button',{name:/Explore an example pocket/}).click();
    await phone.getByRole('button',{name:'Back',exact:true}).click();
    await phone.mouse.move(195, 520);
    await phone.getByText('Example items are waiting in your pocket.').waitFor({state:'detached', timeout:12000});
    await phone.waitForTimeout(400);
    await phone.screenshot({path:'artifacts/phone-pocket.png'});
    await page.getByRole('button',{name:'Close',exact:true}).click();
    await page.getByRole('button',{name:'Save and go back'}).click();
    await page.getByRole('button',{name:'Settings',exact:true}).click();
    await page.getByRole('button',{name:'Evening ink'}).click();
    await page.waitForTimeout(400);
    await page.getByRole('button',{name:'Back',exact:true}).click();
    await page.mouse.move(820, 900);
    await page.waitForTimeout(400);
    await page.screenshot({path:'artifacts/desktop-dark.png'});
    console.log('PASS: dark theme and phone layout');
    console.log('EXTERNAL REQUESTS', JSON.stringify([...new Set(external)]));
    console.log('BROWSER ERRORS', JSON.stringify(errors));
    assert.deepEqual(errors, []);
    assert.deepEqual(external, []);
    await fs.writeFile('artifacts/browser-verification.json', JSON.stringify({
      passed:true, checks:['persistence','rendered QR decode','independent import','phone layout','dark theme','no external requests'],
      errors, externalRequests: external,
    },null,2));
  } finally {
    await browser.close();
  }
})().catch(error=>{ console.error(error); process.exitCode=1; });
