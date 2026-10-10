// Ways into your Sugerly account besides a password, and admin account
// deletion. The app calls this with { action, ... }:
//
//   Email codes (needs BREVO_API_KEY or RESEND_API_KEY, plus MAIL_FROM):
//     code-send     { email, purpose: "login" | "reset" }
//     code-verify   { email, code, password? }        -> { token }
//   Backup codes (written down or saved, for when email doesn't work):
//     backup-create (signed in)                       -> { codes }
//     backup-status (signed in)                       -> { left, created }
//     backup-login  { email, code }                   -> { token }
//   Quick login (like a TV app: the new device shows a QR code / short code,
//   a phone that's already logged in scans or types it and says yes):
//     quick-start   { device }                        -> { id, code, secret }
//     quick-status  { id, secret }                    -> { status, token? }
//     quick-check   { code } (signed in)              -> { device }
//     quick-approve { code, approve } (signed in)
//   Admins:
//     admin-delete  { email } (signed in, admin)      -> deletes the account
//
// A "token" is a one-time sign-in pass the app trades for a session. Codes
// are only kept as fingerprints, run out quickly, and lock after a few
// wrong tries.
import crypto from "node:crypto";
import {
  Problem, addDoc, body, commit, customToken, deleteAccount, deleteDoc, docName, findAccount, findMany, findOne,
  fingerprint, getDoc, handle, isAdmin, mailReady, removeFromList, sameFingerprint, sendMail, setDoc, setPassword,
  signedInUser, updateDoc,
} from "../lib/sugerly.mjs";
import { loginCodeEmail, resetCodeEmail } from "../lib/emails.mjs";

const OWNERS = ["paologionfriddo90@gmail.com"];
const MINUTE = 60_000;
// Letters and numbers that can't be mixed up (no 0/O, 1/I/L).
const ALPHABET = "ABCDEFGHJKMNPQRSTUVWXYZ23456789";

const now = () => Date.now();
const iso = (t = now()) => new Date(t).toISOString();
const cleanEmail = (e) => String(e || "").trim().toLowerCase();
const cleanCode = (c) => String(c || "").toUpperCase().replace(/[^A-Z0-9]/g, "");

function randomCode(length) {
  const bytes = crypto.randomBytes(length);
  return Array.from(bytes, (b) => ALPHABET[b % ALPHABET.length]).join("");
}

function digits(length) {
  return Array.from({ length }, () => crypto.randomInt(10)).join("");
}

function emailKey(email) {
  return fingerprint(`email:${email}`).slice(0, 40);
}

async function tokenFor(email) {
  const account = await findAccount(email);
  if (!account) throw new Problem(404, "There's no Sugerly account with that email.");
  if (account.disabled) throw new Problem(403, "This account has been disabled.");
  return { token: customToken(account.uid), email: account.email };
}

// ---- email codes ----------------------------------------------------------

async function codeSend(input) {
  const email = cleanEmail(input.email);
  const purpose = input.purpose === "reset" ? "reset" : "login";
  if (!email.includes("@")) throw new Problem(400, "That email doesn't look right.");
  if (!mailReady()) return { sent: false, setup: false };
  const key = emailKey(email);
  const last = await getDoc("LoginCode", key);
  if (last && now() - Number(last.sent_at || 0) < 40_000) {
    throw new Problem(429, "A code is already on its way. Wait a few seconds before asking for another.");
  }
  const inWindow = Boolean(last) && now() - Number(last.window_start || 0) < 60 * MINUTE;
  const windowStart = inWindow ? Number(last.window_start) : now();
  const count = inWindow ? Number(last.count || 0) : 0;
  if (count >= 6) throw new Problem(429, "That's a lot of codes! Try again in an hour.");
  // Only accounts that exist get an email, but the answer looks the same
  // either way, so nobody can use this to find out who has an account.
  const account = await findAccount(email);
  if (!account || account.disabled) return { sent: true };
  const code = digits(6);
  await setDoc("LoginCode", key, {
    email, purpose, code_hash: fingerprint(`${key}:${code}`), expires: now() + 10 * MINUTE, tries: 0,
    sent_at: now(), window_start: windowStart, count: count + 1,
  });
  const mail = purpose === "reset" ? resetCodeEmail(code) : loginCodeEmail(code);
  await sendMail({ to: email, ...mail });
  return { sent: true };
}

async function codeVerify(input) {
  const email = cleanEmail(input.email);
  const code = String(input.code || "").replace(/\D/g, "");
  const key = emailKey(email);
  const saved = await getDoc("LoginCode", key);
  if (!saved || now() > Number(saved.expires || 0)) throw new Problem(400, "That code has run out. Ask for a new one.");
  if (Number(saved.tries || 0) >= 5) throw new Problem(429, "Too many wrong tries. Ask for a new code.");
  if (!sameFingerprint(fingerprint(`${key}:${code}`), saved.code_hash)) {
    const tries = Number(saved.tries || 0) + 1;
    await updateDoc("LoginCode", key, { tries });
    const left = 5 - tries;
    throw new Problem(400, left > 0 ? `That code isn't right. ${left} ${left === 1 ? "try" : "tries"} left.` : "Too many wrong tries. Ask for a new code.");
  }
  const account = await findAccount(email);
  if (!account) throw new Problem(404, "There's no Sugerly account with that email.");
  if (saved.purpose === "reset") {
    const password = String(input.password || "");
    if (password.length < 6) throw new Problem(400, "Use at least 6 characters for your password.");
    await setPassword(account.uid, password);
  }
  await deleteDoc("LoginCode", key);
  return tokenFor(email);
}

// ---- backup codes ---------------------------------------------------------

async function backupCreate(event) {
  const user = await signedInUser(event);
  const codes = Array.from({ length: 10 }, () => randomCode(8));
  await setDoc("AccountSecurity", user.uid, {
    email: user.email,
    backup_hashes: codes.map((c) => fingerprint(`backup:${user.uid}:${c}`)),
    backup_created: iso(), backup_fails: 0, backup_locked_until: 0,
  });
  return { codes: codes.map((c) => `${c.slice(0, 4)}-${c.slice(4)}`) };
}

async function backupStatus(event) {
  const user = await signedInUser(event);
  const saved = await getDoc("AccountSecurity", user.uid);
  return { left: (saved?.backup_hashes || []).length, created: saved?.backup_created || "" };
}

async function backupLogin(input) {
  const email = cleanEmail(input.email);
  const code = cleanCode(input.code);
  const wrong = new Problem(400, "That backup code doesn't work. Check the email and the code.");
  const account = await findAccount(email);
  if (!account || code.length !== 8) throw wrong;
  const saved = await getDoc("AccountSecurity", account.uid);
  if (!saved?.backup_hashes?.length) throw wrong;
  if (now() < Number(saved.backup_locked_until || 0)) throw new Problem(429, "Too many wrong tries. Wait 15 minutes and try again.");
  const hash = fingerprint(`backup:${account.uid}:${code}`);
  const match = saved.backup_hashes.find((h) => sameFingerprint(h, hash));
  if (!match) {
    const fails = Number(saved.backup_fails || 0) + 1;
    await updateDoc("AccountSecurity", account.uid, fails >= 5
      ? { backup_fails: 0, backup_locked_until: now() + 15 * MINUTE }
      : { backup_fails: fails });
    throw wrong;
  }
  // Each code works once.
  await updateDoc("AccountSecurity", account.uid, {
    backup_hashes: saved.backup_hashes.filter((h) => h !== match), backup_fails: 0, backup_used: iso(),
  });
  const result = await tokenFor(email);
  return { ...result, left: saved.backup_hashes.length - 1 };
}

// ---- quick login ----------------------------------------------------------

async function quickStart(input) {
  const device = String(input.device || "A new device").replace(/[^\p{L}\p{N} '’._-]/gu, "").slice(0, 40) || "A new device";
  let code = "";
  for (let i = 0; i < 5 && !code; i += 1) {
    const candidate = randomCode(6);
    const taken = await findOne("QuickLogin", "code", candidate);
    if (!taken || now() > Number(taken.expires || 0)) code = candidate;
  }
  if (!code) throw new Problem(503, "Couldn't make a code. Try again.");
  const id = crypto.randomBytes(16).toString("hex");
  const secret = crypto.randomBytes(24).toString("base64url");
  await setDoc("QuickLogin", id, {
    code, secret_hash: fingerprint(`quick:${id}:${secret}`), status: "waiting", device,
    created: iso(), expires: now() + 5 * MINUTE,
  });
  return { id, code, secret, expires: now() + 5 * MINUTE };
}

async function quickStatus(input) {
  const id = String(input.id || "").replace(/[^a-f0-9]/g, "");
  const saved = id ? await getDoc("QuickLogin", id) : null;
  if (!saved || !sameFingerprint(fingerprint(`quick:${id}:${input.secret}`), saved.secret_hash)) throw new Problem(404, "That quick login has ended.");
  if (saved.status === "approved") {
    // The pass is handed over once, then the request is gone.
    await deleteDoc("QuickLogin", id);
    return { status: "approved", ...(await tokenFor(saved.email)) };
  }
  if (saved.status !== "waiting" || now() > Number(saved.expires || 0)) {
    await deleteDoc("QuickLogin", id).catch(() => null);
    return { status: saved.status === "denied" ? "denied" : "expired" };
  }
  return { status: "waiting" };
}

async function pendingQuick(code) {
  const matches = await findMany("QuickLogin", [["code", "EQUAL", cleanCode(code)]], 5);
  const saved = matches.find((m) => m.status === "waiting" && now() <= Number(m.expires || 0));
  if (!saved) {
    throw new Problem(404, "That code isn't waiting any more. Make a new one on the other device.");
  }
  return saved;
}

async function quickCheck(event, input) {
  await signedInUser(event);
  const saved = await pendingQuick(input.code);
  return { device: saved.device, created: saved.created };
}

async function quickApprove(event, input) {
  const user = await signedInUser(event);
  const saved = await pendingQuick(input.code);
  if (input.approve === false) {
    await updateDoc("QuickLogin", saved.id, { status: "denied" });
    return { status: "denied" };
  }
  await updateDoc("QuickLogin", saved.id, { status: "approved", email: user.email, approved_at: iso() });
  return { status: "approved", device: saved.device };
}

// ---- admins ---------------------------------------------------------------

async function adminDelete(event, input) {
  const admin = await signedInUser(event);
  if (!(await isAdmin(admin))) throw new Problem(403, "Only admins can delete accounts.");
  const email = cleanEmail(input.email);
  if (!email.includes("@")) throw new Problem(400, "Pick someone to delete.");
  if (email === admin.email) throw new Problem(400, "Delete your own account from Settings instead.");
  if (OWNERS.includes(email)) throw new Problem(403, "The site owner's account can't be deleted.");
  const account = await findAccount(email);
  const profile = account ? await getDoc("User", account.uid) : await findOne("User", "email", email);
  if (profile?.role === "admin" && !OWNERS.includes(admin.email)) throw new Problem(403, "Only the site owner can delete an admin.");

  // Everything they made, the same as when someone deletes their own account.
  let removed = 0;
  const wipe = async (collection, field, value, op = "EQUAL") => {
    for (let round = 0; round < 20; round += 1) {
      const rows = await findMany(collection, [[field, op, value]], 300);
      if (!rows.length) return;
      await commit(rows.map((r) => ({ delete: docName(collection, r.id) })));
      removed += rows.length;
      if (rows.length < 300) return;
    }
  };
  for (const collection of ["CommunityPost", "MusicReview", "Reel", "CommunityComment", "Comment", "ChannelMessage", "ServerMember", "DirectMessage"]) {
    await wipe(collection, "user_email", email);
  }
  await wipe("Artwork", "created_by", email);
  await wipe("Commission", "artist_email", email);
  await wipe("CommunityComment", "post_id", `profile_${email}`);
  await wipe("Friendship", "requester_email", email);
  await wipe("Friendship", "receiver_email", email);
  await wipe("Notification", "to_email", email);
  await wipe("SupportMessage", "ticket_id", email);
  for (const server of await findMany("Community", [["member_emails", "ARRAY_CONTAINS", email]], 300)) {
    if (cleanEmail(server.owner_email) === email) {
      await deleteDoc("Community", server.id);
    } else {
      await commit([removeFromList("Community", server.id, "member_emails", email)]);
    }
  }
  const uid = account?.uid || profile?.id;
  for (const [collection, id] of [["SupportTicket", email], ["PushToken", email], ["LoginCode", emailKey(email)],
    ["PayoutInfo", uid], ["AccountSecurity", uid], ["User", uid]]) {
    if (id) await deleteDoc(collection, id).catch(() => null);
  }
  if (account) await deleteAccount(account.uid);
  await addDoc("Log", { action: "account_delete", details: `${email} (${removed} items)`, user_email: admin.email, created_date: iso() }).catch(() => null);
  return { deleted: true, removed, login: Boolean(account) };
}

export const handler = (event) => handle(event, async () => {
  if (event.httpMethod !== "POST") throw new Problem(405, "Use POST.");
  const input = body(event);
  switch (input.action) {
    case "code-send": return codeSend(input);
    case "code-verify": return codeVerify(input);
    case "backup-create": return backupCreate(event);
    case "backup-status": return backupStatus(event);
    case "backup-login": return backupLogin(input);
    case "quick-start": return quickStart(input);
    case "quick-status": return quickStatus(input);
    case "quick-check": return quickCheck(event, input);
    case "quick-approve": return quickApprove(event, input);
    case "admin-delete": return adminDelete(event, input);
    default: throw new Problem(400, "Unknown action.");
  }
}, "login server");
