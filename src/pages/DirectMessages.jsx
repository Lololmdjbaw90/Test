import React, { useEffect, useMemo, useState } from "react";
import { Link, useSearchParams } from "react-router-dom";
import { motion } from "framer-motion";
import { ArrowLeft, Check, Crown, Info, Loader2, LogOut, MessageSquare, Phone, PhoneCall, Plus, Trash2, UserPlus, Users, Video } from "lucide-react";
import { base44 } from "@/api/base44Client";
import { useAuth } from "@/lib/AuthContext";
import { useLiveQuery } from "@/lib/useLiveQuery";
import { usePeople } from "@/lib/people";
import { useFriendships, splitFriendships, dmConversationId } from "@/lib/social";
import { toast } from "@/lib/toast";
import { checkText } from "@/lib/moderation";
import { displayName, isOnline, profileLink, timeAgo } from "@/lib/format";
import { SearchInput } from "@/components/common/Controls";
import Modal, { useConfirm } from "@/components/common/Modal";
import Avatar from "@/components/common/Avatar";
import DMChatWindow from "@/components/dm/DMChatWindow";
import voice, { VOICE_STALE_MS } from "@/lib/voice";
import { isLiveCall, joinCall, messagePreview, startCall } from "@/lib/calls";
import { useNow, useVoice } from "@/components/voice/useVoice";
import { useBlocked } from "@/lib/safety";

function GroupIcon({ group, size = 44 }) {
  const initials = (group?.name || "G").slice(0, 1).toUpperCase();
  return <span className="flex items-center justify-center rounded-2xl text-white font-display font-semibold flex-shrink-0" style={{ width: size, height: size, background: "linear-gradient(135deg,#b19cff,rgb(var(--accent-rgb)))", fontSize: size * 0.4 }}>{initials}</span>;
}

function PickFriends({ friends, selected, onToggle }) {
  if (friends.length === 0) return <p className="text-sm text-center py-6" style={{ color: "var(--text-muted)" }}>No friends to add yet.</p>;
  return (
    <div className="space-y-1 max-h-64 overflow-y-auto scroll">
      {friends.map((f) => {
        const on = selected.includes(f.email);
        return (
          <button key={f.email} type="button" onClick={() => onToggle(f.email)} className="w-full flex items-center gap-3 p-2 rounded-2xl text-left transition-colors hover:bg-[var(--surface-2)]" style={on ? { background: "var(--pink-soft)" } : undefined}>
            <Avatar src={f.profile_picture} name={displayName(f)} size={36} />
            <span className="flex-1 text-sm font-semibold truncate" style={{ color: "var(--text-primary)" }}>{displayName(f)}</span>
            <span className="w-6 h-6 rounded-full flex items-center justify-center" style={on ? { background: "var(--accent-grad)", color: "#fff" } : { border: "2px solid var(--border-strong)" }}>{on && <Check className="w-3.5 h-3.5" />}</span>
          </button>
        );
      })}
    </div>
  );
}

function NewGroupModal({ open, onClose, me, friends, onCreated }) {
  const [name, setName] = useState("");
  const [selected, setSelected] = useState([]);
  const [busy, setBusy] = useState(false);
  const create = async () => {
    const mod = await checkText(name, { user: me, where: "group name", kind: "name" });
    if (!mod.safe) { toast.error(mod.reason); return; }
    setBusy(true);
    try {
      const members = [...selected, me.email].sort();
      const names = { [me.email]: displayName(me) };
      friends.forEach((f) => { if (selected.includes(f.email)) names[f.email] = displayName(f); });
      const g = await base44.entities.GroupChat.create({ name: name.trim(), owner_email: me.email, member_emails: members, member_display_names: names });
      toast.success(`Created ${name.trim()}`);
      setName(""); setSelected([]);
      onCreated(g);
      onClose();
    } catch (e) { toast.error(e?.message || "Could not create group."); }
    setBusy(false);
  };
  return (
    <Modal open={open} onClose={onClose} title="New group chat" subtitle="Chat with several friends at once" footer={<><button className="btn-ghost" onClick={onClose}>Cancel</button><button className="btn" disabled={busy || !name.trim() || selected.length === 0} onClick={create}>{busy ? <Loader2 className="w-4 h-4 animate-spin" /> : "Create group"}</button></>}>
      <div className="space-y-4">
        <div><label className="label" htmlFor="g-name">Group name</label><input id="g-name" className="input" placeholder="e.g. Art Squad" value={name} onChange={(e) => setName(e.target.value)} maxLength={40} /></div>
        <div><p className="label">Members · {selected.length} selected</p><PickFriends friends={friends} selected={selected} onToggle={(e) => setSelected((s) => (s.includes(e) ? s.filter((x) => x !== e) : [...s, e]))} /></div>
      </div>
    </Modal>
  );
}

function GroupInfoModal({ open, onClose, group, me, friends, usersByEmail, onLeft }) {
  const confirm = useConfirm();
  const [adding, setAdding] = useState([]);
  const isOwner = group?.owner_email === me.email;
  if (!group) return null;
  const addable = friends.filter((f) => !group.member_emails.includes(f.email));
  const update = (patch) => base44.entities.GroupChat.update(group.id, patch);
  const addMembers = async () => {
    const names = { ...(group.member_display_names || {}) };
    addable.forEach((f) => { if (adding.includes(f.email)) names[f.email] = displayName(f); });
    try { await update({ member_emails: [...group.member_emails, ...adding].sort(), member_display_names: names }); setAdding([]); toast.success("Members added"); } catch (e) { toast.error(e?.message || "Could not add members."); }
  };
  const kick = async (email) => {
    const names = { ...(group.member_display_names || {}) };
    delete names[email];
    try { await update({ member_emails: group.member_emails.filter((e) => e !== email), member_display_names: names }); } catch (e) { toast.error(e?.message || "Could not remove member."); }
  };
  const leave = async () => {
    if (!(await confirm({ title: `Leave ${group.name}?`, confirmLabel: "Leave", danger: true }))) return;
    const names = { ...(group.member_display_names || {}) };
    delete names[me.email];
    try { await update({ member_emails: group.member_emails.filter((e) => e !== me.email), member_display_names: names }); onLeft(); onClose(); } catch (e) { toast.error(e?.message || "Could not leave."); }
  };
  const destroy = async () => {
    if (!(await confirm({ title: `Delete ${group.name}?`, message: "The group will be removed for everyone.", confirmLabel: "Delete group", danger: true }))) return;
    try { await base44.entities.GroupChat.delete(group.id); onLeft(); onClose(); } catch (e) { toast.error(e?.message || "Could not delete."); }
  };
  return (
    <Modal open={open} onClose={onClose} title={group.name} subtitle={`${group.member_emails.length} members`} autoFocus={false}>
      <div className="space-y-5">
        <div className="space-y-1">
          {group.member_emails.map((email) => {
            const u = usersByEmail[email] || { email, display_name: group.member_display_names?.[email] };
            return (
              <div key={email} className="flex items-center gap-3 p-2 rounded-2xl">
                <Link to={profileLink(email)} onClick={onClose}><Avatar src={u.profile_picture} name={displayName(u)} size={36} online={isOnline(u)} /></Link>
                <span className="flex-1 min-w-0 text-sm font-semibold truncate flex items-center gap-1.5" style={{ color: "var(--text-primary)" }}>{displayName(u)}{email === group.owner_email && <Crown className="w-3.5 h-3.5" style={{ color: "#f0a020" }} />}</span>
                {isOwner && email !== me.email && <button onClick={() => kick(email)} className="text-xs font-semibold px-2 py-1 rounded-lg hover:bg-[var(--pink-soft)]" style={{ color: "var(--danger)" }}>Remove</button>}
              </div>
            );
          })}
        </div>
        {isOwner && addable.length > 0 && (
          <div>
            <p className="label">Add friends</p>
            <PickFriends friends={addable} selected={adding} onToggle={(e) => setAdding((s) => (s.includes(e) ? s.filter((x) => x !== e) : [...s, e]))} />
            {adding.length > 0 && <button onClick={addMembers} className="btn w-full mt-3"><UserPlus className="w-4 h-4" /> Add {adding.length}</button>}
          </div>
        )}
        <div className="flex gap-2">
          {!isOwner && <button onClick={leave} className="btn-outline flex-1" style={{ color: "var(--danger)" }}><LogOut className="w-4 h-4" /> Leave group</button>}
          {isOwner && <button onClick={destroy} className="btn-outline flex-1" style={{ color: "var(--danger)" }}><Trash2 className="w-4 h-4" /> Delete group</button>}
        </div>
      </div>
    </Modal>
  );
}

export default function DirectMessagesPage() {
  const { user: me } = useAuth();
  const [params, setParams] = useSearchParams();
  const [search, setSearch] = useState("");
  const [showNewGroup, setShowNewGroup] = useState(false);
  const [showInfo, setShowInfo] = useState(false);
  // Recently active people (live, for online dots) plus everyone you chat with.
  const { data: activeUsers } = useLiveQuery("User", null, { sort: "-last_seen", limit: 300 });
  const { data: groups } = useLiveQuery("GroupChat", { member_emails: { $contains: me.email } }, { sort: "-created_date" });
  const { data: recent, loading } = useLiveQuery("DirectMessage", { member_emails: { $contains: me.email } }, { sort: "-created_date", limit: 300 });
  const { friendships } = useFriendships(me.email);
  const { friendEmails } = splitFriendships(friendships, me.email);
  const chatPeople = usePeople(useMemo(() => [
    ...recent.flatMap((m) => m.member_emails || []), ...groups.flatMap((g) => g.member_emails || []), ...friendEmails,
  ], [recent, groups, friendEmails]), { recentLimit: 50 });
  const users = useMemo(() => {
    const byEmail = new Map(chatPeople.map((u) => [u.email, u]));
    activeUsers.forEach((u) => byEmail.set(u.email, u));
    return [...byEmail.values()];
  }, [chatPeople, activeUsers]);
  const usersByEmail = useMemo(() => Object.fromEntries(users.map((u) => [u.email, u])), [users]);
  const friends = useMemo(() => friendEmails.map((e) => usersByEmail[e]).filter(Boolean), [friendEmails, usersByEmail]);

  const blocked = useBlocked();
  const conversations = useMemo(() => {
    const last = {};
    const unread = {};
    recent.forEach((m) => {
      if (!last[m.conversation_id]) last[m.conversation_id] = m;
      if (m.user_email !== me.email && !(m.read_by || []).includes(me.email)) unread[m.conversation_id] = (unread[m.conversation_id] || 0) + 1;
    });
    const dmEmails = new Set(friendEmails);
    recent.filter((m) => m.conversation_type !== "group").forEach((m) => (m.member_emails || []).forEach((e) => e !== me.email && dmEmails.add(e)));
    blocked.forEach((e) => dmEmails.delete(e)); // hidden unless opened directly
    const withEmail = params.get("with");
    if (withEmail && withEmail !== me.email) dmEmails.add(withEmail);
    const list = [
      ...[...dmEmails].map((email) => {
        const id = dmConversationId(me.email, email);
        return { id, type: "dm", otherUser: usersByEmail[email] || { email, display_name: email.split("@")[0] }, last: last[id], unread: unread[id] || 0 };
      }),
      ...groups.map((g) => ({ id: g.id, type: "group", group: g, last: last[g.id], unread: unread[g.id] || 0 })),
    ];
    return list.sort((a, b) => new Date(b.last?.created_date || b.group?.created_date || 0) - new Date(a.last?.created_date || a.group?.created_date || 0));
  }, [recent, groups, friendEmails, usersByEmail, me.email, params, blocked]);

  const activeId = params.get("with") ? dmConversationId(me.email, params.get("with")) : params.get("c");
  const active = conversations.find((c) => c.id === activeId) || null;
  const open = (c) => setParams(c.type === "dm" ? { with: c.otherUser.email } : { c: c.id });
  const close = () => setParams({});
  useEffect(() => { setShowInfo(false); }, [activeId]);

  // Calls: header buttons + "call in progress" banner for this conversation.
  const vs = useVoice();
  const now = useNow(5000);
  const { data: calls } = useLiveQuery("Call", { member_emails: { $contains: me.email } }, { sort: "-created_date", limit: 15 });
  const liveCall = active ? calls.find((c) => c.conversation_id === active.id && isLiveCall(c, now)) : null;
  const { data: callPresence } = useLiveQuery("VoicePresence", liveCall ? { channel_id: liveCall.id } : null, { enabled: !!liveCall });
  const inCallPeople = liveCall ? callPresence.filter((p) => now - (p.last_active || 0) < VOICE_STALE_MS) : [];
  const inThisCall = !!liveCall && vs.room?.id === liveCall.id;
  const joinable = liveCall && !inThisCall && inCallPeople.length > 0;
  const [calling, setCalling] = useState(false);
  const call = async (video) => {
    if (!active) return;
    if (inThisCall) { voice.setExpanded(true); return; }
    setCalling(true);
    try {
      if (joinable) await joinCall(liveCall, me, { video });
      else await startCall({ conversation: active, me, video, pictures: Object.fromEntries(users.map((u) => [u.email, u.profile_picture || ""])) });
    } catch (e) { toast.error(e?.message || "Could not start the call."); }
    setCalling(false);
  };

  const q = search.trim().toLowerCase();
  const visible = conversations.filter((c) => !q || (c.type === "group" ? c.group.name : displayName(c.otherUser)).toLowerCase().includes(q));

  const list = (
    <div className="flex flex-col h-full min-h-0">
      <div className="p-4 pb-3 flex items-center gap-3">
        <h1 className="font-display text-2xl font-semibold flex-1" style={{ color: "var(--text-primary)" }}>Messages</h1>
        <button onClick={() => setShowNewGroup(true)} className="btn !px-3 text-xs" title="New group"><Plus className="w-4 h-4" /> Group</button>
      </div>
      <div className="px-4 pb-3"><SearchInput value={search} onChange={setSearch} placeholder="Search conversations…" /></div>
      <div className="flex-1 overflow-y-auto scroll px-2 pb-4">
        {loading && conversations.length === 0 && <div className="space-y-2 px-2">{[0, 1, 2, 3].map((i) => <div key={i} className="skeleton h-16" />)}</div>}
        {!loading && visible.length === 0 && (
          <div className="text-center py-12 px-6">
            <Users className="w-8 h-8 mx-auto mb-3" style={{ color: "var(--text-muted)" }} />
            <p className="text-sm mb-4" style={{ color: "var(--text-muted)" }}>{q ? "No conversations match." : "Add friends to start chatting."}</p>
            {!q && <Link to="/Friends" className="btn text-xs"><UserPlus className="w-3.5 h-3.5" /> Find friends</Link>}
          </div>
        )}
        {visible.map((c, i) => {
          const isActive = c.id === activeId;
          const title = c.type === "group" ? c.group.name : displayName(c.otherUser);
          const preview = c.last ? `${c.last.user_email === me.email ? "You: " : c.type === "group" ? `${c.last.user_display_name?.split(" ")[0]}: ` : ""}${messagePreview(c.last, me.email)}` : c.type === "group" ? `${c.group.member_emails.length} members` : "Say hi 👋";
          return (
            <motion.button key={c.id} onClick={() => open(c)} className="enter-side relative w-full flex items-center gap-3 p-2.5 rounded-2xl text-left transition-colors hover:bg-[var(--surface-2)]" style={{ "--d": `${Math.round((Math.min(i, 10) * 0.03) * 1000)}ms`, "--enter-x": "-10px" }}>
              {isActive && <motion.span initial={{ opacity: 0 }} animate={{ opacity: 1 }} className="absolute inset-0 rounded-2xl" style={{ background: "var(--pink-soft)", boxShadow: "inset 0 0 0 1px rgb(var(--accent-rgb) / 0.2)" }} transition={{ type: "spring", stiffness: 420, damping: 34 }} />}
              <span className="relative">{c.type === "group" ? <GroupIcon group={c.group} /> : <Avatar src={c.otherUser.profile_picture} name={title} size={44} online={isOnline(c.otherUser)} />}</span>
              <span className="relative flex-1 min-w-0">
                <span className="flex items-center gap-2">
                  <span className="text-sm font-bold truncate flex-1" style={{ color: "var(--text-primary)" }}>{title}</span>
                  {c.last && <span className="text-[10px] flex-shrink-0" style={{ color: "var(--text-muted)" }}>{timeAgo(c.last.created_date)}</span>}
                </span>
                <span className="flex items-center gap-2">
                  <span className="text-xs truncate flex-1" style={{ color: c.unread ? "var(--text-primary)" : "var(--text-muted)", fontWeight: c.unread ? 700 : 400 }}>{preview}</span>
                  {c.unread > 0 && <span className="min-w-[20px] h-5 px-1.5 rounded-full text-[10px] font-bold text-white flex items-center justify-center" style={{ background: "var(--accent-rose)" }}>{c.unread}</span>}
                </span>
              </span>
            </motion.button>
          );
        })}
      </div>
    </div>
  );

  const callButtons = inThisCall ? (
    <button onClick={() => voice.setExpanded(true)} className="btn !px-3 text-xs" style={{ background: "linear-gradient(90deg,#15803d,#22c55e)" }}><PhoneCall className="w-4 h-4" /> <span className="hidden sm:inline">Return to call</span></button>
  ) : (
    <>
      <button onClick={() => call(false)} disabled={calling} className="icon-btn" aria-label="Start voice call" title="Voice call">{calling ? <Loader2 className="w-5 h-5 animate-spin" /> : <Phone className="w-5 h-5" />}</button>
      <button onClick={() => call(true)} disabled={calling} className="icon-btn" aria-label="Start video call" title="Video call"><Video className="w-5 h-5" /></button>
    </>
  );

  const chat = active ? (
    <div className="flex flex-col h-full min-h-0">
      <div className="h-16 flex-shrink-0 flex items-center gap-3 px-3 sm:px-5 glass" style={{ borderBottom: "1px solid var(--border-c)" }}>
        <button onClick={close} className="icon-btn md:hidden" aria-label="Back to conversations"><ArrowLeft className="w-5 h-5" /></button>
        {active.type === "group" ? (
          <>
            <GroupIcon group={active.group} size={40} />
            <div className="flex-1 min-w-0">
              <p className="text-sm font-bold truncate" style={{ color: "var(--text-primary)" }}>{active.group.name}</p>
              <p className="text-xs" style={{ color: "var(--text-muted)" }}>{active.group.member_emails.length} members · {active.group.member_emails.filter((e) => isOnline(usersByEmail[e])).length} online</p>
            </div>
            {callButtons}
            <button onClick={() => setShowInfo(true)} className="icon-btn" aria-label="Group info"><Info className="w-5 h-5" /></button>
          </>
        ) : (
          <>
            <Link to={profileLink(active.otherUser.email)}><Avatar src={active.otherUser.profile_picture} name={displayName(active.otherUser)} size={40} online={isOnline(active.otherUser)} /></Link>
            <div className="flex-1 min-w-0">
              <Link to={profileLink(active.otherUser.email)} className="text-sm font-bold truncate block hover:underline" style={{ color: "var(--text-primary)" }}>{displayName(active.otherUser)}</Link>
              <p className="text-xs" style={{ color: isOnline(active.otherUser) ? "var(--success)" : "var(--text-muted)" }}>{isOnline(active.otherUser) ? "Online" : active.otherUser.last_seen ? `Active ${timeAgo(active.otherUser.last_seen)}` : "Offline"}</p>
            </div>
            {callButtons}
          </>
        )}
      </div>
      {joinable && (
        <motion.button initial={{ opacity: 0, y: -8 }} animate={{ opacity: 1, y: 0 }} onClick={() => call(false)} className="flex-shrink-0 flex items-center gap-3 px-4 py-2.5 text-left text-white" style={{ background: "linear-gradient(90deg, #15803d, #22c55e)" }}>
          <PhoneCall className="w-4 h-4 flex-shrink-0" />
          <span className="flex-1 min-w-0 text-sm font-semibold truncate">{liveCall.video ? "Video call" : "Call"} in progress · {inCallPeople.length} {inCallPeople.length === 1 ? "person" : "people"}</span>
          <span className="flex -space-x-2">{inCallPeople.slice(0, 4).map((p) => <Avatar key={p.id} src={p.user?.profile_picture} name={p.user?.display_name} size={22} style={{ boxShadow: "0 0 0 2px #16a34a", borderRadius: 9999 }} />)}</span>
          <span className="px-3 py-1 rounded-full text-xs font-bold" style={{ background: "rgb(255 255 255 / 0.22)" }}>Join</span>
        </motion.button>
      )}
      <div className="flex-1 min-h-0"><DMChatWindow key={active.id} conversation={active} me={me} onCall={call} /></div>
    </div>
  ) : (
    <div className="h-full flex flex-col items-center justify-center text-center gap-4 p-8">
      <div className="anim-bob w-20 h-20 rounded-[1.75rem] flex items-center justify-center text-white" style={{ animationDuration: "4s", background: "var(--accent-grad)", boxShadow: "var(--shadow-accent)" }}><MessageSquare className="w-9 h-9" /></div>
      <p className="font-display text-2xl font-semibold" style={{ color: "var(--text-primary)" }}>Your messages</p>
      <p className="text-sm max-w-xs" style={{ color: "var(--text-muted)" }}>Pick a conversation, or start a group with a few friends.</p>
      <button onClick={() => setShowNewGroup(true)} className="btn"><Plus className="w-4 h-4" /> New group</button>
    </div>
  );

  return (
    <div className="h-full flex min-h-0">
      <aside className={`${active ? "hidden md:flex" : "flex"} w-full md:w-[340px] flex-shrink-0 flex-col h-full glass`} style={{ borderRight: "1px solid var(--border-c)" }}>{list}</aside>
      <section className={`${active ? "flex" : "hidden md:flex"} flex-1 min-w-0 flex-col h-full`}>{chat}</section>
      <NewGroupModal open={showNewGroup} onClose={() => setShowNewGroup(false)} me={me} friends={friends} onCreated={(g) => setParams({ c: g.id })} />
      <GroupInfoModal open={showInfo} onClose={() => setShowInfo(false)} group={active?.group} me={me} friends={friends} usersByEmail={usersByEmail} onLeft={close} />
    </div>
  );
}
