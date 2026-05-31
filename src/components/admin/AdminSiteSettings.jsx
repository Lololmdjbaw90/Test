import React, { useState, useEffect } from "react";
import { base44 } from "@/api/base44Client";
import { Loader2, Save } from "lucide-react";
export default function AdminSiteSettings() {
  const [config, setConfig] = useState(null);
  const [form, setForm] = useState({ announcement:"", announcement_active:false, announcement_color:"#e8a0b4", primary_color:"#e8a0b4" });
  const [saving, setSaving] = useState(false); const [saved, setSaved] = useState(false);
  useEffect(()=>{load();},[]);
  const load = async () => { const cs=await base44.entities.SiteConfig.filter({key:"global"}).catch(()=>[]); if(cs[0]){setConfig(cs[0]);setForm(f=>({...f,...cs[0]}));} };
  const save = async () => { setSaving(true); if(config)await base44.entities.SiteConfig.update(config.id,form); else await base44.entities.SiteConfig.create({key:"global",...form}); setSaved(true);setTimeout(()=>setSaved(false),2000);setSaving(false);load(); };
  return (
    <div className="card p-4 space-y-4">
      <p className="text-xs font-semibold uppercase tracking-wider" style={{color:"var(--text-muted)"}}>Site Settings</p>
      <div className="space-y-3">
        <div><label className="text-xs font-medium block mb-1" style={{color:"var(--text-secondary)"}}>Announcement</label><input className="input text-sm" placeholder="Announcement text..." value={form.announcement} onChange={e=>setForm(f=>({...f,announcement:e.target.value}))}/></div>
        <label className="flex items-center gap-2 cursor-pointer"><input type="checkbox" checked={form.announcement_active} onChange={e=>setForm(f=>({...f,announcement_active:e.target.checked}))} className="w-4 h-4"/><span className="text-xs" style={{color:"var(--text-secondary)"}}>Show announcement banner</span></label>
        <div className="flex items-center gap-2"><label className="text-xs" style={{color:"var(--text-secondary)"}}>Accent color</label><input type="color" value={form.primary_color} onChange={e=>setForm(f=>({...f,primary_color:e.target.value}))} className="w-8 h-8 rounded-lg cursor-pointer border-0"/><span className="text-xs" style={{color:"var(--text-muted)"}}>{form.primary_color}</span></div>
      </div>
      <button onClick={save} disabled={saving} className="btn text-xs w-full justify-center">{saving?<Loader2 className="w-3.5 h-3.5 animate-spin"/>:saved?"Saved!":<><Save className="w-3.5 h-3.5"/>Save Settings</>}</button>
    </div>
  );
}