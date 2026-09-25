import React, { useEffect, useState } from "react";
import { useNavigate } from "react-router-dom";
import { AnimatePresence, motion } from "framer-motion";
import { AlertTriangle, ImagePlus, Loader2, Plus, Save, Shield, Trash2, UserMinus, Users, Wrench } from "lucide-react";
import { base44 } from "@/api/base44Client";
import { toast } from "@/lib/toast";
import { displayName } from "@/lib/format";
import Modal, { useConfirm } from "@/components/common/Modal";
import { Segmented } from "@/components/common/Controls";
import Avatar from "@/components/common/Avatar";

const ROLE_COLORS = ["#d9577f", "#8b5cf6", "#2f80e0", "#16a37f", "#f0a020", "#ee6e40", "#64748b", "#db2777"];

function Overview({ community, onSaved }) {
  const [form, setForm] = useState({ name: "", description: "", icon_emoji: "", welcome_message: "" });
  const [banner, setBanner] = useState(null);
  const [bannerPreview, setBannerPreview] = useState(null);
  const [saving, setSaving] = useState(false);
  useEffect(() => {
    setForm({ name: community.name || "", description: community.description || "", icon_emoji: community.icon_emoji || "🌸", welcome_message: community.welcome_message || "" });
    setBannerPreview(community.banner_url || null);
  }, [community.id]);
  const save = async () => {
    setSaving(true);
    try {
      let banner_url = bannerPreview ? community.banner_url || "" : "";
      if (banner) banner_url = (await base44.integrations.Core.UploadFile({ file: banner })).file_url;
      await base44.entities.Community.update(community.id, { ...form, name: form.name.trim() || community.name, banner_url });
      toast.success("Server updated");
      onSaved?.();
    } catch (e) { toast.error(e?.message || "Could not save."); }
    setSaving(false);
  };
  return (
    <div className="space-y-4">
      <label className="relative block h-28 rounded-3xl overflow-hidden cursor-pointer group" style={{ background: "var(--accent-grad)" }}>
        {bannerPreview && <img src={bannerPreview} alt="" className="w-full h-full object-cover" />}
        <span className="absolute inset-0 flex items-center justify-center gap-2 text-white text-sm font-semibold opacity-0 group-hover:opacity-100 transition-opacity" style={{ background: "rgb(20 8 14 / 0.4)" }}><ImagePlus className="w-4 h-4" /> Change banner</span>
        <input type="file" accept="image/*" className="hidden" onChange={(e) => { const f = e.target.files?.[0]; if (f) { setBanner(f); setBannerPreview(URL.createObjectURL(f)); } e.target.value = ""; }} />
      </label>
      {bannerPreview && <button className="text-xs font-semibold" style={{ color: "var(--danger)" }} onClick={() => { setBanner(null); setBannerPreview(null); }}>Remove banner</button>}
      <div className="grid grid-cols-[72px_1fr] gap-3">
        <div><label className="label" htmlFor="ss-emoji">Icon</label><input id="ss-emoji" className="input text-center text-2xl !px-2" value={form.icon_emoji} onChange={(e) => setForm((f) => ({ ...f, icon_emoji: e.target.value.slice(0, 4) }))} /></div>
        <div><label className="label" htmlFor="ss-name">Server name</label><input id="ss-name" className="input" value={form.name} onChange={(e) => setForm((f) => ({ ...f, name: e.target.value }))} maxLength={40} /></div>
      </div>
      <div><label className="label" htmlFor="ss-desc">Description</label><textarea id="ss-desc" className="input resize-none" rows={2} value={form.description} onChange={(e) => setForm((f) => ({ ...f, description: e.target.value }))} maxLength={160} /></div>
      <div><label className="label" htmlFor="ss-welcome">Welcome message</label><input id="ss-welcome" className="input" value={form.welcome_message} onChange={(e) => setForm((f) => ({ ...f, welcome_message: e.target.value }))} maxLength={160} /></div>
      <div className="flex justify-end"><button className="btn" onClick={save} disabled={saving}>{saving ? <Loader2 className="w-4 h-4 animate-spin" /> : <><Save className="w-4 h-4" /> Save changes</>}</button></div>
    </div>
  );
}

function Roles({ community, roles, members }) {
  const confirm = useConfirm();
  const [draft, setDraft] = useState({ name: "", color: ROLE_COLORS[1] });
  const [busy, setBusy] = useState(false);
  const create = async () => {
    if (!draft.name.trim()) return;
    setBusy(true);
    try {
      await base44.entities.ServerRole.create({ community_id: community.id, name: draft.name.trim(), color: draft.color, permissions: {}, position: roles.length });
      setDraft({ name: "", color: ROLE_COLORS[(roles.length + 2) % ROLE_COLORS.length] });
    } catch (e) { toast.error(e?.message || "Could not create role."); }
    setBusy(false);
  };
  const update = (role, patch) => base44.entities.ServerRole.update(role.id, patch).catch((e) => toast.error(e?.message || "Could not update role."));
  const remove = async (role) => {
    if (!(await confirm({ title: `Delete ${role.name}?`, message: "Members will lose this role.", confirmLabel: "Delete role", danger: true }))) return;
    try {
      await base44.entities.ServerRole.delete(role.id);
      await Promise.all(members.filter((m) => (m.roles || []).includes(role.id) && m.id).map((m) => base44.entities.ServerMember.update(m.id, { roles: m.roles.filter((r) => r !== role.id) }).catch(() => {})));
    } catch (e) { toast.error(e?.message || "Could not delete role."); }
  };
  return (
    <div className="space-y-4">
      <p className="text-xs" style={{ color: "var(--text-muted)" }}>Roles color names in chat, group the member list, can be @mentioned and can restrict who posts in a channel.</p>
      <div className="space-y-2">
        <AnimatePresence initial={false}>
          {roles.map((r) => (
            <motion.div key={r.id} initial={{ opacity: 0, y: 6 }} animate={{ opacity: 1, y: 0 }} exit={{ opacity: 0, x: -20 }} className="card-sm p-2.5 flex items-center gap-2.5">
              <label className="relative w-8 h-8 rounded-xl cursor-pointer flex-shrink-0" style={{ background: r.color }} title="Change color">
                <input type="color" value={r.color} onChange={(e) => update(r, { color: e.target.value })} className="absolute inset-0 opacity-0 cursor-pointer" />
              </label>
              <input defaultValue={r.name} onBlur={(e) => e.target.value.trim() && e.target.value !== r.name && update(r, { name: e.target.value.trim() })} className="flex-1 min-w-0 bg-transparent outline-none text-sm font-bold" style={{ color: r.color }} maxLength={24} aria-label="Role name" />
              <span className="text-xs flex items-center gap-1" style={{ color: "var(--text-muted)" }}><Users className="w-3.5 h-3.5" />{members.filter((m) => (m.roles || []).includes(r.id)).length}</span>
              <button onClick={() => remove(r)} className="icon-btn w-8 h-8" aria-label={`Delete ${r.name}`}><Trash2 className="w-4 h-4" style={{ color: "var(--danger)" }} /></button>
            </motion.div>
          ))}
        </AnimatePresence>
      </div>
      <div className="card-sm p-3">
        <p className="label">New role</p>
        <div className="flex gap-2 items-center">
          <input className="input flex-1" placeholder="Role name" value={draft.name} onChange={(e) => setDraft((d) => ({ ...d, name: e.target.value }))} onKeyDown={(e) => e.key === "Enter" && create()} maxLength={24} />
          <button className="btn" onClick={create} disabled={busy || !draft.name.trim()}><Plus className="w-4 h-4" /></button>
        </div>
        <div className="flex gap-1.5 mt-2.5">{ROLE_COLORS.map((c) => <button key={c} onClick={() => setDraft((d) => ({ ...d, color: c }))} className="w-7 h-7 rounded-full transition-transform hover:scale-110" style={{ background: c, boxShadow: draft.color === c ? "0 0 0 2px var(--surface), 0 0 0 4px " + c : "none" }} aria-label={`Color ${c}`} />)}</div>
      </div>
    </div>
  );
}

function Members({ community, members, roles, usersByEmail, me, onKick, onRoleChange }) {
  return (
    <div className="space-y-1 max-h-[55vh] overflow-y-auto scroll">
      {members.map((m) => {
        const u = usersByEmail[m.user_email];
        const isOwner = m.user_email === community.owner_email;
        return (
          <div key={m.user_email} className="p-2.5 rounded-2xl hover:bg-[var(--surface-2)]">
            <div className="flex items-center gap-3">
              <Avatar src={u?.profile_picture || m.user_profile_picture} name={displayName(u || m)} size={36} />
              <div className="flex-1 min-w-0">
                <p className="text-sm font-bold truncate" style={{ color: "var(--text-primary)" }}>{displayName(u || m)} {isOwner && <span className="badge-pink ml-1">Owner</span>}</p>
                <p className="text-xs truncate" style={{ color: "var(--text-muted)" }}>{m.user_email}</p>
              </div>
              {!isOwner && m.user_email !== me.email && <button onClick={() => onKick(m)} className="btn-ghost text-xs" style={{ color: "var(--danger)" }}><UserMinus className="w-3.5 h-3.5" /> Kick</button>}
            </div>
            {!isOwner && roles.length > 0 && (
              <div className="flex flex-wrap gap-1 mt-2 ml-12">
                {roles.map((r) => {
                  const has = (m.roles || []).includes(r.id);
                  return <button key={r.id} onClick={() => onRoleChange(m, r.id, !has)} className="text-[11px] font-bold px-2 py-0.5 rounded-full" style={has ? { background: r.color, color: "#fff" } : { border: `1px solid ${r.color}66`, color: r.color }}>{r.name}</button>;
                })}
              </div>
            )}
          </div>
        );
      })}
    </div>
  );
}

function DangerZone({ community }) {
  const navigate = useNavigate();
  const confirm = useConfirm();
  const [busy, setBusy] = useState(false);
  const del = async () => {
    if (!(await confirm({ title: `Delete ${community.name}?`, message: "The server, its channels and roles will be deleted for everyone. This can't be undone.", confirmLabel: "Delete server", danger: true }))) return;
    setBusy(true);
    try {
      const [channels, roles, members] = await Promise.all([
        base44.entities.ServerChannel.filter({ community_id: community.id }),
        base44.entities.ServerRole.filter({ community_id: community.id }),
        base44.entities.ServerMember.filter({ community_id: community.id }),
      ]);
      await Promise.all([...channels.map((c) => base44.entities.ServerChannel.delete(c.id)), ...roles.map((r) => base44.entities.ServerRole.delete(r.id)), ...members.map((m) => base44.entities.ServerMember.delete(m.id))].map((p) => p.catch(() => {})));
      await base44.entities.Community.delete(community.id);
      toast.success("Server deleted");
      navigate("/Communities");
    } catch (e) { toast.error(e?.message || "Could not delete server."); setBusy(false); }
  };
  return (
    <div className="rounded-3xl p-5" style={{ border: "1px solid rgb(224 82 107 / 0.35)", background: "rgb(224 82 107 / 0.06)" }}>
      <div className="flex items-start gap-3">
        <AlertTriangle className="w-5 h-5 mt-0.5 flex-shrink-0" style={{ color: "var(--danger)" }} />
        <div className="flex-1">
          <p className="font-bold text-sm" style={{ color: "var(--text-primary)" }}>Delete this server</p>
          <p className="text-xs mt-1" style={{ color: "var(--text-muted)" }}>Removes the server, all channels and roles.</p>
        </div>
        <button className="btn-danger text-xs" onClick={del} disabled={busy}>{busy ? <Loader2 className="w-4 h-4 animate-spin" /> : "Delete"}</button>
      </div>
    </div>
  );
}

export default function ServerSettingsModal({ open, community, members, roles, usersByEmail, me, onClose, onKick, onRoleChange }) {
  const [tab, setTab] = useState("overview");
  const canDelete = me?.role === "admin" || me?.email === community?.owner_email;
  const tabs = [
    { id: "overview", label: "Overview", icon: Wrench },
    { id: "roles", label: "Roles", icon: Shield, count: roles.length },
    { id: "members", label: "Members", icon: Users, count: members.length },
    ...(canDelete ? [{ id: "danger", label: "Danger", icon: AlertTriangle }] : []),
  ];
  return (
    <Modal open={open} onClose={onClose} title="Server settings" subtitle={community?.name} size="lg">
      {community && (
        <>
          <Segmented options={tabs} value={tab} onChange={setTab} size="sm" className="mb-5" />
          <AnimatePresence mode="wait">
            <motion.div key={tab} initial={{ opacity: 0, y: 8 }} animate={{ opacity: 1, y: 0 }} exit={{ opacity: 0, y: -6 }} transition={{ duration: 0.18 }}>
              {tab === "overview" && <Overview community={community} />}
              {tab === "roles" && <Roles community={community} roles={roles} members={members} />}
              {tab === "members" && <Members community={community} members={members} roles={roles} usersByEmail={usersByEmail} me={me} onKick={onKick} onRoleChange={onRoleChange} />}
              {tab === "danger" && <DangerZone community={community} />}
            </motion.div>
          </AnimatePresence>
        </>
      )}
    </Modal>
  );
}
