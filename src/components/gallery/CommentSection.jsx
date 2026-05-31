import React, { useState, useEffect } from "react";
import { base44 } from "@/api/base44Client";
import { Send, Loader2, Trash2 } from "lucide-react";
export default function CommentSection({ artworkId, currentUser }) {
  const [comments,setComments]=useState([]),[text,setText]=useState(""),[loading,setLoading]=useState(true),[sending,setSending]=useState(false);
  useEffect(()=>{load();},[artworkId]);
  const load=async()=>{setLoading(true);const data=await base44.entities.Comment.filter({artwork_id:artworkId},"created_date",50);setComments(data);setLoading(false);};
  const send=async()=>{if(!currentUser||!text.trim())return;setSending(true);const c=await base44.entities.Comment.create({artwork_id:artworkId,content:text.trim(),user_full_name:currentUser.display_name||currentUser.full_name,user_email:currentUser.email,likes:[]});setComments(p=>[...p,c]);setText("");setSending(false);};
  const del=async(id)=>{await base44.entities.Comment.delete(id);setComments(p=>p.filter(c=>c.id!==id));};
  return(
    <div className="space-y-3 pt-2 border-t" style={{borderColor:"var(--border-c)"}}>
      <p className="text-xs font-medium" style={{color:"var(--text-secondary)"}}>Comments ({comments.length})</p>
      {loading?<div className="flex justify-center py-3"><Loader2 className="w-4 h-4 animate-spin" style={{color:"var(--accent-pink)"}}/></div>:<div className="space-y-2 max-h-40 overflow-y-auto scroll">{comments.length===0&&<p className="text-xs text-center py-3" style={{color:"var(--text-muted)"}}>No comments yet.</p>}{comments.map(c=><div key={c.id} className="flex gap-2 group"><div className="w-6 h-6 rounded-full flex-shrink-0 flex items-center justify-center text-white text-[10px] font-semibold" style={{background:"var(--accent-pink)"}}>{c.user_full_name?.[0]?.toUpperCase()||"?"}</div><div className="flex-1 min-w-0"><span className="text-[10px] font-semibold" style={{color:"var(--text-primary)"}}>{c.user_full_name} </span><span className="text-xs" style={{color:"var(--text-secondary)"}}>{c.content}</span></div>{currentUser&&(currentUser.email===c.user_email||currentUser.role==="admin")&&<button onClick={()=>del(c.id)} className="opacity-0 group-hover:opacity-100 flex-shrink-0"><Trash2 className="w-3 h-3 text-red-400"/></button>}</div>)}</div>}
      {currentUser?<div className="flex gap-2"><input className="input flex-1 text-xs py-2" placeholder="Add a comment..." value={text} onChange={e=>setText(e.target.value)} onKeyDown={e=>e.key==="Enter"&&!e.shiftKey&&send()}/><button onClick={send} disabled={sending||!text.trim()} className="w-8 h-8 rounded-full flex items-center justify-center text-white flex-shrink-0 disabled:opacity-40" style={{background:"var(--accent-pink)"}}>{sending?<Loader2 className="w-3 h-3 animate-spin"/>:<Send className="w-3 h-3"/>}</button></div>:<p className="text-xs" style={{color:"var(--text-muted)"}}>Log in to comment.</p>}
    </div>
  );
}