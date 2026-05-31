import React, { useState, useEffect } from "react";
import { base44 } from "@/api/base44Client";
import { Loader2, ClipboardList } from "lucide-react";
export default function LogsPage() {
  const [logs,setLogs]=useState([]),[loading,setLoading]=useState(true);
  useEffect(()=>{base44.auth.me().then(me=>{if(me?.role!=="admin")window.location.href="/";return base44.entities.Log.list("-created_date");}).then(data=>setLogs(data)).catch(()=>{}).finally(()=>setLoading(false));},[]);
  return(
    <div className="h-full flex flex-col overflow-hidden">
      <div className="flex-shrink-0 px-4 sm:px-6 py-4 border-b flex items-center gap-3" style={{background:"var(--surface)",borderColor:"var(--border-c)"}}><ClipboardList className="w-5 h-5" style={{color:"var(--accent-pink)"}}/><div><h1 className="text-base font-semibold" style={{color:"var(--text-primary)"}}>Activity Logs</h1><p className="text-xs" style={{color:"var(--text-muted)"}}>Admin only</p></div></div>
      <div className="flex-1 overflow-y-auto scroll px-4 sm:px-6 py-4">
        {loading?<div className="flex justify-center py-12"><Loader2 className="w-5 h-5 animate-spin" style={{color:"var(--accent-pink)"}}/></div>:<div className="space-y-2 pb-6">{logs.length===0&&<p className="text-center text-sm py-12" style={{color:"var(--text-muted)"}}>No logs yet.</p>}{logs.map(log=><div key={log.id} className="card-sm px-3 py-2.5 flex items-center gap-3"><div className="w-8 h-8 rounded-lg flex items-center justify-center flex-shrink-0" style={{background:"var(--pink-soft)"}}><ClipboardList className="w-4 h-4" style={{color:"var(--accent-pink)"}}/></div><div className="flex-1 min-w-0"><p className="text-xs font-medium truncate" style={{color:"var(--text-primary)"}}>{log.details}</p><p className="text-[10px]" style={{color:"var(--text-muted)"}}>{log.user_email} · {log.action}</p></div><span className="text-[10px] flex-shrink-0" style={{color:"var(--text-muted)"}}>{new Date(log.created_date).toLocaleDateString()}</span></div>)}</div>}
      </div>
    </div>
  );
}