import React, { useEffect, useMemo, useRef, useState } from "react";
import { Link, useSearchParams } from "react-router-dom";
import { AnimatePresence, motion } from "framer-motion";
import { AudioLines, ChevronRight, Disc3, Headphones, ImagePlus, Loader2, Music as MusicIcon, Pause, Play, Shuffle, Sparkles, Trash2, TrendingUp, Upload, X } from "lucide-react";
import { base44 } from "@/api/base44Client";
import { useAuth } from "@/lib/AuthContext";
import { useLiveQuery } from "@/lib/useLiveQuery";
import { usePlayer, formatTime } from "@/lib/player";
import { toggleLike } from "@/lib/likes";
import { checkText } from "@/lib/moderation";
import { toast } from "@/lib/toast";
import { compactNumber, displayName, isOnline, profileLink, timeAgo } from "@/lib/format";
import { splitFriendships, useFriendships } from "@/lib/social";
import { buildTaste, rankTracks, trendingTracks } from "@/lib/ranking";
import Avatar from "@/components/common/Avatar";
import { Page, EmptyState } from "@/components/common/Page";
import { ChipRow, SearchInput } from "@/components/common/Controls";
import Modal, { useConfirm } from "@/components/common/Modal";
import DropZone from "@/components/common/DropZone";
import LikeButton from "@/components/common/LikeButton";
import { useBlocked } from "@/lib/safety";

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
              {coverPreview ? <img loading="lazy" decoding="async" src={coverPreview} alt="" className="w-full h-full object-cover" /> : <span className="absolute inset-0 flex items-center justify-center" style={{ color: "var(--text-muted)" }}><ImagePlus className="w-5 h-5" /></span>}
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
      <div className="orb w-72 h-72 -right-16 -top-20" style={{ "--orb": "rgb(255 255 255 / 0.25)" }} />
      <div className="relative flex items-center gap-6">
        <div className="relative flex-shrink-0 w-28 h-28 sm:w-36 sm:h-36">
          <div data-paused={!playing} className="anim-spin absolute inset-0 rounded-full" style={{ animationDuration: "6s", background: "repeating-radial-gradient(circle, #1a1017 0 2px, #2a1a24 2px 4px)", boxShadow: "0 20px 40px rgb(0 0 0 / 0.3)" }}>
            <div className="absolute inset-[30%] rounded-full overflow-hidden" style={{ background: "var(--accent-grad)" }}>{track.cover && <img loading="lazy" decoding="async" src={track.cover} alt="" className="w-full h-full object-cover" />}</div>
          </div>
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

const MOOD_STYLES = {
  Chill: "linear-gradient(135deg,#7dd3fc,#818cf8)",
  Calm: "linear-gradient(135deg,#a7f3d0,#34d399)",
  Dreamy: "linear-gradient(135deg,#f0abfc,#c084fc)",
  Energetic: "linear-gradient(135deg,#fdba74,#f43f5e)",
  Happy: "linear-gradient(135deg,#fde68a,#fb923c)",
  Melancholy: "linear-gradient(135deg,#94a3b8,#475569)",
  Focus: "linear-gradient(135deg,#99f6e4,#0ea5e9)",
};
const plural = (n, word) => `${compactNumber(n)} ${word}${n === 1 ? "" : "s"}`;
const asQueueItem = (t) => ({ id: t.id, title: t.title, artist: t.user_display_name, src: t.music_url, cover: t.cover_url, genre: t.genre, mood: t.mood, user_email: t.user_email, kind: "track" });

function Cover({ track, className = "", rounded = "rounded-2xl" }) {
  return (
    <span className={`relative block overflow-hidden ${rounded} ${className}`} style={{ background: "var(--accent-grad)" }}>
      {track.cover_url ? <img src={track.cover_url} alt="" loading="lazy" className="absolute inset-0 w-full h-full object-cover" /> : <MusicIcon className="absolute inset-0 m-auto w-1/3 h-1/3 text-white/90" />}
    </span>
  );
}

function PlayFab({ playing, onClick, label, className = "" }) {
  return (
    <button onClick={(e) => { e.stopPropagation(); onClick(); }} className={`w-11 h-11 rounded-full flex items-center justify-center text-white transition-[opacity,transform] duration-200 active:scale-90 ${className}`} style={{ background: "var(--accent-grad)", boxShadow: "0 10px 24px rgb(0 0 0 / 0.3)" }} aria-label={label}>
      {playing ? <Pause className="w-5 h-5" /> : <Play className="w-5 h-5 ml-0.5" />}
    </button>
  );
}

function Shelf({ title, subtitle, icon: Icon, children, action }) {
  return (
    <section className="mb-9">
      <div className="flex items-end gap-3 mb-3">
        <div className="flex-1 min-w-0">
          <h2 className="font-display text-xl sm:text-2xl font-semibold flex items-center gap-2" style={{ color: "var(--text-primary)" }}>{Icon && <Icon className="w-5 h-5" style={{ color: "var(--accent-rose)" }} />}{title}</h2>
          {subtitle && <p className="text-xs mt-0.5" style={{ color: "var(--text-muted)" }}>{subtitle}</p>}
        </div>
        {action}
      </div>
      {children}
    </section>
  );
}

// Album-style card used in the horizontal shelves.
function TrackCard({ track, reason, player, queue, index }) {
  const playing = player.isPlaying(track.id);
  const current = player.isCurrent(track.id);
  return (
    <motion.div className="enter group w-[150px] sm:w-[172px] flex-shrink-0 snap-start" style={{ "--d": `${Math.round((Math.min(index, 8) * 0.04) * 1000)}ms`, "--enter-y": "12px" }}>
      <div className="relative cursor-pointer" onClick={() => player.toggle(asQueueItem(track), queue)}>
        <Cover track={track} className="aspect-square w-full card-hover" rounded="rounded-[1.4rem]" />
        {playing && <span className="absolute top-2.5 left-2.5 px-2 py-1 rounded-full text-white" style={{ background: "rgb(0 0 0 / 0.5)" }}><span className="equalizer"><span /><span /><span /></span></span>}
        <PlayFab playing={playing} onClick={() => player.toggle(asQueueItem(track), queue)} label={playing ? `Pause ${track.title}` : `Play ${track.title}`} className={`absolute right-2.5 bottom-2.5 ${current ? "" : "can-hover:opacity-0 can-hover:translate-y-2 group-hover:opacity-100 group-hover:translate-y-0"}`} />
      </div>
      <p className="mt-2.5 text-sm font-bold truncate" style={{ color: current ? "var(--accent-rose)" : "var(--text-primary)" }}>{track.title || "Untitled"}</p>
      <p className="text-xs truncate" style={{ color: "var(--text-muted)" }}>{reason || track.user_display_name}</p>
    </motion.div>
  );
}

function Hero({ pick, player, queue }) {
  const t = pick.track;
  const playing = player.isPlaying(t.id);
  return (
    <motion.div initial={{ opacity: 0, y: 16 }} animate={{ opacity: 1, y: 0 }} className="relative overflow-hidden rounded-[2rem] mb-9 grain" style={{ color: "#fff", boxShadow: "var(--shadow-accent)" }}>
      <div className="absolute inset-0" style={{ background: MOOD_STYLES[t.mood] || "var(--accent-grad)" }} />
      {t.cover_url && <img loading="lazy" decoding="async" src={t.cover_url} alt="" aria-hidden="true" className="absolute inset-0 w-full h-full object-cover opacity-35 blur-2xl scale-125" />}
      <div className="absolute inset-0" style={{ background: "linear-gradient(90deg, rgb(0 0 0 / 0.35), transparent)" }} />
      <div className="relative flex items-center gap-4 sm:gap-6 p-5 sm:p-8">
        <Cover track={t} className="w-24 h-24 sm:w-44 sm:h-44 flex-shrink-0 shadow-2xl" rounded="rounded-2xl sm:rounded-3xl" />
        <div className="flex-1 min-w-0">
          <p className="text-[11px] font-bold uppercase tracking-[0.2em] opacity-90 flex items-center gap-1.5"><Sparkles className="w-3.5 h-3.5" /> Picked for you</p>
          <h2 className="font-display text-2xl sm:text-5xl font-semibold mt-1 sm:mt-1.5 leading-tight truncate">{t.title}</h2>
          <p className="text-sm opacity-90 mt-1 truncate">{t.user_display_name} · {pick.reason}</p>
          <div className="flex items-center gap-3 mt-3 sm:mt-5">
            <motion.button whileTap={{ scale: 0.94 }} onClick={() => player.toggle(asQueueItem(t), queue)} className="h-10 sm:h-12 px-5 sm:px-6 rounded-full bg-white font-bold flex items-center gap-2" style={{ color: "#1d1018" }}>
              {playing ? <><Pause className="w-5 h-5" /> Pause</> : <><Play className="w-5 h-5" /> Play</>}
            </motion.button>
            <span className="text-xs font-semibold opacity-90 hidden min-[420px]:flex items-center gap-3">
              {t.plays > 0 && <span className="flex items-center gap-1"><Headphones className="w-3.5 h-3.5" /> {compactNumber(t.plays)}</span>}
              {t.genre && <span>{t.genre}</span>}{t.mood && <span>· {t.mood}</span>}
            </span>
          </div>
        </div>
      </div>
    </motion.div>
  );
}

function FriendActivity({ people, tracks, player, compact }) {
  if (!people.length) return null;
  const play = (l) => { const t = tracks.find((x) => x.id === l.id); if (t) player.play(asQueueItem(t), [asQueueItem(t)]); };
  if (compact) {
    return (
      <div className="flex gap-3 overflow-x-auto no-scrollbar -mx-4 px-4 pb-1 mb-7">
        {people.map(({ user: u, listening: l, live }) => (
          <button key={u.email} onClick={() => play(l)} className="flex-shrink-0 w-56 card-sm !rounded-2xl p-2.5 flex items-center gap-2.5 text-left">
            <Avatar src={u.profile_picture} name={displayName(u)} size={40} online={isOnline(u) || undefined} />
            <span className="min-w-0 flex-1">
              <span className="block text-xs font-bold truncate" style={{ color: "var(--text-primary)" }}>{displayName(u)}</span>
              <span className="block text-[11px] truncate flex items-center gap-1" style={{ color: "var(--text-muted)" }}>{live && <AudioLines className="w-3 h-3 flex-shrink-0" style={{ color: "var(--accent-rose)" }} />}{l.title}</span>
            </span>
          </button>
        ))}
      </div>
    );
  }
  return (
    <div className="space-y-1">
      {people.map(({ user: u, listening: l, live }) => (
        <button key={u.email} onClick={() => play(l)} className="w-full flex items-center gap-3 p-2 rounded-2xl text-left transition-colors hover:bg-[var(--surface-2)]">
          <Avatar src={u.profile_picture} name={displayName(u)} size={40} online={isOnline(u) || undefined} />
          <span className="flex-1 min-w-0">
            <span className="flex items-center gap-1.5 text-sm font-bold" style={{ color: "var(--text-primary)" }}><span className="truncate">{displayName(u)}</span>{!live && <span className="text-[10px] font-medium flex-shrink-0" style={{ color: "var(--text-muted)" }}>{timeAgo(l.at)}</span>}</span>
            <span className="block text-xs truncate" style={{ color: "var(--text-secondary)" }}>{l.title} · {l.artist}</span>
          </span>
          {live ? <span className="equalizer flex-shrink-0" style={{ color: "var(--accent-rose)" }}><span /><span /><span /></span> : <Play className="w-4 h-4 flex-shrink-0" style={{ color: "var(--text-muted)" }} />}
        </button>
      ))}
    </div>
  );
}

export default function MusicPage() {
  const { user } = useAuth();
  const player = usePlayer();
  const confirm = useConfirm();
  const [params, setParams] = useSearchParams();
  const [search, setSearch] = useState("");
  const [genre, setGenre] = useState("All");
  const [mood, setMood] = useState(null);
  const blocked = useBlocked();
  const { data: allTracks, setData, loading } = useLiveQuery("MusicReview", null, { sort: "-created_date", limit: 300 });
  const tracks = useMemo(() => allTracks.filter((t) => !blocked.has(t.user_email)), [allTracks, blocked]);
  const { data: users } = useLiveQuery("User", null, { live: false });
  const { friendships } = useFriendships(user?.email);
  const { friendEmails } = splitFriendships(friendships, user?.email);
  const highlightRef = useRef(null);
  const allRef = useRef(null);

  const usersByEmail = useMemo(() => Object.fromEntries(users.map((u) => [u.email, u])), [users]);
  const taste = useMemo(() => buildTaste({ me: user, friends: friendEmails, tracks }), [user, friendEmails, tracks]);
  const forYou = useMemo(() => rankTracks(tracks, { taste, users: usersByEmail }), [tracks, taste, usersByEmail]);
  const trending = useMemo(() => trendingTracks(tracks).slice(0, 5), [tracks]);
  const circle = useMemo(() => new Set([...taste.following, ...taste.friends]), [taste]);
  const fromCircle = useMemo(() => tracks.filter((t) => circle.has(t.user_email) && t.music_url), [tracks, circle]);
  const artists = useMemo(() => {
    const m = new Map();
    tracks.forEach((t) => { const a = m.get(t.user_email) || { email: t.user_email, name: t.user_display_name, picture: t.user_profile_picture, tracks: 0, likes: 0 }; a.tracks += 1; a.likes += (t.likes || []).length + (t.plays || 0) / 10; m.set(t.user_email, a); });
    return [...m.values()].sort((a, b) => b.likes - a.likes).slice(0, 10);
  }, [tracks]);
  const activity = useMemo(() => users
    .filter((u) => u.email !== user?.email && u.listening?.at && Date.now() - u.listening.at < 24 * 3600000 && (circle.has(u.email) || circle.size === 0))
    .map((u) => ({ user: u, listening: u.listening, live: Date.now() - u.listening.at < 10 * 60000 }))
    .sort((a, b) => b.listening.at - a.listening.at)
    .slice(0, 8), [users, user?.email, circle]);

  const filtered = useMemo(() => {
    const q = search.trim().toLowerCase();
    return tracks.filter((t) => (genre === "All" || t.genre === genre) && (!mood || t.mood === mood) && (!q || [t.title, t.user_display_name, t.genre, t.mood].some((f) => String(f || "").toLowerCase().includes(q))));
  }, [tracks, search, genre, mood]);
  const genres = useMemo(() => ["All", ...new Set(tracks.map((t) => t.genre).filter(Boolean))], [tracks]);
  const moods = useMemo(() => [...new Set(tracks.map((t) => t.mood).filter(Boolean))], [tracks]);
  const queueOf = (list) => list.filter((t) => t.music_url).map(asQueueItem);
  const allQueue = queueOf(filtered);
  const forYouQueue = queueOf(forYou.map((x) => x.track));
  const current = player.track && tracks.find((t) => t.id === player.track.id);
  const highlight = params.get("track");
  const browsing = !!search.trim() || genre !== "All" || !!mood;

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
    if (!allQueue.length) return;
    const shuffled = [...allQueue].sort(() => Math.random() - 0.5);
    player.play(shuffled[0], shuffled);
  };
  const pickMood = (m) => { setMood((cur) => (cur === m ? null : m)); setTimeout(() => allRef.current?.scrollIntoView({ behavior: "smooth", block: "start" }), 50); };
  const like = (t) => toggleLike({ entity: "MusicReview", record: t, user, setData, message: `liked your track "${t.title}"`, link: `/Music?track=${t.id}` });

  const header = (
    <header className="flex items-center gap-2 sm:gap-3 mb-6">
      <div className="flex-1 min-w-0">
        <h1 className="font-display text-3xl sm:text-4xl font-semibold leading-tight" style={{ color: "var(--text-primary)" }}>Music</h1>
        <p className="text-sm mt-0.5 truncate" style={{ color: "var(--text-muted)" }}>{tracks.length} tracks from {artists.length} artists<span className="hidden sm:inline"> · listen together</span></p>
      </div>
      <button className="btn-outline !px-3 sm:!px-4" onClick={shuffle} disabled={!allQueue.length} aria-label="Shuffle all"><Shuffle className="w-4 h-4" /> <span className="hidden sm:inline">Shuffle</span></button>
      {user && <button className="btn !px-3 sm:!px-4" onClick={() => setParams({ upload: "1" })} aria-label="Share a track"><Upload className="w-4 h-4" /> <span className="hidden sm:inline">Share a track</span></button>}
    </header>
  );

  return (
    <Page width="max-w-7xl">
      <div className="grid xl:grid-cols-[minmax(0,1fr)_300px] gap-10 items-start">
        <div className="min-w-0">
          {header}
          <AnimatePresence mode="wait">
            {current ? <NowPlaying key="now" track={player.track} playing={player.playing} time={player.time} duration={player.duration} onToggle={() => player.toggle()} />
              : !loading && forYou[0] ? <Hero key="hero" pick={forYou[0]} player={player} queue={forYouQueue} /> : null}
          </AnimatePresence>

          {activity.length > 0 && <div className="xl:hidden"><p className="font-bold text-sm mb-2.5 flex items-center gap-1.5" style={{ color: "var(--text-secondary)" }}><AudioLines className="w-4 h-4" style={{ color: "var(--accent-rose)" }} /> Friend activity</p><FriendActivity people={activity} tracks={tracks} player={player} compact /></div>}

          {loading ? (
            <div className="flex gap-4 overflow-hidden">{Array.from({ length: 5 }).map((_, i) => <div key={i} className="skeleton w-[172px] aspect-square flex-shrink-0 !rounded-[1.4rem]" />)}</div>
          ) : tracks.length === 0 ? (
            <EmptyState icon={MusicIcon} title="No tracks yet" text="Share something you made — it plays for everyone right here." action={user && <button className="btn" onClick={() => setParams({ upload: "1" })}>Share a track</button>} />
          ) : (
            <>
              {!browsing && (
                <>
                  <Shelf title="Made for you" subtitle="Based on what you like, play and follow" icon={Sparkles}>
                    <div className="flex gap-4 overflow-x-auto no-scrollbar -mx-4 px-4 sm:mx-0 sm:px-0 pb-2 snap-x">
                      {forYou.slice(0, 12).map((x, i) => <TrackCard key={x.track.id} track={x.track} reason={x.reason} player={player} queue={forYouQueue} index={i} />)}
                    </div>
                  </Shelf>

                  <div className="grid lg:grid-cols-2 gap-x-10">
                    <Shelf title="Trending this week" icon={TrendingUp}>
                      <div className="space-y-1">
                        {trending.map((t, i) => {
                          const playing = player.isPlaying(t.id);
                          return (
                            <div key={t.id} className="group flex items-center gap-3 p-2 rounded-2xl transition-colors hover:bg-[var(--surface-2)] cursor-pointer" onClick={() => player.toggle(asQueueItem(t), queueOf(trending))}>
                              <span className="w-6 text-center font-display text-xl font-semibold" style={{ color: i < 3 ? "var(--accent-rose)" : "var(--text-muted)" }}>{i + 1}</span>
                              <span className="relative w-12 h-12 flex-shrink-0">
                                <Cover track={t} className="w-12 h-12" rounded="rounded-xl" />
                                <span className={`absolute inset-0 rounded-xl flex items-center justify-center text-white transition-opacity ${playing ? "opacity-100" : "opacity-0 group-hover:opacity-100"}`} style={{ background: "rgb(0 0 0 / 0.4)" }}>{playing ? <Pause className="w-4 h-4" /> : <Play className="w-4 h-4" />}</span>
                              </span>
                              <span className="flex-1 min-w-0">
                                <span className="block text-sm font-bold truncate" style={{ color: player.isCurrent(t.id) ? "var(--accent-rose)" : "var(--text-primary)" }}>{t.title}</span>
                                <span className="block text-xs truncate" style={{ color: "var(--text-muted)" }}>{t.user_display_name}{t.plays ? ` · ${plural(t.plays, "play")}` : ""}</span>
                              </span>
                              <span onClick={(e) => e.stopPropagation()}><LikeButton variant="plain" liked={!!user && (t.likes || []).includes(user.email)} count={t.likes?.length || 0} onToggle={() => like(t)} /></span>
                            </div>
                          );
                        })}
                      </div>
                    </Shelf>

                    {moods.length > 0 && (
                      <Shelf title="Browse by mood" icon={Disc3}>
                        <div className="grid grid-cols-2 sm:grid-cols-3 gap-3">
                          {moods.map((m, i) => (
                            <motion.button key={m} whileHover={{ y: -3 }} whileTap={{ scale: 0.96 }} onClick={() => pickMood(m)} className="enter-pop relative h-20 rounded-2xl overflow-hidden text-left p-3 text-white font-display text-lg font-semibold" style={{ "--d": `${Math.round((i * 0.04) * 1000)}ms`, background: MOOD_STYLES[m] || "var(--accent-grad)", boxShadow: "var(--shadow-sm)" }}>
                              {m}
                              <span className="absolute right-2 bottom-1 text-[11px] font-sans font-bold opacity-85">{plural(tracks.filter((t) => t.mood === m).length, "track")}</span>
                            </motion.button>
                          ))}
                        </div>
                      </Shelf>
                    )}
                  </div>

                  {fromCircle.length > 0 && (
                    <Shelf title="From people you follow" icon={Headphones}>
                      <div className="flex gap-4 overflow-x-auto no-scrollbar -mx-4 px-4 sm:mx-0 sm:px-0 pb-2 snap-x">
                        {fromCircle.slice(0, 12).map((t, i) => <TrackCard key={t.id} track={t} reason={`${t.user_display_name} · ${timeAgo(t.created_date)}`} player={player} queue={queueOf(fromCircle)} index={i} />)}
                      </div>
                    </Shelf>
                  )}

                  {artists.length > 0 && (
                    <Shelf title="Artists" icon={Sparkles}>
                      <div className="flex gap-5 overflow-x-auto no-scrollbar -mx-4 px-4 sm:mx-0 sm:px-0 pb-2">
                        {artists.map((a) => {
                          const u = usersByEmail[a.email];
                          return (
                            <Link key={a.email} to={profileLink(a.email)} className="flex flex-col items-center gap-2 w-24 flex-shrink-0 group">
                              <span className="flex rounded-full p-[5px] transition-transform duration-200 group-hover:scale-105" style={{ background: "var(--accent-grad)" }}><Avatar src={u?.profile_picture || a.picture} name={u ? displayName(u) : a.name} size={80} ring={2} ringColor="var(--app-bg)" /></span>
                              <span className="text-xs font-bold truncate w-full text-center" style={{ color: "var(--text-primary)" }}>{u ? displayName(u) : a.name}</span>
                              <span className="text-[10px] -mt-1.5" style={{ color: "var(--text-muted)" }}>{a.tracks} track{a.tracks === 1 ? "" : "s"}</span>
                            </Link>
                          );
                        })}
                      </div>
                    </Shelf>
                  )}
                </>
              )}

              <section ref={allRef} className="scroll-mt-4">
                <div className="flex flex-col md:flex-row gap-3 md:items-center mb-3">
                  <h2 className="font-display text-xl sm:text-2xl font-semibold flex-1" style={{ color: "var(--text-primary)" }}>{mood ? `${mood} tracks` : "All tracks"}</h2>
                  <SearchInput value={search} onChange={setSearch} placeholder="Search tracks, artists, moods…" className="md:w-72" />
                </div>
                <div className="flex items-center gap-2 mb-4">
                  {mood && <button className="chip flex-shrink-0" data-active="true" onClick={() => setMood(null)}>{mood} <X className="w-3.5 h-3.5" /></button>}
                  <ChipRow options={genres} value={genre} onChange={setGenre} className="flex-1" />
                </div>
                {filtered.length === 0 ? (
                  <EmptyState icon={MusicIcon} title="No tracks match" text="Try another genre or mood." />
                ) : (
                  <div className="card !rounded-3xl p-2 sm:p-3">
                    {filtered.map((t, i) => {
                      const isCurrent = player.isCurrent(t.id);
                      const playing = player.isPlaying(t.id);
                      const canDelete = user && (user.email === t.user_email || user.role === "admin");
                      return (
                        <motion.div
                          key={t.id}
                          ref={highlight === t.id ? highlightRef : null}
                          className="enter-side group flex items-center gap-3 sm:gap-4 p-2.5 sm:p-3 rounded-2xl transition-colors hover:bg-[var(--surface-2)]"
                          style={{ "--d": `${Math.min(i, 10) * 30}ms`, ...(isCurrent || highlight === t.id ? { background: "var(--pink-soft)" } : {}) }}
                        >
                          <span className="hidden sm:flex w-6 justify-center text-sm font-semibold tabular-nums" style={{ color: isCurrent ? "var(--accent-rose)" : "var(--text-muted)" }}>
                            {playing ? <span className="equalizer"><span /><span /><span /></span> : i + 1}
                          </span>
                          <button onClick={() => t.music_url && player.toggle(asQueueItem(t), allQueue)} disabled={!t.music_url} className="relative w-14 h-14 rounded-2xl overflow-hidden flex-shrink-0 disabled:opacity-50" aria-label={playing ? `Pause ${t.title}` : `Play ${t.title}`}>
                            <Cover track={t} className="absolute inset-0" rounded="rounded-2xl" />
                            <span className={`absolute inset-0 flex items-center justify-center text-white transition-opacity ${playing ? "opacity-100" : "opacity-0 group-hover:opacity-100"}`} style={{ background: "rgb(20 8 14 / 0.45)" }}>
                              {playing ? <Pause className="w-5 h-5" /> : <Play className="w-5 h-5 ml-0.5" />}
                            </span>
                          </button>
                          <div className="flex-1 min-w-0">
                            <p className="text-sm sm:text-base font-bold truncate" style={{ color: isCurrent ? "var(--accent-rose)" : "var(--text-primary)" }}>{t.title || "Untitled"}</p>
                            <p className="text-xs truncate" style={{ color: "var(--text-muted)" }}><Link to={profileLink(t.user_email)} className="hover:underline">{t.user_display_name}</Link> · {timeAgo(t.created_date)}{t.plays ? ` · ${plural(t.plays, "play")}` : ""}</p>
                            {t.ai_review && <p className="text-xs mt-1 line-clamp-1 hidden sm:block" style={{ color: "var(--text-secondary)" }}>{t.ai_review}</p>}
                          </div>
                          <div className="hidden md:flex gap-1.5">
                            {t.genre && <button onClick={() => setGenre(t.genre)} className="badge-pink">{t.genre}</button>}
                            {t.mood && <button onClick={() => setMood(t.mood)} className="badge-pink" style={{ color: "var(--text-secondary)", background: "var(--surface-2)", borderColor: "var(--border-c)" }}>{t.mood}</button>}
                          </div>
                          <LikeButton variant="plain" liked={!!user && (t.likes || []).includes(user.email)} count={t.likes?.length || 0} onToggle={() => like(t)} />
                          {canDelete && <button onClick={() => remove(t)} className="icon-btn w-8 h-8 can-hover:opacity-0 group-hover:opacity-100 focus:opacity-100" aria-label="Delete track"><Trash2 className="w-4 h-4" style={{ color: "var(--danger)" }} /></button>}
                        </motion.div>
                      );
                    })}
                  </div>
                )}
              </section>
            </>
          )}
        </div>

        <aside className="hidden xl:block sticky top-6 space-y-6">
          <div className="card !rounded-3xl p-4">
            <p className="font-bold text-sm mb-1 flex items-center gap-1.5" style={{ color: "var(--text-primary)" }}><AudioLines className="w-4 h-4" style={{ color: "var(--accent-rose)" }} /> Friend activity</p>
            <p className="text-[11px] mb-3" style={{ color: "var(--text-muted)" }}>What people you follow are listening to</p>
            {activity.length ? <FriendActivity people={activity} tracks={tracks} player={player} /> : (
              <p className="text-sm py-6 text-center" style={{ color: "var(--text-muted)" }}>Nobody's listening right now.<br /><Link to="/Friends" className="font-bold inline-flex items-center gap-0.5 mt-1" style={{ color: "var(--accent-rose)" }}>Find friends <ChevronRight className="w-3.5 h-3.5" /></Link></p>
            )}
          </div>
        </aside>
      </div>

      <UploadModal open={params.get("upload") === "1"} onClose={() => setParams({})} />
    </Page>
  );
}
