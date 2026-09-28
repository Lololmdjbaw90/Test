import React, { useState } from "react";
import { Link, useNavigate } from "react-router-dom";
import { AnimatePresence, motion } from "framer-motion";
import { Check, Loader2, Music, Shield, Upload as UploadIcon, X } from "lucide-react";
import { base44 } from "@/api/base44Client";
import { useAuth } from "@/lib/AuthContext";
import { toast } from "@/lib/toast";
import { displayName } from "@/lib/format";
import { Page, PageHeader, EmptyState } from "@/components/common/Page";
import { Toggle } from "@/components/common/Controls";
import DropZone from "@/components/common/DropZone";
import Confetti from "@/components/common/Confetti";

const MEDIUMS = ["painting", "digital", "drawing", "photography", "sculpture", "mixed_media", "other"];

export default function UploadPage() {
  const navigate = useNavigate();
  const { user, isAdmin } = useAuth();
  const [form, setForm] = useState({ title: "", description: "", medium: "digital", year: String(new Date().getFullYear()), featured: false });
  const [imgFile, setImgFile] = useState(null);
  const [imgPreview, setImgPreview] = useState(null);
  const [musicFile, setMusicFile] = useState(null);
  const [submitting, setSubmitting] = useState(false);
  const [done, setDone] = useState(false);

  if (!isAdmin) {
    return <Page><EmptyState icon={Shield} title="Admins only" text="The gallery is curated by site admins. Share your own work on the Community feed instead!" action={<Link to="/Community?compose=1" className="btn">Share to Community</Link>} /></Page>;
  }

  const set = (k) => (e) => setForm((f) => ({ ...f, [k]: e.target.value }));
  const submit = async (e) => {
    e.preventDefault();
    if (!imgFile || !form.title.trim()) return;
    setSubmitting(true);
    try {
      const { file_url } = await base44.integrations.Core.UploadFile({ file: imgFile });
      let music_url = "";
      if (musicFile) music_url = (await base44.integrations.Core.UploadFile({ file: musicFile })).file_url;
      const art = await base44.entities.Artwork.create({ ...form, title: form.title.trim(), image_url: file_url, music_url, likes: [], user_email: user.email, user_display_name: displayName(user), user_profile_picture: user.profile_picture || "" });
      base44.entities.Log.create({ action: "artwork_added", details: `Added: "${form.title.trim()}"`, user_email: user.email }).catch(() => {});
      setDone(true);
      toast.success("Artwork published");
      setTimeout(() => navigate(`/Gallery?art=${art.id}`), 1300);
    } catch (err) {
      toast.error(err?.message || "Upload failed.");
      setSubmitting(false);
    }
  };

  return (
    <Page width="max-w-5xl">
      <PageHeader eyebrow="Admin" title="Upload artwork" subtitle="Add a piece to the curated gallery." icon={UploadIcon} />
      <form onSubmit={submit} className="grid lg:grid-cols-[1.1fr_1fr] gap-6">
        <div className="space-y-4">
          <DropZone preview={imgPreview} onFile={(f) => { setImgFile(f); setImgPreview(URL.createObjectURL(f)); }} onClear={() => { setImgFile(null); setImgPreview(null); }} height={320} hint="PNG, JPG, GIF or WebP" />
          <div className="card p-4">
            <p className="label">Background music (optional)</p>
            <label className="flex items-center gap-3 cursor-pointer">
              <span className="w-10 h-10 rounded-xl flex items-center justify-center flex-shrink-0" style={{ background: "var(--pink-soft)", color: "var(--accent-rose)" }}><Music className="w-4 h-4" /></span>
              <span className="flex-1 min-w-0 text-sm truncate" style={{ color: musicFile ? "var(--text-primary)" : "var(--text-muted)" }}>{musicFile ? musicFile.name : "Choose an audio file to play with this piece"}</span>
              {musicFile ? <button type="button" onClick={(e) => { e.preventDefault(); setMusicFile(null); }} className="icon-btn" aria-label="Remove audio"><X className="w-4 h-4" /></button> : <span className="btn-outline text-xs">Browse</span>}
              <input type="file" accept="audio/*" className="hidden" onChange={(e) => setMusicFile(e.target.files?.[0] || null)} />
            </label>
          </div>
        </div>
        <div className="card p-5 sm:p-6 space-y-4 relative overflow-hidden">
          {done && <Confetti />}
          <div><label className="label" htmlFor="up-title">Title</label><input id="up-title" className="input" placeholder="Name your piece" value={form.title} onChange={set("title")} required maxLength={80} /></div>
          <div><label className="label" htmlFor="up-desc">Description</label><textarea id="up-desc" className="input resize-none" rows={4} placeholder="The story behind it…" value={form.description} onChange={set("description")} maxLength={600} /></div>
          <div className="grid grid-cols-2 gap-3">
            <div><label className="label" htmlFor="up-medium">Medium</label><select id="up-medium" className="input capitalize" value={form.medium} onChange={set("medium")}>{MEDIUMS.map((m) => <option key={m} value={m}>{m.replace("_", " ")}</option>)}</select></div>
            <div><label className="label" htmlFor="up-year">Year</label><input id="up-year" className="input" value={form.year} onChange={set("year")} maxLength={4} /></div>
          </div>
          <div className="card-sm p-3.5"><Toggle checked={form.featured} onChange={(v) => setForm((f) => ({ ...f, featured: v }))} label="Feature on the home page" description="Featured pieces appear first in the gallery and on Home." /></div>
          <AnimatePresence mode="wait">
            <motion.button key={done ? "done" : "submit"} initial={{ opacity: 0, y: 6 }} animate={{ opacity: 1, y: 0 }} type="submit" disabled={submitting || !imgFile || !form.title.trim()} className="btn w-full py-3">
              {done ? <><Check className="w-4 h-4" /> Published!</> : submitting ? <><Loader2 className="w-4 h-4 animate-spin" /> Uploading…</> : <><UploadIcon className="w-4 h-4" /> Publish to gallery</>}
            </motion.button>
          </AnimatePresence>
        </div>
      </form>
    </Page>
  );
}
