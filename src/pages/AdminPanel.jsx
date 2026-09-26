import React, { useEffect, useMemo, useState } from "react";
import { Link } from "react-router-dom";
import { animate, motion } from "framer-motion";
import { Activity, BarChart3, Check, ExternalLink, Flag, Image as ImageIcon, MessageSquare, Music, Server, Settings as SettingsIcon, Shield, ShieldCheck, ShieldOff, Trash2, Users } from "lucide-react";
import { base44 } from "@/api/base44Client";
import { useAuth } from "@/lib/AuthContext";
import { toast } from "@/lib/toast";
import { displayName, isOnline, profileLink, timeAgo } from "@/lib/format";
import { Page, PageHeader, EmptyState, CenterSpinner } from "@/components/common/Page";
import { SearchInput, Segmented, ChipRow } from "@/components/common/Controls";
import { useConfirm } from "@/components/common/Modal";
import Avatar from "@/components/common/Avatar";
import AdminSiteSettings from "@/components/admin/AdminSiteSettings";

const COLLECTIONS = ["User", "Artwork", "CommunityPost", "Comment", "CommunityComment", "ChannelMessage", "Community", "ServerChannel", "MusicReview", "Commission", "Report"];
// Where each kind of reported thing lives, so "Remove content" can delete it.
const REPORT_TARGET = { post: "CommunityPost", comment: "CommunityComment", track: "MusicReview", message: "ChannelMessage" };

function CountUp({ value }) {
  const [n, setN] = useState(0);
  useEffect(() => { const c = animate(0, value, { duration: 1, ease: "easeOut", onUpdate: (v) => setN(Math.round(v)) }); return () => c.stop(); }, [value]);
  return <>{n.toLocaleString()}</>;
}

function StatCard({ icon: Icon, label, value, sub, delay }) {
  return (
    <motion.div initial={{ opacity: 0, y: 16 }} animate={{ opacity: 1, y: 0 }} transition={{ delay }} className="card p-5">
      <div className="flex items-center justify-between mb-3">
        <span className="w-10 h-10 rounded-2xl flex items-center justify-center" style={{ background: "var(--pink-soft)", color: "var(--accent-rose)" }}><Icon className="w-5 h-5" /></span>
        {sub && <span className="text-[11px] font-bold" style={{ color: "var(--success)" }}>{sub}</span>}
      </div>
      <p className="font-display text-3xl font-semibold" style={{ color: "var(--text-primary)" }}><CountUp value={value} /></p>
      <p className="text-xs font-semibold mt-0.5" style={{ color: "var(--text-muted)" }}>{label}</p>
    </motion.div>
  );
}

function ActivityChart({ data }) {
  const days = useMemo(() => {
    const out = [];
    for (let i = 13; i >= 0; i--) {
      const d = new Date(Date.now() - i * 86400000);
      const key = d.toISOString().slice(0, 10);
      const count = data.filter((x) => (x.created_date || "").slice(0, 10) === key).length;
      out.push({ key, count, label: d.toLocaleDateString(undefined, { weekday: "narrow" }), full: d.toLocaleDateString(undefined, { month: "short", day: "numeric" }) });
    }
    return out;
  }, [data]);
  const max = Math.max(1, ...days.map((d) => d.count));
  return (
    <div className="card p-5">
      <div className="flex items-center gap-2 mb-5"><Activity className="w-4 h-4" style={{ color: "var(--accent-rose)" }} /><h2 className="font-display text-lg font-semibold flex-1" style={{ color: "var(--text-primary)" }}>Activity · last 14 days</h2><span className="text-xs" style={{ color: "var(--text-muted)" }}>posts, art, comments, messages</span></div>
      <div className="flex items-end gap-1.5 sm:gap-2 h-40">
        {days.map((d, i) => (
          <div key={d.key} className="flex-1 flex flex-col items-center gap-1.5 h-full justify-end group">
            <span className="text-[10px] font-bold opacity-0 group-hover:opacity-100 transition-opacity" style={{ color: "var(--text-secondary)" }}>{d.count}</span>
            <motion.div initial={{ height: 0 }} animate={{ height: `${Math.max(3, (d.count / max) * 100)}%` }} transition={{ delay: 0.2 + i * 0.03, type: "spring", stiffness: 140, damping: 18 }} className="w-full rounded-t-xl rounded-b-md" style={{ background: d.count ? "var(--accent-grad)" : "var(--border-c)" }} title={`${d.full}: ${d.count}`} />
            <span className="text-[10px] font-semibold" style={{ color: "var(--text-muted)" }}>{d.label}</span>
          </div>
        ))}
      </div>
    </div>
  );
}

export default function AdminPanel() {
  const { user: me, isAdmin } = useAuth();
  const confirm = useConfirm();
  const [data, setData] = useState(null);
  const [tab, setTab] = useState("overview");
  const [search, setSearch] = useState("");
  const [contentType, setContentType] = useState("all");

  const load = async () => {
    const entries = await Promise.all(COLLECTIONS.map(async (name) => [name, await base44.entities[name].list("-created_date", 500).catch(() => [])]));
    setData(Object.fromEntries(entries));
  };
  useEffect(() => { if (isAdmin) load(); }, [isAdmin]);

  const content = useMemo(() => {
    if (!data) return [];
    return [
      ...data.Artwork.map((x) => ({ collection: "Artwork", label: "Artwork", id: x.id, title: x.title, owner: x.user_display_name || x.created_by, date: x.created_date, image: x.image_url, link: `/Gallery?art=${x.id}` })),
      ...data.CommunityPost.map((x) => ({ collection: "CommunityPost", label: "Post", id: x.id, title: x.title || x.description, owner: x.user_display_name, date: x.created_date, image: x.image_url, link: `/Community?post=${x.id}` })),
      ...data.MusicReview.map((x) => ({ collection: "MusicReview", label: "Track", id: x.id, title: x.title, owner: x.user_display_name, date: x.created_date, link: `/Music?track=${x.id}` })),
      ...data.Comment.map((x) => ({ collection: "Comment", label: "Comment", id: x.id, title: x.content, owner: x.user_display_name || x.user_full_name, date: x.created_date })),
      ...data.CommunityComment.map((x) => ({ collection: "CommunityComment", label: "Comment", id: x.id, title: x.content, owner: x.user_display_name, date: x.created_date })),
      ...data.ChannelMessage.filter((x) => x.type !== "join").map((x) => ({ collection: "ChannelMessage", label: "Message", id: x.id, title: x.content || "📷 Image", owner: x.user_display_name, date: x.created_date, image: x.image_url })),
      ...data.Commission.map((x) => ({ collection: "Commission", label: "Commission", id: x.id, title: x.title, owner: x.artist_display_name, date: x.created_date })),
    ].sort((a, b) => new Date(b.date) - new Date(a.date));
  }, [data]);

  if (!isAdmin) return <Page><EmptyState icon={Shield} title="Admins only" text="This panel is locked to site admins." action={<Link to="/" className="btn">Go home</Link>} /></Page>;
  if (!data) return <CenterSpinner />;

  const remove = async (collection, id, label) => {
    if (!(await confirm({ title: `Delete this ${label.toLowerCase()}?`, confirmLabel: "Delete", danger: true }))) return;
    try {
      await base44.entities[collection].delete(id);
      base44.entities.Log.create({ action: "moderation_delete", details: `Deleted ${label.toLowerCase()} ${id}`, user_email: me.email }).catch(() => {});
      toast.success(`${label} deleted`);
      load();
    } catch (e) { toast.error(e?.message || "Could not delete."); }
  };
  const setRole = async (u, role) => {
    if (u.email === me.email) { toast.error("You can't change your own role"); return; }
    if (!(await confirm({ title: role === "admin" ? `Make ${displayName(u)} an admin?` : `Remove admin from ${displayName(u)}?`, message: role === "admin" ? "Admins can moderate all content and change site settings." : undefined, confirmLabel: "Confirm", danger: role !== "admin" }))) return;
    try {
      await base44.entities.User.update(u.id, { role });
      base44.entities.Log.create({ action: "role_change", details: `${u.email} → ${role}`, user_email: me.email }).catch(() => {});
      toast.success("Role updated");
      load();
    } catch (e) { toast.error(e?.message || "Could not change role."); }
  };

  const q = search.trim().toLowerCase();
  const users = data.User.filter((u) => !q || [u.display_name, u.email].some((f) => String(f || "").toLowerCase().includes(q)));
  const contentFiltered = content.filter((c) => (contentType === "all" || c.label === contentType) && (!q || [c.title, c.owner].some((f) => String(f || "").toLowerCase().includes(q))));
  const weekAgo = Date.now() - 7 * 86400000;
  const newThisWeek = (list) => list.filter((x) => new Date(x.created_date).getTime() > weekAgo).length;

  return (
    <Page width="max-w-6xl">
      <PageHeader eyebrow="Mission control" title="Admin panel" subtitle="Moderate content, manage people and tune the site." icon={Shield} actions={<Link to="/Logs" className="btn-outline">Activity logs</Link>}>
        <Segmented options={[{ id: "overview", label: "Overview", icon: BarChart3 }, { id: "users", label: "Users", icon: Users, count: data.User.length }, { id: "content", label: "Content", icon: ImageIcon }, { id: "servers", label: "Servers", icon: Server }, { id: "reports", label: "Reports", icon: Flag, count: data.Report.filter((r) => r.status !== "resolved").length }, { id: "settings", label: "Site", icon: SettingsIcon }]} value={tab} onChange={(t) => { setTab(t); setSearch(""); }} size="sm" />
      </PageHeader>

      {tab === "overview" && (
        <div className="space-y-6">
          <div className="grid grid-cols-2 lg:grid-cols-4 gap-4">
            <StatCard icon={Users} label="Members" value={data.User.length} sub={`${data.User.filter(isOnline).length} online`} delay={0} />
            <StatCard icon={ImageIcon} label="Posts & artworks" value={data.CommunityPost.length + data.Artwork.length} sub={`+${newThisWeek([...data.CommunityPost, ...data.Artwork])} this week`} delay={0.05} />
            <StatCard icon={MessageSquare} label="Messages & comments" value={data.ChannelMessage.length + data.Comment.length + data.CommunityComment.length} sub={`+${newThisWeek([...data.ChannelMessage, ...data.Comment, ...data.CommunityComment])} this week`} delay={0.1} />
            <StatCard icon={Music} label="Tracks & servers" value={data.MusicReview.length + data.Community.length} delay={0.15} />
          </div>
          <ActivityChart data={[...data.CommunityPost, ...data.Artwork, ...data.Comment, ...data.CommunityComment, ...data.ChannelMessage]} />
          <div className="card p-5">
            <h2 className="font-display text-lg font-semibold mb-3" style={{ color: "var(--text-primary)" }}>Latest content</h2>
            <div className="divide-y" style={{ borderColor: "var(--border-c)" }}>
              {content.slice(0, 8).map((c) => (
                <div key={c.collection + c.id} className="flex items-center gap-3 py-2.5">
                  <span className="badge-pink w-24 justify-center">{c.label}</span>
                  <span className="flex-1 min-w-0 text-sm truncate" style={{ color: "var(--text-primary)" }}>{c.title}</span>
                  <span className="text-xs hidden sm:block" style={{ color: "var(--text-muted)" }}>{c.owner} · {timeAgo(c.date)}</span>
                </div>
              ))}
            </div>
          </div>
        </div>
      )}

      {tab === "users" && (
        <div className="space-y-4">
          <SearchInput value={search} onChange={setSearch} placeholder="Search users…" className="max-w-sm" />
          <div className="card overflow-hidden">
            {users.map((u, i) => (
              <motion.div key={u.id} initial={{ opacity: 0 }} animate={{ opacity: 1 }} transition={{ delay: Math.min(i, 15) * 0.02 }} className="flex items-center gap-3 p-4 border-b last:border-0" style={{ borderColor: "var(--border-c)" }}>
                <Link to={profileLink(u.email)}><Avatar src={u.profile_picture} name={displayName(u)} size={40} online={isOnline(u)} /></Link>
                <div className="flex-1 min-w-0">
                  <p className="text-sm font-bold truncate" style={{ color: "var(--text-primary)" }}>{displayName(u)}</p>
                  <p className="text-xs truncate" style={{ color: "var(--text-muted)" }}>{u.email} · joined {timeAgo(u.created_date)}</p>
                </div>
                <span className="badge-pink hidden sm:inline-flex" style={u.role === "admin" ? undefined : { color: "var(--text-muted)", background: "var(--surface-2)", borderColor: "var(--border-c)" }}>{u.role || "user"}</span>
                {u.email !== me.email && (u.role === "admin"
                  ? <button onClick={() => setRole(u, "user")} className="btn-ghost text-xs" title="Remove admin"><ShieldOff className="w-4 h-4" /><span className="hidden md:inline">Remove admin</span></button>
                  : <button onClick={() => setRole(u, "admin")} className="btn-ghost text-xs" title="Make admin"><ShieldCheck className="w-4 h-4" /><span className="hidden md:inline">Make admin</span></button>)}
              </motion.div>
            ))}
          </div>
        </div>
      )}

      {tab === "content" && (
        <div className="space-y-4">
          <div className="flex flex-col md:flex-row gap-3 md:items-center">
            <ChipRow options={["all", "Artwork", "Post", "Track", "Comment", "Message", "Commission"].map((x) => ({ id: x, label: x === "all" ? "All" : x }))} value={contentType} onChange={setContentType} className="flex-1" />
            <SearchInput value={search} onChange={setSearch} placeholder="Search content…" className="md:w-64" />
          </div>
          {contentFiltered.length === 0 ? <EmptyState icon={ImageIcon} title="Nothing to moderate" /> : (
            <div className="card overflow-hidden">
              {contentFiltered.slice(0, 200).map((c) => (
                <div key={c.collection + c.id} className="flex items-center gap-3 p-3.5 border-b last:border-0" style={{ borderColor: "var(--border-c)" }}>
                  {c.image ? <img src={c.image} alt="" className="w-11 h-11 rounded-xl object-cover flex-shrink-0" /> : <span className="w-11 h-11 rounded-xl flex-shrink-0" style={{ background: "var(--surface-2)" }} />}
                  <div className="flex-1 min-w-0">
                    <p className="text-sm font-semibold truncate" style={{ color: "var(--text-primary)" }}>{c.title || "Untitled"}</p>
                    <p className="text-xs truncate" style={{ color: "var(--text-muted)" }}>{c.label} · {c.owner} · {timeAgo(c.date)}</p>
                  </div>
                  {c.link && <Link to={c.link} className="btn-ghost text-xs hidden sm:inline-flex">View</Link>}
                  <button className="icon-btn" onClick={() => remove(c.collection, c.id, c.label)} aria-label={`Delete ${c.label}`}><Trash2 className="w-4 h-4" style={{ color: "var(--danger)" }} /></button>
                </div>
              ))}
            </div>
          )}
        </div>
      )}

      {tab === "servers" && (
        <div className="grid md:grid-cols-2 gap-4">
          {data.Community.map((c) => (
            <div key={c.id} className="card p-4">
              <div className="flex items-center gap-3">
                <span className="w-12 h-12 rounded-2xl flex items-center justify-center text-2xl overflow-hidden flex-shrink-0" style={{ background: "var(--pink-soft)" }}>{c.icon_url ? <img src={c.icon_url} alt="" className="w-full h-full object-cover" /> : c.icon_emoji || "💬"}</span>
                <div className="flex-1 min-w-0">
                  <Link to={`/CommunityChat?id=${c.id}`} className="text-sm font-bold truncate block hover:underline" style={{ color: "var(--text-primary)" }}>{c.name}</Link>
                  <p className="text-xs truncate" style={{ color: "var(--text-muted)" }}>{c.member_emails?.length || 0} members · owner {c.owner_display_name || c.owner_email}</p>
                </div>
                <button className="icon-btn" onClick={() => remove("Community", c.id, "Server")} aria-label={`Delete ${c.name}`}><Trash2 className="w-4 h-4" style={{ color: "var(--danger)" }} /></button>
              </div>
              <div className="mt-3 flex flex-wrap gap-1.5">{data.ServerChannel.filter((ch) => ch.community_id === c.id).map((ch) => <span key={ch.id} className="text-[11px] px-2 py-1 rounded-full" style={{ background: "var(--surface-2)", color: "var(--text-secondary)" }}>{ch.type === "voice" ? "🔊" : "#"} {ch.name}</span>)}</div>
            </div>
          ))}
        </div>
      )}

      {tab === "reports" && (
        <div className="space-y-3">
          {data.Report.length === 0 && <EmptyState icon={Flag} title="No reports" text="When people report posts or accounts, they show up here." />}
          {[...data.Report].sort((a, b) => Number(a.status === "resolved") - Number(b.status === "resolved") || new Date(b.created_date) - new Date(a.created_date)).map((r) => {
            const collection = REPORT_TARGET[r.target_type];
            const resolved = r.status === "resolved";
            return (
              <div key={r.id} className="card-sm p-4 flex flex-col sm:flex-row sm:items-center gap-3" style={{ opacity: resolved ? 0.55 : 1 }}>
                <div className="flex-1 min-w-0">
                  <div className="flex flex-wrap items-center gap-2 mb-1">
                    <span className="badge-pink" style={{ color: "var(--danger)" }}><Flag className="w-3 h-3" /> {r.reason}</span>
                    <span className="text-[11px] font-bold uppercase tracking-wider" style={{ color: "var(--text-muted)" }}>{r.target_type}</span>
                    {resolved && <span className="text-[11px] font-bold" style={{ color: "var(--success)" }}>✓ {r.resolution || "Resolved"}</span>}
                  </div>
                  {r.target_preview && <p className="text-sm line-clamp-2" style={{ color: "var(--text-primary)" }}>“{r.target_preview}”</p>}
                  {r.details && <p className="text-xs mt-1 italic" style={{ color: "var(--text-secondary)" }}>{r.details}</p>}
                  <p className="text-[11px] mt-1" style={{ color: "var(--text-muted)" }}>Reported by {r.reporter_name || r.reporter_email} · {new Date(r.created_date).toLocaleString()}{r.target_owner_email ? ` · owner ${r.target_owner_email}` : ""}</p>
                </div>
                <div className="flex gap-1.5 flex-shrink-0">
                  {r.link && <Link to={r.link} className="btn-outline text-xs !py-1.5"><ExternalLink className="w-3.5 h-3.5" /> Open</Link>}
                  {!resolved && collection && (
                    <button className="btn-outline text-xs !py-1.5" style={{ color: "var(--danger)" }} onClick={async () => {
                      if (!(await confirm({ title: `Remove this ${r.target_type}?`, confirmLabel: "Remove", danger: true }))) return;
                      await base44.entities[collection].delete(r.target_id).catch(() => {});
                      await base44.entities.Report.update(r.id, { status: "resolved", resolution: "Content removed", resolved_by: me.email });
                      base44.entities.Log.create({ action: "moderation_delete", details: `Removed reported ${r.target_type} ${r.target_id}`, user_email: me.email }).catch(() => {});
                      toast.success("Content removed"); load();
                    }}><Trash2 className="w-3.5 h-3.5" /> Remove</button>
                  )}
                  {!resolved && <button className="btn-outline text-xs !py-1.5" onClick={async () => { await base44.entities.Report.update(r.id, { status: "resolved", resolution: "Dismissed", resolved_by: me.email }).catch((e) => toast.error(e?.message)); load(); }}><Check className="w-3.5 h-3.5" /> Dismiss</button>}
                </div>
              </div>
            );
          })}
        </div>
      )}

      {tab === "settings" && <div className="max-w-2xl"><AdminSiteSettings /></div>}
    </Page>
  );
}
