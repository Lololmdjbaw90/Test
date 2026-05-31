import React, { useEffect, useState, useCallback } from "react";
import { motion, AnimatePresence } from "framer-motion";
import { Mic, MicOff, Volume2, VolumeX, PhoneOff, Headphones, Loader2, AlertTriangle, PhoneCall } from "lucide-react";
import voice from "@/lib/voice";

function initials(user) {
  const n = (user && (user.display_name || user.full_name || user.email)) || "?";
  return n.trim()[0]?.toUpperCase() || "?";
}

function ParticipantTile({ p }) {
  const name = (p.user && (p.user.display_name || p.user.full_name || p.user.email)) || "Someone";
  const pic = p.user && (p.user.profile_picture || p.user.user_profile_picture);
  return (
    <motion.div
      layout
      initial={{ opacity: 0, scale: 0.85 }}
      animate={{ opacity: 1, scale: 1 }}
      exit={{ opacity: 0, scale: 0.85 }}
      transition={{ type: "spring", stiffness: 320, damping: 26 }}
      className="relative flex flex-col items-center gap-2.5 rounded-2xl p-5"
      style={{ background: "var(--surface)", border: "1px solid var(--border-c)", boxShadow: "0 8px 24px rgba(148,83,103,0.06)" }}
    >
      <div className="relative">
        {/* speaking ring */}
        <motion.span
          className="absolute -inset-1.5 rounded-full"
          animate={p.speaking ? { boxShadow: "0 0 0 3px var(--accent-rose)", opacity: 1 } : { boxShadow: "0 0 0 0px rgba(0,0,0,0)", opacity: 0 }}
          transition={{ duration: 0.18 }}
        />
        <motion.div
          animate={p.speaking ? { scale: [1, 1.04, 1] } : { scale: 1 }}
          transition={p.speaking ? { repeat: Infinity, duration: 1.1 } : { duration: 0.2 }}
          className="w-16 h-16 rounded-full overflow-hidden flex items-center justify-center text-xl font-bold"
          style={{ background: "var(--pink-soft)", color: "var(--accent-rose)" }}
        >
          {pic ? <img src={pic} alt="" className="w-full h-full object-cover" /> : initials(p.user)}
        </motion.div>
        {p.muted && (
          <span className="absolute -bottom-1 -right-1 w-6 h-6 rounded-full flex items-center justify-center" style={{ background: "var(--surface)", border: "1px solid var(--border-c)" }}>
            <MicOff className="w-3.5 h-3.5" style={{ color: "hsl(var(--destructive))" }} />
          </span>
        )}
      </div>
      <div className="flex items-center gap-1.5 max-w-full">
        <span className="text-sm font-semibold truncate" style={{ color: "var(--text-primary)" }}>{name}{p.self ? " (you)" : ""}</span>
        {p.deafened && <VolumeX className="w-3.5 h-3.5 flex-shrink-0" style={{ color: "hsl(var(--destructive))" }} />}
      </div>
    </motion.div>
  );
}

function CtrlButton({ active, danger, onClick, children, title }) {
  const base = { border: "1px solid var(--border-c)", background: "var(--surface)", color: "var(--text-secondary)" };
  const on = danger
    ? { border: "1px solid transparent", background: "hsl(var(--destructive))", color: "#fff" }
    : { border: "1px solid transparent", background: "var(--accent-pink)", color: "#fff" };
  return (
    <motion.button
      whileTap={{ scale: 0.92 }}
      onClick={onClick}
      title={title}
      className="w-12 h-12 rounded-full flex items-center justify-center transition-colors"
      style={active ? on : base}
    >
      {children}
    </motion.button>
  );
}

export default function VoiceChannelView({ channel, me }) {
  const [vs, setVs] = useState(voice.getState());
  const joinedHere = vs.connected && vs.channelId === channel?.id;

  useEffect(() => {
    const unsub = voice.subscribe(setVs);
    return () => {
      unsub();
      // release mic / leave the call when navigating away from this channel
      voice.leave();
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  const handleJoin = useCallback(() => { voice.join(channel, me); }, [channel, me]);

  return (
    <div className="flex-1 flex flex-col min-h-0" style={{ background: "var(--app-bg)" }}>
      {/* header */}
      <div className="flex-shrink-0 h-12 flex items-center gap-2 px-4 border-b" style={{ background: "var(--surface)", borderColor: "var(--border-c)" }}>
        <Volume2 className="w-4 h-4" style={{ color: "var(--accent-rose)" }} />
        <span className="font-semibold text-sm" style={{ color: "var(--text-primary)" }}>{channel?.name || "Voice"}</span>
        {joinedHere && (
          <span className="text-xs px-2 py-0.5 rounded-full" style={{ background: "var(--pink-soft)", color: "var(--accent-rose)" }}>
            {vs.participants.length} in voice
          </span>
        )}
        <div className="flex-1" />
        {vs.connecting && <span className="text-xs flex items-center gap-1" style={{ color: "var(--text-muted)" }}><Loader2 className="w-3 h-3 animate-spin" /> connecting</span>}
        {joinedHere && <span className="text-xs flex items-center gap-1" style={{ color: "#16a34a" }}><span className="w-1.5 h-1.5 rounded-full" style={{ background: "#16a34a" }} /> connected</span>}
      </div>

      {/* body */}
      <div className="flex-1 overflow-y-auto p-5 scroll">
        {!joinedHere ? (
          <div className="h-full flex flex-col items-center justify-center text-center gap-4">
            <div className="w-20 h-20 rounded-3xl flex items-center justify-center" style={{ background: "var(--pink-soft)" }}>
              <Volume2 className="w-9 h-9" style={{ color: "var(--accent-rose)" }} />
            </div>
            <div>
              <p className="font-bold text-base" style={{ color: "var(--text-primary)" }}>{channel?.name || "Voice channel"}</p>
              <p className="text-xs mt-1 max-w-xs" style={{ color: "var(--text-muted)" }}>
                {channel?.description || "Join the call to talk with others here."} Open a second tab and join to hear a real call.
              </p>
            </div>
            <button onClick={handleJoin} disabled={vs.connecting} className="btn px-6 py-3">
              {vs.connecting ? <><Loader2 className="w-4 h-4 animate-spin" /> Connecting…</> : <><PhoneCall className="w-4 h-4" /> Join Voice</>}
            </button>
          </div>
        ) : (
          <>
            {vs.micError && (
              <div className="mb-4 flex items-center gap-2 rounded-xl px-3 py-2 text-xs" style={{ background: "color-mix(in srgb, hsl(var(--destructive)) 10%, var(--surface))", color: "hsl(var(--destructive))", border: "1px solid color-mix(in srgb, hsl(var(--destructive)) 30%, var(--border-c))" }}>
                <AlertTriangle className="w-4 h-4 flex-shrink-0" /> Microphone unavailable — you're connected as a listener.
              </div>
            )}
            <div className="grid gap-3" style={{ gridTemplateColumns: "repeat(auto-fill, minmax(150px, 1fr))" }}>
              <AnimatePresence>
                {vs.participants.map((p) => <ParticipantTile key={p.peerId} p={p} />)}
              </AnimatePresence>
            </div>
          </>
        )}
      </div>

      {/* control bar */}
      {joinedHere && (
        <motion.div
          initial={{ y: 20, opacity: 0 }}
          animate={{ y: 0, opacity: 1 }}
          className="flex-shrink-0 flex items-center justify-center gap-3 py-4 border-t"
          style={{ background: "var(--surface)", borderColor: "var(--border-c)" }}
        >
          <CtrlButton active={vs.muted} onClick={() => voice.toggleMute()} title={vs.muted ? "Unmute" : "Mute"}>
            {vs.muted ? <MicOff className="w-5 h-5" /> : <Mic className="w-5 h-5" />}
          </CtrlButton>
          <CtrlButton active={vs.deafened} onClick={() => voice.toggleDeafen()} title={vs.deafened ? "Undeafen" : "Deafen"}>
            {vs.deafened ? <VolumeX className="w-5 h-5" /> : <Headphones className="w-5 h-5" />}
          </CtrlButton>
          <CtrlButton danger active onClick={() => voice.leave()} title="Leave call">
            <PhoneOff className="w-5 h-5" />
          </CtrlButton>
        </motion.div>
      )}
    </div>
  );
}
