import assert from "node:assert/strict";
import test from "node:test";
import { ringRecipients } from "../../netlify/lib/call-ring-policy.mjs";

const now = 1_800_000_000_000;
const call = { status: "ringing", started_at: now - 1000,
  member_emails: ["caller@example.com", " A@example.com ", "a@example.com", "b@example.com", "c@example.com"],
  joined_emails: ["b@example.com"], declined_by: ["C@example.com"] };

test("only rings unanswered members, normalizes and deduplicates addresses", () => {
  assert.deepEqual(ringRecipients(call, "caller@example.com", now), ["a@example.com"]);
});
test("does not ring active or ended calls", () => {
  for (const status of ["active", "ended", ""]) {
    assert.deepEqual(ringRecipients({ ...call, status }, "caller@example.com", now), []);
  }
});
test("ringing stops at 45 seconds, including calls never marked ended", () => {
  assert.deepEqual(ringRecipients({ ...call, started_at: now - 45_000 }, "caller@example.com", now), []);
  assert.equal(ringRecipients({ ...call, started_at: now - 44_999 }, "caller@example.com", now).length, 1);
});
test("invalid and future timestamps cannot keep a call ringing indefinitely", () => {
  for (const started_at of [undefined, null, "broken", 0, now + 5001]) {
    assert.deepEqual(ringRecipients({ ...call, started_at }, "caller@example.com", now), []);
  }
});
