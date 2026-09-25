import React from "react";
import { useNavigate } from "react-router-dom";
import { AnimatePresence, motion } from "framer-motion";
import { HeadphoneOff, Headphones, Mic, MicOff, PhoneOff, Video } from "lucide-react";
import voice from "@/lib/voice";
import Avatar from "@/components/common/Avatar";
import { useElapsed, useVoice } from "@/components/voice/useVoice";

// "Tap to return to call" bar shown at the top of the app while you're in a
// voice channel or call that isn't on screen.
export default function VoiceDock() {
  const vs = useVoice();
  const navigate = useNavigate();
  const elapsed = useElapsed(vs.joinedAt);
  const show = !!vs.room && (vs.connected || vs.connecting) && !vs.expanded;
  const open = () => {
    if (vs.room.type === "call") voice.setExpanded(true);
    else navigate(vs.room.link);
  };
  const speaking = vs.participants.filter((p) => p.speaking);

  return (
    <AnimatePresence initial={false}>
      {show && (
        <motion.div
          key="dock"
          initial={{ height: 0, opacity: 0 }}
          animate={{ height: "auto", opacity: 1 }}
          exit={{ height: 0, opacity: 0 }}
          transition={{ type: "spring", stiffness: 420, damping: 38 }}
          className="flex-shrink-0 overflow-hidden relative z-30"
        >
          <div className="flex items-center gap-2 px-3 sm:px-5 py-2 text-white" style={{ background: "linear-gradient(90deg, #15803d, #22c55e)" }}>
            <button onClick={open} className="flex-1 min-w-0 flex items-center gap-3 text-left" aria-label={`Return to ${vs.room?.name}`}>
              <span className="relative flex w-2.5 h-2.5 flex-shrink-0">
                <span className="absolute inline-flex h-full w-full rounded-full bg-white opacity-60 animate-ping" />
                <span className="relative w-2.5 h-2.5 rounded-full bg-white" />
              </span>
              <span className="min-w-0">
                <span className="block text-[11px] font-bold opacity-90 tabular-nums">
                  {vs.connecting ? "Connecting…" : `${vs.room?.type === "call" ? "In a call" : "Voice connected"} · ${elapsed}`}
                </span>
                <span className="block text-sm font-bold truncate leading-tight">
                  {vs.room?.type === "call" ? "" : "🔊 "}{vs.room?.name}
                  {speaking.length > 0 && <span className="font-medium opacity-90"> — {speaking.map((p) => (p.self ? "you" : p.user?.display_name?.split(" ")[0])).join(", ")} talking</span>}
                </span>
              </span>
              <span className="hidden sm:flex -space-x-2 ml-auto pl-2">
                {vs.participants.slice(0, 5).map((p) => (
                  <span key={p.peerId} className="rounded-full transition-shadow" style={{ boxShadow: p.speaking ? "0 0 0 2px #fff" : "0 0 0 2px #16a34a" }}>
                    <Avatar src={p.user?.profile_picture} name={p.user?.display_name} size={26} />
                  </span>
                ))}
              </span>
              {vs.video && <Video className="w-4 h-4 flex-shrink-0 opacity-90" />}
            </button>
            <button onClick={voice.toggleMute} disabled={vs.micError} className="w-9 h-9 rounded-full flex items-center justify-center flex-shrink-0 transition-colors hover:bg-white/20 disabled:opacity-50" style={vs.muted ? { background: "rgb(255 255 255 / 0.25)" } : undefined} aria-label={vs.muted ? "Unmute" : "Mute"} aria-pressed={vs.muted}>
              {vs.muted ? <MicOff className="w-[18px] h-[18px]" /> : <Mic className="w-[18px] h-[18px]" />}
            </button>
            <button onClick={voice.toggleDeafen} className="w-9 h-9 rounded-full items-center justify-center flex-shrink-0 transition-colors hover:bg-white/20 hidden sm:flex" style={vs.deafened ? { background: "rgb(255 255 255 / 0.25)" } : undefined} aria-label={vs.deafened ? "Undeafen" : "Deafen"} aria-pressed={vs.deafened}>
              {vs.deafened ? <HeadphoneOff className="w-[18px] h-[18px]" /> : <Headphones className="w-[18px] h-[18px]" />}
            </button>
            <button onClick={() => voice.leave()} className="w-9 h-9 rounded-full flex items-center justify-center flex-shrink-0 transition-colors" style={{ background: "#ef4444" }} aria-label="Leave call" title="Leave">
              <PhoneOff className="w-[18px] h-[18px]" />
            </button>
          </div>
        </motion.div>
      )}
    </AnimatePresence>
  );
}
