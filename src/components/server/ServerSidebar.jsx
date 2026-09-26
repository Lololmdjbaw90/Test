import React, { useEffect, useRef, useState } from "react";
import { Link } from "react-router-dom";
import { AnimatePresence, motion } from "framer-motion";
import { ArrowLeft, ChevronDown, Hash, Link2, Lock, LogOut, MicOff, Plus, Settings, Users, Video, Volume2 } from "lucide-react";
import { VOICE_STALE_MS } from "@/lib/voice";
import { useVoice } from "@/components/voice/useVoice";
import { useLiveQuery } from "@/lib/useLiveQuery";
import { toast } from "@/lib/toast";
import Avatar from "@/components/common/Avatar";
import Popover from "@/components/common/Popover";

function ChannelRow({ ch, active, canManage, onSelect, onSettings, voicePeers, live }) {
  const Icon = ch.type === "voice" ? Volume2 : Hash;
  const locked = ch.allowed_roles?.length > 0;
  const inVoice = ch.type === "voice" ? voicePeers.filter((p) => p.channel_id === ch.id) : [];
  return (
    <div>
      <div className="group relative flex items-center rounded-xl">
        {active && <motion.span initial={{ opacity: 0 }} animate={{ opacity: 1 }} className="absolute inset-0 rounded-xl" style={{ background: "var(--pink-soft)" }} transition={{ type: "spring", stiffness: 420, damping: 34 }} />}
        <button onClick={() => onSelect(ch)} className="relative flex items-center gap-2 flex-1 min-w-0 h-9 px-2.5 text-left rounded-xl hover:bg-[var(--surface-2)] transition-colors" style={{ color: active ? "var(--accent-rose)" : "var(--text-secondary)" }}>
          <Icon className="w-4 h-4 flex-shrink-0 opacity-80" />
          <span className="truncate text-sm" style={{ fontWeight: active ? 700 : 500 }}>{ch.name}</span>
          {locked && <Lock className="w-3 h-3 flex-shrink-0 opacity-60" />}
        </button>
        {canManage && (
          <button onClick={() => onSettings(ch)} className="relative icon-btn w-7 h-7 opacity-0 group-hover:opacity-100 focus:opacity-100 mr-1" aria-label={`Settings for ${ch.name}`}><Settings className="w-3.5 h-3.5" /></button>
        )}
      </div>
      {inVoice.length > 0 && (
        <div className="ml-8 mb-1 space-y-0.5">
          {inVoice.map((p) => {
            // Live speaking / mute state for the channel we're connected to.
            const l = live?.find((x) => x.peerId === p.peer_id);
            const muted = l ? l.muted : p.muted;
            return (
              <div key={p.id} className="flex items-center gap-2 py-1 text-xs" style={{ color: l?.speaking ? "var(--text-primary)" : "var(--text-secondary)" }}>
                <Avatar src={p.user?.profile_picture} name={p.user?.display_name} size={20} ring={l?.speaking ? 2 : 0} ringColor="#3ddc97" className="transition-shadow duration-150" />
                <span className="truncate flex-1" style={{ fontWeight: l?.speaking ? 700 : 500 }}>{p.user?.display_name || "Someone"}</span>
                {p.video && <Video className="w-3 h-3 flex-shrink-0 opacity-70" />}
                {muted && <MicOff className="w-3 h-3 flex-shrink-0" style={{ color: "var(--danger)" }} aria-label="Muted" />}
              </div>
            );
          })}
        </div>
      )}
    </div>
  );
}

export default function ServerSidebar({ community, channels, activeChannel, canManage, isOwner, memberCount, onSelectChannel, onAddChannel, onChannelSettings, onServerSettings, onMembers, onLeave }) {
  const [menu, setMenu] = useState(false);
  const menuRef = useRef(null);
  const [now, setNow] = useState(Date.now());
  useEffect(() => { const t = setInterval(() => setNow(Date.now()), 15000); return () => clearInterval(t); }, []);
  const { data: presence } = useLiveQuery("VoicePresence", { community_id: community.id });
  const voicePeers = presence.filter((p) => now - (p.last_active || 0) < VOICE_STALE_MS);
  const vs = useVoice();
  const text = channels.filter((c) => c.type !== "voice");
  const voiceChannels = channels.filter((c) => c.type === "voice");
  const invite = async () => {
    const url = `${window.location.origin}/CommunityChat?id=${community.id}`;
    try { await navigator.clipboard.writeText(url); toast.success("Invite link copied"); } catch { toast(url); }
    setMenu(false);
  };

  return (
    <div className="flex flex-col h-full w-full glass" style={{ borderRight: "1px solid var(--border-c)" }}>
      <div className="relative flex-shrink-0">
        <div className="h-24 relative overflow-hidden" style={{ background: "var(--accent-grad)" }}>
          {community.banner_url && <img src={community.banner_url} alt="" className="w-full h-full object-cover" />}
          <div className="absolute inset-0" style={{ background: "linear-gradient(to top, rgb(20 8 14 / 0.6), transparent)" }} />
          <Link to="/Communities" className="absolute top-2.5 left-2.5 icon-btn glass w-8 h-8" aria-label="Back to servers"><ArrowLeft className="w-4 h-4" /></Link>
        </div>
        <button ref={menuRef} onClick={() => setMenu((v) => !v)} className="absolute bottom-0 inset-x-0 flex items-center gap-2 px-3 py-2.5 text-white text-left" aria-expanded={menu}>
          <span className="w-8 h-8 rounded-xl flex items-center justify-center text-lg overflow-hidden flex-shrink-0" style={{ background: "rgb(255 255 255 / 0.25)" }}>{community.icon_url ? <img src={community.icon_url} alt="" className="w-full h-full object-cover" /> : community.icon_emoji || "💬"}</span>
          <span className="flex-1 min-w-0 font-display text-lg font-semibold truncate drop-shadow">{community.name}</span>
          <motion.span animate={{ rotate: menu ? 180 : 0 }}><ChevronDown className="w-4 h-4" /></motion.span>
        </button>
        <Popover open={menu} onClose={() => setMenu(false)} anchorRef={menuRef} placement="bottom-start" width={240} label="Server menu">
          <div className="p-1.5">
            <button onClick={invite} className="w-full flex items-center gap-2.5 px-3 py-2 rounded-xl text-sm font-semibold hover:bg-[var(--pink-soft)]" style={{ color: "var(--accent-rose)" }}><Link2 className="w-4 h-4" /> Copy invite link</button>
            {canManage && <button onClick={() => { setMenu(false); onServerSettings(); }} className="w-full flex items-center gap-2.5 px-3 py-2 rounded-xl text-sm font-semibold hover:bg-[var(--surface-2)]" style={{ color: "var(--text-secondary)" }}><Settings className="w-4 h-4" /> Server settings</button>}
            {canManage && <button onClick={() => { setMenu(false); onAddChannel("text"); }} className="w-full flex items-center gap-2.5 px-3 py-2 rounded-xl text-sm font-semibold hover:bg-[var(--surface-2)]" style={{ color: "var(--text-secondary)" }}><Plus className="w-4 h-4" /> Create channel</button>}
            {!isOwner && <button onClick={() => { setMenu(false); onLeave(); }} className="w-full flex items-center gap-2.5 px-3 py-2 rounded-xl text-sm font-semibold hover:bg-[var(--surface-2)]" style={{ color: "var(--danger)" }}><LogOut className="w-4 h-4" /> Leave server</button>}
          </div>
        </Popover>
      </div>

      <div className="flex-1 overflow-y-auto no-scrollbar px-2 py-3 space-y-4">
        {[{ label: "Text channels", list: text, type: "text" }, { label: "Voice channels", list: voiceChannels, type: "voice" }].map((group) => (
          (group.list.length > 0 || canManage) && (
            <div key={group.label}>
              <div className="flex items-center px-2.5 mb-1">
                <span className="eyebrow flex-1">{group.label}</span>
                {canManage && <button onClick={() => onAddChannel(group.type)} className="icon-btn w-6 h-6" aria-label={`Add ${group.type} channel`}><Plus className="w-3.5 h-3.5" /></button>}
              </div>
              <div className="space-y-0.5">
                {group.list.map((ch) => <ChannelRow key={ch.id} ch={ch} active={activeChannel?.id === ch.id} canManage={canManage} onSelect={onSelectChannel} onSettings={onChannelSettings} voicePeers={voicePeers} live={vs.room?.id === ch.id ? vs.participants : null} />)}
              </div>
            </div>
          )
        ))}
      </div>

      <button onClick={onMembers} className="flex-shrink-0 flex items-center gap-2.5 px-4 h-12 text-sm font-semibold hover:bg-[var(--surface-2)] transition-colors" style={{ borderTop: "1px solid var(--border-c)", color: "var(--text-secondary)" }}>
        <Users className="w-4 h-4" /> {memberCount} member{memberCount === 1 ? "" : "s"}
      </button>
    </div>
  );
}
