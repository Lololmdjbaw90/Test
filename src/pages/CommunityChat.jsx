import React, { useState, useEffect, useCallback } from "react";
import { base44 } from "@/api/base44Client";
import { Loader2, ArrowLeft, Users, Menu } from "lucide-react";
import { Link } from "react-router-dom";
import { AnimatePresence, motion } from "framer-motion";
import ServerSidebar from "../components/server/ServerSidebar";
import ChatArea from "../components/server/ChatArea";
import MemberList from "../components/server/MemberList";
import ServerSettingsModal from "../components/server/ServerSettingsModal";
import ChannelSettingsModal from "../components/server/ChannelSettingsModal";
import AddChannelModal from "../components/server/AddChannelModal";
import VoiceChannelView from "../components/server/VoiceChannelView";

export default function CommunityChatPage() {
  const params = new URLSearchParams(window.location.search), communityId = params.get("id");
  const [community,setCommunity]=useState(null),[channels,setChannels]=useState([]),[roles,setRoles]=useState([]),[members,setMembers]=useState([]),[me,setMe]=useState(null),[myMember,setMyMember]=useState(null),[activeChannel,setActiveChannel]=useState(null),[loading,setLoading]=useState(true);
  const [showMembers,setShowMembers]=useState(false),[showSidebar,setShowSidebar]=useState(false),[showServerSettings,setShowServerSettings]=useState(false),[channelSettings,setChannelSettings]=useState(null),[showAddChannel,setShowAddChannel]=useState(false);
  const isOwner=me?.email===community?.owner_email,isAdmin=me?.role==="admin",canManage=isOwner||isAdmin,isMember=me&&community?.member_emails?.includes(me.email);

  const fetchData = useCallback(async () => {
    if(!communityId)return; setLoading(true);
    const[comms,meData,chs,rs,allUsers]=await Promise.all([base44.entities.Community.filter({id:communityId}),base44.auth.me().catch(()=>null),base44.entities.ServerChannel.filter({community_id:communityId},"position"),base44.entities.ServerRole.filter({community_id:communityId},"position"),base44.entities.User.list().catch(()=>[])]);
    const comm=comms[0]||null; setCommunity(comm); setMe(meData); setRoles(rs);
    let finalChannels=chs;
    if(chs.length===0&&comm){const general=await base44.entities.ServerChannel.create({community_id:communityId,name:"general",type:"text",description:"General chat",position:0,allowed_roles:[]});finalChannels=[general];}
    setChannels(finalChannels); if(finalChannels.length>0)setActiveChannel(prev=>prev||finalChannels[0]);
    if(comm?.member_emails){const userMap={};allUsers.forEach(u=>{userMap[u.email]=u;});const existingMembers=await base44.entities.ServerMember.filter({community_id:communityId});const existingEmails=new Set(existingMembers.map(m=>m.user_email));const toCreate=comm.member_emails.filter(e=>!existingEmails.has(e));const created=await Promise.all(toCreate.map(email=>{const u=userMap[email];return base44.entities.ServerMember.create({community_id:communityId,user_email:email,user_display_name:u?.display_name||u?.full_name||email,user_profile_picture:u?.profile_picture||"",roles:[]});}));const allMembers=[...existingMembers,...created].map(m=>{const u=userMap[m.user_email];return{...m,user_display_name:u?.display_name||u?.full_name||m.user_display_name,user_profile_picture:u?.profile_picture||m.user_profile_picture};});setMembers(allMembers);if(meData)setMyMember(allMembers.find(m=>m.user_email===meData.email)||null);}
    setLoading(false);
  },[communityId]);

  useEffect(() => { fetchData(); }, [fetchData]);
  const handleKick = async(member) => { if(!canManage)return; const newEmails=(community.member_emails||[]).filter(e=>e!==member.user_email); await Promise.all([base44.entities.Community.update(communityId,{member_emails:newEmails}),base44.entities.ServerMember.delete(member.id)]); setMembers(prev=>prev.filter(m=>m.user_email!==member.user_email)); setCommunity(prev=>({...prev,member_emails:newEmails})); };
  const handleRoleChange = async(member,roleId,add) => { const newRoles=add?[...(member.roles||[]),roleId]:(member.roles||[]).filter(r=>r!==roleId); await base44.entities.ServerMember.update(member.id,{roles:newRoles}); setMembers(prev=>prev.map(m=>m.id===member.id?{...m,roles:newRoles}:m)); };
  const handleChannelDeleted=()=>{base44.entities.ServerChannel.filter({community_id:communityId},"position").then(chs=>{setChannels(chs);setActiveChannel(chs[0]||null);});};

  if(loading)return<div className="h-full flex items-center justify-center"><Loader2 className="w-5 h-5 animate-spin" style={{ color:"var(--accent-pink)" }}/></div>;
  if(!community)return<div className="h-full flex items-center justify-center p-4"><div className="text-center"><p className="text-sm mb-3" style={{ color:"var(--text-muted)" }}>Community not found.</p><Link to="/Communities" className="btn text-sm">Go back</Link></div></div>;

  return (
    <div className="flex overflow-hidden" style={{ background:"var(--app-bg)",height:"100%",minHeight:0 }}>
      <div className="hidden md:flex flex-col w-52 flex-shrink-0 h-full border-r" style={{ borderColor:"var(--border-c)" }}>
        <ServerSidebar community={community} channels={channels} activeChannel={activeChannel} me={me} memberCount={community.member_emails?.length||0} onSelectChannel={setActiveChannel} onAddChannel={()=>setShowAddChannel(true)} onChannelSettings={setChannelSettings} onServerSettings={()=>setShowServerSettings(true)} onMembersOpen={()=>setShowMembers(v=>!v)} />
      </div>
      <AnimatePresence>{showSidebar&&(<><motion.div initial={{ opacity:0 }} animate={{ opacity:1 }} exit={{ opacity:0 }} className="md:hidden fixed inset-0 bg-black/30 z-40 backdrop-blur-sm" onClick={()=>setShowSidebar(false)}/><motion.div initial={{ x:"-100%" }} animate={{ x:0 }} exit={{ x:"-100%" }} transition={{ type:"spring",damping:30,stiffness:300 }} className="md:hidden fixed left-0 top-0 bottom-0 w-56 z-50 border-r" style={{ borderColor:"var(--border-c)" }}><ServerSidebar community={community} channels={channels} activeChannel={activeChannel} me={me} memberCount={community.member_emails?.length||0} onSelectChannel={ch=>{setActiveChannel(ch);setShowSidebar(false);}} onAddChannel={()=>{setShowAddChannel(true);setShowSidebar(false);}} onChannelSettings={ch=>{setChannelSettings(ch);setShowSidebar(false);}} onServerSettings={()=>{setShowServerSettings(true);setShowSidebar(false);}} onMembersOpen={()=>{setShowMembers(v=>!v);setShowSidebar(false);}}/></motion.div></>)}</AnimatePresence>
      <div className="flex-1 flex flex-col min-w-0 overflow-hidden">
        <div className="md:hidden flex-shrink-0 h-12 flex items-center gap-2 px-3 border-b" style={{ background:"var(--surface)",borderColor:"var(--border-c)" }}>
          <button onClick={()=>setShowSidebar(true)} className="w-8 h-8 rounded-lg flex items-center justify-center" style={{ background:"var(--pink-soft)" }}><Menu className="w-4 h-4" style={{ color:"var(--accent-rose)" }}/></button>
          <span className="font-semibold text-sm flex-1 truncate" style={{ color:"var(--text-primary)" }}>#{activeChannel?.name||community.name}</span>
          <Link to="/Communities" className="w-8 h-8 rounded-lg flex items-center justify-center" style={{ background:"var(--pink-soft)" }}><ArrowLeft className="w-4 h-4" style={{ color:"var(--text-secondary)" }}/></Link>
          <button onClick={()=>setShowMembers(v=>!v)} className="w-8 h-8 rounded-lg flex items-center justify-center" style={{ background:"var(--pink-soft)" }}><Users className="w-4 h-4" style={{ color:"var(--text-secondary)" }}/></button>
        </div>
        <div className="hidden md:flex flex-shrink-0 h-12 items-center gap-2 px-4 border-b" style={{ background:"var(--surface)",borderColor:"var(--border-c)" }}>
          <Link to="/Communities" className="w-7 h-7 rounded-lg flex items-center justify-center" style={{ background:"var(--pink-soft)" }}><ArrowLeft className="w-3.5 h-3.5" style={{ color:"var(--text-secondary)" }}/></Link>
          <div className="flex-1"/>
          <button onClick={()=>setShowMembers(v=>!v)} className="flex items-center gap-1.5 text-xs font-medium px-3 py-1.5 rounded-full transition-all" style={showMembers?{background:"var(--accent-pink)",color:"white"}:{background:"var(--pink-soft)",color:"var(--text-secondary)"}}><Users className="w-3.5 h-3.5"/> Members</button>
        </div>
        {isMember||canManage?(activeChannel?.type==="voice"?<VoiceChannelView key={activeChannel.id} channel={activeChannel} me={me}/>:<ChatArea channel={activeChannel} community={community} me={me} roles={roles} myMember={myMember} canManage={canManage}/>):<div className="flex-1 flex flex-col items-center justify-center gap-3 p-6 text-center"><div className="w-14 h-14 rounded-2xl flex items-center justify-center text-2xl" style={{ background:"var(--pink-soft)" }}>{community.icon_emoji||"💬"}</div><p className="font-semibold text-sm" style={{ color:"var(--text-primary)" }}>{community.name}</p><p className="text-xs" style={{ color:"var(--text-muted)" }}>Join the server to start chatting.</p><Link to="/Communities" className="btn text-sm">Browse Servers</Link></div>}
      </div>
      <AnimatePresence>{showMembers&&(<motion.div initial={{ width:0,opacity:0 }} animate={{ width:220,opacity:1 }} exit={{ width:0,opacity:0 }} transition={{ type:"spring",damping:30,stiffness:300 }} className="hidden md:block flex-shrink-0 h-full overflow-hidden"><MemberList members={members} roles={roles} community={community} me={me} onKick={handleKick} onRoleChange={handleRoleChange} onClose={()=>setShowMembers(false)}/></motion.div>)}</AnimatePresence>
      {showServerSettings&&<ServerSettingsModal community={community} channels={channels} members={members} roles={roles} me={me} onClose={()=>setShowServerSettings(false)} onUpdated={()=>{fetchData();setShowServerSettings(false);}} onKick={handleKick} onRoleChange={handleRoleChange}/>}
      {channelSettings&&<ChannelSettingsModal channel={channelSettings} roles={roles} onClose={()=>setChannelSettings(null)} onUpdated={()=>{base44.entities.ServerChannel.filter({community_id:communityId},"position").then(chs=>{setChannels(chs);setActiveChannel(prev=>chs.find(c=>c.id===prev?.id)||chs[0]||null);});}} onDeleted={handleChannelDeleted}/>}
      {showAddChannel&&<AddChannelModal communityId={communityId} channelCount={channels.length} onClose={()=>setShowAddChannel(false)} onCreated={()=>{base44.entities.ServerChannel.filter({community_id:communityId},"position").then(chs=>{setChannels(chs);if(chs.length>0)setActiveChannel(chs[chs.length-1]);});}}/>}
    </div>
  );
}