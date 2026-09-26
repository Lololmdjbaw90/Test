import React, { useEffect, useState } from "react";
import { motion } from "framer-motion";
import { Loader2, MicOff, PhoneCall, Video, Volume2 } from "lucide-react";
import voice, { VOICE_STALE_MS } from "@/lib/voice";
import { useLiveQuery } from "@/lib/useLiveQuery";
import Avatar from "@/components/common/Avatar";
import CallStage from "@/components/voice/CallStage";
import { useNow, useVoice } from "@/components/voice/useVoice";

// A server voice channel: a lobby showing who's hanging out, then the call
// stage once you join. The connection keeps running when you switch channels
// or pages (the dock at the top of the app brings you back).
export default function VoiceChannelView({ channel, me }) {
  const vs = useVoice();
  const now = useNow(10000);
  const [busy, setBusy] = useState(false);
  const joinedHere = vs.room?.id === channel.id && (vs.connected || vs.connecting);
  const { data: presence } = useLiveQuery("VoicePresence", { channel_id: channel.id });
  const inRoom = presence.filter((p) => now - (p.last_active || 0) < VOICE_STALE_MS);

  // While this view shows the stage, the global dock stays hidden.
  useEffect(() => {
    if (!joinedHere) return undefined;
    voice.setExpanded(true);
    return () => { if (voice.getState().room?.id === channel.id) voice.setExpanded(false); };
  }, [joinedHere, channel.id]);

  const join = async (video) => {
    setBusy(true);
    await voice.join({ id: channel.id, name: channel.name, type: "channel", communityId: channel.community_id, link: `/CommunityChat?id=${channel.community_id}&channel=${channel.id}` }, me, { video });
    setBusy(false);
  };

  if (joinedHere) return <CallStage vs={vs} className="flex-1" />;

  const elsewhere = vs.connected && vs.room && vs.room.id !== channel.id;
  return (
    <div className="flex-1 min-h-0 overflow-y-auto call-stage">
      <div className="min-h-full flex flex-col items-center justify-center text-center gap-6 p-6">
        <motion.div initial={{ scale: 0.8, opacity: 0 }} animate={{ scale: 1, opacity: 1 }} transition={{ type: "spring", stiffness: 300, damping: 22 }} className="relative w-20 h-20 rounded-[1.75rem] flex items-center justify-center" style={{ background: "rgb(255 255 255 / 0.1)" }}>
          {inRoom.length > 0 && <><span className="ripple !rounded-[1.75rem]" /><span className="ripple !rounded-[1.75rem]" /></>}
          <Volume2 className="w-9 h-9" />
        </motion.div>
        <div>
          <p className="font-display text-2xl font-semibold">{channel.name}</p>
          <p className="text-sm mt-1 opacity-70 max-w-sm">{channel.description || (inRoom.length ? "People are hanging out — hop in!" : "No one's here yet. Start the hangout!")}</p>
        </div>

        {inRoom.length > 0 && (
          <div className="flex flex-wrap justify-center gap-3 max-w-md">
            {inRoom.map((p, i) => (
              <motion.div key={p.id} initial={{ opacity: 0, y: 10 }} animate={{ opacity: 1, y: 0 }} transition={{ delay: i * 0.04 }} className="flex flex-col items-center gap-1.5 w-20">
                <span className="relative flex">
                  <Avatar src={p.user?.profile_picture} name={p.user?.display_name} size={56} />
                  {p.muted && <span className="absolute -bottom-1 -right-1 w-6 h-6 rounded-full flex items-center justify-center" style={{ background: "#140f17" }}><MicOff className="w-3.5 h-3.5 text-[#ff8b8b]" /></span>}
                  {p.video && <span className="absolute -top-1 -right-1 w-6 h-6 rounded-full flex items-center justify-center" style={{ background: "#140f17" }}><Video className="w-3.5 h-3.5" /></span>}
                </span>
                <span className="text-xs font-semibold truncate max-w-full opacity-90">{p.user?.display_name || "Someone"}</span>
              </motion.div>
            ))}
          </div>
        )}

        <div className="flex flex-wrap justify-center gap-3">
          <button onClick={() => join(false)} disabled={busy || vs.connecting} className="call-btn call-btn-accept !w-auto !h-12 px-6 gap-2 font-bold">
            {busy ? <Loader2 className="w-4 h-4 animate-spin" /> : <PhoneCall className="w-4 h-4" />} {elsewhere ? "Switch here" : "Join voice"}
          </button>
          <button onClick={() => join(true)} disabled={busy || vs.connecting} className="call-btn !w-auto !h-12 px-6 gap-2 font-bold">
            <Video className="w-4 h-4" /> Join with video
          </button>
        </div>
        {elsewhere && <p className="text-xs opacity-60">You're currently in <strong>{vs.room.name}</strong>.</p>}
      </div>
    </div>
  );
}
