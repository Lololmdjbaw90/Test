import React, { useState, useEffect, useRef } from "react";
import { base44 } from "@/api/base44Client";
const UploadFile = (args) => base44.integrations.Core.UploadFile(args);
import { Plus, Search, Loader2, Trash2, ExternalLink, X, ImageIcon } from "lucide-react";
import { motion } from "framer-motion";
import { Dialog, DialogContent } from "@/components/ui/dialog";
import { Link } from "react-router-dom";

function ArtistAvatar({ commission }) {
  const [err,setErr]=useState(false);
  if(commission.artist_profile_picture&&!err)return<img src={commission.artist_profile_picture} onError={()=>setErr(true)} className="w-8 h-8 rounded-full object-cover flex-shrink-0" alt=""/>;
  return<div className="w-8 h-8 rounded-full flex items-center justify-center text-white text-xs font-semibold flex-shrink-0" style={{ background:"var(--accent-pink)" }}>{commission.artist_display_name?.[0]?.toUpperCase()||"?"}</div>;
}

function CommissionCard({ commission, me, onUpdate, onClick }) {
  const isOwner=me?.email===commission.artist_email,[deleting,setDeleting]=useState(false);
  const del=async(e)=>{e.stopPropagation();setDeleting(true);await base44.entities.Commission.delete(commission.id).catch(()=>{});setDeleting(false);onUpdate();};
  const minPrice=commission.tiers?.length>0?Math.min(...commission.tiers.map(t=>Number(t.price)||0)):null;
  return(
    <motion.div initial={{ opacity:0,y:10 }} animate={{ opacity:1,y:0 }} className="card overflow-hidden cursor-pointer hover:shadow-md transition-shadow group" onClick={onClick}>
      <div className="relative h-44 overflow-hidden" style={{ background:"var(--pink-soft)" }}>
        {commission.samples?.length>0?<img src={commission.samples[0]} alt="" className="w-full h-full object-cover group-hover:scale-105 transition-transform duration-500"/>:<div className="w-full h-full flex items-center justify-center"><ImageIcon className="w-8 h-8" style={{ color:"var(--text-muted)" }}/></div>}
        <div className="absolute top-2 right-2"><span className="text-[10px] font-semibold px-2 py-0.5 rounded-full" style={commission.is_open?{background:"rgba(34,197,94,0.15)",color:"#16a34a"}:{background:"rgba(0,0,0,0.1)",color:"#888"}}>{commission.is_open?"● Open":"Closed"}</span></div>
      </div>
      <div className="p-3 space-y-2">
        <div className="flex items-center gap-2"><ArtistAvatar commission={commission}/><div className="flex-1 min-w-0"><p className="font-semibold text-sm truncate" style={{ color:"var(--text-primary)" }}>{commission.title}</p><Link to={`/Profile?email=${encodeURIComponent(commission.artist_email)}`} onClick={e=>e.stopPropagation()} className="text-[10px]" style={{ color:"var(--text-muted)" }}>{commission.artist_display_name}</Link></div>{isOwner&&<button onClick={del} disabled={deleting} className="w-6 h-6 flex items-center justify-center flex-shrink-0"><Trash2 className="w-3.5 h-3.5 text-red-400"/></button>}</div>
        {commission.description&&<p className="text-xs leading-relaxed line-clamp-2" style={{ color:"var(--text-secondary)" }}>{commission.description}</p>}
        {minPrice!==null&&<p className="text-xs font-semibold" style={{ color:"var(--accent-rose)" }}>Starting at ${minPrice}</p>}
      </div>
    </motion.div>
  );
}

function CommissionDetail({ commission, me, onClose, onUpdate }) {
  const isOwner=me?.email===commission.artist_email,[deleting,setDeleting]=useState(false);
  const del=async()=>{setDeleting(true);await base44.entities.Commission.delete(commission.id).catch(()=>{});setDeleting(false);onClose();onUpdate();};
  return(
    <DialogContent className="max-w-lg w-[95vw] max-h-[90vh] rounded-2xl border-0 p-0 overflow-hidden" style={{ background:"var(--surface)",border:"1px solid var(--border-c)" }}>
      <div className="flex flex-col max-h-[90vh]">
        {commission.samples?.length>0&&<div className="flex-shrink-0 h-52 overflow-hidden relative"><img src={commission.samples[0]} className="w-full h-full object-cover" alt=""/><div className="absolute inset-0 bg-gradient-to-t from-black/30 to-transparent"/></div>}
        <div className="flex-1 overflow-y-auto scroll p-5 space-y-4">
          <div className="flex items-start justify-between gap-3">
            <div><h2 className="font-semibold text-base" style={{ color:"var(--text-primary)" }}>{commission.title}</h2><Link to={`/Profile?email=${encodeURIComponent(commission.artist_email)}`} className="text-xs flex items-center gap-1.5 mt-1" style={{ color:"var(--accent-rose)" }}><ArtistAvatar commission={commission}/>{commission.artist_display_name}</Link></div>
            <span className="text-[10px] font-semibold px-2 py-1 rounded-full flex-shrink-0" style={commission.is_open?{background:"rgba(34,197,94,0.1)",color:"#16a34a",border:"1px solid rgba(34,197,94,0.2)"}:{background:"var(--gray-100)",color:"var(--text-muted)"}}>{commission.is_open?"Open for commissions":"Currently closed"}</span>
          </div>
          {commission.description&&<p className="text-sm leading-relaxed" style={{ color:"var(--text-secondary)" }}>{commission.description}</p>}
          {commission.tiers?.length>0&&<div><p className="text-xs font-semibold uppercase tracking-wider mb-2" style={{ color:"var(--text-muted)" }}>Pricing</p><div className="space-y-2">{commission.tiers.map((t,i)=><div key={i} className="flex items-center justify-between p-3 rounded-xl" style={{ background:"var(--pink-soft)",border:"1px solid var(--border-c)" }}><div><p className="text-sm font-semibold" style={{ color:"var(--text-primary)" }}>{t.name}</p>{t.description&&<p className="text-xs mt-0.5" style={{ color:"var(--text-muted)" }}>{t.description}</p>}{t.delivery_days&&<p className="text-[10px] mt-0.5" style={{ color:"var(--text-muted)" }}>{t.delivery_days} day delivery</p>}</div><p className="text-base font-bold" style={{ color:"var(--accent-rose)" }}>${t.price}</p></div>)}</div></div>}
          <div className="flex gap-2 pt-1">{commission.paypal_link&&commission.is_open&&<a href={commission.paypal_link} target="_blank" rel="noopener noreferrer" className="btn flex-1 justify-center"><ExternalLink className="w-3.5 h-3.5"/> Commission Now</a>}{isOwner&&<button onClick={del} disabled={deleting} className="px-4 py-2 rounded-full text-xs font-semibold text-white flex-shrink-0" style={{ background:"#e05a5a" }}>{deleting?"...":"Delete"}</button>}</div>
        </div>
      </div>
    </DialogContent>
  );
}

function CreateModal({ me, onCreated, onClose }) {
  const [form,setForm]=useState({title:"",description:"",paypal_link:"",is_open:true}),[tiers,setTiers]=useState([{name:"",price:"",description:""}]),[sampleFiles,setSampleFiles]=useState([]),[samplePreviews,setSamplePreviews]=useState([]),[submitting,setSubmitting]=useState(false);
  const fileRef=useRef(null);
  const addSample=(e)=>{const f=e.target.files?.[0];if(!f)return;setSampleFiles(prev=>[...prev,f]);setSamplePreviews(prev=>[...prev,URL.createObjectURL(f)]);};
  const submit=async(e)=>{e.preventDefault();if(!form.title.trim())return;setSubmitting(true);const sampleUrls=await Promise.all(sampleFiles.map(f=>UploadFile({file:f}).then(r=>r.file_url)));await base44.entities.Commission.create({...form,artist_email:me.email,artist_display_name:me.display_name||me.full_name,artist_profile_picture:me.profile_picture||"",tiers:tiers.filter(t=>t.name&&t.price),samples:sampleUrls,tags:[]});onCreated();onClose();setSubmitting(false);};
  return(
    <DialogContent className="max-w-sm w-[92vw] rounded-2xl border-0 p-0 max-h-[88vh] overflow-y-auto scroll" style={{ background:"var(--surface)",border:"1px solid var(--border-c)" }}>
      <div className="p-5">
        <div className="flex items-center justify-between mb-4"><h2 className="font-semibold text-sm" style={{ color:"var(--text-primary)" }}>List Commission</h2><button onClick={onClose}><X className="w-4 h-4" style={{ color:"var(--text-muted)" }}/></button></div>
        <form onSubmit={submit} className="space-y-3">
          <input className="input text-sm" placeholder="Title *" value={form.title} onChange={e=>setForm(f=>({...f,title:e.target.value}))}/>
          <textarea className="input text-sm resize-none" rows={3} placeholder="Describe what you offer..." value={form.description} onChange={e=>setForm(f=>({...f,description:e.target.value}))}/>
          <input className="input text-sm" placeholder="PayPal.me link" value={form.paypal_link} onChange={e=>setForm(f=>({...f,paypal_link:e.target.value}))}/>
          <div><p className="text-xs font-medium mb-1.5" style={{ color:"var(--text-secondary)" }}>Sample Images</p><div className="flex gap-2 flex-wrap">{samplePreviews.map((p,i)=><img key={i} src={p} className="w-14 h-14 rounded-xl object-cover"/>)}<button type="button" onClick={()=>fileRef.current?.click()} className="w-14 h-14 rounded-xl border-2 border-dashed flex items-center justify-center" style={{ borderColor:"var(--border-c)" }}><Plus className="w-4 h-4" style={{ color:"var(--text-muted)" }}/></button></div><input ref={fileRef} type="file" accept="image/*" className="hidden" onChange={addSample}/></div>
          <div><p className="text-xs font-medium mb-1.5" style={{ color:"var(--text-secondary)" }}>Pricing Tiers</p><div className="space-y-2">{tiers.map((t,i)=><div key={i} className="flex gap-2 items-center"><input className="input text-xs flex-1" placeholder="e.g. Sketch" value={t.name} onChange={e=>{const n=[...tiers];n[i].name=e.target.value;setTiers(n);}}/><input className="input text-xs w-20" placeholder="$" type="number" value={t.price} onChange={e=>{const n=[...tiers];n[i].price=e.target.value;setTiers(n);}}/>{tiers.length>1&&<button type="button" onClick={()=>setTiers(tiers.filter((_,j)=>j!==i))}><X className="w-3.5 h-3.5" style={{ color:"var(--text-muted)" }}/></button>}</div>)}</div><button type="button" className="btn-ghost text-xs mt-1.5" onClick={()=>setTiers([...tiers,{name:"",price:"",description:""}])}><Plus className="w-3 h-3"/> Add tier</button></div>
          <label className="flex items-center gap-2 cursor-pointer"><input type="checkbox" checked={form.is_open} onChange={e=>setForm(f=>({...f,is_open:e.target.checked}))} className="w-4 h-4"/><span className="text-xs" style={{ color:"var(--text-secondary)" }}>Open for commissions</span></label>
          <div className="flex gap-2 pt-1"><button type="button" className="flex-1 btn-ghost" onClick={onClose}>Cancel</button><button type="submit" disabled={submitting||!form.title.trim()} className="flex-1 btn justify-center">{submitting?<Loader2 className="w-3.5 h-3.5 animate-spin"/>:"Publish"}</button></div>
        </form>
      </div>
    </DialogContent>
  );
}

export default function CommissionsPage() {
  const [commissions,setCommissions]=useState([]),[me,setMe]=useState(null),[loading,setLoading]=useState(true),[search,setSearch]=useState(""),[showCreate,setShowCreate]=useState(false),[selected,setSelected]=useState(null);
  useEffect(()=>{fetchData();},[]);
  const fetchData=async()=>{setLoading(true);const[cs,me]=await Promise.all([base44.entities.Commission.list("-created_date"),base44.auth.me().catch(()=>null)]);setCommissions(cs);setMe(me);setLoading(false);};
  const filtered=commissions.filter(c=>!search.trim()||c.title?.toLowerCase().includes(search.toLowerCase())||c.artist_display_name?.toLowerCase().includes(search.toLowerCase()));
  return(
    <div className="h-full flex flex-col overflow-hidden">
      <div className="flex-shrink-0 px-4 sm:px-6 py-4 border-b flex items-center gap-3" style={{ background:"var(--surface)",borderColor:"var(--border-c)" }}><div className="flex-1"><h1 className="text-base font-semibold" style={{ color:"var(--text-primary)" }}>Commissions</h1><p className="text-xs" style={{ color:"var(--text-muted)" }}>{commissions.filter(c=>c.is_open).length} open</p></div>{me&&<button className="btn text-xs px-3 py-2" onClick={()=>setShowCreate(true)}><Plus className="w-3.5 h-3.5"/> List</button>}</div>
      <div className="flex-shrink-0 px-4 sm:px-6 py-3 border-b" style={{ background:"var(--surface)",borderColor:"var(--border-c)" }}><div className="relative"><Search className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4" style={{ color:"var(--text-muted)" }}/><input className="input pl-9 text-sm" placeholder="Search artists or styles..." value={search} onChange={e=>setSearch(e.target.value)}/></div></div>
      <div className="flex-1 overflow-y-auto scroll px-4 sm:px-6 py-4">{loading?<div className="flex justify-center py-12"><Loader2 className="w-5 h-5 animate-spin" style={{ color:"var(--accent-pink)" }}/></div>:<div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4 pb-6">{filtered.map(c=><CommissionCard key={c.id} commission={c} me={me} onUpdate={fetchData} onClick={()=>setSelected(c)}/>)}{filtered.length===0&&<p className="col-span-full text-center text-sm py-12" style={{ color:"var(--text-muted)" }}>No commissions yet.</p>}</div>}</div>
      <Dialog open={showCreate} onOpenChange={setShowCreate}>{showCreate&&me&&<CreateModal me={me} onCreated={fetchData} onClose={()=>setShowCreate(false)}/>}</Dialog>
      <Dialog open={!!selected} onOpenChange={v=>!v&&setSelected(null)}>{selected&&<CommissionDetail commission={selected} me={me} onClose={()=>setSelected(null)} onUpdate={fetchData}/>}</Dialog>
    </div>
  );
}