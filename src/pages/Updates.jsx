import React, { useEffect, useState } from "react";
import { Loader2, Megaphone, Send, Trash2 } from "lucide-react";
import { base44 } from "@/api/base44Client";
import { useAuth } from "@/lib/AuthContext";
import { useUpdates, markUpdatesSeen } from "@/lib/updates";
import { toast } from "@/lib/toast";
import { displayName } from "@/lib/format";
import { Page, PageHeader } from "@/components/common/Page";
import { useConfirm } from "@/components/common/Modal";

const fmt = (iso) => new Date(iso).toLocaleDateString(undefined, { day: "numeric", month: "long", year: "numeric" });
const EMOJIS = ["📣", "✨", "🎉", "🛠️", "🎨", "🎬", "💖", "🚀"];

function Composer() {
  const { user } = useAuth();
  const [title, setTitle] = useState("");
  const [body, setBody] = useState("");
  const [emoji, setEmoji] = useState("📣");
  const [busy, setBusy] = useState(false);
  const post = async (e) => {
    e.preventDefault();
    if (!title.trim() || busy) return;
    setBusy(true);
    try {
      await base44.entities.AppUpdate.create({ title: title.trim(), body: body.trim(), emoji, author_name: displayName(user) });
      setTitle(""); setBody("");
      toast.success("Update posted", { description: "Everyone sees it in What's new." });
    } catch (err) { toast.error(err?.message || "Could not post the update."); }
    setBusy(false);
  };
  return (
    <form onSubmit={post} className="card p-5 space-y-3 mb-8">
      <p className="eyebrow">Post an update (admins)</p>
      <div className="flex gap-2 flex-wrap">
        {EMOJIS.map((e) => <button key={e} type="button" onClick={() => setEmoji(e)} className="w-10 h-10 rounded-xl text-xl" style={{ background: emoji === e ? "var(--pink-soft)" : "var(--surface-2)", boxShadow: emoji === e ? "0 0 0 2px rgb(var(--accent-rgb) / 0.5)" : "none" }} aria-pressed={emoji === e}>{e}</button>)}
      </div>
      <input className="input" placeholder="Title — e.g. New stickers in Reels" value={title} onChange={(e) => setTitle(e.target.value)} maxLength={80} aria-label="Update title" />
      <textarea className="input resize-none" rows={3} placeholder="What changed? One line per point works nicely." value={body} onChange={(e) => setBody(e.target.value)} maxLength={1500} aria-label="Update details" />
      <div className="flex justify-end"><button className="btn" disabled={busy || !title.trim()}>{busy ? <Loader2 className="w-4 h-4 animate-spin" /> : <Send className="w-4 h-4" />} Post update</button></div>
    </form>
  );
}

export default function UpdatesPage() {
  const { isAdmin } = useAuth();
  const confirm = useConfirm();
  const { updates, loading } = useUpdates();
  useEffect(() => { if (!loading) markUpdatesSeen(); }, [loading, updates.length]);

  const remove = async (u) => {
    if (!(await confirm({ title: "Delete this update?", confirmLabel: "Delete", danger: true }))) return;
    try { await base44.entities.AppUpdate.delete(u.id); toast.success("Update deleted"); } catch (e) { toast.error(e?.message || "Could not delete."); }
  };

  return (
    <Page width="max-w-2xl">
      <PageHeader eyebrow="App updates" title="What's new" subtitle="Everything new in Sugerly, newest first." icon={Megaphone} />
      {isAdmin && <Composer />}
      <ol className="relative space-y-6 before:content-[''] before:absolute before:left-[1.35rem] before:top-2 before:bottom-2 before:w-0.5 before:rounded-full before:bg-[var(--border-c)]">
        {updates.map((u, i) => (
          <li key={u.id} className="relative flex gap-4 enter" style={{ "--d": `${Math.min(i, 8) * 50}ms` }}>
            <span className="relative z-10 w-11 h-11 rounded-2xl flex items-center justify-center text-xl flex-shrink-0" style={{ background: i === 0 ? "var(--accent-grad)" : "var(--surface)", border: "1px solid var(--border-c)", boxShadow: i === 0 ? "var(--shadow-accent)" : "var(--shadow-sm)" }}>{u.emoji}</span>
            <div className="card-sm p-4 sm:p-5 flex-1 min-w-0">
              <div className="flex items-center gap-2 flex-wrap mb-1">
                {u.version && <span className="badge-pink">v{u.version}</span>}
                {u.custom && <span className="badge-pink" style={{ color: "var(--text-secondary)", background: "var(--surface-2)", borderColor: "var(--border-c)" }}>From the team</span>}
                <span className="text-xs" style={{ color: "var(--text-muted)" }}>{fmt(u.date)}</span>
                {u.custom && isAdmin && <button onClick={() => remove(u)} className="ml-auto icon-btn w-8 h-8" aria-label="Delete update"><Trash2 className="w-4 h-4" style={{ color: "var(--danger)" }} /></button>}
              </div>
              <h2 className="font-display text-xl mb-2" style={{ color: "var(--text-primary)" }}>{u.title}</h2>
              {u.items && <ul className="space-y-1.5">{u.items.map((it, k) => <li key={k} className="text-sm leading-relaxed flex gap-2" style={{ color: "var(--text-secondary)" }}><span style={{ color: "var(--accent-rose)" }}>•</span><span>{it}</span></li>)}</ul>}
              {u.body && <p className="text-sm leading-relaxed whitespace-pre-line" style={{ color: "var(--text-secondary)" }}>{u.body}</p>}
              {u.author && <p className="text-xs mt-2" style={{ color: "var(--text-muted)" }}>— {u.author}</p>}
            </div>
          </li>
        ))}
      </ol>
    </Page>
  );
}
