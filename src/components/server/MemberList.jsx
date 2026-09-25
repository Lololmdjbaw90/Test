import React, { useMemo } from "react";
import { Crown, X } from "lucide-react";
import { isOnline } from "@/lib/format";
import Avatar from "@/components/common/Avatar";

function MemberRow({ member, roles, user, isOwner, onOpenProfile }) {
  const top = roles.find((r) => (member.roles || []).includes(r.id));
  const online = isOnline(user);
  const name = member.nickname || user?.display_name || member.user_display_name || member.user_email;
  return (
    <button
      onClick={(e) => onOpenProfile(member.user_email, e.currentTarget)}
      className="w-full flex items-center gap-2.5 px-2 py-1.5 rounded-xl text-left transition-colors hover:bg-[var(--surface-2)]"
      style={{ opacity: online ? 1 : 0.6 }}
      aria-label={`View ${name}'s profile`}
    >
      <Avatar src={user?.profile_picture || member.user_profile_picture} name={name} size={34} online={online} />
      <span className="flex-1 min-w-0">
        <span className="text-sm font-semibold truncate flex items-center gap-1" style={{ color: top?.color || "var(--text-primary)" }}>{name}{isOwner && <Crown className="w-3.5 h-3.5 flex-shrink-0" style={{ color: "#f0a020" }} />}</span>
        {user?.bio && <span className="block text-[11px] truncate" style={{ color: "var(--text-muted)" }}>{user.bio}</span>}
      </span>
    </button>
  );
}

export default function MemberList({ members, roles, usersByEmail, community, onOpenProfile, onClose }) {
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
      <div className="flex-1 overflow-y-auto scroll px-2 py-3 space-y-4 safe-bottom">
        {groups.map((g) => (
          <div key={g.label}>
            <p className="eyebrow px-2 mb-1 flex items-center gap-1.5">{g.color && <span className="w-2 h-2 rounded-full" style={{ background: g.color }} />}{g.label} — {g.list.length}</p>
            {g.list.map((m) => <MemberRow key={m.user_email} member={m} roles={roles} user={usersByEmail[m.user_email]} isOwner={m.user_email === community.owner_email} onOpenProfile={onOpenProfile} />)}
          </div>
        ))}
      </div>
    </div>
  );
}
