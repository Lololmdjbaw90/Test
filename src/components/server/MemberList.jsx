import React, { useState } from "react";
import { Link } from "react-router-dom";
import { Crown, X, UserMinus, ChevronDown } from "lucide-react";

function Avatar({ member }) {
  const [err,setErr]=useState(false);
  if(member.user_profile_picture&&!err)return<img src={member.user_profile_picture} onError={()=>setErr(true)} className="w-8 h-8 rounded-full object-cover flex-shrink-0" alt=""/>;
  return<div className="w-8 h-8 rounded-full flex items-center justify-center text-white text-xs font-semibold flex-shrink-0" style={{ background:"var(--accent-pink)" }}>{member.user_display_name?.[0]?.toUpperCase()||"?"}</div>;
}

function MemberItem({ member, allRoles, isOwner, canManage, onKick, onRoleChange }) {
  const [expanded,setExpanded]=useState(false);
  const memberRoles=allRoles.filter(r=>member.roles?.includes(r.id));
  const topRole=memberRoles[0];
  return(
    <div className="px-2">
      <div className="flex items-center gap-2 px-2 py-1.5 rounded-lg cursor-pointer transition-all group" onClick={()=>setExpanded(!expanded)} onMouseEnter={e=>e.currentTarget.style.background="var(--pink-soft)"} onMouseLeave={e=>e.currentTarget.style.background="transparent"}>
        <Avatar member={member}/>
        <div className="flex-1 min-w-0">
          <div className="flex items-center gap-1.5">{isOwner&&<Crown className="w-3 h-3 flex-shrink-0" style={{ color:"#f59e0b" }}/>}<p className="text-xs font-medium truncate" style={{ color:"var(--text-primary)" }}>{member.nickname||member.user_display_name}</p></div>
          {topRole&&<span className="text-[9px] font-semibold" style={{ color:topRole.color }}>{topRole.name}</span>}
        </div>
        {canManage&&!isOwner&&<ChevronDown className="w-3 h-3 opacity-0 group-hover:opacity-100 flex-shrink-0" style={{ color:"var(--text-muted)" }}/>}
      </div>
      {expanded&&canManage&&!isOwner&&<div className="ml-10 mb-1 p-2 rounded-xl space-y-2" style={{ background:"var(--pink-soft)",border:"1px solid var(--border-c)" }}>
        <p className="text-[10px] font-semibold uppercase tracking-wider mb-1" style={{ color:"var(--text-muted)" }}>Roles</p>
        <div className="flex flex-wrap gap-1">{allRoles.map(role=>{const has=member.roles?.includes(role.id);return<button key={role.id} onClick={()=>onRoleChange(member,role.id,!has)} className="text-[10px] font-semibold px-2 py-0.5 rounded-full transition-all" style={has?{background:role.color,color:"white"}:{background:"var(--surface)",color:role.color,border:`1px solid ${role.color}`}}>{role.name}</button>;})}</div>
        <button onClick={()=>onKick(member)} className="flex items-center gap-1 text-[10px] font-semibold text-red-400 mt-1"><UserMinus className="w-3 h-3"/> Kick from server</button>
        <Link to={`/Profile?email=${encodeURIComponent(member.user_email)}`} className="flex items-center gap-1 text-[10px] font-semibold" style={{ color:"var(--accent-rose)" }}>View Profile</Link>
      </div>}
    </div>
  );
}

export default function MemberList({ members, roles, community, me, onKick, onRoleChange, onClose }) {
  const canManage=me?.email===community?.owner_email||me?.role==="admin";
  return(
    <div className="flex flex-col h-full w-full border-l" style={{ background:"var(--surface)",borderColor:"var(--border-c)" }}>
      <div className="flex-shrink-0 h-12 flex items-center justify-between px-3 border-b" style={{ borderColor:"var(--border-c)" }}>
        <span className="font-semibold text-sm" style={{ color:"var(--text-primary)" }}>Members — {members.length}</span>
        <button onClick={onClose} className="w-7 h-7 rounded-lg flex items-center justify-center" style={{ background:"var(--pink-soft)" }}><X className="w-3.5 h-3.5" style={{ color:"var(--text-muted)" }}/></button>
      </div>
      <div className="flex-1 overflow-y-auto scroll py-2 space-y-0.5">
        {members.filter(m=>m.user_email===community?.owner_email).map(m=><MemberItem key={m.user_email} member={m} allRoles={roles} isOwner={true} canManage={canManage} onKick={onKick} onRoleChange={onRoleChange}/>)}
        {members.filter(m=>m.user_email!==community?.owner_email).map(m=><MemberItem key={m.user_email} member={m} allRoles={roles} isOwner={false} canManage={canManage} onKick={onKick} onRoleChange={onRoleChange}/>)}
      </div>
    </div>
  );
}