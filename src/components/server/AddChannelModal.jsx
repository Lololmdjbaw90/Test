import React, { useEffect, useState } from "react";
import { Hash, Loader2, Volume2 } from "lucide-react";
import { base44 } from "@/api/base44Client";
import { toast } from "@/lib/toast";
import { useAuth } from "@/lib/AuthContext";
import { checkText } from "@/lib/moderation";
import Modal from "@/components/common/Modal";

export const channelSlug = (name, type) => (type === "voice" ? name.trim() : name.trim().toLowerCase().replace(/\s+/g, "-").replace(/[^a-z0-9_-]/g, ""));

export default function AddChannelModal({ open, communityId, channelCount = 0, defaultType = "text", onClose, onCreated }) {
  const { user } = useAuth();
  const [name, setName] = useState("");
  const [type, setType] = useState(defaultType);
  const [description, setDescription] = useState("");
  const [saving, setSaving] = useState(false);
  useEffect(() => { if (open) { setType(defaultType); setName(""); setDescription(""); } }, [open, defaultType]);

  const create = async () => {
    const clean = channelSlug(name, type);
    if (!clean) return;
    const mod = await checkText(`${name}\n${description}`, { user, where: "channel name", kind: "name" });
    if (!mod.safe) { toast.error(mod.reason); return; }
    setSaving(true);
    try {
      const ch = await base44.entities.ServerChannel.create({ community_id: communityId, name: clean, type, description: description.trim(), position: channelCount, allowed_roles: [] });
      toast.success(`${type === "voice" ? "🔊" : "#"}${clean} created`);
      onCreated?.(ch);
      onClose();
    } catch (e) { toast.error(e?.message || "Could not create channel."); }
    setSaving(false);
  };

  return (
    <Modal open={open} onClose={onClose} title="Create channel" footer={<><button className="btn-ghost" onClick={onClose}>Cancel</button><button className="btn" onClick={create} disabled={saving || !channelSlug(name, type)}>{saving ? <Loader2 className="w-4 h-4 animate-spin" /> : "Create channel"}</button></>}>
      <div className="space-y-4">
        <div className="grid grid-cols-2 gap-2">
          {[{ id: "text", label: "Text", desc: "Messages, images, reactions", icon: Hash }, { id: "voice", label: "Voice", desc: "Talk with your mic", icon: Volume2 }].map((t) => (
            <button key={t.id} onClick={() => setType(t.id)} className="card-sm p-3 text-left" style={type === t.id ? { borderColor: "var(--accent-rose)", boxShadow: "0 0 0 3px rgb(var(--accent-rgb) / 0.15)" } : undefined}>
              <t.icon className="w-5 h-5 mb-2" style={{ color: type === t.id ? "var(--accent-rose)" : "var(--text-muted)" }} />
              <span className="block text-sm font-bold" style={{ color: "var(--text-primary)" }}>{t.label}</span>
              <span className="block text-xs" style={{ color: "var(--text-muted)" }}>{t.desc}</span>
            </button>
          ))}
        </div>
        <div>
          <label className="label" htmlFor="ch-name">Channel name</label>
          <div className="relative">
            {type === "text" ? <Hash className="absolute left-3.5 top-1/2 -translate-y-1/2 w-4 h-4" style={{ color: "var(--text-muted)" }} /> : <Volume2 className="absolute left-3.5 top-1/2 -translate-y-1/2 w-4 h-4" style={{ color: "var(--text-muted)" }} />}
            <input id="ch-name" className="input pl-10" value={name} onChange={(e) => setName(e.target.value)} onKeyDown={(e) => e.key === "Enter" && create()} placeholder={type === "text" ? "new-channel" : "Lounge"} maxLength={32} />
          </div>
        </div>
        <div><label className="label" htmlFor="ch-desc">Topic (optional)</label><input id="ch-desc" className="input" value={description} onChange={(e) => setDescription(e.target.value)} placeholder="What's this channel for?" maxLength={120} /></div>
      </div>
    </Modal>
  );
}
