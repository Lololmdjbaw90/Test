import React, { useEffect, useRef, useState } from "react";
import { createPortal } from "react-dom";
import { ArrowLeft, Hash, Loader2, Send } from "lucide-react";
import { base44 } from "@/api/base44Client";
import { useAuth } from "@/lib/AuthContext";
import { applyFilterToCanvas, bakePhoto, filterCss } from "@/lib/filters";
import { hashtags } from "@/lib/ranking";
import { checkText, hasLink } from "@/lib/moderation";
import { feedback } from "@/lib/feedback";
import { toast } from "@/lib/toast";
import { displayName } from "@/lib/format";
import { capLength, clipsOf, locate, newClip, totalLength } from "@/lib/clips";
import FilterLayers from "@/components/media/FilterLayers";
import AICaptionHelper from "@/components/ai/AICaptionHelper";
import { withHashtags } from "@/lib/ai";
import ReelCamera, { MAX_SECONDS } from "./ReelCamera";
import ReelEditor from "./ReelEditor";
import { TextStickers, photoLength } from "./ReelMedia";

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

// Seconds of finished reel (after cuts and speed).
const reelLength = (media, edits) => (media.kind === "video" ? totalLength(clipsOf(edits, media.duration)) / (edits.speed || 1) : photoLength(media.files?.length || 1));

function PostStep({ media, edits, music, coverTime, coverUrl, onBack, onPosted }) {
  const { user } = useAuth();
  const [caption, setCaption] = useState("");
  const [busy, setBusy] = useState("");
  const [allowComments, setAllowComments] = useState(true);
  const tags = hashtags(caption);
  const clips = media.kind === "video" ? clipsOf(edits, media.duration) : [];

  const post = async () => {
    if (busy) return;
    if (hasLink(caption)) { toast.error("Links aren't allowed in captions"); return; }
    const mod = await checkText(caption, { user, where: "reel caption", kind: "caption" });
    if (!mod.safe) { toast.error(mod.reason); return; }
    try {
      const upload = async (file) => (await base44.integrations.Core.UploadFile({ file })).file_url;
      let mediaUrls = [];
      let mediaUrl, cover, finalEdits = { trim_start: 0, trim_end: 0, filter: "none", speed: 1, muted: false, text: [], mirror: false, ...edits };
      if (media.kind === "photo") {
        setBusy("Applying your filter…");
        // The filter is drawn into the photo; text stays live so it can animate.
        const pics = media.files?.length > 1 ? media.files : [media.file];
        const urls = [];
        for (let i = 0; i < pics.length; i++) {
          setBusy(pics.length > 1 ? `Uploading ${i + 1} of ${pics.length}…` : "Uploading…");
          urls.push(await upload(await bakePhoto(pics[i], { filter: edits.filter, max: 1440 })));
        }
        mediaUrl = urls[0];
        mediaUrls = urls.length > 1 ? urls : [];
        cover = mediaUrl;
        finalEdits = { ...finalEdits, filter: "none" };
        delete finalEdits.clips;
      } else {
        setBusy("Uploading video…");
        mediaUrl = await upload(media.file);
        setBusy("Making the cover…");
        const blob = await grabFrame(media.url, locate(clips, coverTime || 0).source || 0.05, { filter: edits.filter, mirror: edits.mirror });
        cover = blob ? await upload(new File([blob], "cover.jpg", { type: "image/jpeg" })) : "";
        // Older versions of the app only know trim_start / trim_end.
        finalEdits = { ...finalEdits, clips: clips.map(({ id, start, end }) => ({ id, start: Math.round(start * 1000) / 1000, end: Math.round(end * 1000) / 1000 })), trim_start: clips[0].start, trim_end: clips[clips.length - 1].end };
      }
      setBusy("Posting…");
      const span = reelLength(media, edits);
      const created = await base44.entities.Reel.create({
        user_email: user.email, user_display_name: displayName(user), user_profile_picture: user.profile_picture || "",
        kind: media.kind, media_url: mediaUrl, cover_url: cover, caption: caption.trim(), tags,
        music_url: music?.url || "", music_title: music?.title || "", music_artist: music?.artist || "", music_source: music?.source || "", media_urls: mediaUrls,
        edits: finalEdits, likes: [], views: 0, duration: Math.round(span * 10) / 10, comments_off: !allowComments,
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
        <div className="mt-3">
          <AICaptionHelper kind="reel" dark getImage={() => (media.kind === "photo" ? media.file : coverUrl)} draft={caption} onPick={(o) => setCaption(withHashtags(o).slice(0, 300))} />
        </div>
        {tags.length > 0 && <div className="flex flex-wrap gap-1.5 mt-3">{tags.map((t) => <span key={t} className="px-2.5 py-1 rounded-full text-xs font-bold flex items-center gap-1" style={{ background: "rgb(255 255 255 / 0.12)" }}><Hash className="w-3 h-3" />{t}</span>)}</div>}
        <ul className="mt-5 space-y-2 text-sm opacity-80">
          {music && <li>♪ {music.title} · {music.artist}</li>}
          {media.kind === "video" && <li>✂️ {clips.length > 1 ? `${clips.length} clips · ` : ""}{reelLength(media, edits).toFixed(1)}s{edits.speed && edits.speed !== 1 ? ` at ${edits.speed}x` : ""}{edits.muted ? " · original sound off" : ""}</li>}
          {(edits.text || []).length > 0 && <li>🔤 {edits.text.length} text{edits.text.length === 1 ? "" : "s"}</li>}
          {media.files?.length > 1 && <li>🖼️ Slideshow of {media.files.length} pictures</li>}
          <li>👀 Everyone on Sugerly can watch it in Reels</li>
        </ul>
        <button type="button" role="switch" aria-checked={allowComments} onClick={() => { feedback("toggle"); setAllowComments((v) => !v); }} className="mt-4 w-full flex items-center gap-3 p-3 rounded-2xl text-left" style={{ background: "rgb(255 255 255 / 0.08)" }}>
          <span className="flex-1 text-sm font-bold">Allow comments</span>
          <span className="relative w-12 h-7 rounded-full transition-colors" style={{ background: allowComments ? "#34c759" : "rgb(255 255 255 / 0.25)" }}>
            <span className="absolute top-0.5 w-6 h-6 rounded-full bg-white shadow transition-all" style={{ left: allowComments ? 22 : 2 }} />
          </span>
        </button>
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
  const [draft, setDraft] = useState(null); // { edits, music, coverTime }
  const latest = useRef(null); // the editor's latest state (a ref, so gestures don't re-render the studio)
  const [editorKey, setEditorKey] = useState(0);
  const [coverUrl, setCoverUrl] = useState("");

  useEffect(() => {
    const prev = document.body.style.overflow;
    document.body.style.overflow = "hidden";
    return () => { document.body.style.overflow = prev; };
  }, []);
  useEffect(() => () => { if (media?.url) URL.revokeObjectURL(media.url); }, [media]);

  const captured = async (m) => {
    feedback("success");
    const edits = { filter: "none", speed: 1, muted: false, text: [], mirror: false, ...m.edits };
    if (m.kind === "video") {
      // Library videos start as one clip, cut down to the length limit.
      const clips = capLength(m.edits?.clips?.length ? m.edits.clips : [newClip(0, m.duration || MAX_SECONDS)], MAX_SECONDS);
      Object.assign(edits, { clips, trim_start: clips[0].start, trim_end: clips[clips.length - 1].end });
    }
    let thumb = "";
    if (m.kind === "video") {
      const b = await grabFrame(m.url, (edits.clips?.[0]?.start || 0) + 0.1, { width: 160, mirror: m.edits?.mirror });
      if (b) thumb = URL.createObjectURL(b);
    }
    latest.current = { edits, music: null, coverTime: 0 };
    setDraft(latest.current);
    setEditorKey((k) => k + 1);
    setMedia({ ...m, thumb });
    setStep("edit");
  };
  const toPost = async () => {
    const d = latest.current;
    setDraft(d);
    if (media.kind === "video") {
      const clips = clipsOf(d.edits, media.duration);
      const b = await grabFrame(media.url, locate(clips, d.coverTime || 0).source || 0.1, { filter: d.edits.filter, mirror: d.edits.mirror, width: 360 });
      setCoverUrl(b ? URL.createObjectURL(b) : "");
    } else setCoverUrl(media.url);
    setStep("post");
  };

  return createPortal(
    <div className="fixed inset-0 z-[125] bg-black safe-x" role="dialog" aria-modal="true" aria-label="Create a reel">
      {step === "camera" && <ReelCamera onClose={() => onClose(null)} onCaptured={captured} />}
      {step === "edit" && media && draft && (
        <ReelEditor key={editorKey} media={media} initial={draft} onChange={(d) => { latest.current = d; }} onBack={() => { setMedia(null); setDraft(null); setStep("camera"); }} onNext={toPost} />
      )}
      {step === "post" && media && draft && (
        <PostStep media={media} edits={draft.edits} music={draft.music} coverTime={draft.coverTime} coverUrl={coverUrl} onBack={() => { setEditorKey((k) => k + 1); setStep("edit"); }} onPosted={(id) => onClose(id)} />
      )}
    </div>,
    document.body,
  );
}
