import React, { useEffect, useState } from "react";
import { Loader2, Lock, Trash2 } from "lucide-react";
import { base44 } from "@/api/base44Client";
import { toast } from "@/lib/toast";
import Modal, { useConfirm } from "@/components/common/Modal";
import { channelSlug } from "./AddChannelModal";

export default function ChannelSettingsModal({ channel, roles = [], onClose, onDeleted }) {
  const confirm = useConfirm();
  const [name, setName] = useState("");
  const [description, setDescription] = useState("");
  const [allowed, setAllowed] = useState([]);
  const [saving, setSaving] = useState(false);
  useEffect(() => {
    if (!channel) return;
    setName(channel.name || "");
    setDescription(channel.description || "");
    setAllowed(channel.allowed_roles || []);
  }, [channel?.id]);

  const save = async () => {
    setSaving(true);
    try {
      await base44.entities.ServerChannel.update(channel.id, { name: channelSlug(name, channel.type) || channel.name, description: description.trim(), allowed_roles: allowed });
      toast.success("Channel updated");
      onClose();
    } catch (e) { toast.error(e?.message || "Could not save."); }
    setSaving(false);
  };
  const del = async () => {
    if (!(await confirm({ title: `Delete ${channel.type === "voice" ? "" : "#"}${channel.name}?`, message: "Messages in this channel will no longer be reachable.", confirmLabel: "Delete channel", danger: true }))) return;
    try { await base44.entities.ServerChannel.delete(channel.id); toast.success("Channel deleted"); onDeleted?.(channel); onClose(); } catch (e) { toast.error(e?.message || "Could not delete."); }
  };

  return (
    <Modal open={!!channel} onClose={onClose} title="Channel settings" subtitle={channel ? `${channel.type === "voice" ? "🔊" : "#"}${channel.name}` : ""}
      footer={<><button className="btn-ghost mr-auto" style={{ color: "var(--danger)" }} onClick={del}><Trash2 className="w-4 h-4" /> Delete</button><button className="btn-ghost" onClick={onClose}>Cancel</button><button className="btn" onClick={save} disabled={saving}>{saving ? <Loader2 className="w-4 h-4 animate-spin" /> : "Save"}</button></>}>
      {channel && (
        <div className="space-y-4">
          <div><label className="label" htmlFor="cs-name">Name</label><input id="cs-name" className="input" value={name} onChange={(e) => setName(e.target.value)} maxLength={32} /></div>
          <div><label className="label" htmlFor="cs-desc">Topic</label><textarea id="cs-desc" className="input resize-none" rows={2} value={description} onChange={(e) => setDescription(e.target.value)} maxLength={120} /></div>
          {channel.type !== "voice" && (
            <div>
              <p className="label flex items-center gap-1.5"><Lock className="w-3.5 h-3.5" /> Who can post</p>
              <p className="text-xs mb-2" style={{ color: "var(--text-muted)" }}>{allowed.length ? "Only members with these roles (and server managers) can send messages." : "Everyone in the server can post."}</p>
              <div className="flex flex-wrap gap-1.5">
                {roles.map((r) => {
                  const on = allowed.includes(r.name);
                  return <button key={r.id} onClick={() => setAllowed((a) => (on ? a.filter((x) => x !== r.name) : [...a, r.name]))} className="text-xs font-bold px-2.5 py-1.5 rounded-full transition-colors" style={on ? { background: r.color, color: "#fff" } : { border: `1px solid ${r.color}`, color: r.color }}>{r.name}</button>;
                })}
                {roles.length === 0 && <p className="text-xs" style={{ color: "var(--text-muted)" }}>Create roles in server settings first.</p>}
              </div>
            </div>
          )}
        </div>
      )}
    </Modal>
  );
}
