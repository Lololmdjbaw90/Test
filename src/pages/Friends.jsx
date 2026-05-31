import React, { useState, useEffect } from "react";
import { base44 } from "@/api/base44Client";
import { notify } from "../utils/notifications";
import { UserPlus, UserCheck, Clock, Search, Loader2, Check, X, Users, MessageSquare, Trash2 } from "lucide-react";
import { motion, AnimatePresence } from "framer-motion";
import { useNavigate } from "react-router-dom";

function Avatar({ user, size=40 }) {
  const [err,setErr]=useState(false);
  const style={width:size,height:size,borderRadius:"50%",objectFit:"cover",flexShrink:0};
  if(user?.profile_picture&&!err)return<img src={user.profile_picture} onError={()=>setErr(true)} style={style} alt=""/>;
  return<div style={{...style,background:"var(--accent-pink)",display:"flex",alignItems:"center",justifyContent:"center",color:"white",fontSize:size/3,fontWeight:600}}>{user?.display_name?.[0]?.toUpperCase()||"?"}</div>;
}

const TABS=[{id:"friends",label:"Friends",icon:UserCheck},{id:"requests",label:"Requests",icon:Clock},{id:"add",label:"Discover",icon:UserPlus}];

export default function FriendsPage() {
  const navigate=useNavigate();
  const [me,setMe]=useState(null),[allUsers,setAllUsers]=useState([]),[friendships,setFriendships]=useState([]),[loading,setLoading]=useState(true),[tab,setTab]=useState("friends"),[search,setSearch]=useState("");
  useEffect(()=>{fetchData();},[]);
  const fetchData=async()=>{setLoading(true);const[meData,users,fs]=await Promise.all([base44.auth.me().catch(()=>null),base44.entities.User.list(),base44.entities.Friendship.list()]);setMe(meData);setAllUsers(users);setFriendships(fs);setLoading(false);};
  const sendRequest=async(toUser)=>{await base44.entities.Friendship.create({requester_email:me.email,requester_display_name:me.display_name||me.full_name,requester_profile_picture:me.profile_picture||"",requester_profile_emoji:"",receiver_email:toUser.email,receiver_display_name:toUser.display_name||toUser.full_name,receiver_profile_picture:toUser.profile_picture||"",receiver_profile_emoji:"",status:"pending"});notify({to_email:toUser.email,from_email:me.email,from_display_name:me.display_name||me.full_name,from_profile_picture:me.profile_picture,type:"friend_request",message:`${me.display_name||me.full_name} sent you a friend request`,link:"/Friends"});fetchData();};
  const respond=async(id,status)=>{const f=friendships.find(f=>f.id===id);await base44.entities.Friendship.update(id,{status});if(status==="accepted"&&f){notify({to_email:f.requester_email,from_email:me.email,from_display_name:me.display_name||me.full_name,from_profile_picture:me.profile_picture,type:"friend_accepted",message:`${me.display_name||me.full_name} accepted your friend request`,link:"/Friends"});}fetchData();};
  const remove=async(id)=>{if(confirm("Remove this friend?"))await base44.entities.Friendship.delete(id);fetchData();};

  if(loading||!me)return<div className="flex items-center justify-center h-full"><Loader2 className="w-5 h-5 animate-spin" style={{ color:"var(--accent-pink)" }}/></div>;

  const friends=friendships.filter(f=>f.status==="accepted"&&(f.requester_email===me.email||f.receiver_email===me.email));
  const incoming=friendships.filter(f=>f.status==="pending"&&f.receiver_email===me.email);
  const outgoing=friendships.filter(f=>f.status==="pending"&&f.requester_email===me.email);
  const friendEmails=new Set([...friends.map(f=>f.requester_email===me.email?f.receiver_email:f.requester_email),...outgoing.map(f=>f.receiver_email)]);
  const addable=allUsers.filter(u=>u.email!==me.email&&!friendEmails.has(u.email)&&(!search.trim()||u.display_name?.toLowerCase().includes(search.toLowerCase())||u.email.includes(search.toLowerCase())));
  const friendUsers=friends.map(f=>{const email=f.requester_email===me.email?f.receiver_email:f.requester_email;const name=f.requester_email===me.email?f.receiver_display_name:f.requester_display_name;const pic=f.requester_email===me.email?f.receiver_profile_picture:f.requester_profile_picture;const user=allUsers.find(u=>u.email===email);return{...f,otherEmail:email,otherName:name,otherPic:pic,user};});

  return (
    <div className="h-full flex flex-col overflow-hidden" style={{ background:"var(--app-bg)" }}>
      <div className="flex-shrink-0 px-4 sm:px-6 py-4 border-b flex items-center gap-3" style={{ background:"var(--surface)",borderColor:"var(--border-c)" }}>
        <Users className="w-5 h-5" style={{ color:"var(--accent-pink)" }}/><div className="flex-1"><h1 className="text-lg font-bold" style={{ color:"var(--text-primary)" }}>Friends</h1><p className="text-xs" style={{ color:"var(--text-muted)" }}>{friends.length} friends</p></div>
        {incoming.length>0&&<motion.span className="badge-pink" whileHover={{ scale:1.05 }}>{incoming.length}</motion.span>}
      </div>
      <div className="flex-shrink-0 border-b" style={{ background:"var(--surface)",borderColor:"var(--border-c)" }}>
        <div className="flex">{TABS.map(t=>{const Icon=t.icon,count=t.id==="requests"?(incoming.length+outgoing.length):0,active=tab===t.id;return<button key={t.id} onClick={()=>setTab(t.id)} className="flex-1 flex items-center justify-center gap-1.5 py-3 text-xs font-medium border-b-2 transition-all" style={active?{borderColor:"var(--accent-pink)",color:"var(--accent-rose)"}:{borderColor:"transparent",color:"var(--text-muted)"}}><Icon className="w-4 h-4"/>{t.label}{count>0&&<span className="badge-pink px-1.5 py-0.5 text-[10px]">{count}</span>}</button>;})}</div>
      </div>
      <div className="flex-1 overflow-y-auto scroll" style={{ background:"var(--app-bg)" }}>
        <AnimatePresence mode="wait">
          {tab==="friends"&&<motion.div initial={{ opacity:0 }} animate={{ opacity:1 }} exit={{ opacity:0 }} transition={{ duration:0.2 }} className="px-4 sm:px-6 py-4">
            {friendUsers.length===0?<div className="flex flex-col items-center justify-center py-16 gap-3"><div className="w-14 h-14 rounded-full flex items-center justify-center" style={{ background:"var(--pink-soft)" }}><Users className="w-6 h-6" style={{ color:"var(--accent-pink)" }}/></div><p className="text-sm" style={{ color:"var(--text-muted)" }}>No friends yet. Discover people!</p></div>
              :<div className="space-y-2">{friendUsers.map((f,i)=><motion.div key={f.id} initial={{ opacity:0,x:-10 }} animate={{ opacity:1,x:0 }} transition={{ delay:i*0.03 }} className="card-sm px-4 py-3 flex items-center gap-3 hover:shadow-sm transition-all"><Avatar user={{...f.user,profile_picture:f.otherPic}} size={40}/><div className="flex-1 min-w-0"><p className="text-sm font-semibold truncate" style={{ color:"var(--text-primary)" }}>{f.otherName||f.otherEmail}</p><p className="text-xs truncate" style={{ color:"var(--text-muted)" }}>{f.otherEmail}</p></div><button onClick={()=>navigate("/DirectMessages")} className="btn text-xs px-3 py-1.5 flex items-center gap-1.5"><MessageSquare className="w-3.5 h-3.5"/></button><button onClick={()=>remove(f.id)} className="text-xs py-1.5 px-2 rounded-lg" style={{ color:"var(--text-muted)" }}><Trash2 className="w-3.5 h-3.5" style={{ color:"#e05a5a" }}/></button></motion.div>)}</div>}
          </motion.div>}
          {tab==="requests"&&<motion.div initial={{ opacity:0 }} animate={{ opacity:1 }} exit={{ opacity:0 }} transition={{ duration:0.2 }} className="px-4 sm:px-6 py-4 space-y-6">
            {incoming.length===0&&outgoing.length===0?<div className="flex flex-col items-center justify-center py-16 gap-3"><div className="w-14 h-14 rounded-full flex items-center justify-center" style={{ background:"var(--pink-soft)" }}><Clock className="w-6 h-6" style={{ color:"var(--accent-pink)" }}/></div><p className="text-sm" style={{ color:"var(--text-muted)" }}>No pending requests</p></div>
              :<>{incoming.length>0&&<div><p className="text-xs font-semibold uppercase tracking-wider mb-3 px-1" style={{ color:"var(--text-muted)" }}>Incoming ({incoming.length})</p><div className="space-y-2">{incoming.map((f,i)=>{const u=allUsers.find(u=>u.email===f.requester_email);return<motion.div key={f.id} initial={{ opacity:0,x:-10 }} animate={{ opacity:1,x:0 }} transition={{ delay:i*0.05 }} className="card-sm px-4 py-3 flex items-center gap-3"><Avatar user={u} size={40}/><div className="flex-1 min-w-0"><p className="text-sm font-semibold" style={{ color:"var(--text-primary)" }}>{f.requester_display_name}</p><p className="text-xs" style={{ color:"var(--text-muted)" }}>Sent you a friend request</p></div><div className="flex gap-1"><button onClick={()=>respond(f.id,"accepted")} className="btn text-xs px-2.5 py-1.5"><Check className="w-3 h-3"/></button><button onClick={()=>respond(f.id,"rejected")} className="btn-outline text-xs px-2.5 py-1.5"><X className="w-3 h-3"/></button></div></motion.div>;})}</div></div>}
              {outgoing.length>0&&<div><p className="text-xs font-semibold uppercase tracking-wider mb-3 px-1" style={{ color:"var(--text-muted)" }}>Sent ({outgoing.length})</p><div className="space-y-2">{outgoing.map((f,i)=>{const u=allUsers.find(u=>u.email===f.receiver_email);return<motion.div key={f.id} initial={{ opacity:0,x:-10 }} animate={{ opacity:1,x:0 }} transition={{ delay:i*0.05 }} className="card-sm px-4 py-3 flex items-center gap-3"><Avatar user={u} size={40}/><div className="flex-1 min-w-0"><p className="text-sm font-semibold" style={{ color:"var(--text-primary)" }}>{f.receiver_display_name}</p><p className="text-xs" style={{ color:"var(--text-muted)" }}>Awaiting response...</p></div><button onClick={()=>remove(f.id)} className="btn-outline text-xs px-2.5 py-1.5">Cancel</button></motion.div>;})}</div></div>}</>}
          </motion.div>}
          {tab==="add"&&<motion.div initial={{ opacity:0 }} animate={{ opacity:1 }} exit={{ opacity:0 }} transition={{ duration:0.2 }} className="px-4 sm:px-6 py-4 space-y-4">
            <div className="relative"><Search className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4" style={{ color:"var(--text-muted)" }}/><input className="input pl-9 text-sm w-full" placeholder="Search by name or email..." value={search} onChange={e=>setSearch(e.target.value)}/></div>
            {addable.length===0?<div className="flex flex-col items-center justify-center py-16 gap-3"><div className="w-14 h-14 rounded-full flex items-center justify-center" style={{ background:"var(--pink-soft)" }}><UserPlus className="w-6 h-6" style={{ color:"var(--accent-pink)" }}/></div><p className="text-sm" style={{ color:"var(--text-muted)" }}>{search?"No users found":"No users to discover"}</p></div>
              :<div className="space-y-2">{addable.slice(0,50).map((u,i)=><motion.div key={u.email} initial={{ opacity:0,x:-10 }} animate={{ opacity:1,x:0 }} transition={{ delay:i*0.02 }} className="card-sm px-4 py-3 flex items-center gap-3"><Avatar user={u} size={40}/><div className="flex-1 min-w-0"><p className="text-sm font-semibold truncate" style={{ color:"var(--text-primary)" }}>{u.display_name||u.full_name}</p><p className="text-xs truncate" style={{ color:"var(--text-muted)" }}>{u.email}</p></div><button onClick={()=>sendRequest(u)} className="btn text-xs px-3 py-1.5"><UserPlus className="w-3.5 h-3.5"/></button></motion.div>)}</div>}
          </motion.div>}
        </AnimatePresence>
      </div>
    </div>
  );
}