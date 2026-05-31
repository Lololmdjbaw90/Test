import React, { useState } from "react";
import { Hash } from "lucide-react";
import { base44 } from "@/api/base44Client";
import SimpleModal from "@/components/common/SimpleModal";
import { Button } from "@/components/ui/button";

// Reconstructed fallback (full source: Base44 Code tab → components/server/AddChannelModal.jsx).
export default function AddChannelModal({ communityId, channelCount = 0, onClose, onCreated }) {
  const [name, setName] = useState("");
  const [type, setType] = useState("text");
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState("");
  const create = async () => {
    const clean = name.trim().toLowerCase().replace(/\s+/g, "-");
    if (!clean) { setError("Channel name is required."); return; }
    setSaving(true); setError("");
    try {
      await base44.entities.ServerChannel.create({ community_id: communityId, name: clean, type, position: channelCount });
      onCreated?.();
    } catch (e) { setError(e?.message || "Could not create channel."); setSaving(false); }
  };
  return (
    <SimpleModal title="Create Channel" onClose={onClose}
      footer={<><Button variant="ghost" size="sm" onClick={onClose}>Cancel</Button><Button size="sm" onClick={create} disabled={saving}>{saving ? "Creating\u2026" : "Create"}</Button></>}>
      <div className="p-5 space-y-4">
        <div>
          <label className="block text-xs font-semibold mb-1.5" style={{ color: "var(--text-secondary)" }}>Channel name</label>
          <div className="flex items-center gap-2 rounded-lg border px-3 py-2" style={{ borderColor: "var(--border-c)" }}>
            <Hash className="w-4 h-4" style={{ color: "var(--text-muted)" }} />
            <input autoFocus value={name} onChange={(e) => setName(e.target.value)} onKeyDown={(e) => e.key === "Enter" && create()} placeholder="new-channel" className="flex-1 bg-transparent outline-none text-sm" style={{ color: "var(--text-primary)" }} />
          </div>
        </div>
        <div>
          <label className="block text-xs font-semibold mb-1.5" style={{ color: "var(--text-secondary)" }}>Type</label>
          <div className="flex gap-2">
            {["text", "voice"].map((t) => (
              <button key={t} onClick={() => setType(t)} className="flex-1 py-2 rounded-lg text-sm capitalize border transition-colors" style={type === t ? { background: "var(--pink-soft)", borderColor: "var(--accent-pink)", color: "var(--accent-rose)" } : { borderColor: "var(--border-c)", color: "var(--text-secondary)" }}>{t}</button>
            ))}
          </div>
        </div>
        {error && <p className="text-xs" style={{ color: "hsl(var(--destructive))" }}>{error}</p>}
      </div>
    </SimpleModal>
  );
}
