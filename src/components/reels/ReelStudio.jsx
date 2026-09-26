import React, { useEffect, useState } from "react";
import { createPortal } from "react-dom";
import { ArrowLeft, Hash, Loader2, Send } from "lucide-react";
import { base44 } from "@/api/base44Client";
import { useAuth } from "@/lib/AuthContext";
import { applyFilterToCanvas, bakePhoto, filterCss } from "@/lib/filters";
import { hashtags } from "@/lib/ranking";
import { feedback } from "@/lib/feedback";
import { toast } from "@/lib/toast";
import { displayName } from "@/lib/format";
import FilterLayers from "@/components/media/FilterLayers";
import ReelCamera, { MAX_SECONDS } from "./ReelCamera";
import ReelEditor from "./ReelEditor";
import { TextStickers } from "./ReelMedia";

// A frame of the video as a JPEG (for the cover and the filter thumbnails).
function grabFrame(url, time, { filter = "none", mirror = false, width = 720 } = {}) {
  return new Promise((resolve) => {
    const v = document.createElement("video");
    v.muted = true; v.playsInline = true; v.preload = "auto"; v.src = url;
    v.onloadeddata = () => { v.currentTime = Math.max(0.05, time); };
    v.onseeked = () => {
      const c = document.createElement("canvas");
      const w = Math.min(width, v.videoWidth || width);
      c.width = w; c.height = Math.round(w * (v.videoHeight || 16) / (v.videoWidth || 9));
      const ctx = c.getContext("2d");
      if (mirror) { ctx.translate(c.width, 0); ctx.scale(-1, 1); }
      ctx.drawImage(v, 0, 0, c.width, c.height);
      applyFilterToCanvas(c, filter);
      c.toBlob((b) => resolve(b), "image/jpeg", 0.85);
    };
    v.onerror = () => resolve(null);
  });
}

function PostStep({ media, edits, music, coverUrl, onBack, onPosted }) {
  const { user } = useAuth();
  const [caption, setCaption] = useState("");
  const [busy, setBusy] = useState("");
  const tags = hashtags(caption);

  const post = async () => {
    if (busy) return;
    try {
      const upload = async (file) => (await base44.integrations.Core.UploadFile({ file })).file_url;
      let mediaUrl, cover, finalEdits = { trim_start: 0, trim_end: 0, filter: "none", speed: 1, muted: false, text: [], mirror: false, ...edits };
      if (media.kind === "photo") {
        setBusy("Applying your edits…");
        // Filters and text are drawn into the photo, so it looks the same everywhere.
        const baked = await bakePhoto(media.file, { filter: edits.filter, stickers: edits.text || [], max: 1440 });
        setBusy("Uploading…");
        mediaUrl = await upload(baked);
        cover = mediaUrl;
        finalEdits = { ...finalEdits, filter: "none", text: [] };
      } else {
        setBusy("Uploading video…");
        mediaUrl = await upload(media.file);
        setBusy("Making the cover…");
        const blob = await grabFrame(media.url, media.coverTime ?? edits.trim_start ?? 0, { filter: edits.filter, mirror: edits.mirror });
        cover = blob ? await upload(new File([blob], "cover.jpg", { type: "image/jpeg" })) : "";
      }
      setBusy("Posting…");
      const span = media.kind === "video" ? Math.min(MAX_SECONDS, (edits.trim_end || media.duration) - (edits.trim_start || 0)) / (edits.speed || 1) : 7;
      const created = await base44.entities.Reel.create({
        user_email: user.email, user_display_name: displayName(user), user_profile_picture: user.profile_picture || "",
        kind: media.kind, media_url: mediaUrl, cover_url: cover, caption: caption.trim(), tags,
        music_url: music?.url || "", music_title: music?.title || "", music_artist: music?.artist || "",
        edits: finalEdits, likes: [], views: 0, duration: Math.round(span * 10) / 10,
      });
      toast.success("Your reel is live ✨");
      onPosted(created.id);
    } catch (e) {
      toast.error(e?.message || "Could not post your reel.");
      setBusy("");
    }
  };

  return (
    <div className="absolute inset-0 flex flex-col bg-black text-white">
      <div className="flex items-center justify-between px-3 pt-[calc(env(safe-area-inset-top)+0.5rem)] pb-2">
        <button onClick={onBack} disabled={!!busy} className="w-10 h-10 rounded-full flex items-center justify-center disabled:opacity-40" style={{ background: "rgb(255 255 255 / 0.12)" }} aria-label="Back to editing"><ArrowLeft className="w-5 h-5" /></button>
        <span className="font-display text-lg">New reel</span>
        <span className="w-10" />
      </div>
      <div className="flex-1 min-h-0 overflow-y-auto px-4 pb-4">
        <div className="flex gap-4 items-start">
          <div className="relative w-28 aspect-[9/16] rounded-xl overflow-hidden flex-shrink-0 bg-neutral-900" style={{ containerType: "inline-size" }}>
            {coverUrl && <img src={coverUrl} alt="" className="absolute inset-0 w-full h-full object-cover" style={{ filter: media.kind === "photo" ? filterCss(edits.filter) : undefined }} />}
            {media.kind === "photo" && <FilterLayers filter={edits.filter} />}
            {media.kind === "photo" && <TextStickers items={edits.text} />}
          </div>
          <textarea
            className="flex-1 min-h-[9rem] rounded-2xl p-3 text-[16px] outline-none resize-none"
            style={{ background: "rgb(255 255 255 / 0.08)", color: "#fff" }}
            placeholder="Write a caption… add #hashtags so the right people find it"
            maxLength={300}
            value={caption}
            onChange={(e) => setCaption(e.target.value)}
            aria-label="Caption"
          />
        </div>
        {tags.length > 0 && <div className="flex flex-wrap gap-1.5 mt-3">{tags.map((t) => <span key={t} className="px-2.5 py-1 rounded-full text-xs font-bold flex items-center gap-1" style={{ background: "rgb(255 255 255 / 0.12)" }}><Hash className="w-3 h-3" />{t}</span>)}</div>}
        <ul className="mt-5 space-y-2 text-sm opacity-80">
          {music && <li>♪ {music.title} · {music.artist}</li>}
          {media.kind === "video" && <li>✂️ {((edits.trim_end || media.duration) - (edits.trim_start || 0)).toFixed(1)}s{edits.speed && edits.speed !== 1 ? ` at ${edits.speed}x` : ""}{edits.muted ? " · original sound off" : ""}</li>}
          <li>👀 Everyone on Sugerly can watch it in Reels</li>
        </ul>
      </div>
      <div className="flex-shrink-0 px-4 pt-2 pb-[calc(env(safe-area-inset-bottom)+1rem)]">
        <button onClick={post} disabled={!!busy} className="btn w-full !py-3.5 text-base">{busy ? <><Loader2 className="w-5 h-5 animate-spin" /> {busy}</> : <><Send className="w-5 h-5" /> Post reel</>}</button>
      </div>
    </div>
  );
}

// Camera → edit → post, full screen.
export default function ReelStudio({ onClose }) {
  const [step, setStep] = useState("camera");
  const [media, setMedia] = useState(null);
  const [edits, setEdits] = useState({ filter: "none", speed: 1, muted: false, text: [], trim_start: 0, trim_end: 0 });
  const [music, setMusic] = useState(null);
  const [coverTime, setCoverTime] = useState(0);
  const [coverUrl, setCoverUrl] = useState("");

  useEffect(() => {
    const prev = document.body.style.overflow;
    document.body.style.overflow = "hidden";
    return () => { document.body.style.overflow = prev; };
  }, []);
  useEffect(() => () => { if (media?.url) URL.revokeObjectURL(media.url); }, [media]);

  const captured = async (m) => {
    feedback("success");
    const trimEnd = m.kind === "video" ? Math.min(m.duration || MAX_SECONDS, MAX_SECONDS) : 0;
    setEdits({ filter: "none", speed: 1, muted: false, text: [], trim_start: 0, trim_end: trimEnd, mirror: false, ...m.edits });
    setCoverTime(0);
    let thumb = "";
    if (m.kind === "video") {
      const b = await grabFrame(m.url, 0.1, { width: 160, mirror: m.edits?.mirror });
      if (b) thumb = URL.createObjectURL(b);
    }
    setMedia({ ...m, thumb });
    setStep("edit");
  };
  const toPost = async () => {
    if (media.kind === "video") {
      const b = await grabFrame(media.url, coverTime || edits.trim_start || 0.1, { filter: edits.filter, mirror: edits.mirror, width: 360 });
      setCoverUrl(b ? URL.createObjectURL(b) : "");
    } else setCoverUrl(media.url);
    setStep("post");
  };

  return createPortal(
    <div className="fixed inset-0 z-[125] bg-black safe-x" role="dialog" aria-modal="true" aria-label="Create a reel">
      {step === "camera" && <ReelCamera onClose={() => onClose(null)} onCaptured={captured} />}
      {step === "edit" && media && (
        <ReelEditor media={media} edits={edits} setEdits={setEdits} music={music} setMusic={setMusic} coverTime={coverTime} setCoverTime={setCoverTime} onBack={() => { setMedia(null); setStep("camera"); }} onNext={toPost} />
      )}
      {step === "post" && media && (
        <PostStep media={{ ...media, coverTime }} edits={edits} music={music} coverUrl={coverUrl} onBack={() => setStep("edit")} onPosted={(id) => onClose(id)} />
      )}
    </div>,
    document.body,
  );
}
