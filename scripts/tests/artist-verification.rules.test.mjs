import { before, after, beforeEach, test } from 'node:test';
import { readFileSync } from 'node:fs';
import { initializeTestEnvironment, assertSucceeds, assertFails } from '@firebase/rules-unit-testing';
import { doc, setDoc, updateDoc } from 'firebase/firestore';
let env;
const email = uid => `${uid}@example.invalid`;
const db = uid => env.authenticatedContext(uid, { email: email(uid) }).firestore();
const listing = { artist_email: email('artist'), created_by: email('artist'), is_open: true };
before(async () => { env = await initializeTestEnvironment({ projectId: 'demo-sugerly-rules', firestore: { rules: readFileSync('firestore.rules', 'utf8') } }); });
after(async () => { await env?.cleanup(); });
beforeEach(async () => {
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async context => {
    for (const uid of ['artist', 'buyer', 'admin']) await setDoc(doc(context.firestore(), 'User', uid), { email: email(uid), role: uid === 'admin' ? 'admin' : 'user' });
    await setDoc(doc(context.firestore(), 'Commission', 'existing'), listing);
    await setDoc(doc(context.firestore(), 'CommissionOrder', 'paid'), { artist_email: email('artist'), buyer_email: email('buyer'), status: 'paid' });
  });
});
const approve = () => setDoc(doc(db('admin'), 'SiteConfig', 'artist-artist'), { verified: true });
test('artists cannot award themselves a review badge', async () => {
  await assertFails(setDoc(doc(db('artist'), 'SiteConfig', 'artist-artist'), { verified: true }));
});
test('unverified artists cannot publish, even with a forged profile badge', async () => {
  await assertSucceeds(updateDoc(doc(db('artist'), 'User', 'artist'), { artist_verified: true }));
  await assertFails(setDoc(doc(db('artist'), 'Commission', 'new'), listing));
});
test('reviewed artist can publish and reopen; unreviewed can still close', async () => {
  await assertFails(updateDoc(doc(db('artist'), 'Commission', 'existing'), { is_open: true }));
  await assertSucceeds(updateDoc(doc(db('artist'), 'Commission', 'existing'), { is_open: false }));
  await assertSucceeds(approve());
  await assertSucceeds(setDoc(doc(db('artist'), 'Commission', 'new'), listing));
  await assertSucceeds(updateDoc(doc(db('artist'), 'Commission', 'existing'), { is_open: true }));
});
test('approval cannot be used to publish under someone else’s identity', async () => {
  await approve();
  await assertFails(setDoc(doc(db('artist'), 'Commission', 'new'), { ...listing, artist_email: email('buyer') }));
});
test('new requests require an approved artist and cannot spoof their uid', async () => {
  const request = { commission_id: 'existing', artist_email: email('artist'), artist_uid: 'artist', buyer_email: email('buyer'), status: 'requested', price: 10 };
  await assertFails(setDoc(doc(db('buyer'), 'CommissionOrder', 'new'), request));
  await approve();
  await assertSucceeds(setDoc(doc(db('buyer'), 'CommissionOrder', 'new'), request));
  await assertFails(setDoc(doc(db('buyer'), 'CommissionOrder', 'fake'), { ...request, artist_uid: 'buyer' }));
});
test('unverified artists retain access to fulfil existing paid orders', async () => {
  await assertSucceeds(updateDoc(doc(db('artist'), 'CommissionOrder', 'paid'), { status: 'in_progress' }));
});
