import React, { useEffect, useMemo, useRef, useState } from "react";
import { Link } from "react-router-dom";
import { AnimatePresence, motion } from "framer-motion";
import { ArrowDown, Hash, Menu, Pencil, Pin, PinOff, Reply, Search, SmilePlus, Sparkles, Trash2, Users, X } from "lucide-react";
import { base44 } from "@/api/base44Client";
import { useLiveQuery } from "@/lib/useLiveQuery";
import { checkText } from "@/lib/moderation";
import { toast } from "@/lib/toast";
import { clockTime, dayLabel, displayName, profileLink, timeAgo } from "@/lib/format";
import { notify } from "@/utils/notifications";
import { sendBadMessage } from "@/utils/discordWebhook";
import Avatar from "@/components/common/Avatar";
import { useConfirm } from "@/components/common/Modal";
import ChatComposer from "@/components/chat/ChatComposer";
import RichText, { mentionedNames } from "@/components/chat/RichText";
import { QUICK_REACTIONS } from "@/components/chat/EmojiPicker";
import { useBlocked } from "@/lib/safety";

const compact = (s) => String(s || "").replace(/\s+/g, "").toLowerCase();

// Only messages that arrive while you're here animate in.
const loadedAt = Date.now();
const isFreshMsg = (m) => new Date(m?.created_date || 0).getTime() > loadedAt - 1500;

function MessageItem({ msg, grouped, me, roleColor, mentionsMe, canPin, canDelete, canReact = true, onReply, onEdit, onDelete, onPin, onReact, onJumpTo, onOpenProfile, tapped, onTap }) {
  const [picker, setPicker] = useState(false);
  const own = msg.user_email === me.email;
  if (msg.type === "join" || msg.user_email === "__system__") {
    return (
      <motion.div initial={{ opacity: 0, scale: 0.95 }} animate={{ opacity: 1, scale: 1 }} className="flex items-center gap-2 px-4 sm:px-6 py-2 text-xs" style={{ color: "var(--text-muted)" }}>
        <Sparkles className="w-3.5 h-3.5" style={{ color: "var(--accent-rose)" }} /><span><strong style={{ color: "var(--text-secondary)" }}>{msg.user_display_name}</strong> joined the server 👋</span><span>· {timeAgo(msg.created_date)}</span>
      </motion.div>
    );
  }
  const reactions = Object.entries(msg.reactions || {}).filter(([, u]) => u?.length);
  return (
    <motion.div
      id={`msg-${msg.id}`}
      initial={isFreshMsg(msg) ? { opacity: 0, y: 8 } : false}
      animate={{ opacity: 1, y: 0 }}
      transition={{ type: "spring", stiffness: 420, damping: 34 }}
      className={`group relative flex gap-3 px-4 sm:px-6 ${grouped ? "py-0.5" : "pt-3 pb-0.5"} transition-colors hover:bg-[var(--surface-2)]`}
      style={mentionsMe ? { background: "rgb(240 160 32 / 0.08)", boxShadow: "inset 3px 0 0 #f0a020" } : undefined}
      onMouseLeave={() => setPicker(false)}
      onClick={(e) => { if (window.matchMedia("(hover: none)").matches && !e.target.closest("button,a,input,textarea")) onTap?.(msg.id); }}
    >
      <div className="w-10 flex-shrink-0">
        {!grouped ? (
          <button onClick={(e) => onOpenProfile?.(msg.user_email, e.currentTarget)} className="rounded-full transition-transform hover:scale-105" aria-label={`View ${msg.user_display_name}'s profile`}><Avatar src={msg.user_profile_picture} name={msg.user_display_name} size={40} /></button>
        ) : (
          <span className="text-[10px] opacity-0 group-hover:opacity-100 block text-right pt-1" style={{ color: "var(--text-muted)" }}>{clockTime(msg.created_date)}</span>
        )}
      </div>
      <div className="flex-1 min-w-0">
        {msg.reply_to_preview && !grouped && (
          <button onClick={() => onJumpTo(msg.reply_to_id)} className="flex items-center gap-1.5 text-xs mb-1 max-w-full hover:underline" style={{ color: "var(--text-muted)" }}>
            <Reply className="w-3 h-3 flex-shrink-0 -scale-x-100" /><span className="truncate">{msg.reply_to_preview}</span>
          </button>
        )}
        {!grouped && (
          <div className="flex items-baseline gap-2 flex-wrap">
            <button onClick={(e) => onOpenProfile?.(msg.user_email, e.currentTarget)} className="text-sm font-bold hover:underline" style={{ color: roleColor || "var(--text-primary)" }}>{msg.user_display_name}</button>
            <span className="text-[11px]" style={{ color: "var(--text-muted)" }}>{clockTime(msg.created_date)}</span>
            {msg.is_pinned && <span className="text-[10px] font-bold flex items-center gap-0.5" style={{ color: "#f0a020" }}><Pin className="w-3 h-3" /> pinned</span>}
          </div>
        )}
        {msg.content && <div className="text-sm leading-relaxed" style={{ color: "var(--text-primary)" }}><RichText text={msg.content} />{msg.is_edited && <span className="text-[10px] ml-1.5" style={{ color: "var(--text-muted)" }}>(edited)</span>}</div>}
        {msg.image_url && <a href={msg.image_url} target="_blank" rel="noopener noreferrer" className="block mt-1.5 w-fit"><img src={msg.image_url} alt="" loading="lazy" className="rounded-2xl max-w-[min(360px,100%)] max-h-80 object-cover" style={{ border: "1px solid var(--border-c)" }} /></a>}
        {reactions.length > 0 && (
          <div className="flex flex-wrap gap-1 mt-1.5">
            {reactions.map(([emoji, users]) => (
              <motion.button key={emoji} initial={{ scale: 0 }} animate={{ scale: 1 }} disabled={!canReact} onClick={() => onReact(msg, emoji)} className="text-xs px-2 py-0.5 rounded-full flex items-center gap-1 font-semibold transition-colors disabled:cursor-default" style={users.includes(me.email) ? { background: "var(--pink-soft)", border: "1px solid rgb(var(--accent-rgb) / 0.45)", color: "var(--accent-rose)" } : { background: "var(--surface)", border: "1px solid var(--border-c)", color: "var(--text-secondary)" }} title={`${users.length} reaction${users.length > 1 ? "s" : ""}`}>{emoji}<span>{users.length}</span></motion.button>
            ))}
          </div>
        )}
      </div>
      <div className={`absolute -top-3 right-4 sm:right-6 flex items-center gap-0.5 p-0.5 rounded-xl transition-opacity z-10 ${tapped ? "opacity-100" : "opacity-0 pointer-events-none can-hover:group-hover:opacity-100 can-hover:group-hover:pointer-events-auto focus-within:opacity-100 focus-within:pointer-events-auto"}`} style={{ background: "var(--surface)", border: "1px solid var(--border-c)", boxShadow: "var(--shadow-sm)" }}>
        {canReact && <button onClick={() => setPicker((v) => !v)} className="icon-btn w-8 h-8" aria-label="Add reaction"><SmilePlus className="w-4 h-4" /></button>}
        <button onClick={() => onReply(msg)} className="icon-btn w-8 h-8" aria-label="Reply"><Reply className="w-4 h-4" /></button>
        {own && msg.content && <button onClick={() => onEdit(msg)} className="icon-btn w-8 h-8" aria-label="Edit"><Pencil className="w-4 h-4" /></button>}
        {canPin && <button onClick={() => onPin(msg)} className="icon-btn w-8 h-8" aria-label={msg.is_pinned ? "Unpin" : "Pin"}>{msg.is_pinned ? <PinOff className="w-4 h-4" /> : <Pin className="w-4 h-4" />}</button>}
        {canDelete && <button onClick={() => onDelete(msg)} className="icon-btn w-8 h-8" aria-label="Delete"><Trash2 className="w-4 h-4" style={{ color: "var(--danger)" }} /></button>}
      </div>
      <AnimatePresence>
        {picker && (
          <motion.div initial={{ opacity: 0, scale: 0.85, y: -4 }} animate={{ opacity: 1, scale: 1, y: 0 }} exit={{ opacity: 0, scale: 0.85 }} className="absolute right-4 sm:right-6 top-7 z-20 flex gap-0.5 p-1 rounded-full" style={{ background: "var(--surface)", border: "1px solid var(--border-c)", boxShadow: "var(--shadow-md)" }}>
            {QUICK_REACTIONS.map((e) => <motion.button key={e} whileHover={{ scale: 1.3 }} onClick={() => { onReact(msg, e); setPicker(false); }} className="w-8 h-8 rounded-full text-lg">{e}</motion.button>)}
          </motion.div>
        )}
      </AnimatePresence>
    </motion.div>
  );
}

export default function ChatArea({ channel, community, me, roles, members, actor, access, onOpenSidebar, onToggleMembers, showMembers, onOpenProfile }) {
  const perms = actor.perms;
  const myRoleIds = actor.roleIds;
  const confirm = useConfirm();
  const [tapped, setTapped] = useState(null); // message showing its action bar on touch screens
  const scrollRef = useRef(null);
  const [atBottom, setAtBottom] = useState(true);
  const [replyTo, setReplyTo] = useState(null);
  const [editing, setEditing] = useState(null);
  const [showSearch, setShowSearch] = useState(false);
  const [showPinned, setShowPinned] = useState(false);
  const [query, setQuery] = useState("");
  const { data: raw, loading } = useLiveQuery("ChannelMessage", { channel_id: channel.id }, { sort: "-created_date", limit: 150 });
  const blocked = useBlocked();
  const messages = useMemo(() => [...raw].reverse().filter((m) => !blocked.has(m.user_email)), [raw, blocked]);

  const myRoles = roles.filter((r) => myRoleIds.includes(r.id));
  const canPost = !!access?.post;
  const postRoles = (channel.allowed_roles || []).map((a) => roles.find((r) => r.id === a || r.name === a)?.name).filter(Boolean);
  const roleColorFor = useMemo(() => {
    const map = {};
    members.forEach((m) => { const top = roles.find((r) => (m.roles || []).includes(r.id)); if (top) map[m.user_email] = top.color; });
    return map;
  }, [members, roles]);
  const myNames = [compact(displayName(me)), ...myRoles.map((r) => compact(r.name)), "everyone", "here"];

  useEffect(() => { setReplyTo(null); setEditing(null); setQuery(""); setShowSearch(false); setShowPinned(false); setAtBottom(true); }, [channel.id]);
  useEffect(() => {
    const el = scrollRef.current;
    if (el && atBottom && !query) el.scrollTo({ top: el.scrollHeight });
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [messages.length, loading, channel.id]);

  const visible = query.trim() ? messages.filter((m) => [m.content, m.user_display_name].some((f) => String(f || "").toLowerCase().includes(query.trim().toLowerCase()))) : messages;
  const pinned = messages.filter((m) => m.is_pinned);

  const jumpTo = (id) => {
    const el = document.getElementById(`msg-${id}`);
    if (!el) { toast("That message is too old to jump to"); return; }
    el.scrollIntoView({ behavior: "smooth", block: "center" });
    el.animate([{ backgroundColor: "rgba(217, 87, 127, 0.22)" }, { backgroundColor: "rgba(217, 87, 127, 0)" }], { duration: 1600 });
  };

  const send = async ({ text, file, gif }) => {
    try {
      if (editing) {
        await base44.entities.ChannelMessage.update(editing.id, { content: text, is_edited: true });
        setEditing(null);
        return true;
      }
      const mod = await checkText(text, { user: me, where: `#${channel.name}` });
      if (!mod.safe) {
        sendBadMessage({ userEmail: me.email, displayName: displayName(me), communityName: community.name, channelName: channel.name, reason: mod.reason, content: text });
        toast.error("Message blocked", { description: mod.reason });
        return false;
      }
      const image_url = gif || (file ? (await base44.integrations.Core.UploadFile({ file })).file_url : "");
      await base44.entities.ChannelMessage.create({
        channel_id: channel.id,
        community_id: community.id,
        content: text,
        image_url,
        user_email: me.email,
        user_display_name: displayName(me),
        user_profile_picture: me.profile_picture || "",
        reply_to_id: replyTo?.id || "",
        reply_to_preview: replyTo ? `${replyTo.user_display_name}: ${(replyTo.content || "image").slice(0, 80)}` : "",
        reactions: {},
        is_pinned: false,
        is_edited: false,
      });
      // Notify mentioned members (and the person being replied to).
      const names = mentionedNames(text);
      const targets = new Set();
      members.forEach((m) => { if (names.includes(compact(m.user_display_name))) targets.add(m.user_email); });
      // @Role and @everyone only notify when you're allowed to mention them.
      if (perms.mention_roles) {
        const everyone = names.includes("everyone") || names.includes("here");
        const roleIds = roles.filter((r) => names.includes(compact(r.name))).map((r) => r.id);
        members.forEach((m) => { if (everyone || (m.roles || []).some((id) => roleIds.includes(id))) targets.add(m.user_email); });
      }
      if (replyTo && replyTo.user_email !== me.email) targets.add(replyTo.user_email);
      targets.delete(me.email);
      await Promise.all([...targets].map((to) => notify({ to_email: to, from_email: me.email, from_display_name: displayName(me), from_profile_picture: me.profile_picture, type: "mention", message: `${displayName(me)} mentioned you in #${channel.name}: "${text.slice(0, 60)}"`, link: `/CommunityChat?id=${community.id}&channel=${channel.id}`, entity_id: channel.id })));
      setReplyTo(null);
      setAtBottom(true);
      return true;
    } catch (e) {
      toast.error(e?.message || "Could not send.");
      return false;
    }
  };
  const remove = async (msg) => {
    if (!(await confirm({ title: "Delete message?", confirmLabel: "Delete", danger: true }))) return;
    base44.entities.ChannelMessage.delete(msg.id).catch((e) => toast.error(e?.message || "Could not delete."));
  };
  const react = (msg, emoji) => {
    const reactions = { ...(msg.reactions || {}) };
    const users = new Set(reactions[emoji] || []);
    if (users.has(me.email)) users.delete(me.email); else users.add(me.email);
    reactions[emoji] = [...users];
    base44.entities.ChannelMessage.update(msg.id, { reactions }).catch((e) => toast.error(e?.message || "Could not react."));
  };
  const pin = (msg) => base44.entities.ChannelMessage.update(msg.id, { is_pinned: !msg.is_pinned }).then(() => toast.success(msg.is_pinned ? "Unpinned" : "Pinned to channel")).catch((e) => toast.error(e?.message || "Could not pin."));

  const mentionCandidates = useMemo(() => [
    ...members.filter((m) => m.user_email !== me.email).map((m) => ({ name: m.user_display_name || m.user_email.split("@")[0], color: roleColorFor[m.user_email], hint: "member" })),
    ...(perms.mention_roles ? [...roles.map((r) => ({ name: r.name, color: r.color, hint: "role" })), { name: "everyone", hint: "notify everyone" }] : []),
  ], [members, roles, roleColorFor, me.email, perms.mention_roles]);

  return (
    <div className="flex flex-col h-full min-h-0 min-w-0">
      <div className="h-14 flex-shrink-0 flex items-center gap-2 px-3 sm:px-5 glass" style={{ borderBottom: "1px solid var(--border-c)" }}>
        <button onClick={onOpenSidebar} className="icon-btn md:hidden" aria-label="Channels"><Menu className="w-5 h-5" /></button>
        <Hash className="w-5 h-5 flex-shrink-0" style={{ color: "var(--text-muted)" }} />
        <span className="font-bold truncate" style={{ color: "var(--text-primary)" }}>{channel.name}</span>
        {channel.description && <span className="hidden lg:block text-xs truncate pl-3 ml-1" style={{ color: "var(--text-muted)", borderLeft: "1px solid var(--border-c)" }}>{channel.description}</span>}
        <div className="flex-1" />
        <button onClick={() => setShowPinned((v) => !v)} className="icon-btn" data-active={showPinned} aria-label="Pinned messages"><Pin className="w-4 h-4" /></button>
        <button onClick={() => { setShowSearch((v) => !v); setQuery(""); }} className="icon-btn" data-active={showSearch} aria-label="Search messages"><Search className="w-4 h-4" /></button>
        <button onClick={onToggleMembers} className="icon-btn" data-active={showMembers} aria-label="Members"><Users className="w-4 h-4" /></button>
      </div>

      <AnimatePresence>
        {showSearch && (
          <motion.div initial={{ height: 0, opacity: 0 }} animate={{ height: "auto", opacity: 1 }} exit={{ height: 0, opacity: 0 }} className="overflow-hidden flex-shrink-0" style={{ borderBottom: "1px solid var(--border-c)" }}>
            <div className="flex items-center gap-2 px-4 sm:px-6 py-2.5">
              <Search className="w-4 h-4" style={{ color: "var(--text-muted)" }} />
              <input autoFocus value={query} onChange={(e) => setQuery(e.target.value)} placeholder={`Search #${channel.name}`} className="flex-1 bg-transparent outline-none text-sm" style={{ color: "var(--text-primary)" }} />
              {query && <span className="badge-pink">{visible.length} result{visible.length === 1 ? "" : "s"}</span>}
            </div>
          </motion.div>
        )}
      </AnimatePresence>

      <div className="relative flex-1 min-h-0 flex">
        <div ref={scrollRef} onScroll={(e) => { const el = e.currentTarget; setAtBottom(el.scrollHeight - el.scrollTop - el.clientHeight < 120); }} className="flex-1 overflow-y-auto scroll pb-3">
          {loading ? (
            <div className="space-y-5 p-6">{[0, 1, 2, 3].map((i) => <div key={i} className="flex gap-3"><div className="skeleton w-10 h-10 !rounded-full" /><div className="flex-1 space-y-2"><div className="skeleton h-3 w-32" /><div className="skeleton h-3" style={{ width: `${40 + i * 12}%` }} /></div></div>)}</div>
          ) : (
            <>
              {!query && (
                <div className="px-4 sm:px-6 pt-10 pb-4">
                  <motion.div initial={{ scale: 0.8, opacity: 0 }} animate={{ scale: 1, opacity: 1 }} className="w-16 h-16 rounded-3xl flex items-center justify-center mb-4 text-white" style={{ background: "var(--accent-grad)", boxShadow: "var(--shadow-accent)" }}><Hash className="w-8 h-8" /></motion.div>
                  <h2 className="font-display text-3xl font-semibold" style={{ color: "var(--text-primary)" }}>Welcome to #{channel.name}</h2>
                  <p className="text-sm mt-1" style={{ color: "var(--text-muted)" }}>{channel.description || `This is the start of the #${channel.name} channel.`}{community.welcome_message ? ` ${community.welcome_message}` : ""}</p>
                </div>
              )}
              {visible.length === 0 && query && <p className="text-center text-sm py-16" style={{ color: "var(--text-muted)" }}>No messages match "{query}".</p>}
              {visible.map((m, i) => {
                const prev = visible[i - 1];
                const newDay = !prev || new Date(prev.created_date).toDateString() !== new Date(m.created_date).toDateString();
                const grouped = !query && prev && !newDay && prev.user_email === m.user_email && prev.type !== "join" && m.type !== "join" && !m.reply_to_id && new Date(m.created_date) - new Date(prev.created_date) < 5 * 60000;
                const mentionsMe = m.user_email !== me.email && mentionedNames(m.content).some((n) => myNames.includes(n));
                return (
                  <React.Fragment key={m.id}>
                    {newDay && <div className="flex items-center gap-3 px-6 my-4"><div className="divider flex-1" /><span className="text-[11px] font-bold uppercase tracking-wider" style={{ color: "var(--text-muted)" }}>{dayLabel(m.created_date)}</span><div className="divider flex-1" /></div>}
                    <MessageItem msg={m} grouped={grouped} me={me} roleColor={roleColorFor[m.user_email]} mentionsMe={mentionsMe} canPin={!!(perms.pin_messages || perms.manage_messages)} canDelete={m.user_email === me.email || !!perms.manage_messages} canReact={!!perms.add_reactions} onReply={setReplyTo} onEdit={setEditing} onDelete={remove} onPin={pin} onReact={react} onJumpTo={jumpTo} onOpenProfile={onOpenProfile} tapped={tapped === m.id} onTap={(id) => setTapped((t) => (t === id ? null : id))} />
                  </React.Fragment>
                );
              })}
            </>
          )}
        </div>

        <AnimatePresence>
          {showPinned && (
            <motion.aside initial={{ x: 40, opacity: 0 }} animate={{ x: 0, opacity: 1 }} exit={{ x: 40, opacity: 0 }} transition={{ type: "spring", stiffness: 360, damping: 32 }} className="absolute right-3 top-3 bottom-3 w-[min(340px,calc(100%-24px))] z-20 rounded-3xl flex flex-col overflow-hidden" style={{ background: "var(--surface)", border: "1px solid var(--border-c)", boxShadow: "var(--shadow-lg)" }}>
              <div className="flex items-center gap-2 px-4 h-12 flex-shrink-0" style={{ borderBottom: "1px solid var(--border-c)" }}>
                <Pin className="w-4 h-4" style={{ color: "#f0a020" }} /><span className="font-bold text-sm flex-1" style={{ color: "var(--text-primary)" }}>Pinned messages</span>
                <button onClick={() => setShowPinned(false)} className="icon-btn w-8 h-8" aria-label="Close pinned"><X className="w-4 h-4" /></button>
              </div>
              <div className="flex-1 overflow-y-auto scroll p-3 space-y-2">
                {pinned.length === 0 ? <p className="text-sm text-center py-10" style={{ color: "var(--text-muted)" }}>Nothing pinned yet.</p> : pinned.map((m) => (
                  <button key={m.id} onClick={() => { setShowPinned(false); setTimeout(() => jumpTo(m.id), 150); }} className="w-full text-left card-sm p-3 card-hover">
                    <div className="flex items-center gap-2 mb-1"><Avatar src={m.user_profile_picture} name={m.user_display_name} size={20} /><span className="text-xs font-bold" style={{ color: "var(--text-primary)" }}>{m.user_display_name}</span><span className="text-[10px]" style={{ color: "var(--text-muted)" }}>{timeAgo(m.created_date)}</span></div>
                    <p className="text-sm line-clamp-3" style={{ color: "var(--text-secondary)" }}>{m.content || "📷 Image"}</p>
                  </button>
                ))}
              </div>
            </motion.aside>
          )}
        </AnimatePresence>

        <AnimatePresence>
          {!atBottom && (
            <motion.button initial={{ opacity: 0, x: "-50%", y: 10 }} animate={{ opacity: 1, x: "-50%", y: 0 }} exit={{ opacity: 0, x: "-50%", y: 10 }} onClick={() => scrollRef.current?.scrollTo({ top: scrollRef.current.scrollHeight, behavior: "smooth" })} className="absolute bottom-3 left-1/2 chip glass z-10" style={{ boxShadow: "var(--shadow-md)" }}><ArrowDown className="w-4 h-4" /> Jump to latest</motion.button>
          )}
        </AnimatePresence>
      </div>

      <ChatComposer
        placeholder={`Message #${channel.name}`}
        onSend={send}
        editing={editing}
        onCancelEdit={() => setEditing(null)}
        replyTo={replyTo}
        onCancelReply={() => setReplyTo(null)}
        disabledReason={canPost ? null : !perms.send_messages ? "You don't have permission to send messages in this server" : `Only ${postRoles.join(" or ") || "certain roles"} can post here`}
        allowAttachments={!!perms.attach_files}
        mentionCandidates={mentionCandidates}
      />
    </div>
  );
}
