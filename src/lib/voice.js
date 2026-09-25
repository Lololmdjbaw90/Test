// Discord-style voice channels.
// -----------------------------------------------------------------------------
// Real microphone capture, voice-activity ("speaking") detection, mute/deafen,
// and a WebRTC mesh between everyone in the channel.
//
// Signalling goes through two backend collections, so it works everywhere the
// data layer works:
//   VoicePresence  one doc per connected peer (who's in which channel, muted…)
//   VoiceSignal    offer / answer / ICE messages addressed to a single peer
// With Firebase this connects people on different devices; in local demo mode
// it connects tabs of the same browser.
//
// Peers connect directly using STUN. Very strict networks may also need a TURN
// server: set VITE_TURN_URL / VITE_TURN_USERNAME / VITE_TURN_CREDENTIAL.
//
//   voice.subscribe(fn) -> unsubscribe; fn(state) on every change
//   voice.getState(), voice.join(channel, user), voice.leave()
//   voice.toggleMute(), voice.toggleDeafen()
//
// state = { channelId, channelName, connecting, connected, muted, deafened,
//           micError, participants: [{ peerId, self, user, muted, deafened, speaking }] }
// -----------------------------------------------------------------------------
import { base44 } from "@/api/base44Client";

const hasWindow = typeof window !== "undefined";
const hasRTC = hasWindow && typeof window.RTCPeerConnection !== "undefined";
const HEARTBEAT_MS = 10000;
export const VOICE_STALE_MS = 35000;

function iceServers() {
  const servers = [{ urls: ["stun:stun.l.google.com:19302", "stun:stun1.l.google.com:19302"] }];
  const turn = import.meta.env?.VITE_TURN_URL;
  if (turn) servers.push({ urls: turn, username: import.meta.env.VITE_TURN_USERNAME, credential: import.meta.env.VITE_TURN_CREDENTIAL });
  return servers;
}

function rid() {
  if (hasWindow && window.crypto?.randomUUID) return window.crypto.randomUUID();
  return "p_" + Math.random().toString(36).slice(2, 11);
}

const state = { channelId: null, channelName: "", connecting: false, connected: false, muted: false, deafened: false, micError: false };
const listeners = new Set();

// ---- per-session state ----
let selfId = null;
let selfUser = null;
let selfEmail = null;
let communityId = null;
let presenceId = null;
let localStream = null;
let audioCtx = null;
let selfSpeaking = false;
let heartbeat = null;
let unsubPresence = null;
let unsubSignals = null;
const vadLoops = new Set();
const peers = new Map(); // peerId -> { peerId, user, email, muted, deafened, speaking, pc, audioEl, lastSeen, pendingIce }

function snapshot() {
  const self = { peerId: selfId, self: true, user: selfUser, muted: state.muted, deafened: state.deafened, speaking: selfSpeaking && !state.muted };
  const others = [...peers.values()].filter((p) => p.user).map((p) => ({ peerId: p.peerId, self: false, user: p.user, muted: !!p.muted, deafened: !!p.deafened, speaking: !!p.speaking && !p.muted }));
  return { ...state, participants: state.connected ? [self, ...others] : [] };
}
function notify() { const s = snapshot(); listeners.forEach((fn) => { try { fn(s); } catch (e) { console.error(e); } }); }

// ---------- audio: microphone + voice activity ----------
function ensureAudioContext() {
  const AC = hasWindow && (window.AudioContext || window.webkitAudioContext);
  if (!AC) return null;
  if (!audioCtx) audioCtx = new AC();
  if (audioCtx.state === "suspended") audioCtx.resume().catch(() => {});
  return audioCtx;
}

// Calls onChange(true/false) when the stream starts/stops carrying speech.
function watchSpeaking(stream, onChange) {
  const ctx = ensureAudioContext();
  if (!ctx || !stream) return;
  try {
    const analyser = ctx.createAnalyser();
    analyser.fftSize = 512;
    ctx.createMediaStreamSource(stream).connect(analyser);
    const data = new Uint8Array(analyser.frequencyBinCount);
    let hangover = 0;
    let speaking = false;
    const loop = { active: true };
    vadLoops.add(loop);
    const tick = () => {
      if (!loop.active) return;
      analyser.getByteFrequencyData(data);
      let sum = 0;
      for (let i = 0; i < data.length; i++) sum += data[i];
      if (sum / data.length > 16) hangover = 12; else if (hangover > 0) hangover--;
      const now = hangover > 0;
      if (now !== speaking) { speaking = now; onChange(now); }
      requestAnimationFrame(tick);
    };
    tick();
  } catch (e) { console.warn("[voice] speaking detection unavailable:", e); }
}

async function startMic() {
  try {
    localStream = await navigator.mediaDevices.getUserMedia({ audio: { echoCancellation: true, noiseSuppression: true, autoGainControl: true }, video: false });
    state.micError = false;
    watchSpeaking(localStream, (on) => { selfSpeaking = on && !state.muted; notify(); });
  } catch (e) {
    console.warn("[voice] mic unavailable:", e?.message);
    localStream = null;
    state.micError = true;
    state.muted = true;
  }
}

// ---------- signalling ----------
const Presence = () => base44.entities.VoicePresence;
const Signal = () => base44.entities.VoiceSignal;

function sendSignal(peer, kind, payload) {
  if (!state.connected && !state.connecting) return;
  Signal().create({
    channel_id: state.channelId, community_id: communityId, from_peer: selfId, to_peer: peer.peerId,
    to_email: peer.email, user_email: selfEmail, kind, payload: JSON.stringify(payload),
  }).catch((e) => console.warn("[voice] signal failed:", e?.message));
}

function pushPresence(extra = {}) {
  if (!presenceId) return;
  Presence().update(presenceId, { muted: state.muted, deafened: state.deafened, last_active: Date.now(), ...extra }).catch(() => {});
}

// ---------- WebRTC mesh ----------
function ensurePeer(peerId, user, email) {
  let p = peers.get(peerId);
  if (!p) { p = { peerId, user: null, email: null, muted: false, deafened: false, speaking: false, pc: null, audioEl: null, lastSeen: Date.now(), pendingIce: [] }; peers.set(peerId, p); }
  if (user) p.user = user;
  if (email) p.email = email;
  p.lastSeen = Date.now();
  return p;
}

function createConnection(peer, initiator) {
  if (!hasRTC) return null;
  if (peer.pc) return peer.pc;
  const pc = new RTCPeerConnection({ iceServers: iceServers() });
  peer.pc = pc;
  if (localStream) localStream.getTracks().forEach((t) => pc.addTrack(t, localStream));
  else pc.addTransceiver("audio", { direction: "recvonly" }); // listen-only when there's no mic
  pc.onicecandidate = (e) => { if (e.candidate) sendSignal(peer, "ice", e.candidate.toJSON()); };
  pc.ontrack = (e) => {
    const stream = e.streams[0] || new MediaStream([e.track]);
    let el = peer.audioEl;
    if (!el) {
      el = document.createElement("audio");
      el.autoplay = true;
      el.dataset.voicePeer = peer.peerId;
      el.style.display = "none";
      document.body.appendChild(el);
      peer.audioEl = el;
    }
    el.srcObject = stream;
    el.muted = state.deafened;
    el.play?.().catch(() => {});
    watchSpeaking(stream, (on) => { peer.speaking = on; notify(); });
  };
  pc.onconnectionstatechange = () => {
    if (pc.connectionState === "failed") { try { pc.restartIce?.(); } catch { /* ignore */ } }
  };
  if (initiator) {
    pc.onnegotiationneeded = async () => {
      try {
        await pc.setLocalDescription(await pc.createOffer());
        sendSignal(peer, "offer", pc.localDescription.toJSON());
      } catch (e) { console.warn("[voice] offer failed:", e); }
    };
  }
  return pc;
}

async function flushIce(peer) {
  const queued = peer.pendingIce.splice(0);
  for (const c of queued) { try { await peer.pc.addIceCandidate(c); } catch { /* ignore */ } }
}

function removePeer(peerId) {
  const p = peers.get(peerId);
  if (!p) return;
  try { p.pc?.close(); } catch { /* ignore */ }
  if (p.audioEl) { try { p.audioEl.srcObject = null; p.audioEl.remove(); } catch { /* ignore */ } }
  peers.delete(peerId);
}

function handlePresence(event) {
  const d = event.data;
  if (!d || d.channel_id !== state.channelId || d.peer_id === selfId) return;
  if (event.type === "delete") { removePeer(d.peer_id); notify(); return; }
  if (Date.now() - (d.last_active || 0) > VOICE_STALE_MS) {
    // Leftover from a crashed tab: clean it up (rules allow deleting stale presence).
    Presence().delete(event.id || d.id).catch(() => {});
    return;
  }
  const p = ensurePeer(d.peer_id, d.user, d.user_email);
  p.muted = !!d.muted;
  p.deafened = !!d.deafened;
  if (!p.pc && selfId < d.peer_id) createConnection(p, true); // lower id makes the offer
  notify();
}

async function handleSignal(event) {
  const d = event.data;
  if (event.type !== "create" || !d || d.to_peer !== selfId || d.channel_id !== state.channelId) return;
  Signal().delete(event.id || d.id).catch(() => {});
  const peer = ensurePeer(d.from_peer, null, d.user_email);
  let payload;
  try { payload = JSON.parse(d.payload); } catch { return; }
  try {
    if (d.kind === "offer") {
      const pc = createConnection(peer, false);
      if (!pc) return;
      await pc.setRemoteDescription(payload);
      await pc.setLocalDescription(await pc.createAnswer());
      sendSignal(peer, "answer", pc.localDescription.toJSON());
      await flushIce(peer);
    } else if (d.kind === "answer" && peer.pc) {
      await peer.pc.setRemoteDescription(payload);
      await flushIce(peer);
    } else if (d.kind === "ice") {
      if (peer.pc?.remoteDescription) await peer.pc.addIceCandidate(payload).catch(() => {});
      else peer.pendingIce.push(payload);
    }
  } catch (e) { console.warn(`[voice] ${d.kind} failed:`, e); }
}

function startHeartbeat() {
  stopHeartbeat();
  heartbeat = setInterval(() => {
    pushPresence();
    const now = Date.now();
    let changed = false;
    for (const [id, p] of peers) { if (now - p.lastSeen > VOICE_STALE_MS) { removePeer(id); changed = true; } }
    if (changed) notify();
  }, HEARTBEAT_MS);
}
function stopHeartbeat() { if (heartbeat) { clearInterval(heartbeat); heartbeat = null; } }

// ---------- public API ----------
async function join(channel, user) {
  if (state.connected || state.connecting) await leave();
  state.channelId = channel?.id;
  state.channelName = channel?.name || "Voice";
  state.connecting = true;
  state.muted = false;
  state.deafened = false;
  communityId = channel?.community_id || "";
  selfId = rid();
  selfEmail = user?.email || "";
  selfUser = { display_name: user?.display_name || user?.full_name || "You", profile_picture: user?.profile_picture || "", email: selfEmail };
  selfSpeaking = false;
  notify();

  await startMic();
  try {
    unsubSignals = Signal().subscribe(handleSignal, { channel_id: state.channelId, to_peer: selfId, to_email: selfEmail });
    const doc = await Presence().create({
      channel_id: state.channelId, community_id: communityId, peer_id: selfId, user_email: selfEmail,
      user: selfUser, muted: state.muted, deafened: state.deafened, last_active: Date.now(),
    });
    presenceId = doc.id;
    state.connecting = false;
    state.connected = true;
    unsubPresence = Presence().subscribe(handlePresence, { channel_id: state.channelId });
    const existing = await Presence().filter({ channel_id: state.channelId }).catch(() => []);
    existing.forEach((d) => handlePresence({ type: "create", id: d.id, data: d }));
    startHeartbeat();
  } catch (e) {
    console.warn("[voice] could not join:", e?.message);
    await leave();
    return;
  }
  notify();
}

async function leave() {
  const id = presenceId;
  presenceId = null;
  stopHeartbeat();
  unsubPresence?.(); unsubPresence = null;
  unsubSignals?.(); unsubSignals = null;
  vadLoops.forEach((l) => { l.active = false; });
  vadLoops.clear();
  for (const peerId of [...peers.keys()]) removePeer(peerId);
  if (localStream) { localStream.getTracks().forEach((t) => { try { t.stop(); } catch { /* ignore */ } }); localStream = null; }
  if (audioCtx) { try { await audioCtx.close(); } catch { /* ignore */ } audioCtx = null; }
  Object.assign(state, { connected: false, connecting: false, channelId: null, channelName: "", muted: false, deafened: false, micError: false });
  selfId = null;
  selfUser = null;
  selfSpeaking = false;
  notify();
  if (id) await Presence().delete(id).catch(() => {});
}

function toggleMute() {
  if (state.micError) return;
  state.muted = !state.muted;
  localStream?.getAudioTracks().forEach((t) => { t.enabled = !state.muted; });
  if (state.muted) selfSpeaking = false;
  pushPresence();
  notify();
}

function toggleDeafen() {
  state.deafened = !state.deafened;
  // Deafening also mutes your own mic (like Discord).
  if (state.deafened && !state.muted && !state.micError) {
    state.muted = true;
    localStream?.getAudioTracks().forEach((t) => { t.enabled = false; });
    selfSpeaking = false;
  }
  for (const p of peers.values()) { if (p.audioEl) p.audioEl.muted = state.deafened; }
  pushPresence();
  notify();
}

function subscribe(fn) { listeners.add(fn); fn(snapshot()); return () => listeners.delete(fn); }
function getState() { return snapshot(); }

if (hasWindow) {
  // Best effort: drop our presence when the tab closes.
  window.addEventListener("pagehide", () => { if (presenceId) Presence().delete(presenceId).catch(() => {}); });
}

const voice = { subscribe, getState, join, leave, toggleMute, toggleDeafen };
export default voice;
