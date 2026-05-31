import React, { useState, useEffect, useRef } from "react";
import { base44 } from "@/api/base44Client";
import { Bell, Heart, MessageCircle, UserPlus, UserCheck, AtSign, Trash2, CheckCheck } from "lucide-react";
import { motion, AnimatePresence } from "framer-motion";
import { Link } from "react-router-dom";
const TYPE_ICONS = { like:Heart, comment:MessageCircle, friend_request:UserPlus, friend_accepted:UserCheck, mention:AtSign, dm:MessageCircle, ping:Bell };
const TYPE_COLORS = { like:"#e8a0b4", comment:"#818cf8", friend_request:"#f59e0b", friend_accepted:"#22c55e", mention:"#e8a0b4", dm:"#818cf8", ping:"#e8a0b4" };
function timeAgo(date) { const diff=Date.now()-new Date(date).getTime(),m=Math.floor(diff/60000); if(m<1)return"just now";if(m<60)return`${m}m ago`;const h=Math.floor(m/60);if(h<24)return`${h}h ago`;return`${Math.floor(h/24)}d ago`; }
export default function NotificationBell({ me }) {
  const [notifications, setNotifications] = useState([]); const [open, setOpen] = useState(false); const ref = useRef(null);
  useEffect(() => {
    if (!me?.email) return;
    base44.entities.Notification.filter({to_email:me.email},"-created_date",50).catch(()=>[]).then(setNotifications);
    const unsub = base44.entities.Notification.subscribe(ev => {
      if(ev.type==="create"&&ev.data?.to_email===me.email)setNotifications(p=>[ev.data,...p]);
      else if(ev.type==="update"&&ev.data?.to_email===me.email)setNotifications(p=>p.map(n=>n.id===ev.data.id?ev.data:n));
      else if(ev.type==="delete")setNotifications(p=>p.filter(n=>n.id!==ev.id));
    });
    return unsub;
  }, [me?.email]);
  useEffect(() => { const h=(e)=>{if(ref.current&&!ref.current.contains(e.target))setOpen(false);}; document.addEventListener("mousedown",h); return()=>document.removeEventListener("mousedown",h); }, []);
  const unread = notifications.filter(n=>!n.is_read).length;
  const markAllRead = async()=>{await Promise.all(notifications.filter(n=>!n.is_read).map(n=>base44.entities.Notification.update(n.id,{is_read:true})));setNotifications(p=>p.map(n=>({...n,is_read:true})));};
  const markRead = async(id)=>{await base44.entities.Notification.update(id,{is_read:true});setNotifications(p=>p.map(n=>n.id===id?{...n,is_read:true}:n));};
  const del = async(id,e)=>{e.stopPropagation();await base44.entities.Notification.delete(id);setNotifications(p=>p.filter(n=>n.id!==id));};
  const clearAll = async()=>{await Promise.all(notifications.map(n=>base44.entities.Notification.delete(n.id)));setNotifications([]);};
  return (
    <div ref={ref} style={{position:"relative"}}>
      <button onClick={()=>setOpen(v=>!v)} style={{width:36,height:36,borderRadius:10,display:"flex",alignItems:"center",justifyContent:"center",background:open?"var(--pink-soft)":"transparent",border:"1px solid var(--border-c)",cursor:"pointer",position:"relative"}}>
        <Bell style={{width:18,height:18,color:"var(--text-secondary)"}}/>
        {unread>0&&<motion.span initial={{scale:0}} animate={{scale:1}} style={{position:"absolute",top:-4,right:-4,background:"var(--accent-rose)",color:"white",fontSize:10,fontWeight:700,minWidth:18,height:18,borderRadius:9,display:"flex",alignItems:"center",justifyContent:"center",padding:"0 4px",border:"2px solid var(--surface)"}}>{unread>9?"9+":unread}</motion.span>}
      </button>
      <AnimatePresence>
        {open&&<motion.div initial={{opacity:0,y:8,scale:0.97}} animate={{opacity:1,y:0,scale:1}} exit={{opacity:0,y:8,scale:0.97}} transition={{type:"spring",stiffness:400,damping:30}}
          style={{position:"absolute",top:"calc(100% + 8px)",right:0,zIndex:100,width:340,maxHeight:440,display:"flex",flexDirection:"column",background:"var(--surface)",border:"1px solid var(--border-c)",borderRadius:16,boxShadow:"0 8px 32px rgba(0,0,0,0.12)",overflow:"hidden"}}>
          <div style={{padding:"12px 16px",borderBottom:"1px solid var(--border-c)",display:"flex",alignItems:"center",gap:8,flexShrink:0}}>
            <span style={{fontWeight:700,fontSize:14,flex:1,color:"var(--text-primary)"}}>Notifications</span>
            {unread>0&&<button onClick={markAllRead} style={{display:"flex",alignItems:"center",gap:4,fontSize:11,fontWeight:600,color:"var(--accent-rose)",cursor:"pointer",padding:"4px 8px",borderRadius:8,background:"var(--pink-soft)"}}><CheckCheck style={{width:12,height:12}}/>Mark all read</button>}
            {notifications.length>0&&<button onClick={clearAll} style={{fontSize:11,color:"var(--text-muted)",cursor:"pointer",padding:"4px 8px",borderRadius:8}}>Clear all</button>}
          </div>
          <div style={{flex:1,overflowY:"auto"}} className="scroll">
            {notifications.length===0?<div style={{padding:32,textAlign:"center"}}><Bell style={{width:32,height:32,color:"var(--border-c)",margin:"0 auto 8px"}}/><p style={{fontSize:13,color:"var(--text-muted)"}}>No notifications yet</p></div>
              :notifications.map(n=>{const Icon=TYPE_ICONS[n.type]||Bell,color=TYPE_COLORS[n.type]||"var(--accent-pink)",Wrapper=n.link?Link:"div";return(
                <Wrapper key={n.id} to={n.link||undefined} onClick={()=>{markRead(n.id);setOpen(false);}} style={{display:"flex",alignItems:"flex-start",gap:12,padding:"12px 16px",background:n.is_read?"transparent":"var(--pink-soft)",cursor:"pointer",textDecoration:"none",borderBottom:"1px solid var(--border-c)"}}>
                  <div style={{width:32,height:32,borderRadius:"50%",display:"flex",alignItems:"center",justifyContent:"center",flexShrink:0,background:`${color}20`}}><Icon style={{width:15,height:15,color}}/></div>
                  <div style={{flex:1,minWidth:0}}><p style={{fontSize:13,color:"var(--text-primary)",lineHeight:1.4,marginBottom:2}}>{n.message}</p><p style={{fontSize:11,color:"var(--text-muted)"}}>{timeAgo(n.created_date)}</p></div>
                  {!n.is_read&&<div style={{width:7,height:7,borderRadius:"50%",background:"var(--accent-rose)",flexShrink:0,marginTop:4}}/>}
                  <button onClick={e=>del(n.id,e)} style={{width:24,height:24,borderRadius:6,display:"flex",alignItems:"center",justifyContent:"center",flexShrink:0,cursor:"pointer",opacity:0.5}}><Trash2 style={{width:12,height:12,color:"#e05a5a"}}/></button>
                </Wrapper>
              );})}
          </div>
        </motion.div>}
      </AnimatePresence>
    </div>
  );
}