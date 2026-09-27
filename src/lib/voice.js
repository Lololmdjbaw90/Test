// Voice/video rooms: server voice channels and DM/group calls.
// -----------------------------------------------------------------------------
// A WebRTC mesh between everyone in a room with microphone, camera and screen
// sharing, speaking detection, mute/deafen, per-person volume and device
// selection. The connection lives at app level, so it keeps going while you
// browse other pages (see <VoiceDock/>).
//
// Signalling goes through two backend collections so it works wherever the
// data layer works (cross-device with Firebase, cross-tab in local demo mode):
//   VoicePresence  one doc per connected peer (room, user, mute state, video)
//   VoiceSignal    SDP descriptions / ICE candidates addressed to one peer
// Negotiation follows the "perfect negotiation" pattern so either side can
// add/remove video at any time without offer collisions breaking the call.
//
// Peers connect directly using STUN. Very strict networks may also need a TURN
// server: set VITE_TURN_URL / VITE_TURN_USERNAME / VITE_TURN_CREDENTIAL.
//
//   voice.subscribe(fn) / voice.getState() / voice.onLeave(fn)
//   voice.join(room, user, { video })   room = { id, name, type: "channel" | "call", communityId, link }
//   voice.leave(), voice.toggleMute(), voice.toggleDeafen()
//   voice.toggleCamera(), voice.toggleScreen(), voice.setPeerVolume(email, v)
//   voice.listDevices(), voice.useDevice(kind, deviceId), voice.setExpanded(bool)
// -----------------------------------------------------------------------------
import { base44 } from "@/api/base44Client";

const hasWindow = typeof window !== "undefined";
const hasRTC = hasWindow && typeof window.RTCPeerConnection !== "undefined";
const HEARTBEAT_MS = 10000;
export const VOICE_STALE_MS = 35000;
const VOLUME_KEY = "mimilocks:__peer_volume";
const DEVICE_KEY = "mimilocks:__devices";

function iceServers() {
  const servers = [{ urls: ["stun:stun.l.google.com:19302", "stun:stun1.l.google.com:19302"] }];
  const turn = import.meta.env?.VITE_TURN_URL;
  if (turn) servers.push({ urls: turn, username: import.meta.env.VITE_TURN_USERNAME, credential: import.meta.env.VITE_TURN_CREDENTIAL });
  return servers;
}
const rid = () => (hasWindow && window.crypto?.randomUUID ? window.crypto.randomUUID() : "p_" + Math.random().toString(36).slice(2, 11));
const readJSON = (key) => { try { return JSON.parse(localStorage.getItem(key) || "{}"); } catch { return {}; } };
const writeJSON = (key, v) => { try { localStorage.setItem(key, JSON.stringify(v)); } catch { /* ignore */ } };

// ---------- sounds ----------
let soundCtx = null;
export function playTone(kind) {
  try {
    const AC = window.AudioContext || window.webkitAudioContext;
    if (!AC) return;
    soundCtx = soundCtx || new AC();
    const notes = { join: [523, 784], leave: [659, 392], mute: [440], unmute: [660], ring: [880, 660, 880, 660] }[kind] || [600];
    notes.forEach((f, i) => {
      const t = soundCtx.currentTime + i * (kind === "ring" ? 0.18 : 0.09);
      const o = soundCtx.createOscillator();
      const g = soundCtx.createGain();
      o.type = "sine";
      o.frequency.value = f;
      g.gain.setValueAtTime(0, t);
      g.gain.linearRampToValueAtTime(kind === "ring" ? 0.12 : 0.08, t + 0.01);
      g.gain.exponentialRampToValueAtTime(0.0001, t + (kind === "ring" ? 0.16 : 0.12));
      o.connect(g).connect(soundCtx.destination);
      o.start(t);
      o.stop(t + 0.2);
    });
  } catch { /* sounds are best-effort */ }
}

// ---------- state ----------
const state = {
  room: null, connecting: false, connected: false, joinedAt: null,
  muted: false, deafened: false, micError: false, video: null, videoError: "", expanded: true,
  canSpeak: true, canVideo: true, // server roles can take these away in a voice channel
};
const listeners = new Set();
let selfId = null;
let selfUser = null;
let selfEmail = null;
let presenceId = null;
let micStream = null;
let videoStream = null; // camera or screen
let audioCtx = null;
let selfSpeaking = false;
let heartbeat = null;
let unsubPresence = null;
let unsubSignals = null;
const vadLoops = new Set();
let micVad = null;
const leaveHooks = new Set();
const peers = new Map(); // peerId -> peer record
let volumes = hasWindow ? readJSON(VOLUME_KEY) : {};

function snapshot() {
  const self = { peerId: selfId, self: true, user: selfUser, email: selfEmail, muted: state.muted, deafened: state.deafened, speaking: selfSpeaking && !state.muted, video: state.video, stream: videoStream };
  const others = [...peers.values()].filter((p) => p.user).map((p) => ({
    peerId: p.peerId, self: false, user: p.user, email: p.email, muted: !!p.muted, deafened: !!p.deafened,
    speaking: !!p.speaking && !p.muted, video: p.video || null, stream: p.stream, volume: volumes[p.email] ?? 1,
    connection: p.pc?.connectionState || "new",
  }));
  return { ...state, selfId, participants: state.connected ? [self, ...others] : [] };
}
function notify() { const s = snapshot(); listeners.forEach((fn) => { try { fn(s); } catch (e) { console.error(e); } }); }

// ---------- audio analysis ----------
function ensureAudioContext() {
  const AC = hasWindow && (window.AudioContext || window.webkitAudioContext);
  if (!AC) return null;
  if (!audioCtx) audioCtx = new AC();
  if (audioCtx.state === "suspended") audioCtx.resume().catch(() => {});
  return audioCtx;
}
function watchSpeaking(track, onChange) {
  const ctx = ensureAudioContext();
  if (!ctx || !track) return null;
  try {
    const analyser = ctx.createAnalyser();
    analyser.fftSize = 512;
    ctx.createMediaStreamSource(new MediaStream([track])).connect(analyser);
    const data = new Uint8Array(analyser.frequencyBinCount);
    let lastSample = 0;
    let hangover = 0;
    let speaking = false;
    const loop = { active: true };
    vadLoops.add(loop);
    const tick = (frameTime = 0) => {
      if (!loop.active) return;
      if (frameTime - lastSample < 80) { requestAnimationFrame(tick); return; }
      lastSample = frameTime;
      analyser.getByteFrequencyData(data);
      let sum = 0;
      for (let i = 0; i < data.length; i++) sum += data[i];
      if (sum / data.length > 16) hangover = 3; else if (hangover > 0) hangover--;
      const now = hangover > 0;
      if (now !== speaking) { speaking = now; onChange(now); }
      requestAnimationFrame(tick);
    };
    tick();
    return loop;
  } catch (e) { console.warn("[voice] speaking detection unavailable:", e); return null; }
}

// ---------- local media ----------
function deviceConstraint(kind) {
  const id = readJSON(DEVICE_KEY)[kind];
  return id ? { deviceId: { ideal: id } } : {};
}
async function startMic() {
  try {
    micStream = await navigator.mediaDevices.getUserMedia({ audio: { echoCancellation: true, noiseSuppression: true, autoGainControl: true, ...deviceConstraint("audioinput") }, video: false });
    state.micError = false;
    micVad = watchSpeaking(micStream.getAudioTracks()[0], (on) => { selfSpeaking = on && !state.muted; notify(); });
  } catch (e) {
    console.warn("[voice] mic unavailable:", e?.message);
    micStream = null;
    state.micError = true;
    state.muted = true;
  }
}
function localVideoTrack() { return videoStream?.getVideoTracks()[0] || null; }

// Put the current video track (or nothing) on every peer connection.
function syncVideoSenders() {
  const track = localVideoTrack();
  for (const p of peers.values()) {
    if (!p.pc) continue;
    if (p.videoSender) p.videoSender.replaceTrack(track).catch(() => {});
    else if (track) p.videoSender = p.pc.addTrack(track, videoStream);
  }
}

// ---------- signalling ----------
const Presence = () => base44.entities.VoicePresence;
const Signal = () => base44.entities.VoiceSignal;

function sendSignal(peer, kind, payload) {
  if (!state.room) return;
  Signal().create({
    channel_id: state.room.id, community_id: state.room.communityId || "", from_peer: selfId, to_peer: peer.peerId,
    to_email: peer.email, user_email: selfEmail, kind, payload: JSON.stringify(payload),
  }).catch((e) => console.warn("[voice] signal failed:", e?.message));
}
function pushPresence(extra = {}) {
  if (!presenceId) return;
  Presence().update(presenceId, { muted: state.muted, deafened: state.deafened, video: state.video, last_active: Date.now(), ...extra }).catch(() => {});
}

// ---------- WebRTC mesh (perfect negotiation) ----------
function ensurePeer(peerId, user, email) {
  let p = peers.get(peerId);
  if (!p) {
    p = { peerId, user: null, email: null, muted: false, deafened: false, speaking: false, video: null, pc: null, audioEl: null, stream: null, videoSender: null, lastSeen: Date.now(), pendingIce: [], makingOffer: false, ignoreOffer: false, vad: null };
    peers.set(peerId, p);
  }
  if (user) p.user = user;
  if (email) p.email = email;
  p.lastSeen = Date.now();
  return p;
}

function createConnection(peer) {
  if (!hasRTC) return null;
  if (peer.pc) return peer.pc;
  const pc = new RTCPeerConnection({ iceServers: iceServers() });
  peer.pc = pc;
  peer.polite = selfId > peer.peerId;
  peer.stream = new MediaStream();
  if (micStream) micStream.getTracks().forEach((t) => pc.addTrack(t, micStream));
  else pc.addTransceiver("audio", { direction: "recvonly" });
  const vt = localVideoTrack();
  if (vt) peer.videoSender = pc.addTrack(vt, videoStream);

  pc.onicecandidate = (e) => { if (e.candidate) sendSignal(peer, "ice", e.candidate.toJSON()); };
  pc.onnegotiationneeded = async () => {
    try {
      peer.makingOffer = true;
      await pc.setLocalDescription();
      sendSignal(peer, "description", pc.localDescription.toJSON());
    } catch (e) { console.warn("[voice] negotiation failed:", e); }
    finally { peer.makingOffer = false; }
  };
  pc.ontrack = (e) => {
    const track = e.track;
    peer.stream.getTracks().filter((t) => t.kind === track.kind).forEach((t) => peer.stream.removeTrack(t));
    peer.stream.addTrack(track);
    peer.stream = new MediaStream(peer.stream.getTracks()); // new object so React sees the change
    if (track.kind === "audio") {
      let el = peer.audioEl;
      if (!el) {
        el = document.createElement("audio");
        el.autoplay = true;
        el.dataset.voicePeer = peer.peerId;
        el.style.display = "none";
        document.body.appendChild(el);
        peer.audioEl = el;
      }
      el.srcObject = new MediaStream([track]);
      el.muted = state.deafened;
      el.volume = Math.min(1, volumes[peer.email] ?? 1);
      el.play?.().catch(() => {});
      peer.vad && (peer.vad.active = false);
      peer.vad = watchSpeaking(track, (on) => { peer.speaking = on; notify(); });
    }
    track.onunmute = () => notify();
    notify();
  };
  pc.onconnectionstatechange = () => {
    if (pc.connectionState === "failed") { try { pc.restartIce?.(); } catch { /* ignore */ } }
    notify();
  };
  return pc;
}

async function flushIce(peer) {
  for (const c of peer.pendingIce.splice(0)) { try { await peer.pc.addIceCandidate(c); } catch { /* ignore */ } }
}

function removePeer(peerId) {
  const p = peers.get(peerId);
  if (!p) return;
  try { p.pc?.close(); } catch { /* ignore */ }
  if (p.vad) p.vad.active = false;
  if (p.audioEl) { try { p.audioEl.srcObject = null; p.audioEl.remove(); } catch { /* ignore */ } }
  peers.delete(peerId);
}

function handlePresence(event) {
  const d = event.data;
  if (!d || !state.room || d.channel_id !== state.room.id || d.peer_id === selfId) return;
  if (event.type === "delete") {
    if (peers.has(d.peer_id)) { removePeer(d.peer_id); playTone("leave"); notify(); }
    return;
  }
  if (Date.now() - (d.last_active || 0) > VOICE_STALE_MS) {
    Presence().delete(event.id || d.id).catch(() => {}); // leftover from a crashed tab
    return;
  }
  const isNew = !peers.get(d.peer_id)?.user;
  const p = ensurePeer(d.peer_id, d.user, d.user_email);
  p.muted = !!d.muted;
  p.deafened = !!d.deafened;
  p.video = d.video || null;
  if (!p.pc && selfId < d.peer_id) createConnection(p); // the lower id starts the connection
  if (isNew && event.type === "create" && !event.initial && !event.existing) playTone("join");
  notify();
}

function handleSignal(event) {
  const d = event.data;
  if (event.type !== "create" || !d || !state.room || d.to_peer !== selfId || d.channel_id !== state.room.id) return;
  const peer = ensurePeer(d.from_peer, null, d.user_email);
  peer.signals = (peer.signals || Promise.resolve()).then(() => processSignal(event)).catch(e => console.warn("[voice] signal:", e));
}
async function processSignal(event) {
  const d = event.data;
  if (event.type !== "create" || !d || !state.room || d.to_peer !== selfId || d.channel_id !== state.room.id) return;
  Signal().delete(event.id || d.id).catch(() => {});
  const peer = ensurePeer(d.from_peer, null, d.user_email);
  let payload;
  try { payload = JSON.parse(d.payload); } catch { return; }
  const pc = createConnection(peer);
  if (!pc) return;
  try {
    if (d.kind === "description") {
      const collision = payload.type === "offer" && (peer.makingOffer || pc.signalingState !== "stable");
      peer.ignoreOffer = !peer.polite && collision;
      if (peer.ignoreOffer) return;
      await pc.setRemoteDescription(payload);
      if (payload.type === "offer") {
        await pc.setLocalDescription();
        sendSignal(peer, "description", pc.localDescription.toJSON());
      }
      await flushIce(peer);
    } else if (d.kind === "ice") {
      if (pc.remoteDescription) await pc.addIceCandidate(payload).catch((e) => { if (!peer.ignoreOffer) console.warn("[voice] ice failed:", e?.message); });
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
async function join(room, user, { video = false, canSpeak = true, canVideo = true } = {}) {
  if (state.connected || state.connecting) await leave({ silent: true });
  Object.assign(state, { room, connecting: true, muted: !canSpeak, deafened: false, video: null, videoError: "", expanded: true, canSpeak, canVideo });
  selfId = rid();
  selfEmail = user?.email || "";
  selfUser = { display_name: user?.display_name || user?.full_name || "You", profile_picture: user?.profile_picture || "", email: selfEmail };
  selfSpeaking = false;
  notify();

  await startMic();
  if (!canSpeak) micStream?.getAudioTracks().forEach((t) => { t.enabled = false; });
  if (video && canVideo) await startVideo("camera");
  try {
    unsubSignals = Signal().subscribe(handleSignal, { channel_id: room.id, to_peer: selfId, to_email: selfEmail });
    const doc = await Presence().create({
      channel_id: room.id, community_id: room.communityId || "", room_type: room.type || "channel", peer_id: selfId, user_email: selfEmail,
      user: selfUser, muted: state.muted, deafened: state.deafened, video: state.video, last_active: Date.now(),
    });
    presenceId = doc.id;
    Object.assign(state, { connecting: false, connected: true, joinedAt: Date.now() });
    unsubPresence = Presence().subscribe(handlePresence, { channel_id: room.id });
    const existing = await Presence().filter({ channel_id: room.id }).catch(() => []);
    existing.forEach((d) => handlePresence({ type: "create", id: d.id, data: d, existing: true }));
    startHeartbeat();
    playTone("join");
  } catch (e) {
    console.warn("[voice] could not join:", e?.message);
    await leave({ silent: true });
    return false;
  }
  notify();
  return true;
}

async function leave({ silent = false } = {}) {
  const id = presenceId;
  const wasConnected = state.connected;
  const info = { room: state.room, joinedAt: state.joinedAt, user: selfUser, others: [...peers.values()].filter((p) => p.user).length };
  presenceId = null;
  stopHeartbeat();
  unsubPresence?.(); unsubPresence = null;
  unsubSignals?.(); unsubSignals = null;
  vadLoops.forEach((l) => { l.active = false; });
  vadLoops.clear();
  micVad = null;
  for (const peerId of [...peers.keys()]) removePeer(peerId);
  micStream?.getTracks().forEach((t) => { try { t.stop(); } catch { /* ignore */ } });
  videoStream?.getTracks().forEach((t) => { try { t.stop(); } catch { /* ignore */ } });
  micStream = null;
  videoStream = null;
  if (audioCtx) { try { await audioCtx.close(); } catch { /* ignore */ } audioCtx = null; }
  Object.assign(state, { room: null, connected: false, connecting: false, joinedAt: null, muted: false, deafened: false, micError: false, video: null, videoError: "", expanded: true, canSpeak: true, canVideo: true });
  selfId = null;
  selfUser = null;
  selfSpeaking = false;
  notify();
  if (wasConnected && !silent) playTone("leave");
  if (id) await Presence().delete(id).catch(() => {});
  if (wasConnected && info.room) leaveHooks.forEach((fn) => { try { fn(info); } catch (e) { console.error(e); } });
}

async function startVideo(kind) {
  if (!state.canVideo) return;
  try {
    const stream = kind === "screen"
      ? await navigator.mediaDevices.getDisplayMedia({ video: { frameRate: 15 }, audio: false })
      : await navigator.mediaDevices.getUserMedia({ video: { width: { ideal: 1280 }, height: { ideal: 720 }, ...deviceConstraint("videoinput") }, audio: false });
    videoStream?.getTracks().forEach((t) => t.stop());
    videoStream = stream;
    state.video = kind;
    state.videoError = "";
    // Browser "Stop sharing" button ends the track.
    stream.getVideoTracks()[0].onended = () => { if (videoStream === stream) stopVideo(); };
    syncVideoSenders();
    pushPresence();
  } catch (e) {
    state.videoError = kind === "screen" ? "Screen sharing was cancelled or isn't supported here." : "Camera unavailable — check permissions.";
    console.warn(`[voice] ${kind} unavailable:`, e?.message);
  }
  notify();
}
function stopVideo() {
  videoStream?.getTracks().forEach((t) => t.stop());
  videoStream = null;
  state.video = null;
  syncVideoSenders();
  pushPresence();
  notify();
}
const toggleCamera = () => (state.video === "camera" ? stopVideo() : startVideo("camera"));
const toggleScreen = () => (state.video === "screen" ? stopVideo() : startVideo("screen"));

function toggleMute() {
  if (state.micError || (!state.canSpeak && state.muted)) return;
  state.muted = !state.muted;
  micStream?.getAudioTracks().forEach((t) => { t.enabled = !state.muted; });
  if (state.muted) selfSpeaking = false;
  playTone(state.muted ? "mute" : "unmute");
  pushPresence();
  notify();
}
function toggleDeafen() {
  state.deafened = !state.deafened;
  if (state.deafened && !state.muted && !state.micError) {
    state.muted = true;
    micStream?.getAudioTracks().forEach((t) => { t.enabled = false; });
    selfSpeaking = false;
  }
  for (const p of peers.values()) { if (p.audioEl) p.audioEl.muted = state.deafened; }
  playTone(state.deafened ? "mute" : "unmute");
  pushPresence();
  notify();
}
function setPeerVolume(email, v) {
  volumes = { ...volumes, [email]: v };
  writeJSON(VOLUME_KEY, volumes);
  for (const p of peers.values()) { if (p.email === email && p.audioEl) p.audioEl.volume = Math.min(1, v); }
  notify();
}
async function listDevices() {
  try {
    const devices = await navigator.mediaDevices.enumerateDevices();
    const chosen = readJSON(DEVICE_KEY);
    return {
      audioinput: devices.filter((d) => d.kind === "audioinput"),
      videoinput: devices.filter((d) => d.kind === "videoinput"),
      chosen,
    };
  } catch { return { audioinput: [], videoinput: [], chosen: {} }; }
}
async function useDevice(kind, deviceId) {
  writeJSON(DEVICE_KEY, { ...readJSON(DEVICE_KEY), [kind]: deviceId });
  if (!state.connected) return;
  if (kind === "audioinput") {
    try {
      const next = await navigator.mediaDevices.getUserMedia({ audio: { deviceId: { exact: deviceId }, echoCancellation: true, noiseSuppression: true }, video: false });
      const track = next.getAudioTracks()[0];
      track.enabled = !state.muted;
      for (const p of peers.values()) {
        const sender = p.pc?.getSenders().find((s) => s.track?.kind === "audio");
        sender?.replaceTrack(track).catch(() => {});
      }
      micStream?.getTracks().forEach((t) => t.stop());
      micStream = next;
      if (micVad) micVad.active = false;
      micVad = watchSpeaking(track, (on) => { selfSpeaking = on && !state.muted; notify(); });
    } catch (e) { console.warn("[voice] could not switch mic:", e?.message); }
  } else if (kind === "videoinput" && state.video === "camera") {
    await startVideo("camera");
  }
  notify();
}
function setExpanded(v) { state.expanded = v; notify(); }

function subscribe(fn) { listeners.add(fn); fn(snapshot()); return () => listeners.delete(fn); }
// Called after leaving a room with { room, joinedAt, user, others } (others = peers still connected).
function onLeave(fn) { leaveHooks.add(fn); return () => leaveHooks.delete(fn); }
function getState() { return snapshot(); }

if (hasWindow) {
  // Best effort: drop our presence when the tab closes.
  window.addEventListener("pagehide", () => { if (presenceId) Presence().delete(presenceId).catch(() => {}); });
}

const canShareScreen = hasWindow && !!navigator.mediaDevices?.getDisplayMedia && !/Android|iPhone|iPad/i.test(navigator.userAgent);

const voice = { subscribe, onLeave, getState, canShareScreen, join, leave, toggleMute, toggleDeafen, toggleCamera, toggleScreen, setPeerVolume, listDevices, useDevice, setExpanded };
export default voice;
