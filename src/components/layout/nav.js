import { Home, Grid2X2, Users, Music, Crown, MessageCircle, UserCheck, Server, Store, Upload, ClipboardList, Shield, Settings, UserCircle } from "lucide-react";

export const NAV_SECTIONS = [
  {
    label: "Discover",
    items: [
      { label: "Home", path: "/", icon: Home },
      { label: "Gallery", path: "/Gallery", icon: Grid2X2 },
      { label: "Community", path: "/Community", icon: Users },
      { label: "Music", path: "/Music", icon: Music },
      { label: "Top Artists", path: "/TopArtists", icon: Crown },
    ],
  },
  {
    label: "Connect",
    items: [
      { label: "Messages", path: "/DirectMessages", icon: MessageCircle, badge: "dms" },
      { label: "Friends", path: "/Friends", icon: UserCheck, badge: "friends" },
      { label: "Servers", path: "/Communities", icon: Server },
    ],
  },
  {
    label: "Create",
    items: [
      { label: "Commissions", path: "/Commissions", icon: Store },
    ],
  },
];

export const ADMIN_SECTION = {
  label: "Admin",
  items: [
    { label: "Upload Art", path: "/Upload", icon: Upload },
    { label: "Logs", path: "/Logs", icon: ClipboardList },
    { label: "Admin Panel", path: "/Admin", icon: Shield },
  ],
};

export const ACCOUNT_ITEMS = [
  { label: "Profile", path: "/Profile", icon: UserCircle },
  { label: "Settings", path: "/Settings", icon: Settings },
];

export const MOBILE_NAV = [
  { label: "Home", path: "/", icon: Home },
  { label: "Gallery", path: "/Gallery", icon: Grid2X2 },
  { label: "create" },
  { label: "Chat", path: "/DirectMessages", icon: MessageCircle, badge: "dms" },
  { label: "Servers", path: "/Communities", icon: Server },
];

export function isActivePath(pathname, path) {
  if (path === "/") return pathname === "/" || pathname === "/Home";
  return pathname.toLowerCase() === path.toLowerCase();
}
