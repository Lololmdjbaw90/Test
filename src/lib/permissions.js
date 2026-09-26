// Server role permissions (Discord-style).
// -----------------------------------------------------------------------------
// - Every member gets the server's "@everyone" permissions.
// - Roles add permissions on top. "Administrator" grants everything.
// - Roles are ordered by `position` (0 = highest). You can only manage roles
//   and people ranked below your own highest role; the owner outranks all.
// - Channels can be private (only chosen roles can see them) or limit who can
//   post; managers of channels always get in.
// The UI uses these helpers directly. The Firestore rules can't search member
// rows, so moderation permissions are also copied into `Community.perm_index`
// ({ permission: [emails] }), which the rules read — see syncPermIndex().
// -----------------------------------------------------------------------------
import { base44 } from "@/api/base44Client";

export const PERMISSION_GROUPS = [
  {
    label: "General",
    items: [
      { key: "administrator", label: "Administrator", desc: "Every permission below, and can manage everything. Give this out carefully." },
      { key: "manage_server", label: "Manage server", desc: "Change the name, icon, banner, description and welcome message." },
      { key: "manage_channels", label: "Manage channels", desc: "Create, edit and delete channels, and see private ones." },
      { key: "manage_roles", label: "Manage roles", desc: "Create and edit roles below their own, and give them to members." },
      { key: "kick_members", label: "Kick members", desc: "Remove members whose highest role is below theirs." },
      { key: "create_invite", label: "Create invites", desc: "Copy the server's invite link." },
    ],
  },
  {
    label: "Text channels",
    items: [
      { key: "send_messages", label: "Send messages", desc: "Post in text channels." },
      { key: "attach_files", label: "Attach images", desc: "Upload pictures in messages." },
      { key: "add_reactions", label: "Add reactions", desc: "React to messages with emoji." },
      { key: "mention_roles", label: "Mention roles & @everyone", desc: "Notify everyone with a role, or the whole server." },
      { key: "pin_messages", label: "Pin messages", desc: "Pin and unpin messages in channels." },
      { key: "manage_messages", label: "Manage messages", desc: "Delete other people's messages and pin them." },
    ],
  },
  {
    label: "Voice channels",
    items: [
      { key: "connect", label: "Connect", desc: "Join voice channels." },
      { key: "speak", label: "Speak", desc: "Talk in voice channels (otherwise they join muted)." },
      { key: "video", label: "Video & screen share", desc: "Turn on the camera or share the screen in voice channels." },
    ],
  },
];
export const PERMISSION_KEYS = PERMISSION_GROUPS.flatMap((g) => g.items.map((i) => i.key));

// What every member can do unless the server changes it.
export const EVERYONE_DEFAULTS = {
  create_invite: true, send_messages: true, attach_files: true, add_reactions: true,
  mention_roles: false, connect: true, speak: true, video: true,
};

// Permissions the Firestore rules need to check (kept in Community.perm_index).
export const INDEXED_PERMISSIONS = ["manage_server", "manage_channels", "manage_roles", "kick_members", "manage_messages", "pin_messages"];

// Older roles stored can_* flags.
const LEGACY = { can_pin_messages: "pin_messages", can_manage_messages: "manage_messages" };
export function normalizePerms(p = {}) {
  const out = {};
  Object.entries(p || {}).forEach(([k, v]) => { out[LEGACY[k] || k] = !!v; });
  return out;
}

const ALL = Object.fromEntries(PERMISSION_KEYS.map((k) => [k, true]));
const sortRoles = (roles) => [...roles].sort((a, b) => (a.position ?? 0) - (b.position ?? 0));
export const everyonePerms = (community) => ({ ...EVERYONE_DEFAULTS, ...(community?.everyone_permissions || {}) });

// Effective permissions for `email` (defaults to `me`).
// Returns { perms, isOwner, top, roleIds } — `top` is the highest role position
// (lower = more senior; the owner / site admins are -Infinity).
export function computePermissions({ community, me, member, roles = [], email }) {
  const who = email || me?.email;
  if (!community || !who) return { perms: {}, isOwner: false, top: Infinity, roleIds: [] };
  const isOwner = community.owner_email === who;
  const siteAdmin = !email && me?.role === "admin";
  const roleIds = member?.roles || [];
  const mine = sortRoles(roles).filter((r) => roleIds.includes(r.id));
  if (isOwner || siteAdmin) return { perms: { ...ALL }, isOwner, top: -Infinity, roleIds };
  const perms = { ...everyonePerms(community) };
  mine.forEach((r) => Object.entries(normalizePerms(r.permissions)).forEach(([k, v]) => { if (v) perms[k] = true; }));
  const top = mine.length ? Math.min(...mine.map((r) => r.position ?? 0)) : Infinity;
  if (perms.administrator) return { perms: { ...ALL }, isOwner, top, roleIds };
  return { perms, isOwner, top, roleIds };
}

// Can `actor` edit / hand out this role?
export const canEditRole = (actor, role) => !!actor.perms.manage_roles && (actor.top === -Infinity || (role.position ?? 0) > actor.top);

// Can `actor` moderate (kick, change roles of) a member ranked `targetTop`?
export function canActOn(actor, target, community) {
  if (!target || target.email === community?.owner_email) return false;
  if (actor.top === -Infinity) return true;
  return target.top > actor.top;
}

// What a member can do in a channel.
export function channelAccess(channel, actor, roles = []) {
  const allowed = channel?.allowed_roles || [];
  const names = roles.filter((r) => actor.roleIds.includes(r.id)).map((r) => r.name);
  const inRole = allowed.some((a) => actor.roleIds.includes(a) || names.includes(a)); // ids, or names on older channels
  const bypass = !!(actor.perms.administrator || actor.perms.manage_channels);
  const view = !channel?.private || !allowed.length || inRole || bypass;
  const post = channel?.type === "voice" ? false : !!actor.perms.send_messages && (!allowed.length || inRole || bypass);
  return { view, post, connect: view && !!actor.perms.connect, speak: !!actor.perms.speak, video: !!actor.perms.video };
}

// ---------- Firestore permission index ----------
export function buildPermIndex(community, roles = [], members = []) {
  const index = Object.fromEntries(INDEXED_PERMISSIONS.map((k) => [k, []]));
  members.forEach((m) => {
    if (!m.user_email || m.user_email === community.owner_email) return;
    const { perms } = computePermissions({ community, member: m, roles, email: m.user_email });
    INDEXED_PERMISSIONS.forEach((k) => { if (perms[k]) index[k].push(m.user_email); });
  });
  INDEXED_PERMISSIONS.forEach((k) => index[k].sort());
  return index;
}

// Writes the index when it's out of date. Only people who can manage roles
// (or the owner) may write it; everyone else just skips.
export async function syncPermIndex(community, roles, members) {
  if (!community) return;
  const next = buildPermIndex(community, roles, members.filter((m) => (community.member_emails || []).includes(m.user_email)));
  const stable = (o) => JSON.stringify(Object.keys(o || {}).sort().map((k) => [k, [...(o[k] || [])].sort()]));
  if (stable(next) === stable(community.perm_index)) return;
  await base44.entities.Community.update(community.id, { perm_index: next }).catch((e) => console.warn("[permissions] index not updated:", e?.message));
}
