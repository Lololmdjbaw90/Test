import React, { useEffect, useMemo, useRef, useState } from "react";
import { Send, Loader2, Trash2, Pencil, Check, X } from "lucide-react";
import { base44 } from "@/api/base44Client";

const nowISO = () => new Date().toISOString();

function Avatar({ user, name, size = 32 }) {
  const label = name || user?.display_name || user?.full_name || user?.email || "?";
  if (user?.profile_picture) return <img src={user.profile_picture} alt="" style={{ width: size, height: size }} className="rounded-full object-cover flex-shrink-0" />;
  return <div style={{ width: size, height: size, background: "var(--accent-pink)" }} className="rounded-full flex items-center justify-center text-white text-xs font-semibold flex-shrink-0">{label[0]?.toUpperCase() || "?"}</div>;
}

export default function DMChatWindow({ conversationId, me, otherUser, isGroup, groupName, groupMemberEmails = [] }) {
  const [messages, setMessages] = useState([]);
  const [text, setText] = useState("");
  const [loading, setLoading] = useState(true);
  const [sending, setSending] = useState(false);
  const [editing, setEditing] = useState(null);
  const [error, setError] = useState("");
  const bottomRef = useRef(null);

  const members = useMemo(() => {
    if (isGroup) return [];
    return [me?.email, otherUser?.email].filter(Boolean).sort();
  }, [isGroup, me?.email, otherUser?.email]);

  const load = async () => {
    if (!conversationId || !me) return;
    setLoading(true);
    setError("");
    try {
      const data = await base44.entities.DirectMessage.filter({ conversation_id: conversationId }, null, 200);
      setMessages(data.sort((a, b) => new Date(a.created_date) - new Date(b.created_date)));
    } catch (e) {
      setError(e?.message || "Could not load messages.");
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => { load(); }, [conversationId, me?.email]);
  useEffect(() => { bottomRef.current?.scrollIntoView({ behavior: "smooth" }); }, [messages.length]);

  useEffect(() => {
    if (!conversationId || !base44.entities.DirectMessage?.subscribe) return;
    const unsub = base44.entities.DirectMessage.subscribe((event) => {
      const rows = Array.isArray(event?.data) ? event.data : [];
      setMessages(rows.filter(m => m.conversation_id === conversationId).sort((a, b) => new Date(a.created_date) - new Date(b.created_date)));
    }, { conversation_id: conversationId }, null, 200);
    return () => unsub?.();
  }, [conversationId]);

  const send = async (e) => {
    e?.preventDefault();
    const clean = text.trim();
    if (!clean || !me || sending) return;
    setSending(true);
    setError("");
    try {
      if (editing) {
        await base44.entities.DirectMessage.update(editing.id, { content: clean, is_edited: true });
        setEditing(null);
        setText("");
        await load();
        return;
      }
      const memberEmails = isGroup ? Array.from(new Set(groupMemberEmails || [])).sort() : members;
      const created = await base44.entities.DirectMessage.create({
        conversation_id: conversationId,
        conversation_type: isGroup ? "group" : "dm",
        group_name: isGroup ? groupName || "Group chat" : "",
        content: clean,
        image_url: "",
        user_email: me.email,
        user_display_name: me.display_name || me.full_name || me.email,
        user_profile_picture: me.profile_picture || "",
        member_emails: memberEmails,
        read_by: [me.email],
        reactions: {},
        is_edited: false,
        sent_at: nowISO(),
      });
      setMessages(prev => [...prev, created]);
      setText("");
    } catch (e) {
      setError(e?.message || "Could not send message.");
    } finally {
      setSending(false);
    }
  };

  const startEdit = (msg) => {
    setEditing(msg);
    setText(msg.content || "");
  };

  const cancelEdit = () => {
    setEditing(null);
    setText("");
  };

  const remove = async (msg) => {
    if (!confirm("Delete this message?")) return;
    await base44.entities.DirectMessage.delete(msg.id);
    setMessages(prev => prev.filter(m => m.id !== msg.id));
  };

  const canManage = (msg) => me?.role === "admin" || msg.user_email === me?.email;

  return (
    <div className="flex flex-col h-full" style={{ background: "var(--surface)" }}>
      <div className="flex-1 overflow-y-auto scroll px-4 py-4 space-y-3">
        {loading ? (
          <div className="h-full flex items-center justify-center"><Loader2 className="w-5 h-5 animate-spin" style={{ color: "var(--accent-pink)" }} /></div>
        ) : messages.length === 0 ? (
          <div className="h-full flex items-center justify-center text-center px-8">
            <div>
              <p className="text-sm font-semibold" style={{ color: "var(--text-primary)" }}>No messages yet</p>
              <p className="text-xs mt-1" style={{ color: "var(--text-muted)" }}>Send the first one. Civilization may recover.</p>
            </div>
          </div>
        ) : messages.map((msg) => {
          const own = msg.user_email === me?.email;
          return (
            <div key={msg.id} className={`group flex gap-2 ${own ? "flex-row-reverse" : ""}`}>
              <Avatar user={{ profile_picture: msg.user_profile_picture }} name={msg.user_display_name} size={30} />
              <div className={`max-w-[78%] flex flex-col gap-1 ${own ? "items-end" : "items-start"}`}>
                <span className="text-[10px]" style={{ color: "var(--text-muted)" }}>{msg.user_display_name || msg.user_email}</span>
                <div className="relative px-3 py-2 rounded-2xl text-sm whitespace-pre-wrap break-words" style={own ? { background: "var(--accent-pink)", color: "white", borderTopRightRadius: 5 } : { background: "var(--pink-soft)", color: "var(--text-primary)", border: "1px solid var(--border-c)", borderTopLeftRadius: 5 }}>
                  {msg.content}
                  {msg.is_edited && <span className="ml-1 text-[10px] opacity-70">edited</span>}
                  {canManage(msg) && (
                    <div className={`absolute -top-3 ${own ? "-left-2" : "-right-2"} hidden group-hover:flex gap-1`}>
                      <button onClick={() => startEdit(msg)} className="w-6 h-6 bg-white rounded-full shadow flex items-center justify-center" style={{ border: "1px solid var(--border-c)" }}><Pencil className="w-3 h-3" style={{ color: "var(--text-muted)" }} /></button>
                      <button onClick={() => remove(msg)} className="w-6 h-6 bg-white rounded-full shadow flex items-center justify-center" style={{ border: "1px solid var(--border-c)" }}><Trash2 className="w-3 h-3 text-red-400" /></button>
                    </div>
                  )}
                </div>
                <span className="text-[10px]" style={{ color: "var(--text-muted)" }}>{msg.created_date ? new Date(msg.created_date).toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" }) : ""}</span>
              </div>
            </div>
          );
        })}
        <div ref={bottomRef} />
      </div>

      {error && <div className="mx-4 mb-2 text-xs rounded-xl px-3 py-2" style={{ background: "#fff0f0", color: "#c24141", border: "1px solid #ffd0d0" }}>{error}</div>}
      {editing && <div className="mx-4 mb-2 flex items-center gap-2 text-xs rounded-xl px-3 py-2" style={{ background: "var(--pink-soft)", color: "var(--text-secondary)" }}><Pencil className="w-3 h-3" /> Editing message <button onClick={cancelEdit} className="ml-auto"><X className="w-3.5 h-3.5" /></button></div>}

      <form onSubmit={send} className="flex items-center gap-2 px-4 py-3 border-t flex-shrink-0" style={{ borderColor: "var(--border-c)" }}>
        <input value={text} onChange={(e) => setText(e.target.value)} placeholder={editing ? "Edit message…" : "Message…"} className="flex-1 rounded-full border px-4 py-2 text-sm bg-transparent outline-none" style={{ borderColor: "var(--border-c)", color: "var(--text-primary)" }} />
        {editing && <button type="button" onClick={cancelEdit} className="w-9 h-9 rounded-full flex items-center justify-center" style={{ background: "var(--pink-soft)" }}><X className="w-4 h-4" style={{ color: "var(--text-muted)" }} /></button>}
        <button disabled={sending || !text.trim()} className="w-9 h-9 rounded-full flex items-center justify-center disabled:opacity-50" style={{ background: "var(--accent-pink)" }}>{sending ? <Loader2 className="w-4 h-4 text-white animate-spin" /> : editing ? <Check className="w-4 h-4 text-white" /> : <Send className="w-4 h-4 text-white" />}</button>
      </form>
    </div>
  );
}
