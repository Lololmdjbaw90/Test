import { base44 } from "@/api/base44Client";
import { displayName } from "@/lib/format";

export const SERVER_TEMPLATES = [
  {
    id: "art",
    label: "Art community",
    emoji: "🎨",
    channels: [
      { name: "general", type: "text", description: "Say hi and hang out" },
      { name: "showcase", type: "text", description: "Share finished work" },
      { name: "wip-and-critique", type: "text", description: "Works in progress & friendly feedback" },
      { name: "Studio", type: "voice", description: "Draw together" },
    ],
  },
  {
    id: "friends",
    label: "Friends hangout",
    emoji: "🫶",
    channels: [
      { name: "general", type: "text", description: "Everything and anything" },
      { name: "memes", type: "text", description: "The good stuff" },
      { name: "Lounge", type: "voice", description: "Hop in" },
    ],
  },
  { id: "blank", label: "Start from scratch", emoji: "✨", channels: [{ name: "general", type: "text", description: "General chat" }] },
];

export async function createServer({ me, name, description, icon_emoji, icon_url, banner_url, welcome_message, template }) {
  const community = await base44.entities.Community.create({
    name, description, icon_emoji, icon_url: icon_url || "", banner_url: banner_url || "", welcome_message,
    owner_email: me.email, owner_display_name: displayName(me), member_emails: [me.email],
  });
  const tpl = SERVER_TEMPLATES.find((t) => t.id === template) || SERVER_TEMPLATES[2];
  for (const [position, ch] of tpl.channels.entries()) {
    await base44.entities.ServerChannel.create({ community_id: community.id, ...ch, position, allowed_roles: [] });
  }
  await base44.entities.ServerRole.create({ community_id: community.id, name: "Moderator", color: "#d9577f", permissions: { pin_messages: true, manage_messages: true, kick_members: true, mention_roles: true }, position: 0 });
  await base44.entities.ServerRole.create({ community_id: community.id, name: "Member", color: "#64748b", permissions: {}, position: 1 });
  await ensureMembership(community, me);
  return community;
}

// Creates the signed-in user's ServerMember row if it doesn't exist yet.
export async function ensureMembership(community, me) {
  const existing = await base44.entities.ServerMember.filter({ community_id: community.id, user_email: me.email });
  if (existing.length) return existing[0];
  return base44.entities.ServerMember.create({ community_id: community.id, user_email: me.email, user_display_name: displayName(me), user_profile_picture: me.profile_picture || "", roles: [], nickname: "" });
}

export async function joinServer(community, me) {
  await base44.entities.Community.changeMembership(community.id, me.email, true);
  await ensureMembership(community, me);
  const channels = await base44.entities.ServerChannel.filter({ community_id: community.id }, "position").catch(() => []);
  const general = channels.find((c) => c.type !== "voice");
  if (general) {
    await base44.entities.ChannelMessage.create({
      channel_id: general.id, community_id: community.id, type: "join", content: `${displayName(me)} joined the server`, image_url: "",
      user_email: me.email, user_display_name: displayName(me), user_profile_picture: me.profile_picture || "",
      reply_to_id: "", reply_to_preview: "", reactions: {}, is_pinned: false, is_edited: false,
    }).catch(() => {});
  }
}

export async function leaveServer(community, me) {
  await base44.entities.Community.changeMembership(community.id, me.email, false);
  const rows = await base44.entities.ServerMember.filter({ community_id: community.id, user_email: me.email }).catch(() => []);
  await Promise.all(rows.map((r) => base44.entities.ServerMember.delete(r.id).catch(() => {})));
}
