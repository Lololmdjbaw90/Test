import React, { useState } from "react";
import { base44 } from "@/api/base44Client";
import SimpleModal from "@/components/common/SimpleModal";
import { Button } from "@/components/ui/button";

// Reconstructed fallback (full source: Base44 Code tab → components/server/ServerSettingsModal.jsx).
// The original splits tabs into components/server/settings/*Tab.jsx; this self-contained
// version covers Overview / Members / Roles using the data passed by CommunityChat.jsx.
export default function ServerSettingsModal({ community, channels = [], members = [], roles = [], me, onClose, onUpdated, onKick, onRoleChange }) {
  const [tab, setTab] = useState("overview");
  const [name, setName] = useState(community?.name || "");
  const [emoji, setEmoji] = useState(community?.icon_emoji || "\u{1F338}");
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState("");
  const saveOverview = async () => {
    setSaving(true); setError("");
    try { await base44.entities.Community.update(community.id, { name: name.trim(), icon_emoji: emoji }); onUpdated?.(); }
    catch (e) { setError(e?.message || "Could not save."); setSaving(false); }
  };
  const tabs = [["overview", "Overview"], ["members", `Members (${members.length})`], ["roles", `Roles (${roles.length})`]];
  return (
    <SimpleModal title="Server Settings" onClose={onClose} maxWidth="max-w-lg">
      <div className="flex border-b px-2" style={{ borderColor: "var(--border-c)" }}>
        {tabs.map(([k, label]) => (
          <button key={k} onClick={() => setTab(k)} className="px-3 py-2.5 text-sm font-medium border-b-2 -mb-px transition-colors" style={tab === k ? { borderColor: "var(--accent-pink)", color: "var(--accent-rose)" } : { borderColor: "transparent", color: "var(--text-muted)" }}>{label}</button>
        ))}
      </div>
      <div className="p-5">
        {tab === "overview" && (
          <div className="space-y-4">
            <div className="flex gap-3">
              <input value={emoji} onChange={(e) => setEmoji(e.target.value)} maxLength={2} className="w-14 h-14 text-2xl text-center rounded-lg border bg-transparent outline-none" style={{ borderColor: "var(--border-c)" }} />
              <div className="flex-1">
                <label className="block text-xs font-semibold mb-1.5" style={{ color: "var(--text-secondary)" }}>Server name</label>
                <input value={name} onChange={(e) => setName(e.target.value)} className="w-full rounded-lg border px-3 py-2 text-sm bg-transparent outline-none" style={{ borderColor: "var(--border-c)", color: "var(--text-primary)" }} />
              </div>
            </div>
            <p className="text-xs" style={{ color: "var(--text-muted)" }}>{channels.length} channels \u00b7 {members.length} members</p>
            {error && <p className="text-xs" style={{ color: "hsl(var(--destructive))" }}>{error}</p>}
            <div className="flex justify-end"><Button size="sm" onClick={saveOverview} disabled={saving}>{saving ? "Saving\u2026" : "Save changes"}</Button></div>
          </div>
        )}
        {tab === "members" && (
          <div className="space-y-1 max-h-[50vh] overflow-y-auto">
            {members.map((m) => (
              <div key={m.id} className="flex items-center gap-3 py-2 px-2 rounded-lg">
                <img src={m.user_profile_picture || `https://ui-avatars.com/api/?name=${encodeURIComponent(m.user_display_name || m.user_email || "U")}`} alt="" className="w-8 h-8 rounded-full object-cover" />
                <div className="flex-1 min-w-0">
                  <p className="text-sm font-medium truncate" style={{ color: "var(--text-primary)" }}>{m.nickname || m.user_display_name || m.user_email}</p>
                  <p className="text-xs truncate" style={{ color: "var(--text-muted)" }}>{m.user_email}</p>
                </div>
                {onKick && m.user_email !== me?.email && (
                  <Button variant="ghost" size="sm" onClick={() => onKick(m)} style={{ color: "hsl(var(--destructive))" }}>Kick</Button>
                )}
              </div>
            ))}
            {members.length === 0 && <p className="text-xs py-4 text-center" style={{ color: "var(--text-muted)" }}>No members.</p>}
          </div>
        )}
        {tab === "roles" && (
          <div className="space-y-1 max-h-[50vh] overflow-y-auto">
            {roles.map((r) => (
              <div key={r.id} className="flex items-center gap-2 py-2 px-2">
                <span className="w-3 h-3 rounded-full" style={{ background: r.color || "var(--accent-pink)" }} />
                <span className="text-sm" style={{ color: "var(--text-primary)" }}>{r.name}</span>
              </div>
            ))}
            {roles.length === 0 && <p className="text-xs py-4 text-center" style={{ color: "var(--text-muted)" }}>No roles defined.</p>}
          </div>
        )}
      </div>
    </SimpleModal>
  );
}
