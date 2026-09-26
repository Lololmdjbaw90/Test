import React, { useEffect, useMemo, useState } from "react";
import { useNavigate } from "react-router-dom";
import { AnimatePresence, motion } from "framer-motion";
import { AlertTriangle, AtSign, ChevronDown, ChevronUp, ImagePlus, Loader2, Lock, Plus, Save, Shield, Trash2, UserMinus, Users, Wrench } from "lucide-react";
import { base44 } from "@/api/base44Client";
import { toast } from "@/lib/toast";
import { displayName } from "@/lib/format";
import Modal, { useConfirm } from "@/components/common/Modal";
import { Segmented, Toggle } from "@/components/common/Controls";
import { EVERYONE_DEFAULTS, PERMISSION_GROUPS, canActOn, canEditRole, computePermissions, everyonePerms, normalizePerms } from "@/lib/permissions";
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
        {bannerPreview && <img loading="lazy" decoding="async" src={bannerPreview} alt="" className="w-full h-full object-cover" />}
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

function PermissionList({ values, onToggle, canToggle, keys, inherited = {} }) {
  return (
    <div className="space-y-4">
      {PERMISSION_GROUPS.map((g) => {
        const items = g.items.filter((i) => !keys || keys.includes(i.key));
        if (!items.length) return null;
        return (
          <div key={g.label}>
            <p className="eyebrow mb-2">{g.label}</p>
            <div className="space-y-3">
              {items.map((i) => {
                const allowed = canToggle(i.key);
                return (
                  <div key={i.key} className={allowed ? "" : "opacity-50 pointer-events-none"} title={allowed ? undefined : "You can only give permissions you have yourself"}>
                    <Toggle checked={!!values[i.key]} onChange={(v) => onToggle(i.key, v)} label={i.label} description={!values[i.key] && inherited[i.key] ? `${i.desc} Everyone already has this.` : i.desc} />
                  </div>
                );
              })}
            </div>
          </div>
        );
      })}
    </div>
  );
}

function Roles({ community, roles, members, actor }) {
  const confirm = useConfirm();
  const sorted = useMemo(() => [...roles].sort((a, b) => (a.position ?? 0) - (b.position ?? 0)), [roles]);
  const [selected, setSelected] = useState("everyone");
  const [draft, setDraft] = useState({ name: "", color: ROLE_COLORS[1] });
  const [busy, setBusy] = useState(false);
  const role = sorted.find((r) => r.id === selected);
  const editable = role ? canEditRole(actor, role) : !!actor.perms.manage_roles;
  // Non-owners can't hand out permissions they don't have.
  const canGive = (key) => editable && (actor.top === -Infinity || !!actor.perms[key]);

  const create = async () => {
    if (!draft.name.trim()) return;
    setBusy(true);
    try {
      const r = await base44.entities.ServerRole.create({ community_id: community.id, name: draft.name.trim(), color: draft.color, permissions: {}, position: sorted.length ? Math.max(...sorted.map((x) => x.position ?? 0)) + 1 : 0 });
      setDraft({ name: "", color: ROLE_COLORS[(roles.length + 2) % ROLE_COLORS.length] });
      setSelected(r.id);
    } catch (e) { toast.error(e?.message || "Could not create role."); }
    setBusy(false);
  };
  const update = (r, patch) => base44.entities.ServerRole.update(r.id, patch).catch((e) => toast.error(e?.message || "Could not update role."));
  const togglePerm = (key, value) => {
    if (role) update(role, { permissions: { ...normalizePerms(role.permissions), [key]: value } });
    else base44.entities.Community.update(community.id, { everyone_permissions: { ...everyonePerms(community), [key]: value } }).catch((e) => toast.error(e?.message || "Could not update."));
  };
  // Swap with the neighbour above/below (both must be below your own role).
  const move = async (r, dir) => {
    const i = sorted.findIndex((x) => x.id === r.id);
    const other = sorted[i + dir];
    if (!other || !canEditRole(actor, other)) return;
    const next = [...sorted];
    [next[i], next[i + dir]] = [next[i + dir], next[i]];
    await Promise.all(next.map((x, pos) => (x.position !== pos ? update(x, { position: pos }) : null)));
  };
  const remove = async (r) => {
    if (!(await confirm({ title: `Delete ${r.name}?`, message: "Members will lose this role and its permissions.", confirmLabel: "Delete role", danger: true }))) return;
    try {
      await base44.entities.ServerRole.delete(r.id);
      await Promise.all(members.filter((m) => (m.roles || []).includes(r.id) && m.id).map((m) => base44.entities.ServerMember.update(m.id, { roles: m.roles.filter((x) => x !== r.id) }).catch(() => {})));
      setSelected("everyone");
    } catch (e) { toast.error(e?.message || "Could not delete role."); }
  };

  return (
    <div className="grid sm:grid-cols-[190px_1fr] gap-4">
      <div className="space-y-1.5">
        <p className="text-[11px] mb-1" style={{ color: "var(--text-muted)" }}>Higher roles outrank lower ones. Members get every permission from all their roles.</p>
        {sorted.map((r, i) => {
          const can = canEditRole(actor, r);
          return (
            <div key={r.id} className="flex items-center gap-1 rounded-xl transition-colors" style={selected === r.id ? { background: "var(--pink-soft)" } : undefined}>
              <button onClick={() => setSelected(r.id)} className="flex-1 min-w-0 flex items-center gap-2 px-2.5 py-2 text-left">
                <span className="w-3 h-3 rounded-full flex-shrink-0" style={{ background: r.color }} />
                <span className="text-sm font-bold truncate" style={{ color: r.color }}>{r.name}</span>
                {!can && <Lock className="w-3 h-3 flex-shrink-0" style={{ color: "var(--text-muted)" }} />}
              </button>
              {can && (
                <span className="flex flex-col -my-0.5 pr-1">
                  <button onClick={() => move(r, -1)} disabled={i === 0 || !canEditRole(actor, sorted[i - 1])} className="icon-btn w-6 h-4 disabled:opacity-20" aria-label={`Move ${r.name} up`}><ChevronUp className="w-3.5 h-3.5" /></button>
                  <button onClick={() => move(r, 1)} disabled={i === sorted.length - 1} className="icon-btn w-6 h-4 disabled:opacity-20" aria-label={`Move ${r.name} down`}><ChevronDown className="w-3.5 h-3.5" /></button>
                </span>
              )}
            </div>
          );
        })}
        <button onClick={() => setSelected("everyone")} className="w-full flex items-center gap-2 px-2.5 py-2 rounded-xl text-left transition-colors" style={selected === "everyone" ? { background: "var(--pink-soft)" } : undefined}>
          <AtSign className="w-3.5 h-3.5" style={{ color: "var(--text-muted)" }} /><span className="text-sm font-bold" style={{ color: "var(--text-secondary)" }}>everyone</span>
        </button>
        {actor.perms.manage_roles && (
          <div className="pt-2">
            <div className="flex gap-1.5">
              <input className="input !min-h-0 !py-2 text-sm" placeholder="New role" value={draft.name} onChange={(e) => setDraft((d) => ({ ...d, name: e.target.value }))} onKeyDown={(e) => e.key === "Enter" && create()} maxLength={24} aria-label="New role name" />
              <button className="btn !px-3" onClick={create} disabled={busy || !draft.name.trim()} aria-label="Create role"><Plus className="w-4 h-4" /></button>
            </div>
            <div className="flex flex-wrap gap-1.5 mt-2">{ROLE_COLORS.map((c) => <button key={c} onClick={() => setDraft((d) => ({ ...d, color: c }))} className="w-5 h-5 rounded-full" style={{ background: c, boxShadow: draft.color === c ? "0 0 0 2px var(--surface), 0 0 0 4px " + c : "none" }} aria-label={`Color ${c}`} />)}</div>
          </div>
        )}
      </div>

      <div className="card-sm p-4 min-w-0">
        {role ? (
          <div className="space-y-4">
            <div className="flex items-center gap-2.5">
              <label className={`relative w-9 h-9 rounded-xl flex-shrink-0 ${editable ? "cursor-pointer" : ""}`} style={{ background: role.color }} title="Change color">
                {editable && <input type="color" value={role.color} onChange={(e) => update(role, { color: e.target.value })} className="absolute inset-0 opacity-0 cursor-pointer" />}
              </label>
              <input key={role.id} defaultValue={role.name} disabled={!editable} onBlur={(e) => e.target.value.trim() && e.target.value !== role.name && update(role, { name: e.target.value.trim() })} className="input flex-1 font-bold" style={{ color: role.color }} maxLength={24} aria-label="Role name" />
              {editable && <button onClick={() => remove(role)} className="icon-btn icon-btn-bordered" aria-label={`Delete ${role.name}`}><Trash2 className="w-4 h-4" style={{ color: "var(--danger)" }} /></button>}
            </div>
            <p className="text-xs flex items-center gap-1.5" style={{ color: "var(--text-muted)" }}><Users className="w-3.5 h-3.5" /> {members.filter((m) => (m.roles || []).includes(role.id)).length} members{!editable && " · you can't edit roles at or above your own"}</p>
            {normalizePerms(role.permissions).administrator && <p className="text-xs font-semibold rounded-xl px-3 py-2" style={{ background: "rgb(240 160 32 / 0.12)", color: "#b7791f" }}>Administrator overrides everything below.</p>}
            <PermissionList values={normalizePerms(role.permissions)} onToggle={togglePerm} canToggle={canGive} inherited={everyonePerms(community)} />
          </div>
        ) : (
          <div className="space-y-4">
            <div>
              <p className="font-bold text-sm flex items-center gap-1.5" style={{ color: "var(--text-primary)" }}><AtSign className="w-4 h-4" /> everyone</p>
              <p className="text-xs mt-0.5" style={{ color: "var(--text-muted)" }}>What every member can do. Roles can add more on top.</p>
            </div>
            <PermissionList values={everyonePerms(community)} onToggle={togglePerm} canToggle={canGive} keys={Object.keys(EVERYONE_DEFAULTS)} />
          </div>
        )}
      </div>
    </div>
  );
}

function Members({ community, members, roles, usersByEmail, me, actor, onKick, onRoleChange }) {
  return (
    <div className="space-y-1 max-h-[55vh] overflow-y-auto scroll">
      {members.map((m) => {
        const u = usersByEmail[m.user_email];
        const isOwner = m.user_email === community.owner_email;
        const target = { email: m.user_email, ...computePermissions({ community, member: m, roles, email: m.user_email }) };
        const outranks = canActOn(actor, target, community);
        const assignable = roles.filter((r) => canEditRole(actor, r));
        return (
          <div key={m.user_email} className="p-2.5 rounded-2xl hover:bg-[var(--surface-2)]">
            <div className="flex items-center gap-3">
              <Avatar src={u?.profile_picture || m.user_profile_picture} name={displayName(u || m)} size={36} />
              <div className="flex-1 min-w-0">
                <p className="text-sm font-bold truncate" style={{ color: "var(--text-primary)" }}>{displayName(u || m)} {isOwner && <span className="badge-pink ml-1">Owner</span>}</p>
                <p className="text-xs truncate" style={{ color: "var(--text-muted)" }}>{m.user_email}</p>
              </div>
              {outranks && actor.perms.kick_members && m.user_email !== me.email && <button onClick={() => onKick(m)} className="btn-ghost text-xs" style={{ color: "var(--danger)" }}><UserMinus className="w-3.5 h-3.5" /> Kick</button>}
            </div>
            {!isOwner && roles.length > 0 && (
              <div className="flex flex-wrap gap-1 mt-2 ml-12">
                {roles.map((r) => {
                  const has = (m.roles || []).includes(r.id);
                  const can = outranks && assignable.includes(r);
                  if (!has && !can) return null;
                  return <button key={r.id} disabled={!can} onClick={() => onRoleChange(m, r.id, !has)} className="text-[11px] font-bold px-2 py-0.5 rounded-full disabled:cursor-default" style={has ? { background: r.color, color: "#fff" } : { border: `1px solid ${r.color}66`, color: r.color }}>{r.name}</button>;
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

export default function ServerSettingsModal({ open, community, members, roles, usersByEmail, me, actor, onClose, onKick, onRoleChange }) {
  const perms = actor?.perms || {};
  const canDelete = me?.role === "admin" || me?.email === community?.owner_email;
  // Only the sections you have permission for.
  const tabs = [
    ...(perms.manage_server ? [{ id: "overview", label: "Overview", icon: Wrench }] : []),
    ...(perms.manage_roles ? [{ id: "roles", label: "Roles", icon: Shield, count: roles.length }] : []),
    ...(perms.manage_roles || perms.kick_members ? [{ id: "members", label: "Members", icon: Users, count: members.length }] : []),
    ...(canDelete ? [{ id: "danger", label: "Danger", icon: AlertTriangle }] : []),
  ];
  const [tabPick, setTab] = useState(null);
  const tab = tabs.some((t) => t.id === tabPick) ? tabPick : tabs[0]?.id;
  return (
    <Modal open={open} onClose={onClose} title="Server settings" subtitle={community?.name} size="max-w-3xl">
      {community && (
        <>
          <Segmented options={tabs} value={tab} onChange={setTab} size="sm" className="mb-5" />
          <AnimatePresence mode="wait">
            <motion.div key={tab} initial={{ opacity: 0, y: 8 }} animate={{ opacity: 1, y: 0 }} exit={{ opacity: 0, y: -6 }} transition={{ duration: 0.18 }}>
              {tab === "overview" && <Overview community={community} />}
              {tab === "roles" && <Roles community={community} roles={roles} members={members} actor={actor} />}
              {tab === "members" && <Members community={community} members={members} roles={roles} usersByEmail={usersByEmail} me={me} actor={actor} onKick={onKick} onRoleChange={onRoleChange} />}
              {tab === "danger" && <DangerZone community={community} />}
            </motion.div>
          </AnimatePresence>
        </>
      )}
    </Modal>
  );
}
