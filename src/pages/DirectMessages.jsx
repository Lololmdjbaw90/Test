import React, { useState, useEffect } from "react";
import { base44 } from "@/api/base44Client";
import { Loader2, Plus, X, Search, Users, MessageSquare, ArrowLeft } from "lucide-react";
import { Link } from "react-router-dom";
import { motion, AnimatePresence } from "framer-motion";
import DMChatWindow from "../components/dm/DMChatWindow";

function Avatar({ user, size=36 }) {
  const [err,setErr]=useState(false);
  const style={width:size,height:size,borderRadius:"50%",flexShrink:0,objectFit:"cover"};
  if(user?.profile_picture&&!err)return<img src={user.profile_picture} onError={()=>setErr(true)} style={style} alt=""/>;
  return<div style={{...style,background:"var(--accent-pink)",display:"flex",alignItems:"center",justifyContent:"center",color:"white",fontSize:size/3,fontWeight:600}}>{(user?.display_name||user?.full_name)?.[0]?.toUpperCase()||"?"}</div>;
}

function Check({...props}){return<svg {...props} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2"><polyline points="20 6 9 17 4 12"/></svg>;}

function CreateGroupModal({ me, friends, onClose, onCreated }) {
  const [name,setName]=useState(""),[selected,setSelected]=useState([]),[submitting,setSubmitting]=useState(false);
  const toggle=(email)=>setSelected(prev=>prev.includes(email)?prev.filter(e=>e!==email):[...prev,email]);
  const create=async()=>{if(!name.trim()||selected.length===0)return;setSubmitting(true);const memberEmails=[...selected,me.email];const memberNames={};friends.forEach(f=>{if(selected.includes(f.email))memberNames[f.email]=f.display_name||f.full_name;});memberNames[me.email]=me.display_name||me.full_name;await base44.entities.GroupChat.create({name:name.trim(),owner_email:me.email,member_emails:memberEmails,member_display_names:memberNames});setSubmitting(false);onCreated();onClose();};
  return(
    <motion.div initial={{ opacity:0 }} animate={{ opacity:1 }} exit={{ opacity:0 }} style={{ position:"fixed",inset:0,zIndex:50,display:"flex",alignItems:"center",justifyContent:"center",padding:16,background:"rgba(0,0,0,0.5)" }}>
      <motion.div initial={{ scale:0.95,opacity:0 }} animate={{ scale:1,opacity:1 }} exit={{ scale:0.95,opacity:0 }} transition={{ type:"spring",stiffness:300,damping:30 }} style={{ width:"100%",maxWidth:400,borderRadius:20,overflow:"hidden",background:"var(--surface)",border:"1px solid var(--border-c)" }}>
        <div style={{ display:"flex",alignItems:"center",justifyContent:"space-between",padding:"16px 20px",borderBottom:"1px solid var(--border-c)" }}><span style={{ fontWeight:600,fontSize:14,color:"var(--text-primary)" }}>New Group Chat</span><button onClick={onClose}><X className="w-4 h-4" style={{ color:"var(--text-muted)" }}/></button></div>
        <div style={{ padding:20,display:"flex",flexDirection:"column",gap:16 }}>
          <div><label style={{ fontSize:12,fontWeight:600,color:"var(--text-muted)",display:"block",marginBottom:6 }}>Group Name</label><input className="input text-sm" placeholder="e.g. Art Squad" value={name} onChange={e=>setName(e.target.value)}/></div>
          <div><label style={{ fontSize:12,fontWeight:600,color:"var(--text-muted)",display:"block",marginBottom:8 }}>Add Members</label><div style={{ maxHeight:220,overflowY:"auto" }} className="scroll space-y-1">{friends.length===0&&<p style={{ fontSize:12,color:"var(--text-muted)",textAlign:"center",padding:"16px 0" }}>No friends yet.</p>}{friends.map(f=><button key={f.email} onClick={()=>toggle(f.email)} style={{ width:"100%",display:"flex",alignItems:"center",gap:10,padding:"10px 12px",borderRadius:12,textAlign:"left",border:selected.includes(f.email)?"1.5px solid var(--accent-pink)":"1.5px solid var(--border-c)",background:selected.includes(f.email)?"var(--pink-soft)":"transparent",transition:"all 0.15s" }}><Avatar user={f} size={32}/><span style={{ flex:1,fontSize:13,fontWeight:500,color:"var(--text-primary)",overflow:"hidden",textOverflow:"ellipsis",whiteSpace:"nowrap" }}>{f.display_name||f.full_name}</span>{selected.includes(f.email)&&<Check style={{ width:16,height:16,color:"var(--accent-rose)" }}/>}</button>)}</div></div>
          <div style={{ display:"flex",gap:8 }}><button onClick={onClose} className="btn-ghost flex-1 text-xs">Cancel</button><button onClick={create} disabled={submitting||!name.trim()||selected.length===0} className="btn flex-1 text-xs justify-center">{submitting?<Loader2 className="w-3 h-3 animate-spin"/>:"Create"}</button></div>
        </div>
      </motion.div>
    </motion.div>
  );
}

export default function DirectMessagesPage() {
  const [me,setMe]=useState(null),[allUsers,setAllUsers]=useState([]),[friendships,setFriendships]=useState([]),[groups,setGroups]=useState([]),[loading,setLoading]=useState(true),[activeConvo,setActiveConvo]=useState(null),[showCreateGroup,setShowCreateGroup]=useState(false),[search,setSearch]=useState(""),[mobileView,setMobileView]=useState("list");
  useEffect(()=>{fetchData();},[]);
  const fetchData=async()=>{setLoading(true);const[meData,users,fs,gs]=await Promise.all([base44.auth.me().catch(()=>null),base44.entities.User.list(),base44.entities.Friendship.list(),base44.entities.GroupChat.list("-created_date")]);setMe(meData);setAllUsers(users);setFriendships(fs);setGroups(gs.filter(g=>g.member_emails?.includes(meData?.email)));setLoading(false);};

  if(!me)return<div style={{ height:"100%",display:"flex",alignItems:"center",justifyContent:"center" }}><Loader2 className="w-5 h-5 animate-spin" style={{ color:"var(--accent-pink)" }}/></div>;

  const friends=friendships.filter(f=>f.status==="accepted"&&(f.requester_email===me.email||f.receiver_email===me.email)).map(f=>{const email=f.requester_email===me.email?f.receiver_email:f.requester_email;return allUsers.find(u=>u.email===email);}).filter(Boolean);
  const getDMConvoId=(a,b)=>[a,b].sort().join("__dm__");
  const isOnline=(u)=>{if(!u?.last_seen)return false;return Date.now()-new Date(u.last_seen).getTime()<5*60*1000;};
  const filteredFriends=friends.filter(f=>!search.trim()||(f.display_name||f.full_name)?.toLowerCase().includes(search.toLowerCase()));
  const filteredGroups=groups.filter(g=>!search.trim()||g.name?.toLowerCase().includes(search.toLowerCase()));
  const openDM=(friend)=>{setActiveConvo({id:getDMConvoId(me.email,friend.email),type:"dm",otherUser:friend});setMobileView("chat");};
  const openGroup=(group)=>{setActiveConvo({id:group.id,type:"group",group});setMobileView("chat");};
  const deleteGroup=async(group)=>{if(!confirm("Delete this group?"))return;await base44.entities.GroupChat.delete(group.id);setActiveConvo(null);setMobileView("list");fetchData();};

  const Sidebar=(
    <div style={{ width:"100%",height:"100%",display:"flex",flexDirection:"column",background:"var(--surface)",borderRight:"1px solid var(--border-c)" }}>
      <div style={{ flexShrink:0,padding:"16px",borderBottom:"1px solid var(--border-c)",display:"flex",alignItems:"center",gap:12 }}><MessageSquare className="w-5 h-5" style={{ color:"var(--accent-pink)",flexShrink:0 }}/><span style={{ fontWeight:600,fontSize:16,flex:1,color:"var(--text-primary)" }}>Messages</span><button onClick={()=>setShowCreateGroup(true)} className="btn text-xs px-3 py-1.5" style={{ gap:4 }}><Plus className="w-3.5 h-3.5"/> Group</button></div>
      <div style={{ flexShrink:0,padding:"12px",borderBottom:"1px solid var(--border-c)" }}><div style={{ position:"relative" }}><Search style={{ position:"absolute",left:12,top:"50%",transform:"translateY(-50%)",width:16,height:16,color:"var(--text-muted)" }}/><input className="input pl-9 text-xs py-2" placeholder="Search conversations..." value={search} onChange={e=>setSearch(e.target.value)}/></div></div>
      <div style={{ flex:1,overflowY:"auto",paddingBlock:8 }} className="scroll">
        {loading?<div style={{ display:"flex",justifyContent:"center",paddingTop:32 }}><Loader2 className="w-4 h-4 animate-spin" style={{ color:"var(--accent-pink)" }}/></div>:<>
          {filteredGroups.length>0&&<div style={{ marginBottom:8 }}><p style={{ fontSize:11,fontWeight:600,textTransform:"uppercase",letterSpacing:"0.05em",padding:"8px 12px",color:"var(--text-muted)" }}>Groups ({filteredGroups.length})</p>{filteredGroups.map(g=>{const active=activeConvo?.id===g.id;return<motion.button key={g.id} onClick={()=>openGroup(g)} whileHover={{ x:2 }} style={{ width:"100%",display:"flex",alignItems:"center",gap:12,padding:"10px 12px",textAlign:"left",background:active?"var(--pink-soft)":"transparent",transition:"background 0.15s" }}><div style={{ width:40,height:40,borderRadius:"50%",display:"flex",alignItems:"center",justifyContent:"center",fontSize:18,flexShrink:0,background:"var(--pink-soft)",border:"1px solid var(--border-c)" }}>👥</div><div style={{ flex:1,minWidth:0 }}><p style={{ fontSize:13,fontWeight:500,color:"var(--text-primary)",overflow:"hidden",textOverflow:"ellipsis",whiteSpace:"nowrap" }}>{g.name}</p><p style={{ fontSize:11,color:"var(--text-muted)" }}>{g.member_emails?.length} members</p></div></motion.button>;})}</div>}
          <p style={{ fontSize:11,fontWeight:600,textTransform:"uppercase",letterSpacing:"0.05em",padding:"8px 12px",color:"var(--text-muted)" }}>Direct Messages ({filteredFriends.length})</p>
          {filteredFriends.length===0?<div style={{ padding:"16px 12px",textAlign:"center" }}><p style={{ fontSize:12,color:"var(--text-muted)",marginBottom:12 }}>No friends yet.</p><Link to="/Friends" className="btn text-xs inline-flex" style={{ gap:6,padding:"6px 12px" }}><Users className="w-3 h-3"/> Add Friends</Link></div>
            :filteredFriends.map(f=>{const convoId=getDMConvoId(me.email,f.email),active=activeConvo?.id===convoId,online=isOnline(f);return<motion.button key={f.email} onClick={()=>openDM(f)} whileHover={{ x:2 }} style={{ width:"100%",display:"flex",alignItems:"center",gap:12,padding:"10px 12px",textAlign:"left",background:active?"var(--pink-soft)":"transparent",transition:"background 0.15s" }}><div style={{ position:"relative",flexShrink:0 }}><Avatar user={f} size={40}/><div style={{ position:"absolute",bottom:0,right:0,width:10,height:10,borderRadius:"50%",background:online?"#22c55e":"#9ca3af",border:"2px solid var(--surface)" }}/></div><div style={{ flex:1,minWidth:0 }}><p style={{ fontSize:13,fontWeight:500,color:"var(--text-primary)",overflow:"hidden",textOverflow:"ellipsis",whiteSpace:"nowrap" }}>{f.display_name||f.full_name}</p><p style={{ fontSize:11,color:online?"#22c55e":"var(--text-muted)" }}>{online?"Online":"Offline"}</p></div></motion.button>;})}
        </>}
      </div>
    </div>
  );

  const ChatPanel=(
    <div style={{ flex:1,minWidth:0,height:"100%",minHeight:0,display:"flex",flexDirection:"column" }}>
      {activeConvo?<>
        <div style={{ flexShrink:0,height:56,padding:"0 16px",display:"flex",alignItems:"center",gap:12,background:"var(--surface)",borderBottom:"1px solid var(--border-c)" }}>
          <button className="md:hidden" onClick={()=>setMobileView("list")} style={{ width:32,height:32,borderRadius:10,display:"flex",alignItems:"center",justifyContent:"center",background:"var(--pink-soft)",flexShrink:0 }}><ArrowLeft className="w-4 h-4" style={{ color:"var(--text-secondary)" }}/></button>
          {activeConvo.type==="group"?<><div style={{ width:40,height:40,borderRadius:"50%",display:"flex",alignItems:"center",justifyContent:"center",fontSize:20,background:"var(--pink-soft)",border:"1px solid var(--border-c)",flexShrink:0 }}>👥</div><div style={{ flex:1,minWidth:0 }}><p style={{ fontWeight:600,fontSize:14,color:"var(--text-primary)",overflow:"hidden",textOverflow:"ellipsis",whiteSpace:"nowrap" }}>{activeConvo.group?.name}</p><p style={{ fontSize:11,color:"var(--text-muted)" }}>{activeConvo.group?.member_emails?.length} members</p></div>{activeConvo.group?.owner_email===me.email&&<button onClick={()=>deleteGroup(activeConvo.group)} style={{ fontSize:11,color:"#e05a5a",padding:"6px 12px",borderRadius:8,background:"#fff0f0",flexShrink:0 }}>Delete</button>}</>
            :<><div style={{ position:"relative",flexShrink:0 }}><Avatar user={activeConvo.otherUser} size={40}/><div style={{ position:"absolute",bottom:0,right:0,width:10,height:10,borderRadius:"50%",background:isOnline(activeConvo.otherUser)?"#22c55e":"#9ca3af",border:"2px solid var(--surface)" }}/></div><div style={{ flex:1,minWidth:0 }}><p style={{ fontWeight:600,fontSize:14,color:"var(--text-primary)",overflow:"hidden",textOverflow:"ellipsis",whiteSpace:"nowrap" }}>{activeConvo.otherUser?.display_name||activeConvo.otherUser?.full_name}</p><p style={{ fontSize:11,color:isOnline(activeConvo.otherUser)?"#22c55e":"var(--text-muted)" }}>{isOnline(activeConvo.otherUser)?"Online":"Offline"}</p></div><Link to={`/Profile?email=${encodeURIComponent(activeConvo.otherUser?.email)}`} className="btn-ghost text-xs" style={{ padding:"6px 12px",flexShrink:0 }}>Profile</Link></>}
        </div>
        <div style={{ flex:1,minHeight:0,overflow:"hidden" }}><DMChatWindow conversationId={activeConvo.id} me={me} otherUser={activeConvo.otherUser} isGroup={activeConvo.type==="group"} groupName={activeConvo.group?.name} groupMemberEmails={activeConvo.group?.member_emails || []}/></div>
      </>:<div style={{ flex:1,display:"flex",flexDirection:"column",alignItems:"center",justifyContent:"center",gap:16,padding:32,textAlign:"center" }}><div style={{ width:72,height:72,borderRadius:18,display:"flex",alignItems:"center",justifyContent:"center",background:"var(--pink-soft)" }}><MessageSquare className="w-8 h-8" style={{ color:"var(--accent-pink)" }}/></div><div><p style={{ fontWeight:600,fontSize:16,color:"var(--text-primary)",marginBottom:6 }}>Select a conversation</p><p style={{ fontSize:13,color:"var(--text-muted)" }}>Choose a friend or group to start messaging</p></div><Link to="/Friends" className="btn text-sm" style={{ gap:8,padding:"10px 18px" }}><Users className="w-4 h-4"/> Add Friends</Link></div>}
    </div>
  );

  return(
    <><div className="hidden md:flex" style={{ height:"100%",overflow:"hidden",background:"var(--app-bg)" }}><div style={{ width:320,flexShrink:0,height:"100%",overflow:"hidden" }}>{Sidebar}</div>{ChatPanel}</div>
    <div className="md:hidden" style={{ height:"100%",overflow:"hidden",background:"var(--app-bg)" }}>{mobileView==="list"?<div style={{ height:"100%",overflow:"hidden" }}>{Sidebar}</div>:<div style={{ height:"100%",overflow:"hidden",display:"flex",flexDirection:"column" }}>{ChatPanel}</div>}</div>
    <AnimatePresence>{showCreateGroup&&<CreateGroupModal me={me} friends={friends} onClose={()=>setShowCreateGroup(false)} onCreated={fetchData}/>}</AnimatePresence></>
  );
}