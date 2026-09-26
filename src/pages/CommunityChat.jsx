import React, { useEffect, useMemo, useState } from "react";
import { Link, useNavigate, useSearchParams } from "react-router-dom";
import { AnimatePresence, motion } from "framer-motion";
import { ArrowLeft, Hash, Loader2, Menu, Server, Users } from "lucide-react";
import { base44 } from "@/api/base44Client";
import { useAuth } from "@/lib/AuthContext";
import { useLiveQuery } from "@/lib/useLiveQuery";
import { ensureMembership, joinServer, leaveServer } from "@/lib/servers";
import { toast } from "@/lib/toast";
import { displayName } from "@/lib/format";
import { EmptyState, CenterSpinner } from "@/components/common/Page";
import { useConfirm } from "@/components/common/Modal";
import Avatar from "@/components/common/Avatar";
import ServerSidebar from "@/components/server/ServerSidebar";
import ChatArea from "@/components/server/ChatArea";
import MemberList from "@/components/server/MemberList";
import ServerSettingsModal from "@/components/server/ServerSettingsModal";
import ChannelSettingsModal from "@/components/server/ChannelSettingsModal";
import AddChannelModal from "@/components/server/AddChannelModal";
import VoiceChannelView from "@/components/server/VoiceChannelView";
import ProfileCard from "@/components/server/ProfileCard";

export default function CommunityChatPage() {
  const navigate = useNavigate();
  const confirm = useConfirm();
  const { user: me } = useAuth();
  const [params, setParams] = useSearchParams();
  const communityId = params.get("id");
  const [showMembers, setShowMembers] = useState(() => window.innerWidth >= 1280);
  const [showSidebar, setShowSidebar] = useState(false);
  const [showSettings, setShowSettings] = useState(false);
  const [channelSettings, setChannelSettings] = useState(null);
  const [addChannel, setAddChannel] = useState(null);
  const [joining, setJoining] = useState(false);
  const [profileTarget, setProfileTarget] = useState(null); // { email, anchor, placement }
  const openProfile = (placement) => (email, anchor) => setProfileTarget({ email, anchor, placement });

  const { data: communities, loading } = useLiveQuery("Community", { id: communityId }, { enabled: !!communityId });
  const community = communities[0] || null;
  const isMember = !!community?.member_emails?.includes(me.email);
  const isOwner = community?.owner_email === me.email;
  const canManage = isOwner || me.role === "admin";
  const enabled = !!community;
  const { data: channels } = useLiveQuery("ServerChannel", { community_id: communityId }, { sort: "position", enabled });
  const { data: roles } = useLiveQuery("ServerRole", { community_id: communityId }, { sort: "position", enabled });
  const { data: memberRows, loading: membersLoading } = useLiveQuery("ServerMember", { community_id: communityId }, { enabled });
  const { data: users } = useLiveQuery("User", null, { live: false, enabled });
  const usersByEmail = useMemo(() => Object.fromEntries(users.map((u) => [u.email, u])), [users]);

  // Everyone in member_emails appears in the list, even before their ServerMember row exists.
  const members = useMemo(() => {
    const rows = Object.fromEntries(memberRows.map((m) => [m.user_email, m]));
    return (community?.member_emails || []).map((email) => {
      const u = usersByEmail[email];
      const row = rows[email] || { user_email: email, roles: [] };
      return { ...row, user_display_name: u ? displayName(u) : row.user_display_name || email.split("@")[0], user_profile_picture: u?.profile_picture || row.user_profile_picture || "" };
    });
  }, [community?.member_emails, memberRows, usersByEmail]);
  const myMember = members.find((m) => m.user_email === me.email);

  useEffect(() => {
    if (community && isMember && !membersLoading && !memberRows.some((m) => m.user_email === me.email)) ensureMembership(community, me).catch(() => {});
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [community?.id, isMember, membersLoading]);

  const channelId = params.get("channel");
  const activeChannel = channels.find((c) => c.id === channelId) || channels.find((c) => c.type !== "voice") || channels[0] || null;
  const selectChannel = (ch) => { setParams({ id: communityId, channel: ch.id }, { replace: true }); setShowSidebar(false); };

  const join = async () => {
    setJoining(true);
    try { await joinServer(community, me); toast.success(`Welcome to ${community.name}!`); } catch (e) { toast.error(e?.message || "Could not join."); }
    setJoining(false);
  };
  const leave = async () => {
    if (!(await confirm({ title: `Leave ${community.name}?`, message: "You can rejoin any time from the server list.", confirmLabel: "Leave server", danger: true }))) return;
    try { await leaveServer(community, me); toast("You left the server"); navigate("/Communities"); } catch (e) { toast.error(e?.message || "Could not leave."); }
  };
  const kick = async (member) => {
    if (!(await confirm({ title: `Kick ${member.user_display_name}?`, message: "They can rejoin unless you make the server private later.", confirmLabel: "Kick", danger: true }))) return;
    try {
      await base44.entities.Community.update(community.id, { member_emails: community.member_emails.filter((e) => e !== member.user_email) });
      if (member.id) await base44.entities.ServerMember.delete(member.id).catch(() => {});
      toast.success(`${member.user_display_name} was removed`);
    } catch (e) { toast.error(e?.message || "Could not kick member."); }
  };
  const changeRole = async (member, roleId, add) => {
    const next = add ? [...new Set([...(member.roles || []), roleId])] : (member.roles || []).filter((r) => r !== roleId);
    try {
      if (member.id) await base44.entities.ServerMember.update(member.id, { roles: next });
      else await base44.entities.ServerMember.create({ community_id: community.id, user_email: member.user_email, user_display_name: member.user_display_name, user_profile_picture: member.user_profile_picture, roles: next, nickname: "" });
    } catch (e) { toast.error(e?.message || "Could not update roles."); }
  };

  if (!communityId) return <EmptyState icon={Server} title="No server selected" action={<Link to="/Communities" className="btn">Browse servers</Link>} />;
  if (loading && !community) return <CenterSpinner />;
  if (!community) return <EmptyState icon={Server} title="Server not found" text="It may have been deleted." action={<Link to="/Communities" className="btn">Browse servers</Link>} />;

  if (!isMember && !canManage) {
    return (
      <div className="h-full overflow-y-auto flex items-center justify-center p-6 app-shell">
        <motion.div initial={{ opacity: 0, y: 20 }} animate={{ opacity: 1, y: 0 }} className="card !rounded-[2rem] overflow-hidden max-w-md w-full text-center">
          <div className="h-32 relative" style={{ background: "var(--accent-grad)" }}>{community.banner_url && <img src={community.banner_url} alt="" className="w-full h-full object-cover" />}</div>
          <div className="px-6 pb-7 -mt-10">
            <div className="w-20 h-20 rounded-3xl mx-auto flex items-center justify-center text-4xl overflow-hidden" style={{ background: "var(--surface)", boxShadow: "0 0 0 5px var(--surface), var(--shadow-md)" }}>{community.icon_url ? <img src={community.icon_url} alt="" className="w-full h-full object-cover" /> : community.icon_emoji || "💬"}</div>
            <h1 className="font-display text-3xl font-semibold mt-4" style={{ color: "var(--text-primary)" }}>{community.name}</h1>
            <p className="text-sm mt-2" style={{ color: "var(--text-muted)" }}>{community.description || "A cozy place to hang out."}</p>
            <div className="flex justify-center -space-x-2 mt-5">{members.slice(0, 6).map((m) => <Avatar key={m.user_email} src={m.user_profile_picture} name={m.user_display_name} size={34} style={{ boxShadow: "0 0 0 3px var(--surface)", borderRadius: 9999 }} />)}</div>
            <p className="text-xs mt-2" style={{ color: "var(--text-muted)" }}>{members.length} members · {channels.length} channels</p>
            <div className="flex gap-2 mt-6">
              <Link to="/Communities" className="btn-outline flex-1"><ArrowLeft className="w-4 h-4" /> Back</Link>
              <button onClick={join} disabled={joining} className="btn flex-1">{joining ? <Loader2 className="w-4 h-4 animate-spin" /> : "Join server"}</button>
            </div>
          </div>
        </motion.div>
      </div>
    );
  }

  const sidebar = (
    <ServerSidebar community={community} channels={channels} activeChannel={activeChannel} canManage={canManage} isOwner={isOwner} memberCount={members.length}
      onSelectChannel={selectChannel} onAddChannel={(type) => { setAddChannel(type); setShowSidebar(false); }} onChannelSettings={(ch) => { setChannelSettings(ch); setShowSidebar(false); }}
      onServerSettings={() => { setShowSettings(true); setShowSidebar(false); }} onMembers={() => { setShowMembers((v) => !v); setShowSidebar(false); }} onLeave={leave} />
  );

  return (
    <div className="h-full flex min-h-0 relative">
      <div className="hidden md:flex w-64 flex-shrink-0 h-full">{sidebar}</div>
      <AnimatePresence>
        {showSidebar && (
          <>
            <motion.div initial={{ opacity: 0 }} animate={{ opacity: 1 }} exit={{ opacity: 0 }} className="md:hidden fixed inset-0 z-[80] backdrop-blur-sm" style={{ background: "rgb(20 8 14 / 0.4)" }} onClick={() => setShowSidebar(false)} />
            <motion.div initial={{ x: "-100%" }} animate={{ x: 0 }} exit={{ x: "-100%" }} transition={{ type: "spring", damping: 32, stiffness: 320 }} className="md:hidden fixed left-0 top-0 bottom-0 w-[82vw] max-w-xs z-[90] flex safe-top safe-bottom" style={{ background: "var(--surface)" }}>{sidebar}</motion.div>
          </>
        )}
      </AnimatePresence>

      <main className="flex-1 min-w-0 h-full flex flex-col">
        {!activeChannel ? (
          <div className="h-full flex flex-col">
            <div className="h-14 flex items-center px-3 md:hidden"><button onClick={() => setShowSidebar(true)} className="icon-btn" aria-label="Channels"><Menu className="w-5 h-5" /></button></div>
            <EmptyState icon={Hash} title="No channels yet" text={canManage ? "Create the first channel to get chatting." : "The owner hasn't created any channels yet."} action={canManage && <button className="btn" onClick={() => setAddChannel("text")}>Create channel</button>} />
          </div>
        ) : activeChannel.type === "voice" ? (
          <div className="h-full flex flex-col min-h-0">
            <div className="h-14 flex-shrink-0 flex items-center gap-2 px-3 sm:px-5 glass" style={{ borderBottom: "1px solid var(--border-c)" }}>
              <button onClick={() => setShowSidebar(true)} className="icon-btn md:hidden" aria-label="Channels"><Menu className="w-5 h-5" /></button>
              <span className="font-bold flex-1 truncate" style={{ color: "var(--text-primary)" }}>🔊 {activeChannel.name}</span>
              <button onClick={() => setShowMembers((v) => !v)} className="icon-btn" data-active={showMembers} aria-label="Members"><Users className="w-4 h-4" /></button>
            </div>
            <div className="flex-1 min-h-0 flex flex-col"><VoiceChannelView key={activeChannel.id} channel={activeChannel} me={me} /></div>
          </div>
        ) : (
          <ChatArea channel={activeChannel} community={community} me={me} roles={roles} members={members} myRoleIds={myMember?.roles || []} canManage={canManage} onOpenSidebar={() => setShowSidebar(true)} onToggleMembers={() => setShowMembers((v) => !v)} showMembers={showMembers} onOpenProfile={openProfile("right-start")} />
        )}
      </main>

      <AnimatePresence initial={false}>
        {showMembers && (
          <motion.div initial={{ width: 0, opacity: 0 }} animate={{ width: 260, opacity: 1 }} exit={{ width: 0, opacity: 0 }} transition={{ type: "spring", damping: 32, stiffness: 320 }} className="hidden lg:flex flex-shrink-0 h-full overflow-hidden">
            <div className="w-[260px] h-full"><MemberList members={members} roles={roles} usersByEmail={usersByEmail} community={community} onOpenProfile={openProfile("left-start")} onClose={() => setShowMembers(false)} /></div>
          </motion.div>
        )}
      </AnimatePresence>
      <AnimatePresence>
        {showMembers && (
          <motion.div initial={{ x: "100%" }} animate={{ x: 0 }} exit={{ x: "100%" }} transition={{ type: "spring", damping: 32, stiffness: 320 }} className="lg:hidden fixed right-0 top-0 bottom-0 w-[82vw] max-w-xs z-[90] flex safe-top safe-bottom" style={{ background: "var(--surface)", boxShadow: "var(--shadow-lg)" }}>
            <MemberList members={members} roles={roles} usersByEmail={usersByEmail} community={community} onOpenProfile={openProfile("left-start")} onClose={() => setShowMembers(false)} />
          </motion.div>
        )}
      </AnimatePresence>

      <ProfileCard
        target={profileTarget}
        onClose={() => setProfileTarget(null)}
        user={profileTarget ? usersByEmail[profileTarget.email] : null}
        member={profileTarget ? members.find((m) => m.user_email === profileTarget.email) : null}
        roles={roles}
        community={community}
        me={me}
        canManage={canManage}
        onRoleChange={changeRole}
        onKick={kick}
      />
      <ServerSettingsModal open={showSettings} community={community} members={members} roles={roles} usersByEmail={usersByEmail} me={me} onClose={() => setShowSettings(false)} onKick={kick} onRoleChange={changeRole} />
      <ChannelSettingsModal channel={channelSettings} roles={roles} onClose={() => setChannelSettings(null)} onDeleted={(ch) => { if (ch.id === activeChannel?.id) setParams({ id: communityId }, { replace: true }); }} />
      <AddChannelModal open={!!addChannel} defaultType={addChannel || "text"} communityId={communityId} channelCount={channels.length} onClose={() => setAddChannel(null)} onCreated={(ch) => selectChannel(ch)} />
    </div>
  );
}
