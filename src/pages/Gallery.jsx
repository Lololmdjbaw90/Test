import React, { useState, useEffect } from "react";
import { base44 } from "@/api/base44Client";
import { Link } from "react-router-dom";
import { Plus, Loader2, Search, Star, Download } from "lucide-react";
import { motion } from "framer-motion";
import ArtworkCard from "../components/gallery/ArtworkCard";
import PingInbox from "../components/gallery/PingInbox";
import { exportToCsv } from "../utils/exportCsv";

const MEDIA = ["All","Painting","Digital","Drawing","Photography","Sculpture","Mixed Media","Other"];

export default function Gallery() {
  const [artworks, setArtworks] = useState([]);
  const [filtered, setFiltered] = useState([]);
  const [loading, setLoading] = useState(true);
  const [medium, setMedium] = useState("All");
  const [search, setSearch] = useState("");
  const [isAdmin, setIsAdmin] = useState(false);
  const [user, setUser] = useState(null);

  useEffect(() => { fetchData(); }, []);
  useEffect(() => {
    let list = artworks;
    if (medium !== "All") list = list.filter(a => a.medium?.toLowerCase().replace("_"," ") === medium.toLowerCase());
    if (search.trim()) list = list.filter(a => a.title?.toLowerCase().includes(search.toLowerCase()));
    setFiltered(list);
  }, [medium, search, artworks]);

  const fetchData = async () => {
    setLoading(true);
    const [art, me] = await Promise.all([base44.entities.Artwork.list("-created_date"), base44.auth.me().catch(() => null)]);
    setArtworks(art); setFiltered(art); setUser(me); setIsAdmin(me?.role === "admin"); setLoading(false);
  };

  return (
    <div className="h-full flex flex-col overflow-hidden">
      <div className="flex-shrink-0 px-4 sm:px-6 py-4 border-b flex items-center gap-3" style={{ background: "var(--surface)", borderColor: "var(--border-c)" }}>
        <div className="flex-1"><h1 className="text-base font-semibold" style={{ color: "var(--text-primary)" }}>Gallery</h1><p className="text-xs" style={{ color: "var(--text-muted)" }}>{filtered.length} artworks</p></div>
        <div className="flex items-center gap-2">
          <PingInbox currentUser={user} />
          <button onClick={() => exportToCsv(filtered.map(a => ({ title: a.title, medium: a.medium, year: a.year, likes: a.likes?.length || 0 })), "gallery")} className="btn-outline text-xs px-3 py-2"><Download className="w-3.5 h-3.5" /></button>
          {isAdmin && <Link to="/Upload" className="btn text-xs px-3 py-2"><Plus className="w-3.5 h-3.5" /> Add</Link>}
        </div>
      </div>
      <div className="flex-shrink-0 px-4 sm:px-6 py-3 space-y-3 border-b" style={{ background: "var(--surface)", borderColor: "var(--border-c)" }}>
        <div className="relative"><Search className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4" style={{ color: "var(--text-muted)" }} /><input className="input pl-9 text-sm" placeholder="Search artworks..." value={search} onChange={e => setSearch(e.target.value)} /></div>
        <div className="flex gap-2 overflow-x-auto pb-1 scroll" style={{ scrollbarWidth: "none" }}>
          {MEDIA.map(m => <button key={m} onClick={() => setMedium(m)} className="flex-shrink-0 text-xs px-3.5 py-1.5 rounded-full font-medium transition-all" style={medium === m ? { background: "var(--accent-pink)", color: "white" } : { background: "var(--pink-soft)", color: "var(--text-secondary)" }}>{m}</button>)}
        </div>
      </div>
      <div className="flex-1 overflow-y-auto scroll px-4 sm:px-6 py-4">
        {loading ? (
          <div className="grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-4 gap-3">{Array.from({ length: 8 }).map((_, i) => <div key={i} className="rounded-2xl overflow-hidden"><div className="skeleton h-40" /><div className="p-2 space-y-1.5"><div className="skeleton h-3 w-3/4" /><div className="skeleton h-3 w-1/2" /></div></div>)}</div>
        ) : filtered.length === 0 ? (
          <div className="flex flex-col items-center justify-center py-20 gap-3"><div className="w-16 h-16 rounded-2xl flex items-center justify-center" style={{ background: "var(--pink-soft)" }}><Star className="w-7 h-7" style={{ color: "var(--accent-pink)" }} /></div><p className="text-sm font-medium" style={{ color: "var(--text-secondary)" }}>No artworks found</p>{isAdmin && <Link to="/Upload" className="btn text-sm">Upload first artwork</Link>}</div>
        ) : (
          <div className="columns-2 sm:columns-3 lg:columns-4 gap-3 pb-6">
            {filtered.map((artwork, i) => <div key={artwork.id} className="break-inside-avoid mb-3"><ArtworkCard artwork={artwork} index={i} onUpdate={fetchData} isAdmin={isAdmin} currentUser={user} /></div>)}
          </div>
        )}
      </div>
    </div>
  );
}