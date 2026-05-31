import React, { useState, useEffect } from "react";
import { base44 } from "@/api/base44Client";
const InvokeLLM = (args) => base44.integrations.Core.InvokeLLM(args);
import { Send, Loader2, Trash2 } from "lucide-react";
import { notify } from "../../utils/notifications";
async function moderate(text) {
  try {
    const r=await InvokeLLM({prompt:"Content moderator. JSON only. Text: \""+text+"\". Flag hate/NSFW/violence. {\"safe\":true/false,\"reason\":\"\"}", response_json_schema:{type:"object",properties:{safe:{type:"boolean"},reason:{type:"string"}}}});
    return r;
  } catch { return {safe:true}; }
}
export default function CommunityCommentSection({ postId, currentUser, postOwnerEmail }) {
  const [comments,setComments]=useState([]),[text,setText]=useState(""),[loading,setLoading]=useState(true),[sending,setSending]=useState(false),[error,setError]=useState(null);
  useEffect(()=>{load();},[postId]);
  const load=async()=>{setLoading(true);const data=await base44.entities.CommunityComment.filter({post_id:postId},"created_date",50);setComments(data);setLoading(false);};
  const send=async()=>{if(!currentUser||!text.trim())return;setSending(true);setError(null);const mod=await moderate(text);if(!mod.safe){setError("Blocked: "+mod.reason);setSending(false);return;}const c=await base44.entities.CommunityComment.create({post_id:postId,content:text.trim(),gif_url:"",user_display_name:currentUser.display_name||currentUser.full_name,user_email:currentUser.email,likes:[]});setComments(p=>[...p,c]);setText("");if(postOwnerEmail&&postOwnerEmail!==currentUser.email){notify({to_email:postOwnerEmail,from_email:currentUser.email,from_display_name:currentUser.display_name||currentUser.full_name,from_profile_picture:currentUser.profile_picture,type:"comment",message:(currentUser.display_name||currentUser.full_name)+" commented on your post",link:"/Community",entity_id:postId});}setSending(false);};
  const del=async(id)=>{await base44.entities.CommunityComment.delete(id);setComments(p=>p.filter(c=>c.id!==id));};
  return(
    <div className="space-y-3">
      <p className="text-xs font-medium" style={{color:"var(--text-secondary)"}}>Comments ({comments.length})</p>
      {loading?<div className="flex justify-center py-4"><Loader2 className="w-4 h-4 animate-spin" style={{color:"var(--accent-pink)"}}/></div>:<div className="space-y-2 max-h-40 overflow-y-auto scroll">{comments.length===0&&<p className="text-xs text-center py-3" style={{color:"var(--text-muted)"}}>No comments yet.</p>}{comments.map(c=><div key={c.id} className="flex gap-2 group"><div className="w-6 h-6 rounded-full flex-shrink-0 flex items-center justify-center text-white text-[10px] font-semibold" style={{background:"var(--accent-pink)"}}>{c.user_display_name?.[0]?.toUpperCase()||"?"}</div><div className="flex-1 min-w-0"><p className="text-xs mt-0.5" style={{color:"var(--text-secondary)"}}>{c.content}</p></div>{currentUser&&(currentUser.email===c.user_email||currentUser.role==="admin")&&<button onClick={()=>del(c.id)} className="opacity-0 group-hover:opacity-100 flex-shrink-0"><Trash2 className="w-3 h-3 text-red-400"/></button>}</div>)}</div>}
      {error&&<p className="text-xs text-red-500">{error}</p>}
      {currentUser?<div className="flex gap-2"><input className="input flex-1 text-xs py-2" placeholder="Add a comment..." value={text} onChange={e=>setText(e.target.value)} onKeyDown={e=>e.key==="Enter"&&!e.shiftKey&&send()}/><button onClick={send} disabled={sending||!text.trim()} className="w-8 h-8 rounded-full flex items-center justify-center text-white flex-shrink-0 disabled:opacity-40" style={{background:"var(--accent-pink)"}}>{sending?<Loader2 className="w-3 h-3 animate-spin"/>:<Send className="w-3 h-3"/>}</button></div>:<p className="text-xs" style={{color:"var(--text-muted)"}}>Log in to comment.</p>}
    </div>
  );
}