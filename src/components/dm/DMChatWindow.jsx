import React, { useEffect, useMemo, useRef, useState } from "react";
import { AnimatePresence, motion } from "framer-motion";
import { ArrowDown, CheckCheck, MessageSquare, Pencil, SmilePlus, Trash2 } from "lucide-react";
import { base44 } from "@/api/base44Client";
import { useLiveQuery } from "@/lib/useLiveQuery";
import { checkText } from "@/lib/moderation";
import { toast } from "@/lib/toast";
import { clockTime, dayLabel, displayName } from "@/lib/format";
import Avatar from "@/components/common/Avatar";
import { useConfirm } from "@/components/common/Modal";
import ChatComposer from "@/components/chat/ChatComposer";
import RichText from "@/components/chat/RichText";
import { QUICK_REACTIONS } from "@/components/chat/EmojiPicker";

function Bubble({ msg, own, showAvatar, showName, isGroup, seen, onEdit, onDelete, onReact, me }) {
  const [react, setReact] = useState(false);
  const reactions = Object.entries(msg.reactions || {}).filter(([, users]) => users?.length);
  return (
    <motion.div layout="position" initial={{ opacity: 0, y: 10, scale: 0.98 }} animate={{ opacity: 1, y: 0, scale: 1 }} transition={{ type: "spring", stiffness: 420, damping: 32 }} className={`group flex gap-2 ${own ? "flex-row-reverse" : ""} ${showAvatar ? "mt-3" : "mt-0.5"}`} onMouseLeave={() => setReact(false)}>
      <div className="w-8 flex-shrink-0">{!own && showAvatar && <Avatar src={msg.user_profile_picture} name={msg.user_display_name} size={32} />}</div>
      <div className={`max-w-[78%] sm:max-w-[65%] flex flex-col ${own ? "items-end" : "items-start"}`}>
        {showName && isGroup && !own && <span className="text-[11px] font-bold mb-1 ml-3" style={{ color: "var(--text-secondary)" }}>{msg.user_display_name}</span>}
        <div className={`relative flex items-center gap-1.5 ${own ? "flex-row-reverse" : ""}`}>
          <div className={`relative ${msg.image_url && !msg.content ? "" : "px-3.5 py-2"} text-sm leading-relaxed rounded-[1.25rem] ${own ? "rounded-br-md bubble-own" : "rounded-bl-md"}`} style={own ? { background: "var(--accent-grad)", color: "#fff", boxShadow: "var(--shadow-sm)" } : { background: "var(--surface)", color: "var(--text-primary)", border: "1px solid var(--border-c)" }}>
            {msg.image_url && <a href={msg.image_url} target="_blank" rel="noopener noreferrer"><img src={msg.image_url} alt="" className={`max-w-[260px] max-h-72 object-cover rounded-2xl ${msg.content ? "mb-1.5 -mx-1.5 -mt-0.5" : ""}`} /></a>}
            {msg.content && <RichText text={msg.content} />}
            {msg.is_edited && <span className="ml-1.5 text-[10px] opacity-70">(edited)</span>}
          </div>
          <div className={`flex items-center gap-0.5 opacity-0 group-hover:opacity-100 focus-within:opacity-100 transition-opacity ${own ? "flex-row-reverse" : ""}`}>
            <button onClick={() => setReact((v) => !v)} className="icon-btn w-7 h-7" aria-label="React"><SmilePlus className="w-3.5 h-3.5" /></button>
            {own && msg.content && <button onClick={() => onEdit(msg)} className="icon-btn w-7 h-7" aria-label="Edit message"><Pencil className="w-3.5 h-3.5" /></button>}
            {(own || me?.role === "admin") && <button onClick={() => onDelete(msg)} className="icon-btn w-7 h-7" aria-label="Delete message"><Trash2 className="w-3.5 h-3.5" style={{ color: "var(--danger)" }} /></button>}
          </div>
          <AnimatePresence>
            {react && (
              <motion.div initial={{ opacity: 0, scale: 0.8, y: 6 }} animate={{ opacity: 1, scale: 1, y: 0 }} exit={{ opacity: 0, scale: 0.8 }} className={`absolute bottom-full mb-1 ${own ? "right-0" : "left-0"} z-10 flex gap-0.5 p-1 rounded-full`} style={{ background: "var(--surface)", border: "1px solid var(--border-c)", boxShadow: "var(--shadow-md)" }}>
                {QUICK_REACTIONS.map((e) => <motion.button key={e} whileHover={{ scale: 1.3 }} onClick={() => { onReact(msg, e); setReact(false); }} className="w-8 h-8 rounded-full text-lg">{e}</motion.button>)}
              </motion.div>
            )}
          </AnimatePresence>
        </div>
        {reactions.length > 0 && (
          <div className={`flex flex-wrap gap-1 mt-1 ${own ? "justify-end" : ""}`}>
            {reactions.map(([emoji, users]) => (
              <motion.button key={emoji} initial={{ scale: 0 }} animate={{ scale: 1 }} onClick={() => onReact(msg, emoji)} className="text-xs px-2 py-0.5 rounded-full flex items-center gap-1 font-semibold" style={users.includes(me?.email) ? { background: "var(--pink-soft)", border: "1px solid rgb(var(--accent-rgb) / 0.4)", color: "var(--accent-rose)" } : { background: "var(--surface)", border: "1px solid var(--border-c)", color: "var(--text-secondary)" }}>{emoji}<span>{users.length}</span></motion.button>
            ))}
          </div>
        )}
        <span className="text-[10px] mt-1 px-1 flex items-center gap-1" style={{ color: "var(--text-muted)" }}>
          {clockTime(msg.created_date)}{seen && <><CheckCheck className="w-3 h-3" style={{ color: "var(--accent-rose)" }} /> Seen</>}
        </span>
      </div>
    </motion.div>
  );
}

export default function DMChatWindow({ conversation, me }) {
  const confirm = useConfirm();
  const isGroup = conversation.type === "group";
  const scrollRef = useRef(null);
  const [atBottom, setAtBottom] = useState(true);
  const [editing, setEditing] = useState(null);
  const { data: raw, loading } = useLiveQuery("DirectMessage", { conversation_id: conversation.id, member_emails: { $contains: me.email } }, { sort: "-created_date", limit: 200 });
  const messages = useMemo(() => [...raw].reverse(), [raw]);

  // Mark incoming messages as read.
  useEffect(() => {
    const unread = messages.filter((m) => m.user_email !== me.email && !(m.read_by || []).includes(me.email));
    unread.forEach((m) => base44.entities.DirectMessage.update(m.id, { read_by: [...(m.read_by || []), me.email] }).catch(() => {}));
  }, [messages, me.email]);

  useEffect(() => {
    const el = scrollRef.current;
    if (el && atBottom) el.scrollTo({ top: el.scrollHeight, behavior: messages.length > 30 ? "auto" : "smooth" });
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [messages.length, loading]);

  const onScroll = (e) => {
    const el = e.currentTarget;
    setAtBottom(el.scrollHeight - el.scrollTop - el.clientHeight < 120);
  };
  const jump = () => scrollRef.current?.scrollTo({ top: scrollRef.current.scrollHeight, behavior: "smooth" });

  const send = async ({ text, file }) => {
    try {
      if (editing) {
        await base44.entities.DirectMessage.update(editing.id, { content: text, is_edited: true });
        setEditing(null);
        return true;
      }
      const mod = await checkText(text, { user: me, where: "direct message" });
      if (!mod.safe) { toast.error("Message blocked", { description: mod.reason }); return false; }
      const image_url = file ? (await base44.integrations.Core.UploadFile({ file })).file_url : "";
      const members = isGroup ? [...new Set(conversation.group.member_emails || [])].sort() : [me.email, conversation.otherUser.email].sort();
      await base44.entities.DirectMessage.create({
        conversation_id: conversation.id,
        conversation_type: isGroup ? "group" : "dm",
        group_name: isGroup ? conversation.group.name : "",
        content: text,
        image_url,
        user_email: me.email,
        user_display_name: displayName(me),
        user_profile_picture: me.profile_picture || "",
        member_emails: members,
        read_by: [me.email],
        reactions: {},
        is_edited: false,
      });
      setAtBottom(true);
      return true;
    } catch (e) {
      toast.error(e?.message || "Could not send message.");
      return false;
    }
  };
  const remove = async (msg) => {
    const ok = await confirm({ title: "Delete message?", confirmLabel: "Delete", danger: true });
    if (ok) base44.entities.DirectMessage.delete(msg.id).catch((e) => toast.error(e?.message || "Could not delete."));
  };
  const react = (msg, emoji) => {
    const reactions = { ...(msg.reactions || {}) };
    const users = new Set(reactions[emoji] || []);
    if (users.has(me.email)) users.delete(me.email); else users.add(me.email);
    reactions[emoji] = [...users];
    base44.entities.DirectMessage.update(msg.id, { reactions }).catch((e) => toast.error(e?.message || "Could not react."));
  };

  const lastOwn = [...messages].reverse().find((m) => m.user_email === me.email);
  const seenId = !isGroup && lastOwn && (lastOwn.read_by || []).includes(conversation.otherUser?.email) ? lastOwn.id : null;
  const mentionCandidates = isGroup ? Object.values(conversation.group.member_display_names || {}).filter((n) => n !== displayName(me)).map((name) => ({ name })) : [];

  return (
    <div className="flex flex-col h-full min-h-0 relative">
      <div ref={scrollRef} onScroll={onScroll} className="flex-1 overflow-y-auto scroll px-3 sm:px-6 py-4">
        {loading ? (
          <div className="space-y-4 py-6">{[40, 60, 35, 55].map((w, i) => <div key={i} className={`flex ${i % 2 ? "justify-end" : ""}`}><div className="skeleton h-10" style={{ width: `${w}%` }} /></div>)}</div>
        ) : messages.length === 0 ? (
          <div className="h-full flex flex-col items-center justify-center text-center gap-3 px-8">
            <motion.div animate={{ y: [0, -6, 0] }} transition={{ duration: 3, repeat: Infinity }} className="w-16 h-16 rounded-3xl flex items-center justify-center" style={{ background: "var(--pink-soft)", color: "var(--accent-rose)" }}><MessageSquare className="w-7 h-7" /></motion.div>
            <p className="font-display text-lg font-semibold" style={{ color: "var(--text-primary)" }}>Say hi 👋</p>
            <p className="text-sm" style={{ color: "var(--text-muted)" }}>This is the start of your conversation{isGroup ? ` in ${conversation.group.name}` : ` with ${displayName(conversation.otherUser)}`}.</p>
          </div>
        ) : (
          messages.map((m, i) => {
            const prev = messages[i - 1];
            const newDay = !prev || new Date(prev.created_date).toDateString() !== new Date(m.created_date).toDateString();
            const grouped = prev && !newDay && prev.user_email === m.user_email && new Date(m.created_date) - new Date(prev.created_date) < 5 * 60000;
            return (
              <React.Fragment key={m.id}>
                {newDay && (
                  <div className="flex items-center gap-3 my-5">
                    <div className="divider flex-1" />
                    <span className="text-[11px] font-bold uppercase tracking-wider" style={{ color: "var(--text-muted)" }}>{dayLabel(m.created_date)}</span>
                    <div className="divider flex-1" />
                  </div>
                )}
                <Bubble msg={m} me={me} own={m.user_email === me.email} showAvatar={!grouped} showName={!grouped} isGroup={isGroup} seen={m.id === seenId} onEdit={setEditing} onDelete={remove} onReact={react} />
              </React.Fragment>
            );
          })
        )}
      </div>
      <AnimatePresence>
        {!atBottom && (
          <motion.button initial={{ opacity: 0, y: 10 }} animate={{ opacity: 1, y: 0 }} exit={{ opacity: 0, y: 10 }} onClick={jump} className="absolute bottom-24 left-1/2 -translate-x-1/2 chip glass" style={{ boxShadow: "var(--shadow-md)" }}>
            <ArrowDown className="w-4 h-4" /> Latest
          </motion.button>
        )}
      </AnimatePresence>
      <ChatComposer
        placeholder={isGroup ? `Message ${conversation.group.name}` : `Message ${displayName(conversation.otherUser)}`}
        onSend={send}
        editing={editing}
        onCancelEdit={() => setEditing(null)}
        mentionCandidates={mentionCandidates}
      />
    </div>
  );
}
