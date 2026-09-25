import React, { useEffect, useMemo, useRef, useState } from "react";
import { Link, useSearchParams } from "react-router-dom";
import { AnimatePresence, motion } from "framer-motion";
import { Disc3, ImagePlus, Loader2, Music as MusicIcon, Pause, Play, Shuffle, Trash2, Upload, X } from "lucide-react";
import { base44 } from "@/api/base44Client";
import { useAuth } from "@/lib/AuthContext";
import { useLiveQuery } from "@/lib/useLiveQuery";
import { usePlayer, formatTime } from "@/lib/player";
import { toggleLike } from "@/lib/likes";
import { checkText } from "@/lib/moderation";
import { toast } from "@/lib/toast";
import { displayName, profileLink, timeAgo } from "@/lib/format";
import { Page, PageHeader, EmptyState } from "@/components/common/Page";
import { ChipRow, SearchInput } from "@/components/common/Controls";
import Modal, { useConfirm } from "@/components/common/Modal";
import DropZone from "@/components/common/DropZone";
import LikeButton from "@/components/common/LikeButton";

const GENRES = ["Lo-fi", "Ambient", "Synthwave", "Dream pop", "Hip-hop", "Electronic", "Acoustic", "Classical", "Rock", "Other"];
const MOODS = ["Chill", "Calm", "Dreamy", "Energetic", "Happy", "Melancholy", "Focus"];

function UploadModal({ open, onClose }) {
  const { user, updateMe } = useAuth();
  const [file, setFile] = useState(null);
  const [cover, setCover] = useState(null);
  const [coverPreview, setCoverPreview] = useState(null);
  const [form, setForm] = useState({ title: "", genre: "Lo-fi", mood: "Chill", ai_review: "" });
  const [submitting, setSubmitting] = useState(false);

  const submit = async (e) => {
    e.preventDefault();
    if (!file) return;
    setSubmitting(true);
    try {
      const title = form.title.trim() || file.name.replace(/\.[^.]+$/, "");
      const mod = await checkText(`${title} ${form.ai_review}`, { user, where: "music upload" });
      if (!mod.safe) { toast.error("Upload blocked", { description: mod.reason }); setSubmitting(false); return; }
      const music_url = (await base44.integrations.Core.UploadFile({ file })).file_url;
      const cover_url = cover ? (await base44.integrations.Core.UploadFile({ file: cover })).file_url : "";
      await base44.entities.MusicReview.create({ ...form, title, music_url, cover_url, identified_song: "", user_email: user.email, user_display_name: displayName(user), user_profile_picture: user.profile_picture || "", likes: [] });
      await updateMe({ xp: (user.xp || 0) + 15 }).catch(() => {});
      toast.success("Track shared!", { description: "+15 XP" });
      setFile(null); setCover(null); setCoverPreview(null); setForm({ title: "", genre: "Lo-fi", mood: "Chill", ai_review: "" });
      onClose();
    } catch (err) {
      toast.error(err?.message || "Upload failed.");
    }
    setSubmitting(false);
  };

  return (
    <Modal open={open} onClose={onClose} title="Share a track" subtitle="MP3, WAV, OGG or M4A" size="lg">
      <form onSubmit={submit} className="space-y-4">
        {file ? (
          <div className="card-sm p-3 flex items-center gap-3">
            <span className="w-10 h-10 rounded-xl flex items-center justify-center text-white" style={{ background: "var(--accent-grad)" }}><MusicIcon className="w-4 h-4" /></span>
            <span className="flex-1 min-w-0 text-sm font-semibold truncate" style={{ color: "var(--text-primary)" }}>{file.name}</span>
            <button type="button" onClick={() => setFile(null)} className="icon-btn" aria-label="Remove file"><X className="w-4 h-4" /></button>
          </div>
        ) : (
          <DropZone accept="audio/*" icon={Upload} onFile={setFile} label="Drop an audio file or click to browse" height={140} />
        )}
        <div className="grid sm:grid-cols-[120px_1fr] gap-4">
          <div>
            <p className="label">Cover</p>
            <label className="block w-[120px] h-[120px] rounded-2xl overflow-hidden cursor-pointer relative" style={{ background: "var(--surface-2)", border: "1px dashed var(--border-strong)" }}>
              {coverPreview ? <img src={coverPreview} alt="" className="w-full h-full object-cover" /> : <span className="absolute inset-0 flex items-center justify-center" style={{ color: "var(--text-muted)" }}><ImagePlus className="w-5 h-5" /></span>}
              <input type="file" accept="image/*" className="hidden" onChange={(e) => { const f = e.target.files?.[0]; if (f) { setCover(f); setCoverPreview(URL.createObjectURL(f)); } }} />
            </label>
          </div>
          <div className="space-y-3">
            <div><label className="label" htmlFor="m-title">Title</label><input id="m-title" className="input" placeholder="Track title" value={form.title} onChange={(e) => setForm((f) => ({ ...f, title: e.target.value }))} maxLength={80} /></div>
            <div><label className="label" htmlFor="m-genre">Genre</label><select id="m-genre" className="input" value={form.genre} onChange={(e) => setForm((f) => ({ ...f, genre: e.target.value }))}>{GENRES.map((g) => <option key={g}>{g}</option>)}</select></div>
          </div>
        </div>
        <div>
          <p className="label">Mood</p>
          <ChipRow options={MOODS} value={form.mood} onChange={(m) => setForm((f) => ({ ...f, mood: m }))} />
        </div>
        <div><label className="label" htmlFor="m-notes">Notes</label><textarea id="m-notes" className="input resize-none" rows={2} placeholder="What inspired it? (optional)" value={form.ai_review} onChange={(e) => setForm((f) => ({ ...f, ai_review: e.target.value }))} maxLength={300} /></div>
        <div className="flex justify-end gap-2">
          <button type="button" className="btn-ghost" onClick={onClose}>Cancel</button>
          <button type="submit" className="btn" disabled={!file || submitting}>{submitting ? <Loader2 className="w-4 h-4 animate-spin" /> : <><Upload className="w-4 h-4" /> Share track</>}</button>
        </div>
      </form>
    </Modal>
  );
}

function NowPlaying({ track, playing, time, duration, onToggle }) {
  return (
    <motion.div initial={{ opacity: 0, y: 16 }} animate={{ opacity: 1, y: 0 }} className="relative overflow-hidden rounded-[2rem] p-6 sm:p-8 mb-8 grain" style={{ background: "linear-gradient(135deg, rgb(var(--accent-rgb) / 0.9), rgb(var(--accent-2-rgb) / 0.85))", color: "#fff", boxShadow: "var(--shadow-accent)" }}>
      <div className="orb w-72 h-72 -right-16 -top-20" style={{ background: "rgb(255 255 255 / 0.25)" }} />
      <div className="relative flex items-center gap-6">
        <div className="relative flex-shrink-0 w-28 h-28 sm:w-36 sm:h-36">
          <motion.div animate={{ rotate: playing ? 360 : 0 }} transition={playing ? { duration: 6, repeat: Infinity, ease: "linear" } : { duration: 0.5 }} className="absolute inset-0 rounded-full" style={{ background: "repeating-radial-gradient(circle, #1a1017 0 2px, #2a1a24 2px 4px)", boxShadow: "0 20px 40px rgb(0 0 0 / 0.3)" }}>
            <div className="absolute inset-[30%] rounded-full overflow-hidden" style={{ background: "var(--accent-grad)" }}>{track.cover && <img src={track.cover} alt="" className="w-full h-full object-cover" />}</div>
          </motion.div>
        </div>
        <div className="flex-1 min-w-0">
          <p className="text-[11px] font-bold uppercase tracking-[0.2em] opacity-80 flex items-center gap-2"><span className={`equalizer ${playing ? "" : "paused"}`}><span /><span /><span /></span> Now playing</p>
          <h2 className="font-display text-3xl sm:text-4xl font-semibold truncate mt-1">{track.title}</h2>
          <p className="text-sm opacity-85 truncate">{track.artist}</p>
          <div className="flex items-center gap-3 mt-4">
            <motion.button whileTap={{ scale: 0.92 }} onClick={onToggle} className="w-12 h-12 rounded-full bg-white flex items-center justify-center" style={{ color: "var(--accent-rose)" }} aria-label={playing ? "Pause" : "Play"}>
              {playing ? <Pause className="w-5 h-5" /> : <Play className="w-5 h-5 ml-0.5" />}
            </motion.button>
            <div className="flex-1 max-w-sm">
              <div className="h-1.5 rounded-full bg-white/30 overflow-hidden"><div className="h-full bg-white rounded-full" style={{ width: `${duration ? (time / duration) * 100 : 0}%` }} /></div>
              <div className="flex justify-between text-[10px] mt-1 opacity-80 tabular-nums"><span>{formatTime(time)}</span><span>{formatTime(duration)}</span></div>
            </div>
          </div>
        </div>
      </div>
    </motion.div>
  );
}

export default function MusicPage() {
  const { user } = useAuth();
  const player = usePlayer();
  const confirm = useConfirm();
  const [params, setParams] = useSearchParams();
  const [search, setSearch] = useState("");
  const [genre, setGenre] = useState("All");
  const { data: tracks, setData, loading } = useLiveQuery("MusicReview", null, { sort: "-created_date", limit: 300 });
  const highlightRef = useRef(null);

  const filtered = useMemo(() => {
    const q = search.trim().toLowerCase();
    return tracks.filter((t) => (genre === "All" || t.genre === genre) && (!q || [t.title, t.user_display_name, t.genre, t.mood].some((f) => String(f || "").toLowerCase().includes(q))));
  }, [tracks, search, genre]);
  const genres = useMemo(() => ["All", ...new Set(tracks.map((t) => t.genre).filter(Boolean))], [tracks]);
  const queue = filtered.filter((t) => t.music_url).map((t) => ({ id: t.id, title: t.title, artist: t.user_display_name, src: t.music_url, cover: t.cover_url }));
  const current = player.track && tracks.find((t) => t.id === player.track.id);
  const highlight = params.get("track");

  useEffect(() => {
    if (highlight && !loading) setTimeout(() => highlightRef.current?.scrollIntoView({ behavior: "smooth", block: "center" }), 300);
  }, [highlight, loading]);

  const remove = async (t) => {
    const ok = await confirm({ title: "Delete track?", message: `"${t.title}" will be removed.`, confirmLabel: "Delete", danger: true });
    if (!ok) return;
    if (player.isCurrent(t.id)) player.close();
    try { await base44.entities.MusicReview.delete(t.id); toast.success("Track deleted"); } catch (e) { toast.error(e?.message || "Could not delete."); }
  };
  const shuffle = () => {
    if (!queue.length) return;
    const shuffled = [...queue].sort(() => Math.random() - 0.5);
    player.play(shuffled[0], shuffled);
  };

  return (
    <Page width="max-w-5xl">
      <PageHeader
        eyebrow="Listen together"
        title="Music"
        subtitle={`${tracks.length} tracks shared by the community`}
        icon={Disc3}
        actions={<>
          <button className="btn-outline" onClick={shuffle} disabled={!queue.length}><Shuffle className="w-4 h-4" /> Shuffle</button>
          {user && <button className="btn" onClick={() => setParams({ upload: "1" })}><Upload className="w-4 h-4" /> Share a track</button>}
        </>}
      >
        <div className="flex flex-col md:flex-row gap-3 md:items-center">
          <ChipRow options={genres} value={genre} onChange={setGenre} className="flex-1" />
          <SearchInput value={search} onChange={setSearch} placeholder="Search tracks…" className="md:w-64" />
        </div>
      </PageHeader>

      <AnimatePresence>{current && <NowPlaying track={player.track} playing={player.playing} time={player.time} duration={player.duration} onToggle={() => player.toggle()} />}</AnimatePresence>

      {loading ? (
        <div className="space-y-3">{Array.from({ length: 5 }).map((_, i) => <div key={i} className="skeleton h-20" />)}</div>
      ) : filtered.length === 0 ? (
        <EmptyState icon={MusicIcon} title="No tracks yet" text="Share something you made — it plays for everyone right here." action={user && <button className="btn" onClick={() => setParams({ upload: "1" })}>Share a track</button>} />
      ) : (
        <div className="card !rounded-3xl p-2 sm:p-3">
          {filtered.map((t, i) => {
            const track = queue.find((q) => q.id === t.id);
            const isCurrent = player.isCurrent(t.id);
            const playing = player.isPlaying(t.id);
            const canDelete = user && (user.email === t.user_email || user.role === "admin");
            return (
              <motion.div
                key={t.id}
                ref={highlight === t.id ? highlightRef : null}
                initial={{ opacity: 0, x: -12 }}
                animate={{ opacity: 1, x: 0 }}
                transition={{ delay: Math.min(i, 10) * 0.04 }}
                className="group flex items-center gap-3 sm:gap-4 p-2.5 sm:p-3 rounded-2xl transition-colors hover:bg-[var(--surface-2)]"
                style={isCurrent || highlight === t.id ? { background: "var(--pink-soft)" } : undefined}
              >
                <span className="hidden sm:flex w-6 justify-center text-sm font-semibold tabular-nums" style={{ color: isCurrent ? "var(--accent-rose)" : "var(--text-muted)" }}>
                  {playing ? <span className="equalizer"><span /><span /><span /></span> : i + 1}
                </span>
                <button onClick={() => track && player.toggle(track, queue)} disabled={!track} className="relative w-14 h-14 rounded-2xl overflow-hidden flex-shrink-0 disabled:opacity-50" style={{ background: "var(--accent-grad)" }} aria-label={playing ? `Pause ${t.title}` : `Play ${t.title}`}>
                  {t.cover_url && <img src={t.cover_url} alt="" className="absolute inset-0 w-full h-full object-cover" />}
                  <span className={`absolute inset-0 flex items-center justify-center text-white transition-opacity ${playing ? "opacity-100" : "opacity-0 group-hover:opacity-100"}`} style={{ background: "rgb(20 8 14 / 0.45)" }}>
                    {playing ? <Pause className="w-5 h-5" /> : <Play className="w-5 h-5 ml-0.5" />}
                  </span>
                  {!t.cover_url && !playing && <MusicIcon className="absolute inset-0 m-auto w-5 h-5 text-white group-hover:opacity-0" />}
                </button>
                <div className="flex-1 min-w-0">
                  <p className="text-sm sm:text-base font-bold truncate" style={{ color: isCurrent ? "var(--accent-rose)" : "var(--text-primary)" }}>{t.title || "Untitled"}</p>
                  <p className="text-xs truncate" style={{ color: "var(--text-muted)" }}><Link to={profileLink(t.user_email)} className="hover:underline">{t.user_display_name}</Link> · {timeAgo(t.created_date)}</p>
                  {t.ai_review && <p className="text-xs mt-1 line-clamp-1 hidden sm:block" style={{ color: "var(--text-secondary)" }}>{t.ai_review}</p>}
                </div>
                <div className="hidden md:flex gap-1.5">
                  {t.genre && <span className="badge-pink">{t.genre}</span>}
                  {t.mood && <span className="badge-pink" style={{ color: "var(--text-secondary)", background: "var(--surface-2)", borderColor: "var(--border-c)" }}>{t.mood}</span>}
                </div>
                <LikeButton variant="plain" liked={!!user && (t.likes || []).includes(user.email)} count={t.likes?.length || 0} onToggle={() => toggleLike({ entity: "MusicReview", record: t, user, setData, message: `liked your track "${t.title}"`, link: `/Music?track=${t.id}` })} />
                {canDelete && <button onClick={() => remove(t)} className="icon-btn w-8 h-8 opacity-0 group-hover:opacity-100 focus:opacity-100" aria-label="Delete track"><Trash2 className="w-4 h-4" style={{ color: "var(--danger)" }} /></button>}
              </motion.div>
            );
          })}
        </div>
      )}

      <UploadModal open={params.get("upload") === "1"} onClose={() => setParams({})} />
    </Page>
  );
}
