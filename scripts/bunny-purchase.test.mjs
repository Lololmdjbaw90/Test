import test from 'node:test';
import assert from 'node:assert/strict';
import { generateKeyPairSync } from 'node:crypto';
import { purchaseBunnyItem, docName } from '../netlify/lib/sugerly.mjs';
const { privateKey } = generateKeyPairSync('rsa', { modulusLength: 2048 });
process.env.FIREBASE_SERVICE_ACCOUNT = JSON.stringify({ client_email: 'test@example.invalid', private_key: privateKey.export({ type: 'pkcs8', format: 'pem' }) });
const user = { uid: 'buyer', email: 'buyer@example.invalid' };
const field = n => ({ integerValue: String(n) });
async function purchase({ coins = 500, price = 100, expected = 100, owned = false, missing = false, conflict = false } = {}) {
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
      return Response.json([
        ...(missing ? [] : [{ found: { name: names[0], fields: { price_coins: field(price) } } }]),
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
