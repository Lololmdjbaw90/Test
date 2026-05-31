import React, { useState } from "react";
import { Trash2 } from "lucide-react";
import { base44 } from "@/api/base44Client";
import SimpleModal from "@/components/common/SimpleModal";
import { Button } from "@/components/ui/button";

// Reconstructed fallback (full source: Base44 Code tab → components/server/ChannelSettingsModal.jsx).
export default function ChannelSettingsModal({ channel, roles = [], onClose, onUpdated, onDeleted }) {
  const [name, setName] = useState(channel?.name || "");
  const [description, setDescription] = useState(channel?.description || "");
  const [saving, setSaving] = useState(false);
  const [confirmDel, setConfirmDel] = useState(false);
  const [error, setError] = useState("");
  const save = async () => {
    setSaving(true); setError("");
    try {
      await base44.entities.ServerChannel.update(channel.id, { name: name.trim().toLowerCase().replace(/\s+/g, "-"), description });
      onUpdated?.(); onClose?.();
    } catch (e) { setError(e?.message || "Could not save changes."); setSaving(false); }
  };
  const del = async () => {
    setSaving(true); setError("");
    try { await base44.entities.ServerChannel.delete(channel.id); onDeleted?.(); onClose?.(); }
    catch (e) { setError(e?.message || "Could not delete channel."); setSaving(false); }
  };
  return (
    <SimpleModal title={`# ${channel?.name || "channel"}`} onClose={onClose}
      footer={<><Button variant="ghost" size="sm" onClick={onClose}>Cancel</Button><Button size="sm" onClick={save} disabled={saving}>{saving ? "Saving\u2026" : "Save"}</Button></>}>
      <div className="p-5 space-y-4">
        <div>
          <label className="block text-xs font-semibold mb-1.5" style={{ color: "var(--text-secondary)" }}>Channel name</label>
          <input value={name} onChange={(e) => setName(e.target.value)} className="w-full rounded-lg border px-3 py-2 text-sm bg-transparent outline-none" style={{ borderColor: "var(--border-c)", color: "var(--text-primary)" }} />
        </div>
        <div>
          <label className="block text-xs font-semibold mb-1.5" style={{ color: "var(--text-secondary)" }}>Description</label>
          <textarea value={description} onChange={(e) => setDescription(e.target.value)} rows={2} placeholder="What's this channel about?" className="w-full rounded-lg border px-3 py-2 text-sm bg-transparent outline-none resize-none" style={{ borderColor: "var(--border-c)", color: "var(--text-primary)" }} />
        </div>
        {error && <p className="text-xs" style={{ color: "hsl(var(--destructive))" }}>{error}</p>}
        <div className="pt-3 border-t" style={{ borderColor: "var(--border-c)" }}>
          {!confirmDel ? (
            <button onClick={() => setConfirmDel(true)} className="flex items-center gap-2 text-sm font-medium" style={{ color: "hsl(var(--destructive))" }}><Trash2 className="w-4 h-4" /> Delete channel</button>
          ) : (
            <div className="flex items-center gap-2 flex-wrap">
              <span className="text-xs" style={{ color: "var(--text-secondary)" }}>Delete this channel?</span>
              <Button variant="destructive" size="sm" onClick={del} disabled={saving}>Delete</Button>
              <Button variant="ghost" size="sm" onClick={() => setConfirmDel(false)}>Cancel</Button>
            </div>
          )}
        </div>
      </div>
    </SimpleModal>
  );
}
