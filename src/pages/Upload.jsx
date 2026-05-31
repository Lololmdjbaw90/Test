import React, { useState, useEffect, useRef } from "react";
import { base44 } from "@/api/base44Client";
const UploadFile = (args) => base44.integrations.Core.UploadFile(args);
import { Upload as UploadIcon, Loader2, ImageIcon, Music, Star, X } from "lucide-react";
import { useNavigate } from "react-router-dom";
export default function UploadPage() {
  const navigate=useNavigate(),imgRef=useRef(null),musicRef=useRef(null);
  const [me,setMe]=useState(null),[form,setForm]=useState({title:"",description:"",medium:"",year:"",featured:false}),[imgFile,setImgFile]=useState(null),[imgPreview,setImgPreview]=useState(null),[musicFile,setMusicFile]=useState(null),[submitting,setSubmitting]=useState(false),[done,setDone]=useState(false);
  useEffect(()=>{base44.auth.me().then(u=>{setMe(u);if(u?.role!=="admin")navigate("/");}).catch(()=>navigate("/"));},[]);
  const submit=async(e)=>{
    e.preventDefault(); if(!imgFile||!form.title.trim())return; setSubmitting(true);
    const{file_url}=await UploadFile({file:imgFile});
    let music_url=null; if(musicFile){const r=await UploadFile({file:musicFile});music_url=r.file_url;}
    await base44.entities.Artwork.create({...form,image_url:file_url,music_url,likes:[]});
    await base44.entities.Log.create({action:"artwork_added",details:"Added: \""+form.title+"\"",user_email:me.email}).catch(()=>{});
    setDone(true); setSubmitting(false); setTimeout(()=>navigate("/"),1500);
  };
  const MEDIUMS=["painting","digital","sculpture","mixed_media","drawing","photography","other"];
  return(
    <div className="h-full overflow-y-auto scroll px-4 sm:px-6 py-6 max-w-xl mx-auto w-full">
      <h1 className="text-base font-semibold mb-6" style={{color:"var(--text-primary)"}}>Upload Artwork</h1>
      {done?<div className="card p-8 text-center"><div className="w-12 h-12 rounded-full flex items-center justify-center mx-auto mb-3 text-white" style={{background:"var(--accent-pink)"}}>✓</div><p className="font-medium text-sm" style={{color:"var(--text-primary)"}}>Artwork uploaded!</p></div>:(
        <form onSubmit={submit} className="space-y-4">
          <div className="card p-4"><p className="text-xs font-medium mb-3" style={{color:"var(--text-secondary)"}}>Artwork Image *</p>{imgPreview?<div className="relative rounded-xl overflow-hidden mb-2"><img src={imgPreview} className="w-full max-h-52 object-cover" alt=""/><button type="button" onClick={()=>{setImgFile(null);setImgPreview(null);}} className="absolute top-2 right-2 w-7 h-7 bg-white rounded-full flex items-center justify-center shadow"><X className="w-3.5 h-3.5 text-gray-500"/></button></div>:<button type="button" onClick={()=>imgRef.current?.click()} className="w-full h-32 rounded-xl border-2 border-dashed flex flex-col items-center justify-center gap-2" style={{borderColor:"var(--border-c)"}}><ImageIcon className="w-5 h-5" style={{color:"var(--text-muted)"}}/><span className="text-xs" style={{color:"var(--text-muted)"}}>Click to upload image</span></button>}<input ref={imgRef} type="file" accept="image/*" className="hidden" onChange={e=>{const f=e.target.files?.[0];if(f){setImgFile(f);setImgPreview(URL.createObjectURL(f));}}}/>{!imgPreview&&<button type="button" className="btn-outline text-xs mt-2 w-full justify-center" onClick={()=>imgRef.current?.click()}><UploadIcon className="w-3.5 h-3.5"/> Choose Image</button>}</div>
          <div className="card p-4 space-y-3"><p className="text-xs font-medium" style={{color:"var(--text-secondary)"}}>Details</p><input className="input text-sm" placeholder="Title *" value={form.title} onChange={e=>setForm(f=>({...f,title:e.target.value}))}/><textarea className="input text-sm resize-none" rows={3} placeholder="Description..." value={form.description} onChange={e=>setForm(f=>({...f,description:e.target.value}))}/><select className="input text-sm" value={form.medium} onChange={e=>setForm(f=>({...f,medium:e.target.value}))}><option value="">Medium (optional)</option>{MEDIUMS.map(m=><option key={m} value={m}>{m.replace("_"," ")}</option>)}</select><input className="input text-sm" placeholder="Year (optional)" value={form.year} onChange={e=>setForm(f=>({...f,year:e.target.value}))}/></div>
          <div className="card p-4"><p className="text-xs font-medium mb-2" style={{color:"var(--text-secondary)"}}>Background Music (optional)</p><div className="flex items-center gap-2"><input ref={musicRef} type="file" accept="audio/*,video/*" className="hidden" onChange={e=>setMusicFile(e.target.files?.[0]||null)}/><button type="button" className="btn-outline text-xs flex-1 justify-center" onClick={()=>musicRef.current?.click()}><Music className="w-3.5 h-3.5"/> {musicFile?musicFile.name.slice(0,20):"Choose audio"}</button>{musicFile&&<button type="button" onClick={()=>setMusicFile(null)}><X className="w-4 h-4" style={{color:"var(--text-muted)"}}/></button>}</div></div>
          <label className="card-sm p-3 flex items-center gap-3 cursor-pointer"><input type="checkbox" checked={form.featured} onChange={e=>setForm(f=>({...f,featured:e.target.checked}))} className="w-4 h-4"/><div><p className="text-xs font-medium" style={{color:"var(--text-primary)"}}>Mark as Featured</p></div><Star className="w-4 h-4 ml-auto" style={{color:form.featured?"#f59e0b":"var(--text-muted)"}}/></label>
          <button type="submit" disabled={submitting||!imgFile||!form.title.trim()} className="btn w-full justify-center py-3">{submitting?<><Loader2 className="w-4 h-4 animate-spin"/> Uploading...</>:<><UploadIcon className="w-4 h-4"/> Upload Artwork</>}</button>
        </form>
      )}
    </div>
  );
}