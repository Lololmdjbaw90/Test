import assert from 'node:assert/strict';
const {chromium}=await import(process.env.PLAYWRIGHT_MODULE || 'playwright');
const browser=await chromium.launch({channel:'msedge',headless:true});
const page=await browser.newPage({viewport:{width:390,height:844}});
const crashes=[];page.on('pageerror',e=>crashes.push(e.message));
try {
 await page.goto('http://127.0.0.1:3000/Login');
 await page.getByPlaceholder('Email',{exact:true}).fill('admin@mimilocks.local');
 await page.getByPlaceholder('Password',{exact:true}).fill('admin123');
 await page.locator('button[type=submit]').click();
 await page.waitForURL(u=>!u.pathname.toLowerCase().includes('login'));
 const results=await page.evaluate(async()=>{
  const {base44}=await import('/src/api/base44Client.js');const me=await base44.auth.me();
  const author={user_email:me.email,user_display_name:me.display_name};
  const rejected=async f=>{try {await f();return '';} catch(e){return e.message;}};
  const links=await rejected(()=>base44.entities.Reel.create({...author,caption:'Visit https://example.com'}));
  const bio=await rejected(()=>base44.auth.updateMe({bio:'example.com'}));
  const abuse=await rejected(()=>base44.entities.CommunityComment.create({...author,post_id:'test',content:'k y s'}));
  const support=await base44.entities.CommunityComment.create({...author,post_id:'test',content:'i want to die'});
  const post=await base44.entities.CommunityPost.create({...author,title:'A lovely drawing',content:'Integration test'});
  const cooldown=await rejected(()=>base44.entities.CommunityPost.create({...author,title:'Another drawing'}));
  await base44.entities.CommunityPost.update(post.id,{likes:[me.email]});
  const server=await base44.entities.Community.create({owner_email:me.email,name:'Test community',member_emails:[me.email]});
  await base44.entities.ServerChannel.create({community_id:server.id,name:'general',type:'text'});
  await base44.entities.ServerChannel.create({community_id:server.id,name:'art',type:'text'});
  await base44.entities.Report.create({reporter_email:me.email,target_preview:'k y s',reason:'Harassment'});
  return {links,bio,abuse,cooldown,support:!!support.id,server:!!server.id};
 });
 assert.match(results.links,/Links/);assert.match(results.bio,/Links/);assert.match(results.abuse,/harm/);assert.match(results.cooldown,/wait/);assert.ok(results.support&&results.server);
 assert.deepEqual(crashes,[]);
 console.log('PASS integrated writes: caption/bio links, abuse, cooldowns, support language, metadata updates, server provisioning, abuse reports; no runtime crashes');
} finally {await browser.close();}
