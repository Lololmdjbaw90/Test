// Local Discord-style voice channels.
// -----------------------------------------------------------------------------
// Provides real microphone capture, speaking (voice-activity) detection, and
// mute/deafen controls. Presence and WebRTC signalling travel over a
// BroadcastChannel, so multiple tabs of the SAME browser actually connect and
// hear each other — a genuine group call you can demo by opening two tabs.
//
// Connecting people across different devices/networks would require a small
// signalling server (and TURN); the WebRTC code here is written so that swapping
// the BroadcastChannel transport for a websocket is the only change needed.
//
//   voice.subscribe(fn)   -> unsubscribe;  fn(state) on every change
//   voice.getState()
//   voice.join(channel, user)
//   voice.leave()
//   voice.toggleMute()
//   voice.toggleDeafen()
//
// state = { channelId, channelName, connecting, connected, muted, deafened,
//           micError, participants: [{ peerId, self, user, muted, deafened, speaking }] }
// -----------------------------------------------------------------------------

const hasWindow = typeof window !== "undefined";
const hasBC = hasWindow && typeof window.BroadcastChannel !== "undefined";
const hasRTC = hasWindow && typeof window.RTCPeerConnection !== "undefined";
const CHAN = "mimilocks-voice";
const ICE = [{ urls: "stun:stun.l.google.com:19302" }];

function rid() {
  if (hasWindow && window.crypto && window.crypto.randomUUID) return window.crypto.randomUUID();
  return "p_" + Math.random().toString(36).slice(2, 11);
}

const state = {
  channelId: null,
  channelName: "",
  connecting: false,
  connected: false,
  muted: false,
  deafened: false,
  micError: false,
  participants: [],
};

const listeners = new Set();
function snapshot() {
  // self first, then others by join time
  const self = { peerId: selfId, self: true, user: selfUser, muted: state.muted, deafened: state.deafened, speaking: selfSpeaking && !state.muted };
  const others = [...peers.values()].map((p) => ({ peerId: p.peerId, self: false, user: p.user, muted: !!p.muted, deafened: !!p.deafened, speaking: !!p.speaking }));
  return { ...state, participants: state.connected ? [self, ...others] : [] };
}
function notify() { const s = snapshot(); listeners.forEach((fn) => { try { fn(s); } catch (e) { console.error(e); } }); }

// ---- per-session state ----
let bc = null;
let selfId = null;
let selfUser = null;
let localStream = null;
let audioCtx = null;
let selfSpeaking = false;
let heartbeat = null;
let vadRAF = null;
const peers = new Map();        // peerId -> { peerId, user, muted, deafened, speaking, pc, audioEl, lastSeen, analyser }

function post(msg) { if (bc) { try { bc.postMessage(msg); } catch { /* ignore */ } } }

// ---------- microphone + voice activity ----------
async function startMic() {
  try {
    localStream = await navigator.mediaDevices.getUserMedia({ audio: { echoCancellation: true, noiseSuppression: true }, video: false });
    state.micError = false;
    setupLocalVAD();
  } catch (e) {
    console.warn("[voice] mic unavailable:", e && e.message);
    localStream = null;
    state.micError = true;
    state.muted = true; // nothing to send
  }
}

function setupLocalVAD() {
  try {
    const AC = window.AudioContext || window.webkitAudioContext;
    if (!AC || !localStream) return;
    audioCtx = new AC();
    const src = audioCtx.createMediaStreamSource(localStream);
    const analyser = audioCtx.createAnalyser();
    analyser.fftSize = 512;
    src.connect(analyser);
    const data = new Uint8Array(analyser.frequencyBinCount);
    let hangover = 0;
    const tick = () => {
      if (!audioCtx) return;
      analyser.getByteFrequencyData(data);
      let sum = 0;
      for (let i = 0; i < data.length; i++) sum += data[i];
      const avg = sum / data.length;
      const talking = !state.muted && avg > 16;
      if (talking) hangover = 12; else if (hangover > 0) hangover--;
      const speakingNow = hangover > 0;
      if (speakingNow !== selfSpeaking) {
        selfSpeaking = speakingNow;
        post({ kind: "state", channelId: state.channelId, peerId: selfId, user: selfUser, muted: state.muted, deafened: state.deafened, speaking: selfSpeaking });
        notify();
      }
      vadRAF = requestAnimationFrame(tick);
    };
    tick();
  } catch (e) { console.warn("[voice] VAD setup failed:", e); }
}

// ---------- WebRTC mesh ----------
function ensurePeer(peerId, user) {
  let p = peers.get(peerId);
  if (!p) { p = { peerId, user: user || null, muted: false, deafened: false, speaking: false, pc: null, audioEl: null, lastSeen: Date.now() }; peers.set(peerId, p); }
  if (user) p.user = user;
  p.lastSeen = Date.now();
  return p;
}

function createConnection(peerId, initiator) {
  if (!hasRTC) return null;
  const p = ensurePeer(peerId);
  if (p.pc) return p.pc;
  const pc = new RTCPeerConnection({ iceServers: ICE });
  p.pc = pc;
  if (localStream) localStream.getTracks().forEach((t) => pc.addTrack(t, localStream));
  pc.onicecandidate = (e) => { if (e.candidate) post({ kind: "ice", channelId: state.channelId, from: selfId, to: peerId, payload: e.candidate }); };
  pc.ontrack = (e) => {
    let el = p.audioEl;
    if (!el) {
      el = document.createElement("audio");
      el.autoplay = true;
      el.dataset.voicePeer = peerId;
      el.style.display = "none";
      document.body.appendChild(el);
      p.audioEl = el;
    }
    el.srcObject = e.streams[0];
    el.muted = state.deafened;
    el.play && el.play().catch(() => {});
  };
  pc.onconnectionstatechange = () => {
    if (["failed", "closed", "disconnected"].includes(pc.connectionState)) { /* keep; heartbeat prunes */ }
  };
  if (initiator) {
    pc.onnegotiationneeded = async () => {
      try {
        const offer = await pc.createOffer();
        await pc.setLocalDescription(offer);
        post({ kind: "offer", channelId: state.channelId, from: selfId, to: peerId, payload: pc.localDescription });
      } catch (e) { console.warn("[voice] offer failed:", e); }
    };
  }
  return pc;
}

// lower id initiates, to avoid both sides offering at once
function shouldInitiate(otherId) { return selfId < otherId; }

function connectTo(peerId, user) {
  if (!hasRTC || peerId === selfId) return;
  ensurePeer(peerId, user);
  if (shouldInitiate(peerId)) createConnection(peerId, true);
}

async function handleMessage(msg) {
  if (!msg || msg.channelId !== state.channelId || !state.connected) return;
  if (msg.peerId === selfId || msg.from === selfId) return;

  if (msg.kind === "join") {
    const p = ensurePeer(msg.peerId, msg.user);
    p.muted = !!msg.muted; p.deafened = !!msg.deafened;
    // tell the newcomer we exist
    post({ kind: "state", channelId: state.channelId, peerId: selfId, user: selfUser, muted: state.muted, deafened: state.deafened, speaking: selfSpeaking });
    connectTo(msg.peerId, msg.user);
    notify();
  } else if (msg.kind === "state") {
    const p = ensurePeer(msg.peerId, msg.user);
    p.muted = !!msg.muted; p.deafened = !!msg.deafened; p.speaking = !!msg.speaking;
    connectTo(msg.peerId, msg.user);
    notify();
  } else if (msg.kind === "leave") {
    removePeer(msg.peerId);
    notify();
  } else if (msg.to === selfId && msg.kind === "offer") {
    const pc = createConnection(msg.from, false);
    if (!pc) return;
    try {
      await pc.setRemoteDescription(msg.payload);
      const answer = await pc.createAnswer();
      await pc.setLocalDescription(answer);
      post({ kind: "answer", channelId: state.channelId, from: selfId, to: msg.from, payload: pc.localDescription });
    } catch (e) { console.warn("[voice] answer failed:", e); }
  } else if (msg.to === selfId && msg.kind === "answer") {
    const p = peers.get(msg.from);
    if (p && p.pc) { try { await p.pc.setRemoteDescription(msg.payload); } catch (e) { console.warn("[voice] setRemote(answer) failed:", e); } }
  } else if (msg.to === selfId && msg.kind === "ice") {
    const p = peers.get(msg.from);
    if (p && p.pc) { try { await p.pc.addIceCandidate(msg.payload); } catch (e) { /* candidate may arrive early */ } }
  }
}

function removePeer(peerId) {
  const p = peers.get(peerId);
  if (!p) return;
  try { p.pc && p.pc.close(); } catch { /* ignore */ }
  if (p.audioEl) { try { p.audioEl.srcObject = null; p.audioEl.remove(); } catch { /* ignore */ } }
  peers.delete(peerId);
}

function startHeartbeat() {
  stopHeartbeat();
  heartbeat = setInterval(() => {
    post({ kind: "state", channelId: state.channelId, peerId: selfId, user: selfUser, muted: state.muted, deafened: state.deafened, speaking: selfSpeaking });
    const now = Date.now();
    let changed = false;
    for (const [id, p] of peers) { if (now - p.lastSeen > 8000) { removePeer(id); changed = true; } }
    if (changed) notify();
  }, 2500);
}
function stopHeartbeat() { if (heartbeat) { clearInterval(heartbeat); heartbeat = null; } }

// ---------- public API ----------
async function join(channel, user) {
  if (state.connected || state.connecting) await leave();
  state.channelId = channel && channel.id;
  state.channelName = (channel && channel.name) || "Voice";
  state.connecting = true;
  state.muted = false;
  state.deafened = false;
  selfId = rid();
  selfUser = user || { display_name: "You" };
  selfSpeaking = false;
  notify();

  await startMic();

  if (hasBC) {
    bc = new BroadcastChannel(CHAN);
    bc.onmessage = (e) => handleMessage(e.data);
  }
  state.connecting = false;
  state.connected = true;
  notify();

  // announce + start keepalive
  post({ kind: "join", channelId: state.channelId, peerId: selfId, user: selfUser, muted: state.muted, deafened: state.deafened });
  startHeartbeat();
}

async function leave() {
  if (!state.connected && !state.connecting) { resetSession(); return; }
  post({ kind: "leave", channelId: state.channelId, peerId: selfId });
  stopHeartbeat();
  if (vadRAF) { cancelAnimationFrame(vadRAF); vadRAF = null; }
  for (const id of [...peers.keys()]) removePeer(id);
  if (localStream) { localStream.getTracks().forEach((t) => { try { t.stop(); } catch { /* ignore */ } }); localStream = null; }
  if (audioCtx) { try { await audioCtx.close(); } catch { /* ignore */ } audioCtx = null; }
  if (bc) { try { bc.close(); } catch { /* ignore */ } bc = null; }
  resetSession();
  notify();
}

function resetSession() {
  state.connected = false;
  state.connecting = false;
  state.channelId = null;
  state.channelName = "";
  state.muted = false;
  state.deafened = false;
  state.micError = false;
  selfId = null;
  selfUser = null;
  selfSpeaking = false;
  peers.clear();
}

function toggleMute() {
  if (state.micError) return;
  state.muted = !state.muted;
  if (localStream) localStream.getAudioTracks().forEach((t) => { t.enabled = !state.muted; });
  if (state.muted) selfSpeaking = false;
  post({ kind: "state", channelId: state.channelId, peerId: selfId, user: selfUser, muted: state.muted, deafened: state.deafened, speaking: selfSpeaking });
  notify();
}

function toggleDeafen() {
  state.deafened = !state.deafened;
  // deafen also mutes your own mic (like Discord)
  if (state.deafened && !state.muted && !state.micError) {
    state.muted = true;
    if (localStream) localStream.getAudioTracks().forEach((t) => { t.enabled = false; });
    selfSpeaking = false;
  }
  for (const p of peers.values()) { if (p.audioEl) p.audioEl.muted = state.deafened; }
  post({ kind: "state", channelId: state.channelId, peerId: selfId, user: selfUser, muted: state.muted, deafened: state.deafened, speaking: selfSpeaking });
  notify();
}

function subscribe(fn) { listeners.add(fn); fn(snapshot()); return () => listeners.delete(fn); }
function getState() { return snapshot(); }

if (hasWindow) { window.addEventListener("beforeunload", () => { try { leave(); } catch { /* ignore */ } }); }

const voice = { subscribe, getState, join, leave, toggleMute, toggleDeafen };
export default voice;
