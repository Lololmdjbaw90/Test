import React from "react";
import { Hash, Plus, Settings, Users, Volume2 } from "lucide-react";

// Reconstructed from pages/CommunityChat.jsx call site. Functional, but may
// differ from the original (full source: Base44 Code tab → components/server/ServerSidebar.jsx).
export default function ServerSidebar({ community, channels = [], activeChannel, me, memberCount = 0, onSelectChannel, onAddChannel, onChannelSettings, onServerSettings, onMembersOpen }) {
  return (
    <div className="hidden md:flex flex-col w-56 flex-shrink-0 h-full border-r" style={{ background: "var(--surface)", borderColor: "var(--border-c)" }}>
      <button onClick={onServerSettings} className="flex items-center gap-2 px-4 h-14 border-b w-full text-left transition-colors hover:bg-black/[0.02]" style={{ borderColor: "var(--border-c)" }}>
        <span className="text-lg">{community?.icon_emoji || "\u{1F338}"}</span>
        <span className="font-semibold text-sm truncate flex-1" style={{ color: "var(--text-primary)" }}>{community?.name || "Server"}</span>
        <Settings className="w-4 h-4" style={{ color: "var(--text-muted)" }} />
      </button>
      <div className="flex-1 overflow-y-auto py-3 px-2">
        <div className="flex items-center justify-between px-2 mb-1">
          <span className="text-[11px] font-semibold uppercase tracking-wide" style={{ color: "var(--text-muted)" }}>Channels</span>
          <button onClick={onAddChannel} className="p-0.5 rounded transition-colors hover:bg-black/[0.04]" title="Add channel"><Plus className="w-3.5 h-3.5" style={{ color: "var(--text-muted)" }} /></button>
        </div>
        {channels.map((ch) => {
          const active = activeChannel?.id === ch.id;
          const Icon = ch.type === "voice" ? Volume2 : Hash;
          return (
            <div key={ch.id} className="group flex items-center gap-1 rounded-lg px-1" style={active ? { background: "var(--pink-soft)" } : undefined}>
              <button onClick={() => onSelectChannel?.(ch)} className="flex items-center gap-1.5 flex-1 py-1.5 px-1 text-left min-w-0">
                <Icon className="w-4 h-4 flex-shrink-0" style={{ color: active ? "var(--accent-rose)" : "var(--text-muted)" }} />
                <span className="text-sm truncate" style={{ color: active ? "var(--accent-rose)" : "var(--text-secondary)", fontWeight: active ? 600 : 400 }}>{ch.name}</span>
              </button>
              <button onClick={() => onChannelSettings?.(ch)} className="opacity-0 group-hover:opacity-100 p-1 rounded transition-opacity" title="Channel settings"><Settings className="w-3 h-3" style={{ color: "var(--text-muted)" }} /></button>
            </div>
          );
        })}
        {channels.length === 0 && <p className="text-xs px-2 py-3" style={{ color: "var(--text-muted)" }}>No channels yet.</p>}
      </div>
      <button onClick={onMembersOpen} className="flex items-center gap-2 px-4 h-12 border-t w-full text-left transition-colors hover:bg-black/[0.02]" style={{ borderColor: "var(--border-c)" }}>
        <Users className="w-4 h-4" style={{ color: "var(--text-secondary)" }} />
        <span className="text-xs font-medium" style={{ color: "var(--text-secondary)" }}>{memberCount} member{memberCount === 1 ? "" : "s"}</span>
      </button>
    </div>
  );
}
