import React, { useMemo } from "react";
import { Link } from "react-router-dom";
import { motion } from "framer-motion";
import { Calendar, Check, Crown, MessageSquare, Plus, UserMinus, UserRound } from "lucide-react";
import Popover from "@/components/common/Popover";
import Avatar from "@/components/common/Avatar";
import LevelBadge from "@/components/profile/LevelBadge";
import NitroBadge from "@/components/profile/NitroBadge";
import { getNameStyle } from "@/components/profile/NameStylePicker";
import { displayName, isNitro, isOnline, profileLink, timeAgo } from "@/lib/format";

// Discord-style member card: opens next to the clicked avatar/name on desktop
// and as a bottom sheet on phones.
export default function ProfileCard({ target, onClose, user, member, roles = [], community, me, canManage, onRoleChange, onKick }) {
  const open = !!target;
  const email = target?.email;
  const u = user || (member ? { email: member.user_email, display_name: member.user_display_name, profile_picture: member.user_profile_picture } : { email });
  const name = member?.nickname || displayName(u);
  const memberRoles = roles.filter((r) => (member?.roles || []).includes(r.id));
  const top = memberRoles[0];
  const isOwner = community?.owner_email === email;
  const nitro = isNitro(u);
  const online = isOnline(u);
  // Stable ref object per opened target (Popover re-measures when it changes).
  const anchorRef = useMemo(() => ({ current: target?.anchor || null }), [target]);

  return (
    <Popover open={open} onClose={onClose} anchorRef={anchorRef} placement={target?.placement || "right-start"} width={320} label={`${name}'s profile`} offset={12}>
      {email && (
        <div>
          <div className="h-24 relative" style={{ background: u.banner_url ? undefined : `linear-gradient(135deg, ${top?.color || "rgb(var(--accent-2-rgb))"}, rgb(var(--accent-rgb)))` }}>
            {u.banner_url && <img src={u.banner_url} alt="" className="w-full h-full object-cover" />}
          </div>
          <div className="px-5 pb-5 -mt-11">
            <div className="flex items-end justify-between">
              <motion.span initial={{ scale: 0.8, opacity: 0 }} animate={{ scale: 1, opacity: 1 }} transition={{ type: "spring", stiffness: 400, damping: 22 }} className="rounded-full" style={{ boxShadow: "0 0 0 5px var(--surface)" }}>
                <Avatar src={u.profile_picture} name={name} size={84} online={online} nitro={nitro} />
              </motion.span>
              <div className="flex gap-1 pb-1">
                {isOwner && <span className="badge-pink" title="Server owner"><Crown className="w-3 h-3" /> Owner</span>}
                <NitroBadge active={nitro} />
              </div>
            </div>

            <div className="mt-3 rounded-2xl p-3.5" style={{ background: "var(--surface-2)" }}>
              <p className="text-xl leading-tight truncate" style={getNameStyle(u.name_style).preview()}>{name}</p>
              <p className="text-xs truncate mt-0.5" style={{ color: "var(--text-muted)" }}>{u.email}</p>
              <div className="flex flex-wrap items-center gap-1.5 mt-2">
                <LevelBadge xp={u.xp || 0} />
                <span className="text-[11px] font-semibold" style={{ color: online ? "var(--success)" : "var(--text-muted)" }}>{online ? "● Online" : u.last_seen ? `Active ${timeAgo(u.last_seen)}` : "Offline"}</span>
              </div>

              {u.bio && (
                <>
                  <div className="divider my-3" />
                  <p className="eyebrow mb-1">About me</p>
                  <p className="text-sm leading-relaxed" style={{ color: "var(--text-secondary)" }}>{u.bio}</p>
                </>
              )}

              <div className="divider my-3" />
              <p className="eyebrow mb-1.5">Member since</p>
              <p className="text-xs flex items-center gap-3" style={{ color: "var(--text-secondary)" }}>
                <span className="flex items-center gap-1"><Calendar className="w-3.5 h-3.5" /> Site: {new Date(u.created_date || Date.now()).toLocaleDateString(undefined, { month: "short", year: "numeric" })}</span>
                {member?.created_date && <span className="flex items-center gap-1"><span className="text-sm leading-none">{community?.icon_emoji || "💬"}</span> {new Date(member.created_date).toLocaleDateString(undefined, { month: "short", day: "numeric", year: "numeric" })}</span>}
              </p>

              {(memberRoles.length > 0 || (canManage && !isOwner && roles.length > 0)) && (
                <>
                  <div className="divider my-3" />
                  <p className="eyebrow mb-1.5">Roles</p>
                  <div className="flex flex-wrap gap-1.5">
                    {(canManage && !isOwner ? roles : memberRoles).map((r) => {
                      const has = (member?.roles || []).includes(r.id);
                      const editable = canManage && !isOwner;
                      return (
                        <motion.button
                          key={r.id}
                          whileTap={editable ? { scale: 0.92 } : undefined}
                          disabled={!editable}
                          onClick={() => editable && onRoleChange?.(member, r.id, !has)}
                          className="text-[11px] font-bold pl-1.5 pr-2 py-1 rounded-full flex items-center gap-1 transition-colors disabled:cursor-default"
                          style={has ? { background: `${r.color}24`, color: r.color, boxShadow: `inset 0 0 0 1px ${r.color}55` } : { color: "var(--text-muted)", boxShadow: "inset 0 0 0 1px var(--border-strong)" }}
                          title={editable ? (has ? `Remove ${r.name}` : `Give ${r.name}`) : r.name}
                        >
                          {has ? <span className="w-2.5 h-2.5 rounded-full" style={{ background: r.color }} /> : <Plus className="w-3 h-3" />}
                          {r.name}
                          {editable && has && <Check className="w-3 h-3" />}
                        </motion.button>
                      );
                    })}
                  </div>
                </>
              )}
            </div>

            <div className="flex gap-2 mt-3">
              <Link to={profileLink(email)} onClick={onClose} className="btn-outline flex-1 !px-3"><UserRound className="w-4 h-4" /> Profile</Link>
              {email !== me?.email && <Link to={`/DirectMessages?with=${encodeURIComponent(email)}`} onClick={onClose} className="btn flex-1 !px-3"><MessageSquare className="w-4 h-4" /> Message</Link>}
              {canManage && !isOwner && member && email !== me?.email && (
                <button onClick={() => { onClose(); onKick?.(member); }} className="icon-btn icon-btn-bordered !w-10 !h-10" style={{ color: "var(--danger)" }} title="Kick from server" aria-label="Kick from server"><UserMinus className="w-4 h-4" /></button>
              )}
            </div>
          </div>
        </div>
      )}
    </Popover>
  );
}
