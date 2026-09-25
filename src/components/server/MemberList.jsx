import React, { useMemo, useState } from "react";
import { Link } from "react-router-dom";
import { AnimatePresence, motion } from "framer-motion";
import { Crown, MessageSquare, UserMinus, X } from "lucide-react";
import { displayName, isOnline, profileLink } from "@/lib/format";
import Avatar from "@/components/common/Avatar";

function MemberRow({ member, roles, user, isOwner, canManage, me, onKick, onRoleChange }) {
  const [open, setOpen] = useState(false);
  const memberRoles = roles.filter((r) => (member.roles || []).includes(r.id));
  const top = memberRoles[0];
  const online = isOnline(user);
  const name = member.nickname || user?.display_name || member.user_display_name || member.user_email;
  return (
    <div className="relative">
      <button onClick={() => setOpen((v) => !v)} className="w-full flex items-center gap-2.5 px-2 py-1.5 rounded-xl text-left transition-colors hover:bg-[var(--surface-2)]" style={{ opacity: online ? 1 : 0.6 }} aria-expanded={open}>
        <Avatar src={user?.profile_picture || member.user_profile_picture} name={name} size={34} online={online} />
        <span className="flex-1 min-w-0">
          <span className="text-sm font-semibold truncate flex items-center gap-1" style={{ color: top?.color || "var(--text-primary)" }}>{name}{isOwner && <Crown className="w-3.5 h-3.5 flex-shrink-0" style={{ color: "#f0a020" }} />}</span>
          {user?.bio && <span className="block text-[11px] truncate" style={{ color: "var(--text-muted)" }}>{user.bio}</span>}
        </span>
      </button>
      <AnimatePresence>
        {open && (
          <>
            <div className="fixed inset-0 z-30" onClick={() => setOpen(false)} />
            <motion.div initial={{ opacity: 0, x: 10, scale: 0.97 }} animate={{ opacity: 1, x: 0, scale: 1 }} exit={{ opacity: 0, x: 10 }} className="absolute right-full mr-2 top-0 z-40 w-64 rounded-3xl overflow-hidden" style={{ background: "var(--surface)", border: "1px solid var(--border-c)", boxShadow: "var(--shadow-lg)" }}>
              <div className="h-14" style={{ background: top?.color ? `linear-gradient(135deg, ${top.color}, rgb(var(--accent-rgb)))` : "var(--accent-grad)" }} />
              <div className="px-4 pb-4 -mt-7">
                <Avatar src={user?.profile_picture || member.user_profile_picture} name={name} size={56} style={{ boxShadow: "0 0 0 4px var(--surface)", borderRadius: 9999 }} />
                <p className="font-display text-lg font-semibold mt-2" style={{ color: "var(--text-primary)" }}>{name}</p>
                <p className="text-xs mb-3" style={{ color: "var(--text-muted)" }}>{member.user_email}</p>
                {memberRoles.length > 0 && <div className="flex flex-wrap gap-1 mb-3">{memberRoles.map((r) => <span key={r.id} className="text-[11px] font-bold px-2 py-0.5 rounded-full flex items-center gap-1" style={{ background: `${r.color}1f`, color: r.color }}><span className="w-2 h-2 rounded-full" style={{ background: r.color }} />{r.name}</span>)}</div>}
                {canManage && !isOwner && roles.length > 0 && (
                  <>
                    <p className="eyebrow mb-1.5">Roles</p>
                    <div className="flex flex-wrap gap-1 mb-3">
                      {roles.map((r) => {
                        const has = (member.roles || []).includes(r.id);
                        return <button key={r.id} onClick={() => onRoleChange(member, r.id, !has)} className="text-[11px] font-bold px-2 py-1 rounded-full transition-colors" style={has ? { background: r.color, color: "#fff" } : { border: `1px solid ${r.color}`, color: r.color }}>{r.name}</button>;
                      })}
                    </div>
                  </>
                )}
                <div className="flex gap-2">
                  <Link to={profileLink(member.user_email)} className="btn-outline text-xs flex-1">Profile</Link>
                  {member.user_email !== me.email && <Link to={`/DirectMessages?with=${encodeURIComponent(member.user_email)}`} className="btn-outline text-xs !px-3" aria-label="Message"><MessageSquare className="w-3.5 h-3.5" /></Link>}
                  {canManage && !isOwner && member.user_email !== me.email && <button onClick={() => { setOpen(false); onKick(member); }} className="btn-outline text-xs !px-3" style={{ color: "var(--danger)" }} aria-label="Kick"><UserMinus className="w-3.5 h-3.5" /></button>}
                </div>
              </div>
            </motion.div>
          </>
        )}
      </AnimatePresence>
    </div>
  );
}

export default function MemberList({ members, roles, usersByEmail, community, me, canManage, onKick, onRoleChange, onClose }) {
  const groups = useMemo(() => {
    const out = [];
    const used = new Set();
    roles.forEach((r) => {
      const list = members.filter((m) => !used.has(m.user_email) && (m.roles || []).includes(r.id));
      list.forEach((m) => used.add(m.user_email));
      if (list.length) out.push({ label: r.name, color: r.color, list });
    });
    const rest = members.filter((m) => !used.has(m.user_email));
    if (rest.length) out.push({ label: "Members", list: rest });
    return out.map((g) => ({ ...g, list: [...g.list].sort((a, b) => Number(isOnline(usersByEmail[b.user_email])) - Number(isOnline(usersByEmail[a.user_email]))) }));
  }, [members, roles, usersByEmail]);
  const online = members.filter((m) => isOnline(usersByEmail[m.user_email])).length;

  return (
    <div className="flex flex-col h-full w-full glass" style={{ borderLeft: "1px solid var(--border-c)" }}>
      <div className="h-14 flex-shrink-0 flex items-center px-4 gap-2" style={{ borderBottom: "1px solid var(--border-c)" }}>
        <span className="font-bold text-sm flex-1" style={{ color: "var(--text-primary)" }}>Members <span style={{ color: "var(--text-muted)" }}>· {online} online</span></span>
        <button onClick={onClose} className="icon-btn w-8 h-8" aria-label="Close members"><X className="w-4 h-4" /></button>
      </div>
      <div className="flex-1 overflow-y-auto scroll px-2 py-3 space-y-4">
        {groups.map((g) => (
          <div key={g.label}>
            <p className="eyebrow px-2 mb-1 flex items-center gap-1.5">{g.color && <span className="w-2 h-2 rounded-full" style={{ background: g.color }} />}{g.label} — {g.list.length}</p>
            {g.list.map((m) => <MemberRow key={m.user_email} member={m} roles={roles} user={usersByEmail[m.user_email]} isOwner={m.user_email === community.owner_email} canManage={canManage} me={me} onKick={onKick} onRoleChange={onRoleChange} />)}
          </div>
        ))}
      </div>
    </div>
  );
}
