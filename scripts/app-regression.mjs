import assert from 'node:assert/strict';
const { chromium } = await import(process.env.PLAYWRIGHT_MODULE || 'playwright');
const browser = await chromium.launch({ channel: process.env.BROWSER_CHANNEL || 'msedge', headless: true, args: ['--use-fake-ui-for-media-stream', '--use-fake-device-for-media-stream'] });
const context = await browser.newContext({ viewport: { width: 430, height: 900 } });
const page = await context.newPage();
const crashes = [];
page.on('pageerror', e => crashes.push(e.message));
await page.route('https://api.deezer.com/**', async route => {
  const url = new URL(route.request().url());
  const offset = Number(url.searchParams.get('index') || 0);
  const data = Array.from({length: 24}, (_, i) => ({ id: offset+i+1, title: `Test song ${offset+i+1}`, artist: {name:'Test artist'}, preview:'https://example.test/preview.wav', album: {cover_medium:'/icons/favicon-32.png'} }));
  await route.fulfill({contentType:'text/javascript',body:`${url.searchParams.get('callback')}(${JSON.stringify({data,next:offset<48?'next':null})})`});
});
await page.route('https://example.test/preview.wav', route => {
  const b=Buffer.alloc(44+44100*2); b.write('RIFF'); b.writeUInt32LE(b.length-8,4); b.write('WAVEfmt ',8); b.writeUInt32LE(16,16); b.writeUInt16LE(1,20); b.writeUInt16LE(1,22); b.writeUInt32LE(44100,24); b.writeUInt32LE(88200,28); b.writeUInt16LE(2,32); b.writeUInt16LE(16,34); b.write('data',36); b.writeUInt32LE(b.length-44,40);
  return route.fulfill({contentType:'audio/wav',body:b});
});
try {
  await page.goto('http://127.0.0.1:3000/Login');
  await page.getByPlaceholder('Email',{exact:true}).fill('admin@mimilocks.local');
  await page.getByPlaceholder('Password',{exact:true}).fill('admin123');
  await page.locator('button[type=submit]').click();
  await page.waitForURL(url => !url.pathname.toLowerCase().includes('login'));
  // Close the release announcement if it appears.
  for (const label of ['Got it', 'Let’s go', "Let's go", 'Close']) {
    const b = page.getByRole('button',{name:label,exact:true});
    if (await b.count() && await b.first().isVisible()) await b.first().click();
  }
  await page.goto('http://127.0.0.1:3000/Reels?create=1');
  const dialog = page.getByRole('dialog',{name:'Create a reel'});
  await dialog.waitFor();
  const photos = await page.evaluate(() => ['red','green','blue'].map(color => { const c=document.createElement('canvas');c.width=60;c.height=90;const x=c.getContext('2d');x.fillStyle=color;x.fillRect(0,0,60,90);return c.toDataURL().split(',')[1]; }));
  await dialog.locator('input[type=file]').setInputFiles(photos.map((png,n)=>({name:`photo${n}.png`,mimeType:'image/png',buffer:Buffer.from(png,'base64')})));
  await dialog.getByRole('button',{name:'Sound',exact:true}).click();
  await dialog.getByRole('button',{name:'Test song 1 Test artist',exact:true}).click();
  await dialog.getByRole('button',{name:'Next',exact:true}).click();
  await dialog.getByRole('textbox',{name:'Caption'}).fill('Regression slideshow');
  await dialog.getByRole('button',{name:'Post reel',exact:true}).click();
  await dialog.waitFor({state:'hidden',timeout:20000});
  const reel = await page.evaluate(async()=>{const {base44}=await import('/src/api/base44Client.js');return (await base44.entities.Reel.list()).find(r=>r.caption==='Regression slideshow')});
  assert.equal(reel.photo_urls.length,3); assert.equal(reel.duration,9); assert.equal(reel.music_title,'Test song 1');
  const activePhoto = page.locator('img[alt="Regression slideshow"]').first();
  await activePhoto.waitFor();
  const first = await activePhoto.getAttribute('src');
  await page.waitForFunction(src => document.querySelector('img[alt="Regression slideshow"]')?.src !== src, first, {timeout:10000});
  console.log('PASS: 3 photos + music -> posted slideshow advances');
  await page.goto('http://127.0.0.1:3000/Music');
  const music = page.getByRole('region',{name:'Discover music'});
  await music.getByText('Test song 1',{exact:true}).waitFor();
  await music.getByText('Test song 24',{exact:true}).scrollIntoViewIfNeeded();
  await music.getByText('Test song 25',{exact:true}).waitFor();
  console.log('PASS: scrolling loads the next music page');
  await page.goto('http://127.0.0.1:3000/Communities?create=1');
  await page.getByRole('button',{name:'Next',exact:true}).click();
  await page.getByLabel('Server name',{exact:true}).fill('Regression server');
  await page.getByRole('button',{name:'Create server',exact:true}).click();
  await page.waitForURL(url=>url.pathname.toLowerCase()==='/communitychat');
  await page.getByText('Welcome to #general',{exact:true}).waitFor();
  console.log('PASS: create server and open channels');
  const ids = await page.evaluate(async()=>{
    const {base44}=await import('/src/api/base44Client.js');
    for(let i=0;i<67;i++) await base44.entities.Reel.create({kind:'photo',media_url:'/icons/favicon-32.png',caption:`Page ${i}`,created_date:'2026-01-01T00:00:00.000Z'});
    let cursor=null, more=true, rows=[];
    while(more){const p=await base44.entities.Reel.page(null,{limit:7,cursor});rows.push(...p.rows);cursor=p.cursor;more=p.hasMore;}
    return rows.map(r=>r.id);
  });
  assert.equal(ids.length,new Set(ids).size); assert.ok(ids.length>=68);
  console.log('PASS: cursor pages have no duplicates across timestamp ties');
  await context.grantPermissions(['microphone','camera'], {origin:'http://127.0.0.1:3000'});
  const peer = await context.newPage();
  peer.on('pageerror', e => crashes.push(e.message));
  await peer.goto('http://127.0.0.1:3000/');
  const joinVoice = async p => p.evaluate(async()=>{
    const {base44}=await import('/src/api/base44Client.js'); const {default:voice}=await import('/src/lib/voice.js');
    return voice.join({id:'regression-room',type:'channel',name:'Test voice'},await base44.auth.me());
  });
  assert.equal(await joinVoice(page),true); assert.equal(await joinVoice(peer),true);
  await page.waitForFunction(async()=>{const {default:voice}=await import('/src/lib/voice.js');return voice.getState().participants.some(p=>!p.self&&p.connection==='connected')},{},{timeout:20000});
  await peer.waitForFunction(async()=>{const {default:voice}=await import('/src/lib/voice.js');return voice.getState().participants.some(p=>!p.self&&p.connection==='connected')},{},{timeout:20000});
  for (const p of [page,peer]) await p.evaluate(async()=>{const {default:voice}=await import('/src/lib/voice.js');await voice.leave();});
  await peer.close();
  console.log('PASS: two local peers establish and leave a WebRTC call');
  assert.deepEqual(crashes,[]);
  console.log('PASS: no browser runtime crashes');
} catch(e) {
  console.error('URL:',page.url()); console.error((await page.locator('body').innerText()).slice(-3500)); console.error('Crashes:',crashes);
  throw e;
} finally { await browser.close(); }
