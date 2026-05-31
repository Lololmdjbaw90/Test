import React, { useState, useEffect, useRef } from "react";
import { base44 } from "@/api/base44Client";
import { Send, Loader2, X } from "lucide-react";
import { motion } from "framer-motion";
export default function ProfileMessageBoard({ profileUser, currentUser }) {
  const [messages, setMessages] = useState([]); const [text, setText] = useState(""); const [loading, setLoading] = useState(true); const [sending, setSending] = useState(false);
  const bottomRef = useRef(null); const boardId = `profile_${profileUser.email}`;
  useEffect(()=>{load();},[profileUser.email]);
  useEffect(()=>{bottomRef.current?.scrollIntoView({behavior:"smooth"});},[messages]);
  const load = async()=>{setLoading(true);const data=await base44.entities.CommunityComment.filter({post_id:boardId},"created_date",50);setMessages(data);setLoading(false);};
  const send = async()=>{if(!currentUser||!text.trim())return;setSending(true);const msg=await base44.entities.CommunityComment.create({post_id:boardId,content:text.trim(),gif_url:"",user_display_name:currentUser.display_name||currentUser.full_name,user_email:currentUser.email,likes:[]});setMessages(p=>[...p,msg]);setText("");setSending(false);};
  const del = async(id)=>{await base44.entities.CommunityComment.delete(id);setMessages(p=>p.filter(m=>m.id!==id));};
  const canDelete=(msg)=>currentUser&&(currentUser.email===msg.user_email||currentUser.email===profileUser.email||currentUser.role==="admin");
  return(
    <div className="card overflow-hidden flex flex-col" style={{height:420}}>
      <div className="px-4 py-3 border-b flex-shrink-0 flex items-center justify-between" style={{borderColor:"var(--border-c)"}}><p className="text-xs font-medium" style={{color:"var(--text-secondary)"}}>Message Board</p><span className="text-xs" style={{color:"var(--text-muted)"}}>{messages.length}</span></div>
      <div className="flex-1 overflow-y-auto scroll p-3 space-y-2">
        {loading?<div className="flex items-center justify-center h-full"><Loader2 className="w-4 h-4 animate-spin" style={{color:"var(--accent-pink)"}}/></div>
         :messages.length===0?<div className="flex items-center justify-center h-full"><p className="text-xs" style={{color:"var(--text-muted)"}}>No messages yet. Be the first!</p></div>
         :messages.map(msg=>{const isOwn=currentUser?.email===msg.user_email;return(<motion.div key={msg.id} initial={{opacity:0,y:6}} animate={{opacity:1,y:0}} className={`flex gap-2 group ${isOwn?"flex-row-reverse":""}`}><div className="w-7 h-7 rounded-full flex items-center justify-center text-white text-[10px] font-semibold flex-shrink-0 mt-0.5" style={{background:"var(--accent-pink)"}}>{msg.user_display_name?.[0]?.toUpperCase()||"?"}</div><div className={`max-w-[72%] flex flex-col gap-0.5 ${isOwn?"items-end":""}`}><span className="text-[10px]" style={{color:"var(--text-muted)"}}>{msg.user_display_name}</span><div className={`relative px-3 py-2 rounded-2xl text-xs ${isOwn?"rounded-tr-sm":"rounded-tl-sm"}`} style={isOwn?{background:"var(--accent-pink)",color:"white"}:{background:"var(--pink-soft)",color:"var(--text-primary)",border:"1px solid var(--border-c)"}}>{msg.content}{canDelete(msg)&&<button onClick={()=>del(msg.id)} className={`absolute -top-2 ${isOwn?"-left-2":"-right-2"} w-4 h-4 bg-white rounded-full items-center justify-center hidden group-hover:flex shadow`} style={{border:"1px solid var(--border-c)"}}><X className="w-2.5 h-2.5 text-red-400"/></button>}</div></div></motion.div>);})}
        <div ref={bottomRef}/>
      </div>
      <div className="p-3 border-t flex-shrink-0" style={{borderColor:"var(--border-c)"}}>
        {!currentUser?<p className="text-center text-xs" style={{color:"var(--text-muted)"}}>Log in to leave a message</p>
         :<div className="flex gap-2"><input className="input flex-1 text-sm" placeholder="Leave a message..." value={text} onChange={e=>setText(e.target.value)} onKeyDown={e=>e.key==="Enter"&&!e.shiftKey&&send()}/><button onClick={send} disabled={sending||!text.trim()} className="w-9 h-9 rounded-full flex items-center justify-center flex-shrink-0 text-white disabled:opacity-40" style={{background:"var(--accent-pink)"}}>{sending?<Loader2 className="w-3.5 h-3.5 animate-spin"/>:<Send className="w-3.5 h-3.5"/>}</button></div>}
      </div>
    </div>
  );
}