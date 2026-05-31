import React, { useState, useEffect, useRef } from "react";
import { base44 } from "@/api/base44Client";
const UploadFile = (args) => base44.integrations.Core.UploadFile(args);
const InvokeLLM = (args) => base44.integrations.Core.InvokeLLM(args);
import { Upload, Play, Pause, Heart, Trash2, Loader2, Music as MusicIcon, Search } from "lucide-react";
import { motion } from "framer-motion";

function MusicCard({ review, currentUser, onUpdate }) {
  const [playing,setPlaying]=useState(false),[audio,setAudio]=useState(null),[likes,setLikes]=useState(review.likes||[]),[deleting,setDeleting]=useState(false);
  const liked=currentUser?likes.includes(currentUser.email):false;
  const canDelete=currentUser&&(currentUser.email===review.user_email||currentUser.role==="admin");
  const togglePlay=()=>{if(!audio)return;if(playing){audio.pause();setPlaying(false);}else{audio.play();setPlaying(true);}};
  const handleLike=async()=>{if(!currentUser)return;const next=liked?likes.filter(e=>e!==currentUser.email):[...likes,currentUser.email];setLikes(next);await base44.entities.MusicReview.update(review.id,{likes:next}).catch(()=>setLikes(review.likes||[]));};
  const handleDelete=async()=>{setDeleting(true);await base44.entities.MusicReview.delete(review.id).catch(()=>{});setDeleting(false);onUpdate();};
  return(
    <motion.div initial={{opacity:0,y:10}} animate={{opacity:1,y:0}} className="card p-4 space-y-3">
      <div className="flex items-start gap-3">
        <button onClick={togglePlay} className="w-10 h-10 rounded-full flex items-center justify-center text-white flex-shrink-0" style={{background:"var(--accent-pink)"}}>{playing?<Pause className="w-4 h-4"/>:<Play className="w-4 h-4 ml-0.5"/>}</button>
        <div className="flex-1 min-w-0"><p className="font-medium text-sm truncate" style={{color:"var(--text-primary)"}}>{review.title||"Untitled"}</p>{review.author&&<p className="text-xs" style={{color:"var(--text-muted)"}}>{review.author}</p>}<div className="flex gap-2 mt-1 flex-wrap">{review.genre&&<span className="badge-pink">{review.genre}</span>}{review.mood&&<span className="badge-pink">{review.mood}</span>}</div></div>
        {canDelete&&<button onClick={handleDelete} disabled={deleting} className="flex-shrink-0"><Trash2 className="w-3.5 h-3.5 text-red-400"/></button>}
      </div>
      <audio ref={setAudio} src={review.music_url} onEnded={()=>setPlaying(false)} className="w-full h-8" controls/>
      {review.ai_review&&<div className="rounded-xl p-3 text-xs leading-relaxed" style={{background:"var(--pink-soft)",color:"var(--text-secondary)"}}>{review.ai_review}</div>}
      <div className="flex items-center justify-between"><p className="text-[10px]" style={{color:"var(--text-muted)"}}>{review.user_display_name}</p><button onClick={handleLike} disabled={!currentUser} className="flex items-center gap-1 text-xs font-medium" style={{color:liked?"var(--accent-rose)":"var(--text-muted)"}}><Heart className={`w-3.5 h-3.5 ${liked?"fill-current":""}`}/> {likes.length}</button></div>
    </motion.div>
  );
}

function UploadForm({ user, onUploaded }) {
  const [file,setFile]=useState(null),[title,setTitle]=useState(""),[submitting,setSubmitting]=useState(false);
  const fileRef=useRef(null);
  const submit=async(e)=>{
    e.preventDefault(); if(!file)return; setSubmitting(true);
    const{file_url}=await UploadFile({file});
    let ai={genre:"",mood:"",ai_review:"",identified_song:""};
    try{
      const prompt = `Analyze this track at ${file_url}. Return JSON: {"genre":"...","mood":"...","ai_review":"...(2-3 sentences)","identified_song":"...or empty"}`;
      ai=await InvokeLLM({prompt,response_json_schema:{type:"object",properties:{genre:{type:"string"},mood:{type:"string"},ai_review:{type:"string"},identified_song:{type:"string"}}}});
    }catch{}
    await base44.entities.MusicReview.create({title:title||file.name.replace(/\.[^.]+$/,""),music_url:file_url,...ai,user_display_name:user.display_name||user.full_name,user_email:user.email,likes:[]});
    setFile(null);setTitle("");if(fileRef.current)fileRef.current.value="";onUploaded();setSubmitting(false);
  };
  return(<form onSubmit={submit} className="card p-4 mb-4 space-y-3"><p className="text-xs font-medium" style={{color:"var(--text-secondary)"}}>Share a track</p><input className="input text-sm" placeholder="Title (optional)" value={title} onChange={e=>setTitle(e.target.value)}/><div className="flex items-center gap-2"><input ref={fileRef} type="file" accept="audio/*,video/*" className="hidden" onChange={e=>setFile(e.target.files?.[0]||null)}/><button type="button" className="btn-outline text-xs flex-1" onClick={()=>fileRef.current?.click()}><Upload className="w-3.5 h-3.5"/> {file?file.name.slice(0,20):"Choose audio file"}</button><button type="submit" disabled={!file||submitting} className="btn text-xs">{submitting?<Loader2 className="w-3.5 h-3.5 animate-spin"/>:"Upload"}</button></div></form>);
}

export default function MusicPage() {
  const [reviews,setReviews]=useState([]),[filtered,setFiltered]=useState([]),[loading,setLoading]=useState(true),[search,setSearch]=useState(""),[user,setUser]=useState(null);
  useEffect(()=>{fetchData();},[]);
  useEffect(()=>{const q=search.trim().toLowerCase();setFiltered(q?reviews.filter(r=>r.title?.toLowerCase().includes(q)||r.user_display_name?.toLowerCase().includes(q)):reviews);},[search,reviews]);
  const fetchData=async()=>{setLoading(true);const[rs,me]=await Promise.all([base44.entities.MusicReview.list("-created_date"),base44.auth.me().catch(()=>null)]);setReviews(rs);setFiltered(rs);setUser(me);setLoading(false);};
  return(
    <div className="h-full flex flex-col overflow-hidden">
      <div className="flex-shrink-0 px-4 sm:px-6 py-4 border-b flex items-center gap-3" style={{background:"var(--surface)",borderColor:"var(--border-c)"}}><MusicIcon className="w-5 h-5 flex-shrink-0" style={{color:"var(--accent-pink)"}}/><div className="flex-1"><h1 className="text-base font-semibold" style={{color:"var(--text-primary)"}}>Music</h1><p className="text-xs" style={{color:"var(--text-muted)"}}>{reviews.length} tracks</p></div></div>
      <div className="flex-shrink-0 px-4 sm:px-6 py-3 border-b" style={{background:"var(--surface)",borderColor:"var(--border-c)"}}><div className="relative"><Search className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4" style={{color:"var(--text-muted)"}}/><input className="input pl-9 text-sm" placeholder="Search music..." value={search} onChange={e=>setSearch(e.target.value)}/></div></div>
      <div className="flex-1 overflow-y-auto scroll px-4 sm:px-6 py-4">
        {user&&<UploadForm user={user} onUploaded={fetchData}/>}
        {loading?<div className="flex justify-center py-12"><Loader2 className="w-5 h-5 animate-spin" style={{color:"var(--accent-pink)"}}/></div>:<div className="space-y-3 pb-6">{filtered.map(r=><MusicCard key={r.id} review={r} currentUser={user} onUpdate={fetchData}/>)}{filtered.length===0&&<p className="text-center text-sm py-12" style={{color:"var(--text-muted)"}}>No tracks yet.</p>}</div>}
      </div>
    </div>
  );
}