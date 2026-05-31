import React, { useEffect, useMemo, useState } from "react";
import { base44 } from "@/api/base44Client";
import AdminSiteSettings from "../components/admin/AdminSiteSettings";
import { BarChart3, Loader2, Shield, Trash2, Users, Image as ImageIcon, MessageSquare, Server, Settings as SettingsIcon } from "lucide-react";

const collections = ["User", "Artwork", "CommunityPost", "Comment", "CommunityComment", "ChannelMessage", "Community", "ServerChannel", "Friendship", "MusicReview"];

function Stat({ icon: Icon, label, value }) {
  return <div className="card p-4 flex items-center gap-3"><div className="w-10 h-10 rounded-2xl flex items-center justify-center" style={{ background: "var(--pink-soft)", color: "var(--accent-rose)" }}><Icon className="w-5 h-5" /></div><div><p className="text-xs" style={{ color: "var(--text-muted)" }}>{label}</p><p className="text-lg font-semibold" style={{ color: "var(--text-primary)" }}>{value}</p></div></div>;
}

export default function AdminPanel() {
  const [me, setMe] = useState(null);
  const [loading, setLoading] = useState(true);
  const [data, setData] = useState({});
  const [tab, setTab] = useState("overview");

  const load = async () => {
    setLoading(true);
    const current = await base44.auth.me().catch(() => null);
    setMe(current);
    if (current?.role !== "admin") { setLoading(false); return; }
    const entries = await Promise.all(collections.map(async name => [name, await base44.entities[name].list("-created_date").catch(() => [])]));
    setData(Object.fromEntries(entries));
    setLoading(false);
  };
  useEffect(() => { load(); }, []);

  const feed = useMemo(() => {
    return [
      ...(data.Artwork || []).map(x => ({ type: "Artwork", text: x.title, by: x.user_display_name || x.created_by, date: x.created_date })),
      ...(data.CommunityPost || []).map(x => ({ type: "Feed post", text: x.title || x.description, by: x.user_display_name || x.created_by, date: x.created_date })),
      ...(data.ChannelMessage || []).map(x => ({ type: "Message", text: x.content || "Image message", by: x.user_display_name || x.created_by, date: x.created_date })),
      ...(data.Comment || []).map(x => ({ type: "Comment", text: x.content, by: x.user_display_name || x.created_by, date: x.created_date })),
    ].sort((a,b) => new Date(b.date) - new Date(a.date)).slice(0, 30);
  }, [data]);

  const remove = async (name, id) => {
    if (!confirm(`Delete this ${name}?`)) return;
    await base44.entities[name].delete(id);
    load();
  };

  if (loading) return <div className="h-full flex items-center justify-center"><Loader2 className="w-5 h-5 animate-spin" style={{ color: "var(--accent-pink)" }} /></div>;
  if (me?.role !== "admin") return <div className="h-full flex items-center justify-center p-6 text-center"><div className="card p-6 max-w-sm"><Shield className="w-10 h-10 mx-auto mb-3" style={{ color: "var(--accent-rose)" }} /><h1 className="font-semibold mb-1" style={{ color: "var(--text-primary)" }}>Admin only</h1><p className="text-sm" style={{ color: "var(--text-muted)" }}>This panel is locked to site admins.</p></div></div>;

  return (
    <div className="h-full overflow-y-auto scroll px-4 sm:px-6 py-6 max-w-6xl mx-auto w-full">
      <div className="flex items-center gap-3 mb-5">
        <div className="w-12 h-12 rounded-2xl flex items-center justify-center text-white" style={{ background: "linear-gradient(135deg,var(--accent-pink),var(--accent-rose))" }}><Shield className="w-6 h-6" /></div>
        <div><h1 className="text-lg font-bold" style={{ color: "var(--text-primary)" }}>Admin Panel</h1><p className="text-xs" style={{ color: "var(--text-muted)" }}>Manage users, feed content, servers, settings and moderation.</p></div>
      </div>

      <div className="flex gap-2 mb-5 overflow-x-auto pb-1">
        {[{id:"overview",label:"Overview",icon:BarChart3},{id:"users",label:"Users",icon:Users},{id:"content",label:"Content",icon:ImageIcon},{id:"servers",label:"Servers",icon:Server},{id:"settings",label:"Site Settings",icon:SettingsIcon}].map(t => <button key={t.id} onClick={() => setTab(t.id)} className="px-3 py-2 rounded-full text-xs font-semibold flex items-center gap-1.5 whitespace-nowrap" style={tab===t.id?{background:"var(--accent-pink)",color:"white"}:{background:"var(--pink-soft)",color:"var(--text-secondary)"}}><t.icon className="w-3.5 h-3.5" />{t.label}</button>)}
      </div>

      {tab === "overview" && <>
        <div className="grid grid-cols-2 lg:grid-cols-4 gap-3 mb-5">
          <Stat icon={Users} label="Users" value={(data.User || []).length} />
          <Stat icon={ImageIcon} label="Artworks" value={(data.Artwork || []).length} />
          <Stat icon={MessageSquare} label="Messages" value={(data.ChannelMessage || []).length} />
          <Stat icon={Server} label="Servers" value={(data.Community || []).length} />
        </div>
        <div className="card p-4"><h2 className="text-sm font-semibold mb-3" style={{ color: "var(--text-primary)" }}>Real Feed Activity</h2><div className="space-y-2">{feed.map((item, i) => <div key={i} className="flex items-start gap-3 rounded-xl p-3" style={{ background: "var(--pink-soft)" }}><span className="text-[10px] font-bold px-2 py-1 rounded-full" style={{ background: "var(--surface)", color: "var(--accent-rose)" }}>{item.type}</span><div className="min-w-0 flex-1"><p className="text-sm truncate" style={{ color: "var(--text-primary)" }}>{item.text}</p><p className="text-[11px]" style={{ color: "var(--text-muted)" }}>by {item.by} • {new Date(item.date).toLocaleString()}</p></div></div>)}</div></div>
      </>}

      {tab === "users" && <div className="card overflow-hidden"><div className="p-4 border-b" style={{ borderColor: "var(--border-c)" }}><h2 className="text-sm font-semibold" style={{ color: "var(--text-primary)" }}>Users</h2></div>{(data.User || []).map(u => <div key={u.id} className="p-4 border-b flex items-center gap-3" style={{ borderColor: "var(--border-c)" }}><img src={u.profile_picture} className="w-9 h-9 rounded-full object-cover" alt=""/><div className="flex-1 min-w-0"><p className="text-sm font-semibold truncate" style={{ color: "var(--text-primary)" }}>{u.display_name || u.full_name}</p><p className="text-xs truncate" style={{ color: "var(--text-muted)" }}>{u.email}</p></div><span className="text-[10px] px-2 py-1 rounded-full" style={{ background: "var(--pink-soft)", color: "var(--accent-rose)" }}>{u.role}</span></div>)}</div>}

      {tab === "content" && <ContentTable data={data} remove={remove} />}
      {tab === "servers" && <ServerTable communities={data.Community || []} channels={data.ServerChannel || []} remove={remove} />}
      {tab === "settings" && <AdminSiteSettings />}
    </div>
  );
}

function ContentTable({ data, remove }) {
  const items = [
    ...(data.Artwork || []).map(x => ({ collection: "Artwork", id: x.id, title: x.title, owner: x.user_email, date: x.created_date })),
    ...(data.CommunityPost || []).map(x => ({ collection: "CommunityPost", id: x.id, title: x.title || x.description, owner: x.user_email, date: x.created_date })),
    ...(data.MusicReview || []).map(x => ({ collection: "MusicReview", id: x.id, title: x.title, owner: x.user_email, date: x.created_date })),
    ...(data.Comment || []).map(x => ({ collection: "Comment", id: x.id, title: x.content, owner: x.user_email, date: x.created_date })),
    ...(data.CommunityComment || []).map(x => ({ collection: "CommunityComment", id: x.id, title: x.content, owner: x.user_email, date: x.created_date })),
  ].sort((a,b) => new Date(b.date) - new Date(a.date));
  return <div className="card overflow-hidden"><div className="p-4 border-b" style={{ borderColor: "var(--border-c)" }}><h2 className="text-sm font-semibold" style={{ color: "var(--text-primary)" }}>Content moderation</h2></div>{items.map(x => <div key={x.collection + x.id} className="p-4 border-b flex items-center gap-3" style={{ borderColor: "var(--border-c)" }}><div className="flex-1 min-w-0"><p className="text-sm font-semibold truncate" style={{ color: "var(--text-primary)" }}>{x.title || "Untitled"}</p><p className="text-xs truncate" style={{ color: "var(--text-muted)" }}>{x.collection} • {x.owner}</p></div><button className="btn-outline text-xs text-red-500" onClick={() => remove(x.collection, x.id)}><Trash2 className="w-3.5 h-3.5" /> Delete</button></div>)}</div>;
}

function ServerTable({ communities, channels, remove }) {
  return <div className="space-y-3">{communities.map(c => <div key={c.id} className="card p-4"><div className="flex items-center gap-3"><div className="w-10 h-10 rounded-xl flex items-center justify-center" style={{ background: "var(--pink-soft)" }}>{c.icon_url ? <img src={c.icon_url} className="w-full h-full object-cover rounded-xl" alt="" /> : c.icon_emoji || "💬"}</div><div className="flex-1 min-w-0"><p className="text-sm font-semibold" style={{ color: "var(--text-primary)" }}>{c.name}</p><p className="text-xs" style={{ color: "var(--text-muted)" }}>{c.member_emails?.length || 0} members • owner {c.owner_email}</p></div><button className="btn-outline text-xs text-red-500" onClick={() => remove("Community", c.id)}><Trash2 className="w-3.5 h-3.5" /> Delete</button></div><div className="mt-3 flex flex-wrap gap-2">{channels.filter(ch => ch.community_id === c.id).map(ch => <span key={ch.id} className="text-[11px] px-2 py-1 rounded-full" style={{ background: "var(--pink-soft)", color: "var(--text-secondary)" }}>{ch.type === "voice" ? "🔊" : "#"} {ch.name}</span>)}</div></div>)}</div>;
}
