import React, { useEffect, useRef, useState } from "react";
import { AnimatePresence, motion } from "framer-motion";
import { ImagePlus, Loader2, Send, X } from "lucide-react";
import { base44 } from "@/api/base44Client";
import { useAuth } from "@/lib/AuthContext";
import { checkText } from "@/lib/moderation";
import { toast } from "@/lib/toast";
import { displayName } from "@/lib/format";
import Avatar from "@/components/common/Avatar";
import DropZone from "@/components/common/DropZone";
import FilterStrip from "@/components/media/FilterStrip";
import FilterLayers from "@/components/media/FilterLayers";
import { bakePhoto, filterCss } from "@/lib/filters";
import AICaptionHelper from "@/components/ai/AICaptionHelper";
import { withHashtags } from "@/lib/ai";

export default function PostComposer({ autoOpen = false }) {
  const { user, updateMe } = useAuth();
  const ref = useRef(null);
  const [open, setOpen] = useState(autoOpen);
  const [img, setImg] = useState(null);
  const [preview, setPreview] = useState(null);
  const [title, setTitle] = useState("");
  const [desc, setDesc] = useState("");
  const [filter, setFilter] = useState("none");
  const [submitting, setSubmitting] = useState(false);

  useEffect(() => {
    if (autoOpen) { setOpen(true); setTimeout(() => ref.current?.scrollIntoView({ behavior: "smooth", block: "center" }), 200); }
  }, [autoOpen]);

  const reset = () => { setImg(null); setPreview(null); setTitle(""); setDesc(""); setFilter("none"); setOpen(false); };
  const submit = async (e) => {
    e.preventDefault();
    if (!img && !desc.trim()) return;
    setSubmitting(true);
    try {
      const mod = await checkText(`${title} ${desc}`, { user, where: "community post" });
      if (!mod.safe) { toast.error("Post blocked", { description: mod.reason }); setSubmitting(false); return; }
      // The chosen filter is drawn into the photo before it's uploaded.
      const file = img && filter !== "none" && img.type !== "image/gif" ? await bakePhoto(img, { filter, max: 2048 }) : img;
      const image_url = file ? (await base44.integrations.Core.UploadFile({ file })).file_url : "";
      await base44.entities.CommunityPost.create({ title: title.trim(), description: desc.trim(), image_url, user_email: user.email, user_display_name: displayName(user), user_profile_picture: user.profile_picture || "", likes: [], like_count: 0 });
      await updateMe({ xp: (user.xp || 0) + 20, coins: (user.coins || 0) + 5 }).catch(() => {});
      toast.success("Posted!", { description: "+20 XP · +5 coins" });
      reset();
    } catch (err) {
      toast.error(err?.message || "Could not post.");
    }
    setSubmitting(false);
  };

  return (
    <motion.div ref={ref} className="card !rounded-3xl mb-8 overflow-hidden">
      <div className="p-4 flex items-center gap-3">
        <Avatar src={user?.profile_picture} name={displayName(user)} size={40} />
        <button onClick={() => setOpen(true)} className="flex-1 text-left h-11 px-4 rounded-full text-sm transition-colors" style={{ background: "var(--surface-2)", color: "var(--text-muted)", border: "1px solid var(--border-c)" }}>
          Share your latest piece, {displayName(user).split(" ")[0]}…
        </button>
        <button onClick={() => setOpen(true)} className="btn hidden sm:inline-flex"><ImagePlus className="w-4 h-4" /> Post</button>
      </div>
      <AnimatePresence initial={false}>
        {open && (
          <motion.form onSubmit={submit} initial={{ height: 0, opacity: 0 }} animate={{ height: "auto", opacity: 1 }} exit={{ height: 0, opacity: 0 }} transition={{ type: "spring", stiffness: 300, damping: 32 }} className="overflow-hidden">
            <div className="px-4 pb-4 space-y-3">
              {preview ? (
                <div className="space-y-2">
                  <div className="relative rounded-2xl overflow-hidden flex items-center justify-center" style={{ background: "var(--surface-2)" }}>
                    <div className="relative">
                      <img src={preview} alt="Your image" className="block max-h-[340px] w-auto max-w-full" style={{ filter: filterCss(filter) }} />
                      <FilterLayers filter={filter} />
                    </div>
                    <button type="button" onClick={() => { setImg(null); setPreview(null); setFilter("none"); }} className="absolute top-2 right-2 w-9 h-9 rounded-full flex items-center justify-center text-white" style={{ background: "rgb(0 0 0 / 0.5)" }} aria-label="Remove image"><X className="w-4 h-4" /></button>
                  </div>
                  <FilterStrip thumb={preview} value={filter} onChange={setFilter} />
                </div>
              ) : (
                <DropZone preview={null} onFile={(f) => { setImg(f); setPreview(URL.createObjectURL(f)); setFilter("none"); }} onClear={() => { setImg(null); setPreview(null); }} height={150} label="Add an image (optional)" hint="Drag & drop or click" />
              )}
              <input className="input" placeholder="Title (optional)" value={title} onChange={(e) => setTitle(e.target.value)} maxLength={80} />
              <textarea className="input resize-none" rows={3} placeholder="What's on your mind?" value={desc} onChange={(e) => setDesc(e.target.value)} maxLength={1000} autoFocus />
              {(img || desc.trim()) && (
                <AICaptionHelper kind="post" getImage={() => img} draft={desc} title={title} onPick={(o) => { if (o.title && !title.trim()) setTitle(o.title); setDesc(withHashtags(o)); }} />
              )}
              <div className="flex items-center gap-2">
                <div className="flex-1" />
                <button type="button" className="btn-ghost" onClick={reset}>Cancel</button>
                <button type="submit" disabled={submitting || (!img && !desc.trim())} className="btn">{submitting ? <Loader2 className="w-4 h-4 animate-spin" /> : <><Send className="w-4 h-4" /> Publish</>}</button>
              </div>
            </div>
          </motion.form>
        )}
      </AnimatePresence>
    </motion.div>
  );
}
