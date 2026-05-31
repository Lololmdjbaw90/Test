import React, { useState, useEffect } from "react";
import { useLocation, Link } from "react-router-dom";
import { base44 } from "@/api/base44Client";
import { Loader2, Settings, Grid3X3, MessageCircle, User, AtSign, Shield, UserPlus, UserCheck, Download, Sparkles } from "lucide-react";
import { exportToCsv } from "../utils/exportCsv";
import { AnimatePresence, motion } from "framer-motion";
import PostCard from "../components/community/PostCard";
import ProfileMessageBoard from "../components/profile/ProfileMessageBoard";
import NameStylePicker, { getNameStyle } from "../components/profile/NameStylePicker";
import LevelBadge from "../components/profile/LevelBadge";
import NitroBadge from "../components/profile/NitroBadge";
import CoinDisplay from "../components/profile/CoinDisplay";
import NitroShop from "../components/profile/NitroShop";

const TABS = [{ id:"posts",label:"Posts",icon:Grid3X3},{id:"about",label:"About",icon:User},{id:"messages",label:"Messages",icon:MessageCircle},{id:"nitro",label:"Nitro",icon:Sparkles,ownerOnly:true}];

function ProfileBanner({ isOwn, profile }) {
  const bannerUrl = profile?.banner_url, bannerColor = profile?.banner_color || "#e8a0b4", isNitro = profile?.nitro_active;
  return (
    <div className="relative w-full overflow-hidden flex-shrink-0" style={{ height: 130 }}>
      {bannerUrl ? <img src={bannerUrl} className="absolute inset-0 w-full h-full object-cover" alt="" />
        : isNitro ? <motion.div className="absolute inset-0" animate={{ background: ["linear-gradient(135deg,#c084fc 0%,#818cf8 50%,#e8a0b4 100%)","linear-gradient(135deg,#e8a0b4 0%,#c084fc 50%,#818cf8 100%)","linear-gradient(135deg,#818cf8 0%,#e8a0b4 50%,#c084fc 100%)"] }} transition={{ duration:4,repeat:Infinity,ease:"linear" }} />
        : <motion.div className="absolute inset-0" animate={{ background: [`linear-gradient(135deg,${bannerColor} 0%,#c0526e 100%)`,`linear-gradient(135deg,#d4708a 0%,${bannerColor} 100%)`] }} transition={{ duration:6,repeat:Infinity,ease:"linear" }} />}
      <motion.div className="absolute inset-0" style={{ background:"linear-gradient(105deg,transparent 30%,rgba(255,255,255,0.15) 50%,transparent 70%)" }} animate={{ x:["-100%","200%"] }} transition={{ duration:2.5,repeat:Infinity,ease:"linear",repeatDelay:3 }} />
      <div className="absolute bottom-0 left-0 right-0 h-16 pointer-events-none" style={{ background:"linear-gradient(to bottom,transparent,var(--app-bg))" }} />
      {isOwn && <Link to="/Settings" className="absolute top-3 right-3 w-8 h-8 rounded-full flex items-center justify-center backdrop-blur-sm border border-white/30 hover:scale-110 transition-transform" style={{ background:"rgba(255,255,255,0.2)" }}><Settings className="w-4 h-4 text-white" /></Link>}
    </div>
  );
}

function ProfileAvatar({ profile }) {
  const [err, setErr] = useState(false);
  return (
    <div className="relative flex-shrink-0" style={{ marginTop:-40,zIndex:10 }}>
      <motion.div className="absolute inset-0 rounded-full" style={{ margin:-3 }} animate={{ boxShadow:["0 0 0 2px rgba(232,160,180,0.5),0 0 16px rgba(232,160,180,0.25)","0 0 0 4px rgba(212,112,138,0.7),0 0 28px rgba(212,112,138,0.4)","0 0 0 2px rgba(232,160,180,0.5),0 0 16px rgba(232,160,180,0.25)"] }} transition={{ duration:2.5,repeat:Infinity,ease:"easeInOut" }} />
      <motion.div className="w-24 h-24 rounded-full overflow-hidden border-4" style={{ borderColor:"var(--surface)",background:"var(--pink-soft)" }} initial={{ scale:0.7,opacity:0 }} animate={{ scale:1,opacity:1 }} transition={{ type:"spring",stiffness:260,damping:20 }}>
        {profile.profile_picture && !err ? <img src={profile.profile_picture} onError={() => setErr(true)} className="w-full h-full object-cover" alt="" /> : <div className="w-full h-full flex items-center justify-center text-3xl font-bold" style={{ color:"var(--accent-pink)",background:"var(--pink-soft)" }}>{profile.display_name?.[0]?.toUpperCase()||"?"}</div>}
      </motion.div>
    </div>
  );
}

function StyledName({ name, styleId, isOwn, onStyleChange }) {
  const style = getNameStyle(styleId), styleProps = style.preview(name), isAurora = styleId === "aurora";
  return (
    <div className="flex items-center gap-2 flex-wrap">
      {isAurora ? <motion.h1 className="font-bold leading-tight" style={{ ...styleProps,backgroundSize:"200%" }} animate={{ backgroundPosition:["0% 50%","100% 50%","0% 50%"] }} transition={{ duration:4,repeat:Infinity,ease:"linear" }}>{name}</motion.h1> : <h1 className="leading-tight" style={styleProps}>{name}</h1>}
      {isOwn && <NameStylePicker currentStyle={styleId} name={name} onSave={onStyleChange} />}
    </div>
  );
}

function StatCard({ value, label, delay }) {
  return <motion.div initial={{ opacity:0,y:14 }} animate={{ opacity:1,y:0 }} transition={{ delay,type:"spring",stiffness:200 }} className="card-sm px-5 py-3 text-center flex-1" whileHover={{ scale:1.04,y:-2 }}><p className="text-lg font-bold" style={{ color:"var(--accent-rose)" }}>{value}</p><p className="text-[10px] font-medium uppercase tracking-widest mt-0.5" style={{ color:"var(--text-muted)" }}>{label}</p></motion.div>;
}

export default function ProfilePage() {
  const location = useLocation();
  const [profile, setProfile] = useState(null), [me, setMe] = useState(null), [posts, setPosts] = useState([]), [loading, setLoading] = useState(true), [tab, setTab] = useState("posts"), [nameStyle, setNameStyle] = useState("default"), [following, setFollowing] = useState(false), [followLoading, setFollowLoading] = useState(false);

  useEffect(() => { fetchData(); }, [location.search]);
  useEffect(() => { const onFocus = () => fetchData(); window.addEventListener("focus", onFocus); return () => window.removeEventListener("focus", onFocus); }, [location.search]);
  useEffect(() => {
    if (!me || !profile || me.email !== profile.email || loading) return;
    const totalLikes = posts.reduce((s, p) => s + (p.likes?.length || 0), 0);
    const earned = posts.length * 20 + totalLikes * 5;
    if (earned > (profile.xp || 0)) base44.auth.updateMe({ xp: earned }).catch(() => {});
  }, [me, profile, posts, loading]);

  const fetchData = async () => {
    setLoading(true);
    const params = new URLSearchParams(location.search), email = params.get("email");
    if (!email) { setLoading(false); return; }
    const [allUsers, ps, meData] = await Promise.all([base44.entities.User.list("-updated_date",200), base44.entities.CommunityPost.filter({ user_email: email },"-created_date"), base44.auth.me().catch(() => null)]);
    let found = allUsers.find(u => u.email === email) || null;
    if (meData && meData.email === email) found = { ...found,...meData };
    setProfile(found); setNameStyle(found?.name_style || "default"); setPosts(ps); setMe(meData);
    if (meData && found && meData.email !== found.email) setFollowing(meData.following?.includes(found.email) || false);
    setLoading(false);
  };

  if (loading) return <div className="flex items-center justify-center h-full"><Loader2 className="w-5 h-5 animate-spin" style={{ color:"var(--accent-pink)" }} /></div>;
  if (!profile) return <div className="flex items-center justify-center h-full"><p className="text-sm" style={{ color:"var(--text-muted)" }}>Profile not found.</p></div>;

  const isOwn = me?.email === profile.email, totalLikes = posts.reduce((s,p) => s + (p.likes?.length || 0), 0);

  const handleFollow = async () => {
    if (!me || isOwn) return;
    setFollowLoading(true);
    const next = following ? (me.following||[]).filter(e => e !== profile.email) : [...(me.following||[]),profile.email];
    await base44.auth.updateMe({ following: next });
    setMe(prev => ({ ...prev,following:next })); setFollowing(!following); setFollowLoading(false);
  };

  const aboutRows = [{ label:"Display Name",value:profile.display_name||profile.full_name,Icon:User },{ label:"Email",value:profile.email,Icon:AtSign },{ label:"Role",value:profile.role,Icon:Shield },{ label:"Bio",value:profile.bio,Icon:MessageCircle }].filter(r => r.value);

  return (
    <div className="h-full overflow-y-auto scroll" style={{ background:"var(--app-bg)" }}>
      <ProfileBanner isOwn={isOwn} profile={profile} />
      <div className="max-w-2xl mx-auto px-4 sm:px-6 pb-16">
        <div className="flex items-end gap-4 mb-5">
          <ProfileAvatar profile={profile} />
          <motion.div className="flex-1 min-w-0 pb-1" initial={{ opacity:0,x:12 }} animate={{ opacity:1,x:0 }} transition={{ delay:0.15,duration:0.4 }}>
            <StyledName name={profile.display_name||profile.full_name} styleId={isOwn?nameStyle:"default"} isOwn={isOwn} onStyleChange={setNameStyle} />
            <div className="flex flex-wrap items-center gap-1.5 mt-1">
              {profile.role === "admin" && <span className="badge-pink inline-flex items-center gap-1"><Shield className="w-2.5 h-2.5" /> Admin</span>}
              <LevelBadge xp={profile.xp||0} showProgress /><NitroBadge active={profile.nitro_active} />
            </div>
            <div className="flex flex-wrap items-center gap-2 mt-1.5">
              <p className="text-xs truncate" style={{ color:"var(--text-muted)" }}>{profile.email}</p>
              {isOwn && <CoinDisplay coins={profile.coins||0} />}
            </div>
            {!isOwn && me && <button onClick={handleFollow} disabled={followLoading} className="mt-2 flex items-center gap-1.5 text-xs font-semibold px-3 py-1.5 rounded-full transition-all" style={following?{background:"var(--pink-soft)",color:"var(--accent-rose)",border:"1.5px solid var(--accent-pink)"}:{background:"var(--accent-pink)",color:"white"}}>{followLoading?<Loader2 className="w-3 h-3 animate-spin"/>:following?<><UserCheck className="w-3 h-3"/> Following</>:<><UserPlus className="w-3 h-3"/> Follow</>}</button>}
          </motion.div>
        </div>
        {profile.bio && <motion.div initial={{ opacity:0,y:8 }} animate={{ opacity:1,y:0 }} transition={{ delay:0.25 }} className="card-sm px-4 py-3 mb-5" style={{ borderLeft:"3px solid var(--accent-pink)" }}><p className="text-sm leading-relaxed" style={{ color:"var(--text-secondary)" }}>{profile.bio}</p></motion.div>}
        <div className="flex gap-3 mb-6"><StatCard value={posts.length} label="Posts" delay={0.3} /><StatCard value={totalLikes} label="Likes" delay={0.38} /><StatCard value={posts.filter(p=>p.image_url).length} label="Art" delay={0.46} /></div>
        <motion.div initial={{ opacity:0 }} animate={{ opacity:1 }} transition={{ delay:0.4 }} className="relative flex rounded-xl p-1 mb-6" style={{ background:"var(--pink-soft)",border:"1px solid var(--border-c)" }}>
          {TABS.filter(t => !t.ownerOnly||isOwn).map(t => {
            const Icon = t.icon, active = tab === t.id;
            return <button key={t.id} onClick={() => setTab(t.id)} className="relative flex-1 flex items-center justify-center gap-1.5 py-2 text-xs font-semibold rounded-lg transition-colors z-10" style={{ color:active?"white":"var(--text-muted)" }}>{active && <motion.div layoutId="tab-pill" className="absolute inset-0 rounded-lg" style={{ background:"linear-gradient(135deg,var(--accent-pink),var(--accent-rose))",boxShadow:"0 2px 10px rgba(212,112,138,0.35)" }} transition={{ type:"spring",stiffness:400,damping:30 }} />}<Icon className="w-3.5 h-3.5 relative z-10" /><span className="relative z-10">{t.label}</span></button>;
          })}
        </motion.div>
        <AnimatePresence mode="wait">
          {tab === "posts" && <motion.div key="posts" initial={{ opacity:0,y:14 }} animate={{ opacity:1,y:0 }} exit={{ opacity:0,y:-8 }} transition={{ duration:0.25 }}>
            {posts.length > 0 && <div className="flex justify-end mb-3"><button onClick={() => exportToCsv(posts.map(p=>({title:p.title||"",likes:p.likes?.length||0})),profile.email+"-posts")} className="btn-outline text-xs px-3 py-1.5 flex items-center gap-1.5"><Download className="w-3 h-3"/> Export CSV</button></div>}
            {posts.length === 0 ? <div className="flex flex-col items-center py-20 gap-3"><div className="w-12 h-12 rounded-full flex items-center justify-center" style={{ background:"var(--pink-soft)" }}><Grid3X3 className="w-5 h-5" style={{ color:"var(--accent-pink)" }}/></div><p className="text-sm" style={{ color:"var(--text-muted)" }}>No posts yet.</p></div>
              : <div className="columns-1 sm:columns-2 gap-4 pb-10">{posts.map((post,i) => <motion.div key={post.id} className="break-inside-avoid mb-4" initial={{ opacity:0,y:18 }} animate={{ opacity:1,y:0 }} transition={{ delay:i*0.05 }}><PostCard post={post} index={i} onUpdate={fetchData} currentUser={me} /></motion.div>)}</div>}
          </motion.div>}
          {tab === "about" && <motion.div key="about" initial={{ opacity:0,y:14 }} animate={{ opacity:1,y:0 }} exit={{ opacity:0,y:-8 }} transition={{ duration:0.25 }} className="space-y-2 mb-8">
            {aboutRows.map((r,i) => { const Icon=r.Icon; return <motion.div key={r.label} initial={{ opacity:0,x:-12 }} animate={{ opacity:1,x:0 }} transition={{ delay:i*0.07 }} className="card-sm px-4 py-3 flex items-start gap-3" whileHover={{ x:3 }}><div className="w-7 h-7 rounded-lg flex items-center justify-center flex-shrink-0 mt-0.5" style={{ background:"var(--pink-soft)" }}><Icon className="w-3.5 h-3.5" style={{ color:"var(--accent-rose)" }}/></div><div><p className="text-[10px] font-semibold uppercase tracking-widest mb-0.5" style={{ color:"var(--text-muted)" }}>{r.label}</p><p className="text-sm" style={{ color:"var(--text-primary)" }}>{r.value}</p></div></motion.div>; })}
          </motion.div>}
          {tab === "messages" && <motion.div key="messages" initial={{ opacity:0,y:14 }} animate={{ opacity:1,y:0 }} exit={{ opacity:0,y:-8 }} transition={{ duration:0.25 }} className="pb-10"><ProfileMessageBoard profileUser={profile} currentUser={me} /></motion.div>}
          {tab === "nitro" && isOwn && <motion.div key="nitro" initial={{ opacity:0,y:14 }} animate={{ opacity:1,y:0 }} exit={{ opacity:0,y:-8 }} transition={{ duration:0.25 }} className="pb-10"><NitroShop user={{ ...me,...profile }} onUpdate={(data) => { setProfile(p => ({ ...p,...data })); fetchData(); }} /></motion.div>}
        </AnimatePresence>
      </div>
    </div>
  );
}