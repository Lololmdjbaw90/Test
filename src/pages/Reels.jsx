import React, { useCallback, useEffect, useLayoutEffect, useMemo, useRef, useState } from "react";
import { Link, useNavigate, useSearchParams } from "react-router-dom";
import { Camera, ChevronDown, ChevronUp, Clapperboard, Loader2, X } from "lucide-react";
import { base44 } from "@/api/base44Client";
import { useAuth } from "@/lib/AuthContext";
import { useLiveQuery } from "@/lib/useLiveQuery";
import { useFriendships, splitFriendships, toggleFollow } from "@/lib/social";
import { rankReels, recordReelSignal } from "@/lib/reelRank";
import { toggleLike } from "@/lib/likes";
import { useBlocked, openReport } from "@/lib/safety";
import { toast } from "@/lib/toast";
import { feedback } from "@/lib/feedback";
import { displayName } from "@/lib/format";
import { usePlayer } from "@/lib/player";
import { useConfirm } from "@/components/common/Modal";
import BottomSheet from "@/components/common/BottomSheet";
import ShareSheet from "@/components/reels/ShareSheet";
import CommentSection from "@/components/gallery/CommentSection";
import ReelItem from "@/components/reels/ReelItem";
import ReelStudio from "@/components/reels/ReelStudio";

const TABS = [{ id: "following", label: "Following" }, { id: "foryou", label: "For you" }];
const sessionSeed = Math.floor(Math.random() * 1e9);
const viewedThisSession = new Set();

export default function ReelsPage() {
  const { user: me, updateMe } = useAuth();
  const navigate = useNavigate();
  const confirm = useConfirm();
  const player = usePlayer();
  const [params, setParams] = useSearchParams();
  const [tab, setTab] = useState("foryou");
  const [active, setActive] = useState(0);
  const [soundOn, setSoundOn] = useState(() => { try { return sessionStorage.getItem("sugerly:reel-sound") === "1"; } catch { return false; } });
  const [commentsFor, setCommentsFor] = useState(null);
  const [shareFor, setShareFor] = useState(null);
  const scroller = useRef(null);
  const tag = params.get("tag");
  const startId = params.get("r");
  const creating = params.get("create") === "1";

  const { data: reels, setData, loading } = useLiveQuery("Reel", null, { sort: "-created_date", limit: 250 });
  const { data: users } = useLiveQuery("User", null, { live: false });
  const usersByEmail = useMemo(() => Object.fromEntries(users.map((u) => [u.email, u])), [users]);
  const { friendships } = useFriendships(me?.email);
  const { friendEmails } = useMemo(() => splitFriendships(friendships, me?.email), [friendships, me?.email]);
  const blocked = useBlocked();
  const following = useMemo(() => new Set(me?.following || []), [me?.following]);
  const savedSet = useMemo(() => new Set(me?.saved_reels || []), [me?.saved_reels]);
  const byId = useMemo(() => new Map(reels.map((r) => [r.id, r])), [reels]);

  // Comment counts for the reels around the one on screen.
  const { data: comments } = useLiveQuery("CommunityComment", null, { sort: "-created_date", limit: 600 });
  const commentCounts = useMemo(() => {
    const m = {};
    comments.forEach((c) => { const id = String(c.post_id || ""); if (id.startsWith("reel_")) m[id.slice(5)] = (m[id.slice(5)] || 0) + 1; });
    return m;
  }, [comments]);

  // ---------- the feed order ----------
  // Ranked once when the feed opens (or the tab / hashtag changes); after each
  // reel you watch, only the reels *below* the next one are re-ranked, so the
  // feed learns as you scroll without anything jumping under your thumb.
  const [order, setOrder] = useState([]); // [{ id, reason }]
  const [nonce, setNonce] = useState(0);
  const orderKey = `${tab}|${tag}|${loading}|${nonce}`;
  const lastKey = useRef("");
  const scrollTarget = useRef(null);
  const candidates = useCallback(() => reels.filter((r) => !blocked.has(r.user_email) && (!tag || (r.tags || []).includes(tag)) && (tab === "foryou" || following.has(r.user_email) || friendEmails.includes(r.user_email))), [reels, blocked, tag, tab, following, friendEmails]);
  const rank = useCallback((list, fixed = []) => {
    if (tab === "following") return list.filter((r) => !fixed.includes(r.id)).map((r) => ({ reel: r, reason: null }));
    return rankReels(list, { me, friends: friendEmails, blocked, commentCounts, seed: sessionSeed, fixed });
  }, [tab, me, friendEmails, blocked, commentCounts]);

  useEffect(() => {
    if (loading || lastKey.current === orderKey) return;
    lastKey.current = orderKey;
    let list = rank(candidates()).map((x) => ({ id: x.reel.id, reason: x.reason }));
    if (startId && byId.has(startId)) list = [{ id: startId, reason: null }, ...list.filter((x) => x.id !== startId)];
    setOrder(list);
    setActive(0);
    scrollTarget.current = 0;
  }, [orderKey, loading]); // eslint-disable-line react-hooks/exhaustive-deps

  // Scroll once the new order is on screen (scroll snapping would otherwise
  // stay on the reel that was there before).
  useLayoutEffect(() => {
    const i = scrollTarget.current;
    const root = scroller.current;
    if (i == null || !root) return;
    scrollTarget.current = null;
    root.scrollTo({ top: i * root.clientHeight });
  }, [order]);

  // New reels arriving while you watch: yours go right after the current one,
  // others join the end of the queue.
  useEffect(() => {
    if (!order.length) return;
    const list = candidates();
    if (startId && !order.some((x) => x.id === startId) && list.some((r) => r.id === startId)) scrollTarget.current = active;
    setOrder((o) => {
      const known = new Set(o.map((x) => x.id));
      const fresh = list.filter((r) => !known.has(r.id));
      if (!fresh.length) return o;
      const mine = fresh.filter((r) => r.user_email === me?.email && r.id !== startId).map((r) => ({ id: r.id, reason: null }));
      const others = fresh.filter((r) => r.user_email !== me?.email && r.id !== startId).map((r) => ({ id: r.id, reason: "New" }));
      // The reel you just posted arrived after the feed was ranked: show it now.
      const opened = fresh.some((r) => r.id === startId) ? [{ id: startId, reason: null }] : [];
      return [...o.slice(0, active), ...opened, ...o.slice(active, active + 1), ...mine, ...o.slice(active + 1), ...others];
    });
  }, [reels]); // eslint-disable-line react-hooks/exhaustive-deps

  // Learn while scrolling: re-rank everything after the next reel.
  const reRank = useCallback((current) => {
    if (tab !== "foryou") return;
    setOrder((o) => {
      const keep = o.slice(0, current + 2);
      const tail = o.slice(current + 2).map((x) => byId.get(x.id)).filter(Boolean);
      if (tail.length < 2) return o;
      const ranked = rank(tail, keep.map((x) => x.id)).map((x) => ({ id: x.reel.id, reason: x.reason }));
      return [...keep, ...ranked];
    });
  }, [tab, byId, rank]);

  // Which reel is on screen.
  useEffect(() => {
    const root = scroller.current;
    if (!root) return undefined;
    const io = new IntersectionObserver((entries) => {
      entries.forEach((e) => { if (e.isIntersecting && e.intersectionRatio > 0.6) setActive(Number(e.target.dataset.index)); });
    }, { root, threshold: [0.6] });
    root.querySelectorAll("[data-index]").forEach((el) => io.observe(el));
    return () => io.disconnect();
  }, [order.length]);
  const prevActive = useRef(0);
  useEffect(() => {
    if (prevActive.current === active) return undefined;
    prevActive.current = active;
    feedback("swipe");
    // Re-rank once the swipe has settled, so it never competes with the scroll.
    const t = setTimeout(() => {
      const run = () => reRank(active);
      if (window.requestIdleCallback) window.requestIdleCallback(run, { timeout: 800 }); else run();
    }, 450);
    return () => clearTimeout(t);
  }, [active]); // eslint-disable-line react-hooks/exhaustive-deps

  // Reels have their own sound: pause the music player while you watch.
  useEffect(() => { if (soundOn && player.playing) player.pause(); }, [soundOn, active]); // eslint-disable-line react-hooks/exhaustive-deps

  const go = (dir) => {
    const root = scroller.current;
    if (!root) return;
    root.scrollTo({ top: Math.max(0, (active + dir) * root.clientHeight), behavior: "smooth" });
  };
  useEffect(() => {
    const onKey = (e) => {
      if (["INPUT", "TEXTAREA"].includes(document.activeElement?.tagName) || commentsFor || shareFor || creating) return;
      if (e.key === "ArrowDown" || e.key === "j") { e.preventDefault(); go(1); }
      if (e.key === "ArrowUp" || e.key === "k") { e.preventDefault(); go(-1); }
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  });

  // ---------- actions ----------
  const setSound = (on = true) => {
    setSoundOn(on);
    try { sessionStorage.setItem("sugerly:reel-sound", on ? "1" : "0"); } catch { /* private mode */ }
  };
  const like = (reel) => {
    const was = (reel.likes || []).includes(me?.email);
    recordReelSignal(reel, { liked: !was });
    toggleLike({ entity: "Reel", record: reel, user: me, setData, message: "liked your reel", link: `/Reels?r=${reel.id}` });
  };
  const save = async (reel) => {
    const was = savedSet.has(reel.id);
    feedback("save");
    recordReelSignal(reel, { saved: !was });
    const next = was ? [...savedSet].filter((id) => id !== reel.id) : [...savedSet, reel.id];
    try { await updateMe({ saved_reels: next }); if (!was) toast.success("Saved to your reels"); } catch (e) { toast.error(e?.message || "Could not save."); }
  };
  const share = (reel) => setShareFor(reel);
  const follow = async (email) => {
    try { const now = await toggleFollow({ me, email, updateMe }); if (now) toast.success(`Following ${usersByEmail[email] ? displayName(usersByEmail[email]) : email.split("@")[0]}`); } catch (e) { toast.error(e?.message || "Could not follow."); }
  };
  const hide = (reel) => {
    recordReelSignal(reel, { hidden: true });
    toast("Got it — you'll see fewer reels like this");
    setOrder((o) => o.filter((x) => x.id !== reel.id));
  };
  const setComments = async (reel, on) => {
    try {
      await base44.entities.Reel.update(reel.id, { comments_off: !on });
      feedback("toggle");
      toast.success(on ? "Comments are on" : "Comments are off for this reel");
    } catch (e) { toast.error(e?.message || "Could not change comments."); }
  };
  const remove = async (reel) => {
    if (!(await confirm({ title: "Delete this reel?", message: "It will be removed for everyone.", confirmLabel: "Delete", danger: true }))) return;
    try { await base44.entities.Reel.delete(reel.id); setOrder((o) => o.filter((x) => x.id !== reel.id)); toast.success("Reel deleted"); } catch (e) { toast.error(e?.message || "Could not delete."); }
  };
  const viewed = (reel) => {
    if (viewedThisSession.has(reel.id)) return;
    viewedThisSession.add(reel.id);
    base44.entities.Reel.update(reel.id, { views: (reel.views || 0) + 1 }).catch(() => {});
  };
  const setTag = (t) => setParams((p) => { const n = new URLSearchParams(p); if (t) n.set("tag", t); else n.delete("tag"); n.delete("r"); return n; });
  const closeStudio = (newId) => {
    setParams((p) => { const n = new URLSearchParams(p); n.delete("create"); if (newId) n.set("r", newId); return n; }, { replace: true });
    if (newId) { setTab("foryou"); setNonce((n) => n + 1); }
  };

  // One stable object for every reel, so reels only re-render when their own
  // data changes (the functions inside always see the latest state).
  const latest = useRef({});
  latest.current = {
    like, save, share, follow, hide, remove, viewed, tag: setTag, setSound,
    comments: setCommentsFor,
    setComments,
    report: (r) => openReport({ type: "reel", id: r.id, owner: r.user_email, preview: r.caption, link: `/Reels?r=${r.id}` }),
  };
  const actions = useMemo(() => new Proxy({}, { get: (_, key) => (...args) => latest.current[key]?.(...args) }), []);

  const items = order.map((x) => ({ ...x, reel: byId.get(x.id) })).filter((x) => x.reel);

  return (
    <div className="relative h-full bg-black text-white overflow-hidden reels-page">
      {/* top bar */}
      <div className="absolute top-0 inset-x-0 z-20 pt-[env(safe-area-inset-top)] pointer-events-none">
        <div className="h-14 px-3 flex items-center gap-2">
          <span className="w-10" />
          <div className="flex-1 flex justify-center gap-5 pointer-events-auto">
            {TABS.map((t) => (
              <button key={t.id} onClick={() => { if (t.id !== tab) { feedback("tab"); setTab(t.id); } }} className="relative py-1 text-[15px] font-bold transition-opacity" style={{ opacity: tab === t.id ? 1 : 0.6, textShadow: "0 1px 4px rgb(0 0 0 / 0.5)" }} aria-pressed={tab === t.id}>
                {t.label}
                <span className="absolute left-1/2 -bottom-0.5 w-6 h-[3px] -ml-3 rounded-full bg-white transition-all duration-300" style={{ opacity: tab === t.id ? 1 : 0, transform: `scaleX(${tab === t.id ? 1 : 0.2})` }} />
              </button>
            ))}
          </div>
          <Link to="/Reels?create=1" onClick={() => feedback("tap")} className="pointer-events-auto w-10 h-10 rounded-full flex items-center justify-center" style={{ background: "rgb(255 255 255 / 0.14)" }} aria-label="Create a reel"><Camera className="w-5 h-5" /></Link>
        </div>
        {tag && (
          <div className="flex justify-center pointer-events-auto">
            <button onClick={() => setTag(null)} className="px-3 py-1 rounded-full text-xs font-bold flex items-center gap-1.5" style={{ background: "rgb(255 255 255 / 0.18)" }}>#{tag} <X className="w-3.5 h-3.5" /></button>
          </div>
        )}
      </div>

      {/* the feed */}
      <div className="md:flex md:justify-center h-full">
        <div ref={scroller} className="relative h-full w-full md:max-w-[min(480px,calc((100dvh-2rem)*9/16))] md:rounded-3xl md:my-0 overflow-y-scroll no-scrollbar snap-y snap-mandatory overscroll-contain" style={{ scrollbarWidth: "none", overflowAnchor: "none" }}>
          {loading && !items.length ? (
            <div className="h-full flex items-center justify-center"><Loader2 className="w-7 h-7 animate-spin opacity-70" /></div>
          ) : !items.length ? (
            <div className="h-full flex flex-col items-center justify-center text-center px-8 gap-3">
              <span className="w-16 h-16 rounded-3xl flex items-center justify-center anim-bob" style={{ background: "rgb(255 255 255 / 0.1)" }}><Clapperboard className="w-8 h-8" /></span>
              <p className="font-display text-2xl">{tab === "following" ? "Nothing from people you follow" : tag ? `No reels with #${tag}` : "No reels yet"}</p>
              <p className="text-sm opacity-70 max-w-xs">{tab === "following" ? "Follow creators from For you to see their reels here." : "Be the first — film something, add a filter and share it."}</p>
              <Link to="/Reels?create=1" className="btn mt-2"><Camera className="w-4 h-4" /> Create a reel</Link>
            </div>
          ) : (
            <>
              {items.map(({ reel, reason }, i) => (
                <section key={reel.id} data-index={i} className="relative h-full w-full snap-start snap-always overflow-hidden">
                  {Math.abs(i - active) <= 3 && (
                    <ReelItem
                      reel={reel}
                      reason={tab === "foryou" ? reason : null}
                      active={i === active && !commentsFor && !shareFor && !creating}
                      near={Math.abs(i - active) <= 1}
                      me={me}
                      author={usersByEmail[reel.user_email]}
                      following={following.has(reel.user_email)}
                      liked={!!me && (reel.likes || []).includes(me.email)}
                      saved={savedSet.has(reel.id)}
                      commentCount={commentCounts[reel.id] || 0}
                      soundOn={soundOn}
                      actions={actions}
                    />
                  )}
                </section>
              ))}
              <section className="relative h-full w-full snap-start flex flex-col items-center justify-center text-center px-8 gap-3">
                <p className="text-3xl">✨</p>
                <p className="font-display text-2xl">You're all caught up</p>
                <p className="text-sm opacity-70">New reels show up here as people post them.</p>
                <div className="flex gap-2 mt-2">
                  <button className="btn-outline !text-white !border-white/30" onClick={() => setNonce((n) => n + 1)}>Start over</button>
                  <Link to="/Reels?create=1" className="btn"><Camera className="w-4 h-4" /> Create</Link>
                </div>
              </section>
            </>
          )}
        </div>
        {/* desktop up / down */}
        {items.length > 1 && (
          <div className="hidden md:flex flex-col gap-3 justify-center ml-4">
            <button onClick={() => go(-1)} disabled={active === 0} className="w-11 h-11 rounded-full flex items-center justify-center disabled:opacity-30" style={{ background: "rgb(255 255 255 / 0.12)" }} aria-label="Previous reel"><ChevronUp className="w-5 h-5" /></button>
            <button onClick={() => go(1)} disabled={active >= items.length} className="w-11 h-11 rounded-full flex items-center justify-center disabled:opacity-30" style={{ background: "rgb(255 255 255 / 0.12)" }} aria-label="Next reel"><ChevronDown className="w-5 h-5" /></button>
          </div>
        )}
      </div>

      <BottomSheet anchorRef={scroller} open={!!commentsFor} onClose={() => setCommentsFor(null)} title={!commentsFor ? "" : byId.get(commentsFor.id)?.comments_off ? "Comments" : `${commentCounts[commentsFor.id] || 0} comment${commentCounts[commentsFor.id] === 1 ? "" : "s"}`} label="Comments">
        {commentsFor && (
          <div className="flex-1 flex flex-col" onSubmitCapture={() => recordReelSignal(commentsFor, { commented: true })}>
            <CommentSection entity="CommunityComment" field="post_id" targetId={`reel_${commentsFor.id}`} ownerEmail={commentsFor.user_email} link={`/Reels?r=${commentsFor.id}`} showTitle={false} sheet disabled={!!byId.get(commentsFor.id)?.comments_off} />
            {byId.get(commentsFor.id)?.comments_off && commentsFor.user_email === me?.email && (
              <div className="flex justify-center -mt-4"><button className="btn" onClick={() => setComments(commentsFor, true)}>Turn comments back on</button></div>
            )}
          </div>
        )}
      </BottomSheet>
      <ShareSheet anchorRef={scroller} reel={shareFor} me={me} friendEmails={friendEmails} usersByEmail={usersByEmail} onClose={() => setShareFor(null)} onShared={() => shareFor && recordReelSignal(shareFor, { shared: true })} />

      {creating && <ReelStudio onClose={closeStudio} />}
    </div>
  );
}
