import React from "react";
import { Link } from "react-router-dom";
import { Clapperboard, Images, Play } from "lucide-react";
import { useLiveQuery } from "@/lib/useLiveQuery";
import { useMediaSrc } from "@/lib/media";
import { compactNumber } from "@/lib/format";
import { EmptyState } from "@/components/common/Page";

function ReelTile({ reel, i }) {
  const cover = useMediaSrc(reel.cover_url || (reel.kind === "photo" ? reel.media_url : ""));
  return (
    <Link to={`/Reels?r=${reel.id}`} className="rise-in relative block aspect-[9/16] rounded-xl overflow-hidden active:scale-[0.97] transition-transform" style={{ "--d": `${Math.min(i, 12) * 25}ms`, background: "var(--surface-2)" }} aria-label={reel.caption || "Reel"}>
      {cover && <img src={cover} alt="" loading="lazy" className="absolute inset-0 w-full h-full object-cover" />}
      <span className="absolute inset-x-0 bottom-0 h-16" style={{ background: "linear-gradient(transparent, rgb(0 0 0 / 0.6))" }} />
      <span className="absolute left-1.5 bottom-1.5 flex items-center gap-1 text-white text-[11px] font-bold"><Play className="w-3.5 h-3.5 fill-white" />{compactNumber(reel.views || 0)}</span>
      {(reel.media_urls || []).length > 1 && <Images className="absolute right-1.5 top-1.5 w-4 h-4 text-white drop-shadow" />}
    </Link>
  );
}

// A profile's reels, newest first, as a TikTok-style grid.
export default function ProfileReels({ email, isOwn }) {
  const { data: reels, loading } = useLiveQuery("Reel", { user_email: email }, { sort: "-created_date", limit: 60, enabled: !!email });
  if (loading) return <div className="grid grid-cols-3 gap-1.5">{[0, 1, 2].map((i) => <div key={i} className="skeleton aspect-[9/16] !rounded-xl" />)}</div>;
  if (!reels.length) {
    return <EmptyState icon={Clapperboard} title={isOwn ? "No reels yet" : "No reels yet"} text={isOwn ? "Film your first reel — tap + and choose Create a reel." : "When they post reels, they'll show up here."} action={isOwn ? <Link to="/Reels?create=1" className="btn">Create a reel</Link> : null} />;
  }
  return <div className="grid grid-cols-3 gap-1.5">{reels.map((r, i) => <ReelTile key={r.id} reel={r} i={i} />)}</div>;
}
