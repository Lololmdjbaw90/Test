import { LayoutGrid, Home, Grid2X2, Users, Music, Crown, MessageCircle, UserCheck, Server, Store, Upload, ClipboardList, Shield, Settings, UserCircle, Clapperboard, Megaphone } from "lucide-react";

export const NAV_SECTIONS = [
  {
    label: "Discover",
    items: [
      { label: "Home", path: "/", icon: Home },
      { label: "Gallery", path: "/Gallery", icon: Grid2X2 },
      { label: "Community", path: "/Community", icon: Users },
      { label: "Reels", path: "/Reels", icon: Clapperboard },
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
      { label: "What's new", path: "/Updates", icon: Megaphone, badge: "updates" },
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

// Everything else is in the menu behind your avatar (top right).
export const MOBILE_NAV = [
  { label: "Home", path: "/", icon: Home },
  { label: "Community", path: "/Community", icon: Users },
  { label: "create" },
  { label: "Reels", path: "/Reels", icon: Clapperboard },
  { label: "Chat", path: "/DirectMessages", icon: MessageCircle, badge: "dms" },
];
export const MORE_ICON = LayoutGrid;

export function isActivePath(pathname, path) {
  if (path === "/") return pathname === "/" || pathname === "/Home";
  return pathname.toLowerCase() === path.toLowerCase();
}
