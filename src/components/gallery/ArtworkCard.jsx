import React, { useState } from "react";
import { motion } from "framer-motion";
import { Heart, Trash2, Star, Play, Pause, Music, X } from "lucide-react";
import { Dialog, DialogContent } from "@/components/ui/dialog";
import { base44 } from "@/api/base44Client";
import CommentSection from "./CommentSection";
import PingButton from "./PingButton";

export default function ArtworkCard({ artwork, index, onUpdate, isAdmin, currentUser }) {
  const [showDetail,setShowDetail]=useState(false),[showDelete,setShowDelete]=useState(false),[deleting,setDeleting]=useState(false),[playing,setPlaying]=useState(false),[audio,setAudio]=useState(null),[likes,setLikes]=useState(artwork.likes||[]);
  const liked=currentUser?likes.includes(currentUser.email):false;
  const handleLike=async(e)=>{e?.stopPropagation();if(!currentUser)return;const next=liked?likes.filter(e=>e!==currentUser.email):[...likes,currentUser.email];setLikes(next);await base44.entities.Artwork.update(artwork.id,{likes:next}).catch(()=>setLikes(artwork.likes||[]));};
  const handleDelete=async()=>{setDeleting(true);await base44.entities.Artwork.delete(artwork.id).catch(()=>{});setDeleting(false);setShowDelete(false);onUpdate();};
  const toggleFeatured=async(e)=>{e.stopPropagation();await base44.entities.Artwork.update(artwork.id,{featured:!artwork.featured});onUpdate();};
  const togglePlay=(e)=>{e?.stopPropagation();if(!audio)return;if(playing){audio.pause();setPlaying(false);}else{audio.play();setPlaying(true);}};
  return(
    <>
      <motion.div initial={{ opacity:0,y:12 }} animate={{ opacity:1,y:0 }} transition={{ delay:index*0.03 }} className="group cursor-pointer card-sm overflow-hidden" onClick={()=>setShowDetail(true)}>
        <div className="relative overflow-hidden">
          <img src={artwork.image_url} alt={artwork.title} className="w-full object-cover transition-transform duration-500 group-hover:scale-105"/>
          <div className="absolute inset-0 bg-black/0 group-hover:bg-black/20 transition-all duration-300"/>
          {artwork.featured&&<div className="absolute top-2 left-2"><span className="badge-pink flex items-center gap-1"><Star className="w-2.5 h-2.5"/> Featured</span></div>}
          {artwork.music_url&&<div className="absolute top-2 right-2"><span className="badge-pink flex items-center gap-1"><Music className="w-2.5 h-2.5"/></span></div>}
          <div className="absolute bottom-2 left-2 right-2 flex items-center justify-between opacity-0 group-hover:opacity-100 transition-all duration-200">
            <button onClick={handleLike} disabled={!currentUser} className="flex items-center gap-1 px-2 py-1 rounded-full text-xs font-semibold transition-all" style={{ background:liked?"var(--accent-pink)":"rgba(255,255,255,0.9)",color:liked?"white":"var(--text-secondary)" }}><Heart className={`w-3 h-3 ${liked?"fill-current":""}`}/> {likes.length}</button>
            <div onClick={e=>e.stopPropagation()} className="flex gap-1">
              <PingButton artwork={artwork} currentUser={currentUser}/>
              {isAdmin&&<><button onClick={toggleFeatured} className="w-6 h-6 rounded-full flex items-center justify-center" style={{ background:"rgba(255,255,255,0.9)" }}><Star className={`w-3 h-3 ${artwork.featured?"fill-yellow-400 text-yellow-400":"text-gray-400"}`}/></button><button onClick={e=>{e.stopPropagation();setShowDelete(true);}} className="w-6 h-6 rounded-full flex items-center justify-center" style={{ background:"rgba(255,255,255,0.9)" }}><Trash2 className="w-3 h-3 text-red-400"/></button></>}
            </div>
          </div>
        </div>
        <div className="px-2.5 py-2"><p className="text-xs font-semibold truncate" style={{ color:"var(--text-primary)" }}>{artwork.title}</p>{artwork.medium&&<p className="text-[10px] mt-0.5 capitalize" style={{ color:"var(--text-muted)" }}>{artwork.medium.replace("_"," ")}</p>}</div>
      </motion.div>
      <Dialog open={showDetail} onOpenChange={setShowDetail}>
        <DialogContent className="max-w-3xl w-[95vw] max-h-[90vh] p-0 overflow-hidden rounded-2xl border-0" style={{ background:"var(--surface)",border:"1px solid var(--border-c)" }}>
          <div className="flex flex-col md:flex-row max-h-[90vh]">
            <div className="md:w-1/2 flex items-center justify-center p-4" style={{ background:"var(--pink-soft)" }}><img src={artwork.image_url} alt={artwork.title} className="max-w-full max-h-80 object-contain rounded-xl shadow"/></div>
            <div className="md:w-1/2 flex flex-col overflow-hidden">
              <div className="p-4 border-b flex items-start justify-between flex-shrink-0" style={{ borderColor:"var(--border-c)" }}>
                <div><h2 className="font-semibold text-base" style={{ color:"var(--text-primary)" }}>{artwork.title}</h2>{artwork.medium&&<span className="badge-pink mt-1 inline-block capitalize">{artwork.medium.replace("_"," ")}</span>}</div>
                <button onClick={()=>setShowDetail(false)} className="w-8 h-8 rounded-full flex items-center justify-center flex-shrink-0" style={{ background:"var(--pink-soft)" }}><X className="w-4 h-4" style={{ color:"var(--text-muted)" }}/></button>
              </div>
              <div className="flex-1 overflow-y-auto scroll p-4 space-y-4">
                {artwork.description&&<p className="text-sm leading-relaxed" style={{ color:"var(--text-secondary)" }}>{artwork.description}</p>}
                {artwork.music_url&&<div className="rounded-xl p-3 flex items-center gap-3" style={{ background:"var(--pink-soft)" }}><button onClick={togglePlay} className="w-9 h-9 rounded-full flex items-center justify-center flex-shrink-0" style={{ background:"var(--accent-pink)" }}>{playing?<Pause className="w-4 h-4 text-white"/>:<Play className="w-4 h-4 text-white ml-0.5"/>}</button><div className="flex-1 min-w-0"><p className="text-xs font-medium" style={{ color:"var(--text-secondary)" }}>Background Music</p><audio ref={setAudio} src={artwork.music_url} onEnded={()=>setPlaying(false)} className="w-full mt-1 h-6" controls/></div></div>}
                <div className="flex items-center gap-2">
                  <button onClick={handleLike} disabled={!currentUser} className="flex items-center gap-1.5 px-3 py-1.5 rounded-full text-sm font-medium transition-all" style={liked?{background:"var(--accent-pink)",color:"white"}:{background:"var(--pink-soft)",color:"var(--accent-rose)",border:"1px solid var(--border-c)"}}><Heart className={`w-3.5 h-3.5 ${liked?"fill-current":""}`}/> {likes.length}</button>
                  <PingButton artwork={artwork} currentUser={currentUser}/>
                </div>
                <CommentSection artworkId={artwork.id} currentUser={currentUser}/>
              </div>
            </div>
          </div>
        </DialogContent>
      </Dialog>
      {isAdmin&&<Dialog open={showDelete} onOpenChange={setShowDelete}><DialogContent className="max-w-xs rounded-2xl border-0" style={{ background:"var(--surface)",border:"1px solid var(--border-c)" }}><div className="p-4 text-center"><div className="w-12 h-12 rounded-full flex items-center justify-center mx-auto mb-3" style={{ background:"#fff0f0" }}><Trash2 className="w-5 h-5 text-red-400"/></div><h3 className="font-semibold text-sm mb-1" style={{ color:"var(--text-primary)" }}>Delete artwork?</h3><p className="text-xs mb-4" style={{ color:"var(--text-muted)" }}>"{artwork.title}" will be permanently removed.</p><div className="flex gap-2"><button onClick={()=>setShowDelete(false)} className="flex-1 btn-outline text-sm py-2">Cancel</button><button onClick={handleDelete} disabled={deleting} className="flex-1 text-sm py-2 rounded-full font-semibold text-white transition-all" style={{ background:"#e05a5a" }}>{deleting?"Deleting...":"Delete"}</button></div></div></DialogContent></Dialog>}
    </>
  );
}