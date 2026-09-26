import React, { useEffect, useState } from "react";
import { EyeOff, Loader2, Lock, Trash2 } from "lucide-react";
import { Toggle } from "@/components/common/Controls";
import { base44 } from "@/api/base44Client";
import { toast } from "@/lib/toast";
import Modal, { useConfirm } from "@/components/common/Modal";
import { channelSlug } from "./AddChannelModal";

export default function ChannelSettingsModal({ channel, roles = [], onClose, onDeleted }) {
  const confirm = useConfirm();
  const [name, setName] = useState("");
  const [description, setDescription] = useState("");
  const [allowed, setAllowed] = useState([]); // role ids
  const [isPrivate, setPrivate] = useState(false);
  const [saving, setSaving] = useState(false);
  useEffect(() => {
    if (!channel) return;
    setName(channel.name || "");
    setDescription(channel.description || "");
    // Older channels stored role names; convert them to ids.
    setAllowed((channel.allowed_roles || []).map((a) => roles.find((r) => r.id === a || r.name === a)?.id).filter(Boolean));
    setPrivate(!!channel.private);
  }, [channel?.id]); // eslint-disable-line react-hooks/exhaustive-deps

  const save = async () => {
    setSaving(true);
    try {
      await base44.entities.ServerChannel.update(channel.id, { name: channelSlug(name, channel.type) || channel.name, description: description.trim(), allowed_roles: allowed, private: isPrivate && allowed.length > 0 });
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
          <div className="space-y-3">
            <p className="label flex items-center gap-1.5 !mb-0"><Lock className="w-3.5 h-3.5" /> Access</p>
            <Toggle checked={isPrivate} onChange={setPrivate} label="Private channel" description="Only the roles below (and people who can manage channels) can see it." />
            <div>
              <p className="text-xs mb-2" style={{ color: "var(--text-muted)" }}>
                {!allowed.length
                  ? (isPrivate ? "Pick at least one role — a private channel needs someone to see it." : channel.type === "voice" ? "Everyone can join." : "Everyone in the server can post.")
                  : isPrivate ? "Only these roles can see and use this channel." : channel.type === "voice" ? "Only these roles can join." : "Everyone can read; only these roles can post."}
              </p>
              <div className="flex flex-wrap gap-1.5">
                {roles.map((r) => {
                  const on = allowed.includes(r.id);
                  return <button key={r.id} onClick={() => setAllowed((a) => (on ? a.filter((x) => x !== r.id) : [...a, r.id]))} className="text-xs font-bold px-2.5 py-1.5 rounded-full transition-colors" style={on ? { background: r.color, color: "#fff" } : { border: `1px solid ${r.color}`, color: r.color }} aria-pressed={on}>{r.name}</button>;
                })}
                {roles.length === 0 && <p className="text-xs" style={{ color: "var(--text-muted)" }}>Create roles in server settings first.</p>}
              </div>
            </div>
            {isPrivate && allowed.length > 0 && <p className="text-xs flex items-center gap-1.5" style={{ color: "var(--text-secondary)" }}><EyeOff className="w-3.5 h-3.5" /> Hidden from everyone else.</p>}
          </div>
        </div>
      )}
    </Modal>
  );
}
