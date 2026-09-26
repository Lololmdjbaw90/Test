import React, { useMemo, useState } from "react";
import { Link, useNavigate } from "react-router-dom";
import { AnimatePresence, motion } from "framer-motion";
import { Check, Clock, Loader2, MessageSquare, UserCheck, UserMinus, UserPlus, Users, X } from "lucide-react";
import { base44 } from "@/api/base44Client";
import { useAuth } from "@/lib/AuthContext";
import { useLiveQuery } from "@/lib/useLiveQuery";
import { useFriendships, splitFriendships } from "@/lib/social";
import { buildTaste, suggestPeople } from "@/lib/ranking";
import { toast } from "@/lib/toast";
import { displayName, isOnline, profileLink, timeAgo } from "@/lib/format";
import { notify } from "@/utils/notifications";
import { Page, PageHeader, EmptyState } from "@/components/common/Page";
import { SearchInput, Segmented } from "@/components/common/Controls";
import { useConfirm } from "@/components/common/Modal";
import Avatar from "@/components/common/Avatar";
import { useBlocked } from "@/lib/safety";

function PersonCard({ person, subtitle, children, index }) {
  return (
    <motion.div exit={{ opacity: 0, scale: 0.95 }} className="enter card-sm p-4 flex items-center gap-3" style={{ "--d": `${Math.round((Math.min(index, 12) * 0.03) * 1000)}ms`, "--enter-y": "16px" }}>
      <Link to={profileLink(person.email)}><Avatar src={person.profile_picture} name={displayName(person)} size={48} online={isOnline(person)} nitro={person.nitro_active} /></Link>
      <div className="flex-1 min-w-0">
        <Link to={profileLink(person.email)} className="block text-sm font-bold truncate hover:underline" style={{ color: "var(--text-primary)" }}>{displayName(person)}</Link>
        <p className="text-xs truncate" style={{ color: isOnline(person) ? "var(--success)" : "var(--text-muted)" }}>{subtitle}</p>
      </div>
      <div className="flex gap-1.5 flex-shrink-0">{children}</div>
    </motion.div>
  );
}

export default function FriendsPage() {
  const navigate = useNavigate();
  const { user: me } = useAuth();
  const confirm = useConfirm();
  const [tab, setTab] = useState("friends");
  const [search, setSearch] = useState("");
  const [busy, setBusy] = useState(null);
  // Most recently active people; enough for Discover and for fresh avatars.
  const { data: users, loading: usersLoading } = useLiveQuery("User", null, { sort: "-last_seen", limit: 300 });
  const { friendships, loading } = useFriendships(me?.email);
  const blocked = useBlocked();
  const { accepted, incoming: allIncoming, outgoing, other, friendEmails } = useMemo(() => splitFriendships(friendships, me?.email), [friendships, me?.email]);
  const incoming = allIncoming.filter((f) => !blocked.has(f.requester_email));
  const byEmail = useMemo(() => Object.fromEntries(users.map((u) => [u.email, u])), [users]);
  const personFor = (f) => {
    const email = other(f);
    const incomingSide = f.requester_email === email;
    return byEmail[email] || { email, display_name: incomingSide ? f.requester_display_name : f.receiver_display_name, profile_picture: incomingSide ? f.requester_profile_picture : f.receiver_profile_picture };
  };
  const q = search.trim().toLowerCase();
  const matches = (p) => !q || displayName(p).toLowerCase().includes(q) || String(p.email || "").includes(q);
  const connected = useMemo(() => new Set(friendships.map(other)), [friendships, other]);
  // Discover is ranked by the recommendation engine (mutual follows, shared
  // interests, activity...) and shows why each person is suggested. It's only
  // worked out while the Discover tab is open.
  const taste = useMemo(() => (tab === "discover" ? buildTaste({ me, friends: friendEmails }) : null), [tab, me?.email, me?.following, me?.interests, friendEmails]); // eslint-disable-line react-hooks/exhaustive-deps
  const discover = useMemo(() => (taste ? suggestPeople(users.filter((u) => matches(u) && !blocked.has(u.email)), { me, taste, limit: 60, exclude: connected }) : []), [users, taste, connected, q, blocked]); // eslint-disable-line react-hooks/exhaustive-deps
  const friends = accepted.map((f) => ({ f, p: personFor(f) })).filter(({ p }) => matches(p)).sort((a, b) => Number(isOnline(b.p)) - Number(isOnline(a.p)));

  const run = async (key, fn) => { setBusy(key); try { await fn(); } catch (e) { toast.error(e?.message || "Something went wrong."); } setBusy(null); };
  const sendRequest = (u) => run(u.email, async () => {
    await base44.entities.Friendship.create({ requester_email: me.email, requester_display_name: displayName(me), requester_profile_picture: me.profile_picture || "", receiver_email: u.email, receiver_display_name: displayName(u), receiver_profile_picture: u.profile_picture || "", status: "pending" });
    await notify({ to_email: u.email, from_email: me.email, from_display_name: displayName(me), from_profile_picture: me.profile_picture, type: "friend_request", message: `${displayName(me)} sent you a friend request`, link: "/Friends" });
    toast.success(`Request sent to ${displayName(u)}`);
  });
  const respond = (f, status) => run(f.id, async () => {
    if (status === "accepted") {
      await base44.entities.Friendship.update(f.id, { status });
      await notify({ to_email: f.requester_email, from_email: me.email, from_display_name: displayName(me), from_profile_picture: me.profile_picture, type: "friend_accepted", message: `${displayName(me)} accepted your friend request`, link: "/Friends" });
      toast.success(`You're now friends with ${f.requester_display_name}`);
    } else {
      await base44.entities.Friendship.delete(f.id);
    }
  });
  const remove = async (f, label) => {
    const ok = await confirm({ title: label === "cancel" ? "Cancel request?" : `Remove ${displayName(personFor(f))}?`, message: label === "cancel" ? undefined : "You can always add them again later.", confirmLabel: label === "cancel" ? "Cancel request" : "Remove friend", danger: label !== "cancel" });
    if (ok) run(f.id, () => base44.entities.Friendship.delete(f.id));
  };

  const tabs = [
    { id: "friends", label: "Friends", icon: UserCheck, count: accepted.length },
    { id: "requests", label: "Requests", icon: Clock, count: incoming.length },
    { id: "discover", label: "Discover", icon: UserPlus },
  ];

  return (
    <Page width="max-w-4xl">
      <PageHeader eyebrow="Your people" title="Friends" subtitle={`${accepted.length} friends · ${accepted.filter((f) => isOnline(personFor(f))).length} online now`} icon={Users}>
        <div className="flex flex-col sm:flex-row gap-3 sm:items-center">
          <Segmented options={tabs} value={tab} onChange={setTab} size="sm" />
          <SearchInput value={search} onChange={setSearch} placeholder="Search people…" className="sm:w-64 sm:ml-auto" />
        </div>
      </PageHeader>

      {loading || (tab === "discover" && usersLoading) ? (
        <div className="grid sm:grid-cols-2 gap-3">{Array.from({ length: 4 }).map((_, i) => <div key={i} className="skeleton h-20" />)}</div>
      ) : (
        <AnimatePresence mode="wait">
          <motion.div key={tab} initial={{ opacity: 0, y: 10 }} animate={{ opacity: 1, y: 0 }} exit={{ opacity: 0 }} transition={{ duration: 0.2 }}>
            {tab === "friends" && (friends.length === 0 ? (
              <EmptyState icon={Users} title={q ? "No matching friends" : "No friends yet"} text="Find people in Discover and send a friend request." action={<button className="btn" onClick={() => setTab("discover")}>Discover people</button>} />
            ) : (
              <div className="grid sm:grid-cols-2 gap-3">
                <AnimatePresence>
                  {friends.map(({ f, p }, i) => (
                    <PersonCard key={f.id} person={p} index={i} subtitle={isOnline(p) ? "Online now" : `Active ${timeAgo(p.last_seen)}`}>
                      <button onClick={() => navigate(`/DirectMessages?with=${encodeURIComponent(p.email)}`)} className="btn !px-3" aria-label={`Message ${displayName(p)}`}><MessageSquare className="w-4 h-4" /></button>
                      <button onClick={() => remove(f)} disabled={busy === f.id} className="icon-btn icon-btn-bordered" aria-label={`Remove ${displayName(p)}`}><UserMinus className="w-4 h-4" /></button>
                    </PersonCard>
                  ))}
                </AnimatePresence>
              </div>
            ))}

            {tab === "requests" && (incoming.length === 0 && outgoing.length === 0 ? (
              <EmptyState icon={Clock} title="No pending requests" text="Requests you send and receive show up here." />
            ) : (
              <div className="space-y-8">
                {incoming.length > 0 && (
                  <div>
                    <p className="eyebrow mb-3">Received · {incoming.length}</p>
                    <div className="grid sm:grid-cols-2 gap-3">
                      {incoming.map((f, i) => (
                        <PersonCard key={f.id} person={personFor(f)} index={i} subtitle={`Sent ${timeAgo(f.created_date)}`}>
                          <button onClick={() => respond(f, "accepted")} disabled={busy === f.id} className="btn !px-3" aria-label="Accept">{busy === f.id ? <Loader2 className="w-4 h-4 animate-spin" /> : <Check className="w-4 h-4" />}</button>
                          <button onClick={() => respond(f, "rejected")} disabled={busy === f.id} className="icon-btn icon-btn-bordered" aria-label="Decline"><X className="w-4 h-4" /></button>
                        </PersonCard>
                      ))}
                    </div>
                  </div>
                )}
                {outgoing.length > 0 && (
                  <div>
                    <p className="eyebrow mb-3">Sent · {outgoing.length}</p>
                    <div className="grid sm:grid-cols-2 gap-3">
                      {outgoing.map((f, i) => (
                        <PersonCard key={f.id} person={personFor(f)} index={i} subtitle="Waiting for a response…">
                          <button onClick={() => remove(f, "cancel")} disabled={busy === f.id} className="btn-outline text-xs">Cancel</button>
                        </PersonCard>
                      ))}
                    </div>
                  </div>
                )}
              </div>
            ))}

            {tab === "discover" && (discover.length === 0 ? (
              <EmptyState icon={UserPlus} title={q ? "No one found" : "You know everyone!"} text={q ? "Try a different name or email." : "Invite friends to join Sugerly."} />
            ) : (
              <div className="grid sm:grid-cols-2 gap-3">
                {discover.map(({ user: u, reason }, i) => (
                  <PersonCard key={u.email} person={u} index={i} subtitle={reason === "Suggested for you" || reason === "Recently active" ? u.bio || (isOnline(u) ? "Online now" : `Active ${timeAgo(u.last_seen)}`) : reason}>
                    <button onClick={() => sendRequest(u)} disabled={busy === u.email} className="btn !px-3" aria-label={`Add ${displayName(u)}`}>{busy === u.email ? <Loader2 className="w-4 h-4 animate-spin" /> : <UserPlus className="w-4 h-4" />}</button>
                  </PersonCard>
                ))}
              </div>
            ))}
          </motion.div>
        </AnimatePresence>
      )}
    </Page>
  );
}
