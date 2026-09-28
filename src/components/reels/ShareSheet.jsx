import React, { useMemo, useState } from "react";
import { Check, Link2, Loader2, Send, Share2 } from "lucide-react";
import { base44 } from "@/api/base44Client";
import { useLiveQuery } from "@/lib/useLiveQuery";
import { dmConversationId } from "@/lib/social";
import { displayName, siteUrl } from "@/lib/format";
import { toast } from "@/lib/toast";
import { checkText } from "@/lib/moderation";
import { feedback } from "@/lib/feedback";
import Avatar from "@/components/common/Avatar";
import BottomSheet from "@/components/common/BottomSheet";

// TikTok-style share: tap friends and group chats to send the reel straight
// into the chat, or copy the link / use the phone's share menu.
export default function ShareSheet({ reel, anchorRef, me, friendEmails = [], usersByEmail = {}, onClose, onShared }) {
  const [picked, setPicked] = useState([]);
  const [note, setNote] = useState("");
  const [sending, setSending] = useState(false);
  const { data: groups } = useLiveQuery("GroupChat", me ? { member_emails: { $contains: me.email } } : null, { sort: "-created_date", limit: 20 });
  const { data: recent } = useLiveQuery("DirectMessage", me ? { member_emails: { $contains: me.email } } : null, { sort: "-created_date", limit: 80, live: false });

  // Recent chats first, then the rest of your friends.
  const targets = useMemo(() => {
    const seen = new Set();
    const out = [];
    const addPerson = (email) => {
      const key = `u:${email}`;
      if (!email || email === me?.email || seen.has(key)) return;
      seen.add(key);
      const u = usersByEmail[email];
      out.push({ key, kind: "dm", email, name: u ? displayName(u) : email.split("@")[0], picture: u?.profile_picture || "" });
    };
    const addGroup = (g) => {
      const key = `g:${g.id}`;
      if (seen.has(key)) return;
      seen.add(key);
      out.push({ key, kind: "group", group: g, name: g.name, picture: g.image_url || "" });
    };
    recent.forEach((m) => {
      if (m.conversation_type === "group") { const g = groups.find((x) => x.id === m.conversation_id); if (g) addGroup(g); } else (m.member_emails || []).forEach(addPerson);
    });
    friendEmails.forEach(addPerson);
    groups.forEach(addGroup);
    return out;
  }, [recent, groups, friendEmails, usersByEmail, me?.email]);

  if (!reel) return null;
  const url = siteUrl(`/Reels?r=${reel.id}`);
  const toggle = (key) => { feedback("tap"); setPicked((p) => (p.includes(key) ? p.filter((k) => k !== key) : [...p, key])); };

  const send = async () => {
    if (!picked.length || sending) return;
    const mod = await checkText(note, { user: me, where: "direct message", kind: "message" });
    if (!mod.safe) { toast.error(mod.reason); return; }
    setSending(true);
    try {
      const base = {
        content: [note.trim(), `🎬 ${reel.user_display_name}'s reel: ${url}`].filter(Boolean).join("\n"),
        image_url: "",
        shared_reel: { id: reel.id, cover_url: reel.cover_url || (reel.kind === "photo" ? reel.media_url : ""), caption: String(reel.caption || "").slice(0, 120), by: reel.user_display_name || "" },
        user_email: me.email, user_display_name: displayName(me), user_profile_picture: me.profile_picture || "",
        read_by: [me.email], reactions: {}, is_edited: false,
      };
      await Promise.all(targets.filter((t) => picked.includes(t.key)).map((t) => base44.entities.DirectMessage.create(t.kind === "group"
        ? { ...base, conversation_id: t.group.id, conversation_type: "group", group_name: t.group.name, member_emails: [...new Set(t.group.member_emails || [])].sort() }
        : { ...base, conversation_id: dmConversationId(me.email, t.email), conversation_type: "dm", group_name: "", member_emails: [me.email, t.email].sort() })));
      feedback("send");
      toast.success(picked.length === 1 ? `Sent to ${targets.find((t) => t.key === picked[0])?.name}` : `Sent to ${picked.length} chats`);
      onShared?.();
      onClose();
    } catch (e) {
      toast.error(e?.message || "Could not send.");
      setSending(false);
    }
  };
  const copy = async () => {
    try { await navigator.clipboard.writeText(url); toast.success("Link copied"); } catch { toast(url); }
    feedback("tap");
    onShared?.();
  };
  const native = async () => {
    try { await navigator.share({ title: `${reel.user_display_name} on Sugerly`, text: reel.caption || "", url }); onShared?.(); } catch { /* cancelled */ }
  };

  return (
    <BottomSheet anchorRef={anchorRef} open={!!reel} onClose={onClose} title="Send to" height="auto" label="Share reel">
      {targets.length ? (
        <div className="grid grid-cols-4 gap-x-2 gap-y-4 pt-1 max-h-[45dvh] overflow-y-auto no-scrollbar">
          {targets.map((t, i) => {
            const on = picked.includes(t.key);
            return (
              <button key={t.key} onClick={() => toggle(t.key)} className="rise-in flex flex-col items-center gap-1.5 min-w-0 active:scale-95 transition-transform" style={{ "--d": `${Math.min(i, 12) * 25}ms` }} aria-pressed={on} aria-label={`Send to ${t.name}`}>
                <span className="relative">
                  <Avatar src={t.picture} name={t.name} size={56} />
                  <span className="absolute -right-0.5 -bottom-0.5 w-5 h-5 rounded-full flex items-center justify-center transition-all duration-200" style={{ background: on ? "#ff4d7d" : "transparent", border: on ? "2px solid var(--surface)" : "none", transform: `scale(${on ? 1 : 0})` }}><Check className="w-3 h-3 text-white" strokeWidth={3} /></span>
                </span>
                <span className="text-[11px] font-semibold leading-tight text-center line-clamp-2 w-full">{t.name}</span>
              </button>
            );
          })}
        </div>
      ) : (
        <p className="text-sm text-center py-4" style={{ color: "var(--text-muted)" }}>Add friends to send reels to them.</p>
      )}

      <div className="overflow-hidden transition-all duration-300" style={{ maxHeight: picked.length ? 120 : 0, opacity: picked.length ? 1 : 0 }}>
        <div className="flex gap-2 pt-4">
          <input value={note} onChange={(e) => setNote(e.target.value)} maxLength={300} placeholder="Add a message…" className="input flex-1 !text-[16px]" aria-label="Message" onKeyDown={(e) => { if (e.key === "Enter") send(); }} />
          <button onClick={send} disabled={sending} className="btn !px-5">{sending ? <Loader2 className="w-4 h-4 animate-spin" /> : <Send className="w-4 h-4" />} Send{picked.length > 1 ? ` (${picked.length})` : ""}</button>
        </div>
      </div>

      <div className="flex gap-5 pt-5 mt-4" style={{ borderTop: "1px solid var(--border-c)" }}>
        <button onClick={copy} className="flex flex-col items-center gap-1.5 text-[11px] font-semibold active:scale-95 transition-transform">
          <span className="w-12 h-12 rounded-full flex items-center justify-center" style={{ background: "var(--surface-2)" }}><Link2 className="w-5 h-5" /></span>Copy link
        </button>
        {typeof navigator !== "undefined" && navigator.share && (
          <button onClick={native} className="flex flex-col items-center gap-1.5 text-[11px] font-semibold active:scale-95 transition-transform">
            <span className="w-12 h-12 rounded-full flex items-center justify-center" style={{ background: "var(--surface-2)" }}><Share2 className="w-5 h-5" /></span>More
          </button>
        )}
      </div>
    </BottomSheet>
  );
}
