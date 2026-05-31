import React, { useState, useEffect, useRef } from "react";
import { base44 } from "@/api/base44Client";
const UploadFile = (args) => base44.integrations.Core.UploadFile(args);
import { Search, Plus, Users, Loader2, X, Hash, ChevronRight, Upload } from "lucide-react";
import ImageCropper from "../components/common/ImageCropper";
import { motion } from "framer-motion";
import { useNavigate } from "react-router-dom";
import { Dialog, DialogContent } from "@/components/ui/dialog";

function CreateModal({ me, onCreated, onClose }) {
  const [form, setForm] = useState({ name:"",description:"",icon_emoji:"🌸",welcome_message:"" });
  const [submitting, setSubmitting] = useState(false), [iconFile, setIconFile] = useState(null), [iconPreview, setIconPreview] = useState(null), [iconCropSrc, setIconCropSrc] = useState(null);
  const iconRef = useRef(null);
  const submit = async (e) => {
    e.preventDefault(); if (!form.name.trim()) return; setSubmitting(true);
    let icon_url = ""; if (iconFile) { const r = await UploadFile({ file: iconFile }); icon_url = r.file_url; }
    await base44.entities.Community.create({ name:form.name.trim(),description:form.description.trim(),icon_emoji:form.icon_emoji,icon_url,banner_url:"",owner_email:me.email,owner_display_name:me.display_name||me.full_name,member_emails:[me.email],welcome_message:form.welcome_message.trim() });
    onCreated(); onClose(); setSubmitting(false);
  };
  return (
    <DialogContent className="max-w-sm w-[90vw] rounded-2xl border-0 p-0" style={{ background:"var(--surface)",border:"1px solid var(--border-c)" }}>
      <div className="p-5">
        <div className="flex items-center justify-between mb-4"><h2 className="font-semibold text-sm" style={{ color:"var(--text-primary)" }}>Create Server</h2><button onClick={onClose}><X className="w-4 h-4" style={{ color:"var(--text-muted)" }}/></button></div>
        <form onSubmit={submit} className="space-y-3">
          <div className="flex flex-col items-center gap-2 mb-3">
            <div className="w-16 h-16 rounded-2xl overflow-hidden flex items-center justify-center text-2xl cursor-pointer" style={{ background:"var(--pink-soft)" }} onClick={() => iconRef.current?.click()}>{iconPreview?<img src={iconPreview} className="w-full h-full object-cover" alt=""/>:form.icon_emoji}</div>
            <input ref={iconRef} type="file" accept="image/*" className="hidden" onChange={e=>{const f=e.target.files?.[0];if(f){setIconCropSrc(URL.createObjectURL(f));e.target.value="";}}} />
            <div className="flex items-center gap-2">
              <button type="button" className="btn-outline text-xs px-2.5 py-1" onClick={() => iconRef.current?.click()}><Upload className="w-3 h-3"/> {iconPreview?"Change":"Upload Icon"}</button>
              {!iconPreview && <input className="input text-center text-sm" placeholder="emoji" value={form.icon_emoji} onChange={e=>setForm(f=>({...f,icon_emoji:e.target.value}))} style={{ width:70 }}/>}
              {iconPreview && <button type="button" className="btn-ghost text-xs text-red-400" onClick={() => {setIconFile(null);setIconPreview(null);}}>Remove</button>}
            </div>
          </div>
          <input className="input text-sm" placeholder="Server name *" value={form.name} onChange={e=>setForm(f=>({...f,name:e.target.value}))} />
          <textarea className="input text-sm resize-none" rows={2} placeholder="Description..." value={form.description} onChange={e=>setForm(f=>({...f,description:e.target.value}))} />
          <textarea className="input text-sm resize-none" rows={2} placeholder="Welcome message..." value={form.welcome_message} onChange={e=>setForm(f=>({...f,welcome_message:e.target.value}))} />
          <div className="flex gap-2 pt-1"><button type="button" className="flex-1 btn-ghost" onClick={onClose}>Cancel</button><button type="submit" disabled={submitting||!form.name.trim()} className="flex-1 btn justify-center">{submitting?<Loader2 className="w-3.5 h-3.5 animate-spin"/>:"Create"}</button></div>
        </form>
      </div>
      {iconCropSrc && <div className="absolute inset-0 z-10 flex items-center justify-center p-4 rounded-2xl" style={{ background:"rgba(0,0,0,0.7)" }}><ImageCropper imageSrc={iconCropSrc} onCrop={(file,url)=>{setIconFile(file);setIconPreview(url);setIconCropSrc(null);}} onCancel={() => setIconCropSrc(null)} /></div>}
    </DialogContent>
  );
}

export default function CommunitiesPage() {
  const [communities, setCommunities] = useState([]), [me, setMe] = useState(null), [loading, setLoading] = useState(true), [search, setSearch] = useState(""), [showCreate, setShowCreate] = useState(false), [tab, setTab] = useState("all");
  const navigate = useNavigate();
  useEffect(() => { fetchData(); }, []);
  const fetchData = async () => { setLoading(true); const [cs,me] = await Promise.all([base44.entities.Community.list("-created_date"),base44.auth.me().catch(()=>null)]); setCommunities(cs); setMe(me); setLoading(false); };
  const join = async (e, community) => {
    e.stopPropagation(); if (!me) return;
    const isMember = community.member_emails?.includes(me.email);
    const next = isMember ? community.member_emails.filter(em=>em!==me.email) : [...(community.member_emails||[]),me.email];
    await base44.entities.Community.update(community.id,{member_emails:next});
    if (!isMember && community.welcome_message?.trim()) await base44.entities.CommunityComment.create({ post_id:`community_chat_${community.id}`,content:community.welcome_message.trim(),gif_url:"",user_display_name:community.owner_display_name||"Admin",user_email:community.owner_email,likes:[] });
    fetchData();
  };
  const filtered = communities.filter(c => { if(search.trim()&&!c.name?.toLowerCase().includes(search.toLowerCase()))return false; if(tab==="mine")return c.owner_email===me?.email; if(tab==="joined")return c.member_emails?.includes(me?.email); return true; });
  const TABS = [{id:"all",label:"Discover"},{id:"joined",label:"Joined"},{id:"mine",label:"Mine"}];
  return (
    <div className="h-full flex flex-col overflow-hidden">
      <div className="flex-shrink-0 px-4 sm:px-6 py-4 border-b flex items-center gap-3" style={{ background:"var(--surface)",borderColor:"var(--border-c)" }}>
        <div className="flex-1"><h1 className="text-base font-semibold" style={{ color:"var(--text-primary)" }}>Servers</h1><p className="text-xs" style={{ color:"var(--text-muted)" }}>{communities.length} communities</p></div>
        {me && <button className="btn text-xs px-3 py-2" onClick={() => setShowCreate(true)}><Plus className="w-3.5 h-3.5"/> New Server</button>}
      </div>
      <div className="flex-shrink-0 px-4 sm:px-6 py-3 space-y-2 border-b" style={{ background:"var(--surface)",borderColor:"var(--border-c)" }}>
        <div className="relative"><Search className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4" style={{ color:"var(--text-muted)" }}/><input className="input pl-9 text-sm" placeholder="Search servers..." value={search} onChange={e=>setSearch(e.target.value)}/></div>
        <div className="flex gap-1">{TABS.map(t=><button key={t.id} onClick={()=>setTab(t.id)} className="text-xs px-3 py-1.5 rounded-full font-medium transition-all" style={tab===t.id?{background:"var(--accent-pink)",color:"white"}:{background:"var(--pink-soft)",color:"var(--text-secondary)"}}>{t.label}</button>)}</div>
      </div>
      <div className="flex-1 overflow-y-auto scroll px-4 sm:px-6 py-4">
        {loading ? <div className="flex justify-center py-12"><Loader2 className="w-5 h-5 animate-spin" style={{ color:"var(--accent-pink)" }}/></div> : (
          <div className="space-y-2 pb-6 max-w-2xl mx-auto">
            {filtered.length === 0 && <p className="text-center text-sm py-12" style={{ color:"var(--text-muted)" }}>No servers found.</p>}
            {filtered.map((c,i) => { const isMember = me && c.member_emails?.includes(me.email); return (
              <motion.div key={c.id} initial={{ opacity:0,y:8 }} animate={{ opacity:1,y:0 }} transition={{ delay:i*0.03 }}>
                <div onClick={() => navigate(`/CommunityChat?id=${c.id}`)} className="card-sm overflow-hidden flex items-center gap-3 p-3 cursor-pointer hover:shadow-sm transition-shadow group">
                  <div className="relative flex-shrink-0"><div className="w-12 h-12 rounded-xl flex items-center justify-center overflow-hidden" style={{ background:c.banner_url?"transparent":"var(--accent-pink)" }}>{c.banner_url?<img src={c.banner_url} className="w-full h-full object-cover" alt=""/>:c.icon_url?<img src={c.icon_url} className="w-full h-full object-cover" alt=""/>:<span className="text-2xl">{c.icon_emoji||"💬"}</span>}</div></div>
                  <div className="flex-1 min-w-0"><div className="flex items-center gap-1.5"><Hash className="w-3 h-3 flex-shrink-0" style={{ color:"var(--text-muted)" }}/><p className="font-semibold text-sm truncate" style={{ color:"var(--text-primary)" }}>{c.name}</p></div>{c.description&&<p className="text-xs mt-0.5 line-clamp-1" style={{ color:"var(--text-muted)" }}>{c.description}</p>}<div className="flex items-center gap-1 mt-0.5"><Users className="w-3 h-3" style={{ color:"var(--text-muted)" }}/><span className="text-[10px]" style={{ color:"var(--text-muted)" }}>{c.member_emails?.length||0} members</span></div></div>
                  <div className="flex items-center gap-2 flex-shrink-0">{me&&<button onClick={e=>join(e,c)} className={`text-xs px-2.5 py-1 rounded-full font-medium transition-all ${isMember?"btn-ghost":"btn"}`} style={isMember?{border:"1px solid var(--border-c)",color:"var(--text-muted)"}:{}}>{isMember?"Leave":"Join"}</button>}<ChevronRight className="w-4 h-4 opacity-0 group-hover:opacity-100 transition-opacity" style={{ color:"var(--text-muted)" }}/></div>
                </div>
              </motion.div>
            ); })}
          </div>
        )}
      </div>
      <Dialog open={showCreate} onOpenChange={setShowCreate}>{showCreate&&me&&<CreateModal me={me} onCreated={fetchData} onClose={()=>setShowCreate(false)}/>}</Dialog>
    </div>
  );
}