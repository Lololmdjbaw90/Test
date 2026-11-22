import test from 'node:test';
import assert from 'node:assert/strict';
import { generateKeyPairSync } from 'node:crypto';
import { purchaseBunnyItem, sellBunnyItem, docName } from '../netlify/lib/sugerly.mjs';
const { privateKey } = generateKeyPairSync('rsa', { modulusLength: 2048 });
process.env.FIREBASE_SERVICE_ACCOUNT = JSON.stringify({ client_email: 'test@example.invalid', private_key: privateKey.export({ type: 'pkcs8', format: 'pem' }) });
const user = { uid: 'buyer', email: 'buyer@example.invalid' };
const field = n => ({ integerValue: String(n) });
async function purchase({ coins = 500, price = 100, expected = 100, owned = false, missing = false, conflict = false, seller = "", sellerMissing = false, sellerCoins = 20, active = true } = {}) {
  const writes = [];
  let tries = 0;
  const original = global.fetch;
  global.fetch = async (url, init) => {
    const path = String(url);
    if (path.includes('oauth2.googleapis.com')) return new Response(JSON.stringify({ access_token: 'fake', expires_in: 3600 }));
    if (path.endsWith(':beginTransaction')) return Response.json({ transaction: `txn${++tries}` });
    if (path.endsWith(':rollback')) return Response.json({});
    if (path.endsWith(':batchGet')) {
      const names = JSON.parse(init.body).documents;
      if (names.length === 1) return Response.json(sellerMissing ? [] : [{ found: { name: names[0], fields: { coins: field(sellerCoins) } } }]);
      return Response.json([
        ...(missing ? [] : [{ found: { name: names[0], fields: { price_coins: field(price), seller_uid: { stringValue: seller }, is_active: { booleanValue: active } } } }]),
        { found: { name: names[1], fields: { coins: field(coins) } } },
        ...(owned ? [{ found: { name: names[2], fields: { item_id: { stringValue: 'hat' } } } }] : []),
      ]);
    }
    if (path.endsWith(':commit')) {
      if (conflict && tries === 1) return Response.json({ error: { message: 'ABORTED' } }, { status: 409 });
      writes.push(JSON.parse(init.body).writes);
      return Response.json({});
    }
    throw Error(`Unexpected request: ${path}`);
  };
  try { return { result: await purchaseBunnyItem(user, 'hat', expected), writes, tries }; }
  finally { global.fetch = original; }
}
test('debits the server price and creates ownership in the same transaction', async () => {
  const { result, writes } = await purchase();
  assert.equal(result.coins, 400);
  assert.equal(writes.length, 1);
  assert.equal(writes[0].length, 2);
  assert.equal(writes[0][0].update.name, docName('User', 'buyer'));
  assert.equal(writes[0][0].update.fields.coins.integerValue, '400');
  assert.deepEqual(writes[0][1].currentDocument, { exists: false });
});
test('retrying an owned item never charges again', async () => {
  const { result, writes } = await purchase({ owned: true });
  assert.equal(result.owned, true); assert.equal(writes.length, 0);
});
test('insufficient coins are rejected', async () => { await assert.rejects(purchase({ coins: 50 }), /enough coins/); });
test('changed price requires a new confirmation', async () => { await assert.rejects(purchase({ expected: 1 }), /price changed/); });
test('deleted items cannot be bought', async () => { await assert.rejects(purchase({ missing: true }), /no longer available/); });
test('invalid negative prices cannot credit a buyer', async () => { await assert.rejects(purchase({ price: -20, expected: -20 }), /price needs correcting/); });
test('transaction contention retries without a second debit', async () => {
  const { result, writes, tries } = await purchase({ conflict: true });
  assert.equal(tries, 2); assert.equal(writes.length, 1); assert.equal(result.coins, 400);
});

test('creator receives the full coin price in the same atomic purchase', async () => {
  const { writes, result } = await purchase({ seller: 'creator' });
  assert.equal(result.coins, 400);
  assert.equal(writes[0].length, 3);
  assert.equal(writes[0][0].update.name, docName('User', 'creator'));
  assert.equal(writes[0][0].update.fields.coins.integerValue, '120');
});
test('owned retries never pay the creator twice', async () => {
  const { writes } = await purchase({ seller: 'creator', owned: true });
  assert.equal(writes.length, 0);
});
test('missing seller cannot consume buyer coins', async () => { await assert.rejects(purchase({ seller: 'creator', sellerMissing: true }), /cannot receive coins/); });
test('creators cannot pay themselves for their own item', async () => {
  const { writes, result } = await purchase({ seller: 'buyer' });
  assert.equal(writes.length, 0); assert.equal(result.coins, 500);
});
test('withdrawn items reject new purchases', async () => { await assert.rejects(purchase({ active: false }), /no longer for sale/); });
test('seller balance overflow is rejected', async () => { await assert.rejects(purchase({ seller: 'creator', sellerCoins: Number.MAX_SAFE_INTEGER }), /cannot receive coins/); });

async function sell({ image = 'https://firebasestorage.googleapis.com/v0/b/umikoworks-86333.firebasestorage.app/o/uploads%2Fbuyer%2Fart.png?alt=media', price = 100, existing = null, active = true } = {}) {
  const writes = [];
  const original = global.fetch;
  const encode = x => ({ stringValue: x });
  global.fetch = async (url, init) => {
    const path = String(url);
    if (path.includes('oauth2.googleapis.com')) return Response.json({ access_token: 'fake', expires_in: 3600 });
    if (init?.method === 'PATCH') { writes.push(JSON.parse(init.body)); return Response.json({ name: docName('BunnyItem', 'listed'), fields: {} }); }
    if (path.includes('/User/buyer')) return Response.json({ name: docName('User', 'buyer'), fields: { bunny_items: encode(JSON.stringify([{ id: 'personal-test', name: 'My bow', slot: 'head', image_url: image }])), display_name: encode('Artist') } });
    if (path.includes('/BunnyItem/')) return existing ? Response.json({ name: docName('BunnyItem', 'listed'), fields: { image_url: encode(existing), slot: encode('head') } }) : new Response('{}', { status: 404 });
    throw Error('Unexpected request');
  };
  try { return { result: await sellBunnyItem(user, { item_id: 'personal-test', price, active }), writes }; }
  finally { global.fetch = original; }
}
test('listing credits the authenticated seller identity', async () => {
  const { writes } = await sell();
  assert.equal(writes[0].fields.seller_uid.stringValue, 'buyer');
  assert.equal(writes[0].fields.price_coins.integerValue, '100');
});
test('listing rejects someone else’s Storage artwork', async () => {
  await assert.rejects(sell({ image: 'https://firebasestorage.googleapis.com/v0/b/umikoworks-86333.firebasestorage.app/o/uploads%2Fother%2Fart.png' }), /own account/);
});
test('listing rejects external images and negative prices', async () => {
  await assert.rejects(sell({ image: 'https://example.com/art.png' }), /own account/);
  await assert.rejects(sell({ price: -10 }), /Choose a price/);
});
test('published artwork cannot silently change for existing buyers', async () => {
  await assert.rejects(sell({ existing: 'https://old.example.com/old.png' }), /cannot be replaced/);
});

test('creator payout retries contention as one purchase', async () => {
  const { writes, tries } = await purchase({ seller: 'creator', conflict: true });
  assert.equal(tries, 2); assert.equal(writes.length, 1); assert.equal(writes[0][0].update.fields.coins.integerValue, '120');
});
