import React, { useState, useEffect, useRef } from "react";
import { base44 } from "@/api/base44Client";
const UploadFile = (args) => base44.integrations.Core.UploadFile(args);
const InvokeLLM = (args) => base44.integrations.Core.InvokeLLM(args);
import { ImageIcon, Loader2, Search, Shield, X, Download } from "lucide-react";
import { AnimatePresence, motion } from "framer-motion";
import PostCard from "../components/community/PostCard";
import { exportToCsv } from "../utils/exportCsv";
import { sendModerationStrike } from "../utils/discordWebhook";

async function moderate(text, imageUrl) {
  try {
    const prompt = `Content moderator. JSON only. Text: "${text||""}" Image: "${imageUrl||""}". Flag hate speech, explicit NSFW, violence. Art is fine. {"safe": true/false, "reason": ""}`;
    const r = await InvokeLLM({ prompt, response_json_schema: { type: "object", properties: { safe: { type: "boolean" }, reason: { type: "string" } } } });
    return r;
  } catch { return { safe: true }; }
}

function PostForm({ user, onPosted }) {
  const [img,setImg]=useState(null),[preview,setPreview]=useState(null),[title,setTitle]=useState(""),[desc,setDesc]=useState(""),[submitting,setSubmitting]=useState(false),[error,setError]=useState(null),[expanded,setExpanded]=useState(false);
  const imgRef=useRef(null);
  const submit=async(e)=>{
    e.preventDefault(); if(!img)return; setSubmitting(true); setError(null);
    const{file_url}=await UploadFile({file:img});
    const mod=await moderate(title+" "+desc,file_url);
    if(!mod.safe){setError("Blocked: "+mod.reason);sendModerationStrike({userEmail:user.email,displayName:user.display_name||user.full_name,reason:mod.reason,content:(title+" "+desc).trim()});setSubmitting(false);return;}
    await base44.entities.CommunityPost.create({title,description:desc,image_url:file_url,user_display_name:user.display_name||user.full_name,user_email:user.email});
    await base44.auth.updateMe({xp:(user.xp||0)+20,coins:(user.coins||0)+5});
    setImg(null);setPreview(null);setTitle("");setDesc("");setExpanded(false);
    if(imgRef.current)imgRef.current.value=""; onPosted(); setSubmitting(false);
  };
  return(
    <div className="card mb-4 overflow-hidden">
      <div className="p-3 flex items-center gap-3">
        <div className="w-8 h-8 rounded-full flex-shrink-0 flex items-center justify-center font-semibold text-white text-xs" style={{background:"var(--accent-pink)"}}>{user.display_name?.[0]?.toUpperCase()||"?"}</div>
        <div className="flex-1 px-3 py-2 rounded-full text-sm cursor-pointer" style={{background:"var(--pink-soft)",color:"var(--text-muted)"}} onClick={()=>imgRef.current?.click()}>Share your artwork...</div>
        <button onClick={()=>imgRef.current?.click()} className="btn text-xs px-3 py-2"><ImageIcon className="w-3.5 h-3.5"/> Upload</button>
        <input ref={imgRef} type="file" accept="image/*" className="hidden" onChange={e=>{const f=e.target.files?.[0];if(f?.type.startsWith("image/")){setImg(f);setPreview(URL.createObjectURL(f));setExpanded(true);setError(null);}}}/>
      </div>
      <AnimatePresence>{expanded&&<motion.div initial={{height:0}} animate={{height:"auto"}} exit={{height:0}} className="overflow-hidden"><form onSubmit={submit} className="px-3 pb-3 space-y-2">{error&&<p className="text-xs text-red-500 px-1">{error}</p>}{preview&&<div className="relative rounded-xl overflow-hidden"><img src={preview} className="w-full max-h-48 object-cover" alt=""/><button type="button" onClick={()=>{setImg(null);setPreview(null);}} className="absolute top-2 right-2 w-6 h-6 rounded-full flex items-center justify-center bg-white shadow"><X className="w-3.5 h-3.5 text-gray-500"/></button></div>}<input className="input text-sm" placeholder="Title (optional)" value={title} onChange={e=>setTitle(e.target.value)}/><textarea className="input text-sm resize-none" rows={2} placeholder="Description..." value={desc} onChange={e=>setDesc(e.target.value)}/><div className="flex gap-2 justify-end"><button type="button" className="btn-ghost text-xs" onClick={()=>{setExpanded(false);setImg(null);setPreview(null);}}>Cancel</button><button type="submit" disabled={submitting||!img} className="btn text-xs">{submitting?<Loader2 className="w-3.5 h-3.5 animate-spin"/>:"Post"}</button></div></form></motion.div>}</AnimatePresence>
    </div>
  );
}

export default function CommunityPage() {
  const [posts,setPosts]=useState([]),[filtered,setFiltered]=useState([]),[loading,setLoading]=useState(true),[search,setSearch]=useState(""),[user,setUser]=useState(null),[topEmail,setTopEmail]=useState(null);
  useEffect(()=>{fetchData();},[]);
  useEffect(()=>{const q=search.trim().toLowerCase();setFiltered(q?posts.filter(p=>p.title?.toLowerCase().includes(q)||p.user_display_name?.toLowerCase().includes(q)):posts);},[search,posts]);
  const fetchData=async()=>{setLoading(true);const[ps,me]=await Promise.all([base44.entities.CommunityPost.list("-created_date"),base44.auth.me().catch(()=>null)]);setPosts(ps);setFiltered(ps);setUser(me);const stats={};ps.forEach(p=>{if(!p.user_email)return;if(!stats[p.user_email])stats[p.user_email]=0;stats[p.user_email]+=p.likes?.length||0;});const top=Object.entries(stats).sort((a,b)=>b[1]-a[1])[0];setTopEmail(top?.[0]||null);setLoading(false);};
  return(
    <div className="h-full flex flex-col overflow-hidden">
      <div className="flex-shrink-0 px-4 sm:px-6 py-4 border-b flex items-center gap-3" style={{background:"var(--surface)",borderColor:"var(--border-c)"}}>
        <div className="flex-1"><h1 className="text-base font-semibold" style={{color:"var(--text-primary)"}}>Community</h1><p className="text-xs" style={{color:"var(--text-muted)"}}>{posts.length} posts</p></div>
        <div className="flex items-center gap-2">
          <button onClick={()=>exportToCsv(filtered.map(p=>({title:p.title||"",user:p.user_display_name,likes:p.likes?.length||0})),"community")} className="btn-outline text-xs px-3 py-2"><Download className="w-3.5 h-3.5"/></button>
          <div className="flex items-center gap-1.5 text-[10px] font-medium px-2 py-1 rounded-full" style={{background:"rgba(34,197,94,0.08)",color:"#16a34a"}}><Shield className="w-3 h-3"/> AI Moderated</div>
        </div>
      </div>
      <div className="flex-shrink-0 px-4 sm:px-6 py-3 border-b" style={{background:"var(--surface)",borderColor:"var(--border-c)"}}><div className="relative"><Search className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4" style={{color:"var(--text-muted)"}}/><input className="input pl-9 text-sm" placeholder="Search posts..." value={search} onChange={e=>setSearch(e.target.value)}/></div></div>
      <div className="flex-1 overflow-y-auto scroll px-4 sm:px-6 py-4">
        {user?.display_name&&<PostForm user={user} onPosted={fetchData}/>}
        {!user?.display_name&&user&&<div className="card p-3 mb-4 text-sm text-center" style={{color:"var(--text-muted)"}}>Set a display name in <a href="/Settings" className="underline" style={{color:"var(--accent-rose)"}}>Settings</a> to post.</div>}
        {loading?<div className="flex justify-center py-12"><Loader2 className="w-5 h-5 animate-spin" style={{color:"var(--accent-pink)"}}/></div>:<div className="columns-1 sm:columns-2 lg:columns-3 gap-4 pb-6">{filtered.map((post,i)=><div key={post.id} className="break-inside-avoid mb-4"><PostCard post={post} index={i} onUpdate={fetchData} currentUser={user} isTopArtist={post.user_email===topEmail}/></div>)}</div>}
      </div>
    </div>
  );
}