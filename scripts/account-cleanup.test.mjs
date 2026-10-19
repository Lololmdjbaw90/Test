import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { createHash } from 'node:crypto';
import vm from 'node:vm';
const source = readFileSync(new URL('../functions/account-cleanup.js', import.meta.url), 'utf8')
  .replace(/^import .*;\r?\n/gm, '').replace('export const accountChatCleanup =', 'globalThis.worker =');
function fixture(messages, failCommit = false) {
  const tables = { DirectMessage: new Map(messages.map((m, i) => [`m${i}`, m])), User: new Map([['gone-id', { email: 'gone@example.invalid' }]]), Notification: new Map(), ChatRemoval: new Map() };
  let failed = false;
  const ref = (table, id) => ({ table, id, delete: async () => tables[table].delete(id) });
  const apply = operations => { for (const [type, r, data] of operations) {
    if (type === 'delete') tables[r.table].delete(r.id);
    else if (type === 'create') { assert.ok(!tables[r.table].has(r.id)); tables[r.table].set(r.id, data); }
    else tables[r.table].set(r.id, { ...tables[r.table].get(r.id), ...data });
  }};
  const db = {
    collection: table => ({
      doc: id => ref(table, id),
      where: (field, op, email) => ({ limit: limit => ({ get: async () => {
        const docs = [...tables[table]].filter(([, d]) => d[field].includes(email)).slice(0, limit).map(([id, d]) => ({ data: () => d, ref: ref(table, id) }));
        return { docs, empty: !docs.length };
      } }) }),
    }),
    runTransaction: async callback => {
      const ops = [];
      await callback({ get: async r => ({ exists: tables[r.table].has(r.id) }), create: (r, d) => ops.push(['create', r, d]) });
      apply(ops);
    },
    batch: () => {
      const ops = [];
      return { delete: r => ops.push(['delete', r]), update: (r, d) => ops.push(['update', r, d]), commit: async () => {
        if (failCommit && !failed) { failed = true; throw Error('transient'); }
        apply(ops);
      }};
    },
  };
  const context = { createHash, getApps: () => [{}], initializeApp: () => {}, getFirestore: () => db,
    functionsV1: { runWith: () => ({ auth: { user: () => ({ onDelete: fn => fn }) } }) } };
  vm.runInNewContext(source, context);
  return { tables, run: () => context.worker({ uid: 'gone-id', email: 'gone@example.invalid' }) };
}
const dm = { member_emails: ['gone@example.invalid', 'friend@example.invalid'], conversation_id: 'chat', user_email: 'friend@example.invalid' };
test('deletion paginates every private message and emits one notice per conversation', async () => {
  const f = fixture(Array.from({ length: 305 }, () => ({ ...dm })));
  await f.run();
  assert.equal(f.tables.DirectMessage.size, 0);
  assert.equal(f.tables.ChatRemoval.size, 1);
  assert.equal(f.tables.Notification.size, 1);
  assert.equal([...f.tables.Notification.values()][0].to_email, 'friend@example.invalid');
  assert.equal(f.tables.User.size, 0);
});
test('retry after a partial failure does not duplicate the notification', async () => {
  const f = fixture([dm], true);
  await assert.rejects(f.run(), /transient/);
  await f.run();
  assert.equal(f.tables.DirectMessage.size, 0);
  assert.equal(f.tables.Notification.size, 1);
});
test('keeps other people’s group messages and removes the deleted member', async () => {
  const f = fixture([{ ...dm, conversation_type: 'group' }, { ...dm, conversation_type: 'group', user_email: 'gone@example.invalid' }]);
  await f.run();
  assert.equal(f.tables.DirectMessage.size, 1);
  assert.equal(f.tables.DirectMessage.get('m0').member_emails.join(','), 'friend@example.invalid');
  assert.equal(f.tables.Notification.size, 0);
});
