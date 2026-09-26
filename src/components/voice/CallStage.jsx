import React, { useEffect, useMemo, useRef, useState } from "react";
import { Link } from "react-router-dom";
import { motion } from "framer-motion";
import {
  AlertTriangle, Check, HeadphoneOff, Headphones, Loader2, MessageSquare, Mic, MicOff, MoreHorizontal, PhoneOff,
  Pin, PinOff, ScreenShare, ScreenShareOff, Settings2, UserRound, Video, VideoOff, Volume1, Volume2, VolumeX,
} from "lucide-react";
import voice from "@/lib/voice";
import { profileLink } from "@/lib/format";
import { useIsMobile } from "@/lib/useMediaQuery";
import Avatar from "@/components/common/Avatar";
import Popover from "@/components/common/Popover";

const nameOf = (p) => p.user?.display_name || p.email?.split("@")[0] || "Someone";
function tint(email = "") {
  let h = 0;
  for (let i = 0; i < email.length; i++) h = (h * 31 + email.charCodeAt(i)) % 360;
  return `hsl(${h} 70% 62% / 0.35)`;
}

function VideoView({ stream, mirror, contain }) {
  const ref = useRef(null);
  useEffect(() => {
    const el = ref.current;
    if (!el) return;
    if (el.srcObject !== stream) el.srcObject = stream || null;
    el.play?.().catch(() => {});
  }, [stream]);
  return <video ref={ref} autoPlay playsInline muted className={`absolute inset-0 w-full h-full ${contain ? "object-contain bg-black" : "object-cover"}`} style={mirror ? { transform: "scaleX(-1)" } : undefined} />;
}

function ParticipantMenu({ target, onClose, pinned, onPin }) {
  const p = target?.p;
  const anchorRef = useMemo(() => ({ current: target?.anchor || null }), [target]);
  const vol = Math.round((p?.volume ?? 1) * 100);
  return (
    <Popover open={!!target} onClose={onClose} anchorRef={anchorRef} placement="bottom-end" width={260} label="Participant options">
      {p && (
        <div className="p-3 space-y-3">
          <div className="flex items-center gap-2.5 px-1">
            <Avatar src={p.user?.profile_picture} name={nameOf(p)} size={36} />
            <div className="min-w-0">
              <p className="text-sm font-bold truncate" style={{ color: "var(--text-primary)" }}>{nameOf(p)}{p.self ? " (you)" : ""}</p>
              <p className="text-[11px]" style={{ color: "var(--text-muted)" }}>{p.muted ? "Muted" : p.speaking ? "Speaking" : "Connected"}{p.video ? ` · ${p.video === "screen" ? "Sharing screen" : "Camera on"}` : ""}</p>
            </div>
          </div>
          {!p.self && (
            <div className="rounded-2xl p-3" style={{ background: "var(--surface-2)" }}>
              <p className="text-xs font-bold mb-2 flex items-center justify-between" style={{ color: "var(--text-secondary)" }}>User volume <span className="tabular-nums">{vol}%</span></p>
              <div className="flex items-center gap-2" style={{ color: "var(--text-muted)" }}>
                {vol === 0 ? <VolumeX className="w-4 h-4" /> : <Volume1 className="w-4 h-4" />}
                <input type="range" min={0} max={100} step={5} value={vol} onChange={(e) => voice.setPeerVolume(p.email, Number(e.target.value) / 100)} className="range-call" aria-label={`Volume for ${nameOf(p)}`} />
                <Volume2 className="w-4 h-4" />
              </div>
            </div>
          )}
          <div className="grid gap-1">
            <button onClick={() => { onPin(pinned ? null : p.peerId); onClose(); }} className="flex items-center gap-2.5 px-2.5 py-2 rounded-xl text-sm font-semibold text-left transition-colors hover:bg-[var(--surface-2)]" style={{ color: "var(--text-primary)" }}>
              {pinned ? <PinOff className="w-4 h-4" /> : <Pin className="w-4 h-4" />} {pinned ? "Unpin" : "Pin to spotlight"}
            </button>
            {p.email && <Link to={profileLink(p.email)} onClick={onClose} className="flex items-center gap-2.5 px-2.5 py-2 rounded-xl text-sm font-semibold transition-colors hover:bg-[var(--surface-2)]" style={{ color: "var(--text-primary)" }}><UserRound className="w-4 h-4" /> View profile</Link>}
            {!p.self && p.email && <Link to={`/DirectMessages?with=${encodeURIComponent(p.email)}`} onClick={() => { voice.setExpanded(false); onClose(); }} className="flex items-center gap-2.5 px-2.5 py-2 rounded-xl text-sm font-semibold transition-colors hover:bg-[var(--surface-2)]" style={{ color: "var(--text-primary)" }}><MessageSquare className="w-4 h-4" /> Message</Link>}
          </div>
        </div>
      )}
    </Popover>
  );
}

function Tile({ p, size = "md", onMenu, className = "", style }) {
  const showVideo = !!p.video && !!p.stream?.getVideoTracks?.().length;
  const avatar = size === "lg" ? 120 : size === "sm" ? 44 : 84;
  const connecting = !p.self && p.connection && !["connected", "completed"].includes(p.connection);
  return (
    <motion.div
      initial={{ opacity: 0, scale: 0.94 }}
      animate={{ opacity: 1, scale: 1 }}
      transition={{ type: "spring", stiffness: 380, damping: 30 }}
      className={`call-tile group ${className}`}
      data-speaking={p.speaking}
      style={style}
    >
      {showVideo ? (
        <VideoView stream={p.stream} mirror={p.self && p.video === "camera"} contain={p.video === "screen"} />
      ) : (
        <div className="absolute inset-0 flex items-center justify-center">
          <div className="absolute inset-0" style={{ background: `radial-gradient(circle at 50% 45%, ${tint(p.email)}, transparent 70%)` }} />
          <Avatar src={p.user?.profile_picture} name={nameOf(p)} size={avatar} className="transition-shadow duration-150" style={{ boxShadow: p.speaking ? "0 0 0 4px #3ddc97, 0 0 30px rgb(61 220 151 / 0.45)" : "0 0 0 4px rgb(255 255 255 / 0.08)" }} />
        </div>
      )}
      <div className="absolute left-2 right-2 bottom-2 flex items-end gap-1.5">
        <span className="call-name">
          {p.muted ? <MicOff className="w-3 h-3 flex-shrink-0 text-[#ff8b8b]" /> : p.speaking ? <Mic className="w-3 h-3 flex-shrink-0 text-[#3ddc97]" /> : null}
          <span className="truncate">{nameOf(p)}{p.self ? " (you)" : ""}</span>
          {p.deafened && <HeadphoneOff className="w-3 h-3 flex-shrink-0 text-[#ff8b8b]" />}
        </span>
      </div>
      {(connecting || p.video === "screen") && (
        <span className="call-name absolute top-2 left-2">
          {connecting ? <><Loader2 className="w-3 h-3 animate-spin" /> Connecting</> : <><ScreenShare className="w-3 h-3" /> Screen</>}
        </span>
      )}
      {onMenu && (
        <button
          onClick={(e) => { e.stopPropagation(); onMenu(p, e.currentTarget); }}
          className="absolute top-2 right-2 w-8 h-8 rounded-full flex items-center justify-center text-white can-hover:opacity-0 group-hover:opacity-100 focus:opacity-100 transition-opacity"
          style={{ background: "rgb(0 0 0 / 0.45)" }}
          aria-label={`Options for ${nameOf(p)}`}
        >
          <MoreHorizontal className="w-4 h-4" />
        </button>
      )}
    </motion.div>
  );
}

function RingingTile({ person, size = "md", className = "", style }) {
  return (
    <div className={`call-tile ${className}`} style={style}>
      <div className="absolute inset-0 flex flex-col items-center justify-center gap-3">
        <span className="relative flex">
          <span className="ripple" /><span className="ripple" />
          <Avatar src={person.picture} name={person.name} size={size === "sm" ? 44 : 72} />
        </span>
        {size !== "sm" && <span className="text-xs font-semibold opacity-70">Ringing…</span>}
      </div>
      <div className="absolute left-2 bottom-2"><span className="call-name opacity-80"><span className="truncate">{person.name}</span></span></div>
    </div>
  );
}

function DeviceMenu({ open, onClose, anchorRef }) {
  const [devices, setDevices] = useState({ audioinput: [], videoinput: [], chosen: {} });
  useEffect(() => { if (open) voice.listDevices().then(setDevices); }, [open]);
  const pick = async (kind, id) => { await voice.useDevice(kind, id); setDevices(await voice.listDevices()); };
  const section = (kind, label, Icon) => (
    <div>
      <p className="eyebrow px-2 mb-1.5 flex items-center gap-1.5"><Icon className="w-3.5 h-3.5" /> {label}</p>
      {devices[kind].length === 0 ? (
        <p className="text-xs px-2 py-1.5" style={{ color: "var(--text-muted)" }}>No devices found</p>
      ) : devices[kind].map((d, i) => {
        const on = devices.chosen[kind] ? devices.chosen[kind] === d.deviceId : i === 0;
        return (
          <button key={d.deviceId || i} onClick={() => pick(kind, d.deviceId)} className="w-full flex items-center gap-2 px-2.5 py-2 rounded-xl text-sm text-left transition-colors hover:bg-[var(--surface-2)]" style={{ color: on ? "var(--accent-rose)" : "var(--text-primary)", fontWeight: on ? 700 : 500 }}>
            <span className="flex-1 truncate">{d.label || `${label} ${i + 1}`}</span>
            {on && <Check className="w-4 h-4 flex-shrink-0" />}
          </button>
        );
      })}
    </div>
  );
  return (
    <Popover open={open} onClose={onClose} anchorRef={anchorRef} placement="top-center" width={300} label="Audio & video settings">
      <div className="p-3 space-y-3">
        {section("audioinput", "Microphone", Mic)}
        <div className="divider" />
        {section("videoinput", "Camera", Video)}
      </div>
    </Popover>
  );
}

export function CallControls({ vs, onLeave, className = "", style }) {
  const [devices, setDevices] = useState(false);
  const devRef = useRef(null);
  const tip = (on, off, active) => (active ? on : off);
  return (
    <div className={`flex items-center justify-center gap-2 sm:gap-3 ${className}`} style={style}>
      <button className="call-btn" data-warn={vs.muted} disabled={vs.micError} onClick={voice.toggleMute} title={vs.micError ? "No microphone" : tip("Unmute", "Mute", vs.muted)} aria-label={tip("Unmute", "Mute", vs.muted)} aria-pressed={vs.muted}>
        {vs.muted ? <MicOff className="w-5 h-5" /> : <Mic className="w-5 h-5" />}
      </button>
      <button className="call-btn" data-warn={vs.deafened} onClick={voice.toggleDeafen} title={tip("Undeafen", "Deafen", vs.deafened)} aria-label={tip("Undeafen", "Deafen", vs.deafened)} aria-pressed={vs.deafened}>
        {vs.deafened ? <HeadphoneOff className="w-5 h-5" /> : <Headphones className="w-5 h-5" />}
      </button>
      <button className="call-btn" data-on={vs.video === "camera"} onClick={voice.toggleCamera} title={tip("Turn camera off", "Turn camera on", vs.video === "camera")} aria-label="Camera" aria-pressed={vs.video === "camera"}>
        {vs.video === "camera" ? <Video className="w-5 h-5" /> : <VideoOff className="w-5 h-5" />}
      </button>
      {voice.canShareScreen && (
        <button className="call-btn" data-on={vs.video === "screen"} onClick={voice.toggleScreen} title={tip("Stop sharing", "Share your screen", vs.video === "screen")} aria-label="Share screen" aria-pressed={vs.video === "screen"}>
          {vs.video === "screen" ? <ScreenShareOff className="w-5 h-5" /> : <ScreenShare className="w-5 h-5" />}
        </button>
      )}
      <button ref={devRef} className="call-btn hidden sm:inline-flex" onClick={() => setDevices((v) => !v)} title="Audio & video settings" aria-label="Audio and video settings"><Settings2 className="w-5 h-5" /></button>
      <button className="call-btn call-btn-danger" onClick={onLeave || (() => voice.leave())} title="Leave" aria-label="Leave call"><PhoneOff className="w-5 h-5" /></button>
      <DeviceMenu open={devices} onClose={() => setDevices(false)} anchorRef={devRef} />
    </div>
  );
}

// Everything visible inside a call: participant tiles (with spotlight for
// screen shares / pinned people), ringing placeholders and the control bar.
export default function CallStage({ vs, ringing = [], calling, onLeave, className = "", showControls = true, bare = false }) {
  const isMobile = useIsMobile();
  const [pinned, setPinned] = useState(null);
  const [menu, setMenu] = useState(null);
  const people = vs.participants;
  const alone = people.length <= 1;
  const spotlightId = people.length > 1 ? (people.some((p) => p.peerId === pinned) ? pinned : people.find((p) => p.video === "screen")?.peerId) : null;
  const openMenu = (p, anchor) => setMenu({ p, anchor });
  const self = people.find((p) => p.self);

  let body;
  if (!vs.connected) {
    body = (
      <div className="flex-1 flex flex-col items-center justify-center gap-3 opacity-80">
        {vs.connecting ? <Loader2 className="w-8 h-8 animate-spin" /> : <PhoneOff className="w-8 h-8" />}
        <p className="text-sm font-semibold">{vs.connecting ? "Connecting…" : "Call ended"}</p>
      </div>
    );
  } else if (alone && calling) {
    // Outgoing call nobody has picked up yet: phone-style "Calling…" screen.
    body = (
      <div className="flex-1 min-h-0 relative flex flex-col items-center justify-center gap-5 px-6 text-center">
        <div className="flex -space-x-6">
          {calling.people.slice(0, 3).map((person) => (
            <span key={person.email} className="relative flex rounded-full" style={{ boxShadow: "0 0 0 4px #140f17" }}>
              <span className="ripple" /><span className="ripple" /><span className="ripple" />
              <Avatar src={person.picture} name={person.name} size={calling.people.length > 1 ? 96 : 128} />
            </span>
          ))}
        </div>
        <div>
          <p className="font-display text-2xl font-semibold">{calling.title}</p>
          <p className="text-sm mt-1 opacity-70">{calling.status}</p>
        </div>
        {self?.video && (
          <div className="absolute right-4 bottom-4 w-28 sm:w-40 aspect-[3/4] sm:aspect-video rounded-2xl overflow-hidden" style={{ boxShadow: "0 12px 30px rgb(0 0 0 / 0.4)" }}>
            <VideoView stream={self.stream} mirror={self.video === "camera"} contain={self.video === "screen"} />
          </div>
        )}
      </div>
    );
  } else if (people.length === 2 && !spotlightId && !ringing.length && people.some((p) => p.video)) {
    // One-on-one video: the other person fills the stage, you float in a corner.
    const other = people.find((p) => !p.self) || people[1];
    body = (
      <div className="flex-1 min-h-0 relative p-3">
        <Tile p={other} size="lg" onMenu={openMenu} className="w-full h-full" />
        <motion.div drag dragMomentum={false} dragElastic={0.1} className="absolute right-6 bottom-6 w-28 sm:w-52 aspect-[3/4] sm:aspect-video cursor-grab active:cursor-grabbing z-10" style={{ touchAction: "none" }}>
          <Tile p={self} size="sm" className="w-full h-full" style={{ boxShadow: "0 12px 30px rgb(0 0 0 / 0.45)" }} />
        </motion.div>
      </div>
    );
  } else if (spotlightId) {
    const main = people.find((p) => p.peerId === spotlightId);
    const rest = people.filter((p) => p.peerId !== spotlightId);
    body = (
      <div className="flex-1 min-h-0 flex flex-col gap-3 p-3">
        <Tile p={main} size="lg" onMenu={openMenu} className="flex-1 min-h-0 cursor-pointer" />
        <div className="flex gap-2 overflow-x-auto no-scrollbar flex-shrink-0">
          {rest.map((p) => (
            <button key={p.peerId} onClick={() => setPinned(p.peerId)} className="flex-shrink-0 w-36 sm:w-44 aspect-video text-left" aria-label={`Spotlight ${nameOf(p)}`}>
              <Tile p={p} size="sm" className="w-full h-full" />
            </button>
          ))}
          {ringing.map((person) => <RingingTile key={person.email} person={person} size="sm" className="flex-shrink-0 w-36 sm:w-44 aspect-video" />)}
        </div>
      </div>
    );
  } else {
    const n = people.length + ringing.length;
    const cols = isMobile ? (n <= 2 ? 1 : 2) : n === 1 ? 1 : n <= 4 ? 2 : n <= 9 ? 3 : 4;
    const fill = isMobile && n <= 2; // phones: stack 1–2 people full height
    body = (
      <div className="flex-1 min-h-0 overflow-y-auto no-scrollbar">
        <div className={`min-h-full flex items-center justify-center p-3 ${fill ? "h-full" : ""}`}>
          <div
            className={`grid gap-3 w-full ${fill ? "h-full" : ""}`}
            style={{ gridTemplateColumns: `repeat(${cols}, minmax(0, 1fr))`, gridTemplateRows: fill ? `repeat(${n}, minmax(0, 1fr))` : undefined, maxWidth: fill ? undefined : cols * 520 }}
          >
            {people.map((p) => <Tile key={p.peerId} p={p} onMenu={openMenu} className={fill ? "h-full" : isMobile ? "aspect-[3/4]" : "aspect-video"} />)}
            {ringing.map((person) => <RingingTile key={person.email} person={person} className={fill ? "h-full" : isMobile ? "aspect-[3/4]" : "aspect-video"} />)}
          </div>
        </div>
      </div>
    );
  }

  return (
    <div className={`${bare ? "" : "call-stage"} flex flex-col min-h-0 ${className}`}>
      {(vs.micError || vs.videoError) && vs.connected && (
        <div className="mx-3 mt-3 flex items-center gap-2 rounded-2xl px-3 py-2 text-xs font-semibold" style={{ background: "rgb(239 68 68 / 0.15)", color: "#ffb4b4" }}>
          <AlertTriangle className="w-4 h-4 flex-shrink-0" />
          <span className="flex-1">{vs.videoError || "Microphone unavailable — you're connected as a listener."}</span>
        </div>
      )}
      {body}
      {showControls && vs.connected && <CallControls vs={vs} onLeave={onLeave} className="flex-shrink-0 px-3 pt-2" style={{ paddingBottom: "max(1rem, env(safe-area-inset-bottom))" }} />}
      <ParticipantMenu target={menu} onClose={() => setMenu(null)} pinned={menu && menu.p.peerId === spotlightId && pinned === menu.p.peerId} onPin={setPinned} />
    </div>
  );
}
