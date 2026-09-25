export function displayName(user) {
  if (!user) return "Someone";
  return user.display_name || user.user_display_name || user.full_name || (user.email || user.user_email || "Someone").split("@")[0];
}

export function initials(name) {
  return String(name || "?").trim().charAt(0).toUpperCase() || "?";
}

export function timeAgo(date) {
  if (!date) return "";
  const diff = Date.now() - new Date(date).getTime();
  const m = Math.floor(diff / 60000);
  if (m < 1) return "just now";
  if (m < 60) return `${m}m ago`;
  const h = Math.floor(m / 60);
  if (h < 24) return `${h}h ago`;
  const d = Math.floor(h / 24);
  if (d < 7) return `${d}d ago`;
  return new Date(date).toLocaleDateString(undefined, { month: "short", day: "numeric" });
}

export function clockTime(date) {
  return date ? new Date(date).toLocaleTimeString([], { hour: "numeric", minute: "2-digit" }) : "";
}

export function dayLabel(date) {
  const d = new Date(date);
  const today = new Date();
  const yesterday = new Date(Date.now() - 86400000);
  if (d.toDateString() === today.toDateString()) return "Today";
  if (d.toDateString() === yesterday.toDateString()) return "Yesterday";
  return d.toLocaleDateString(undefined, { weekday: "long", month: "short", day: "numeric" });
}

export function compactNumber(n) {
  return new Intl.NumberFormat(undefined, { notation: "compact", maximumFractionDigits: 1 }).format(n || 0);
}

export function isOnline(user) {
  return !!user?.last_seen && Date.now() - new Date(user.last_seen).getTime() < 5 * 60 * 1000;
}

export function profileLink(email) {
  return `/Profile?email=${encodeURIComponent(email || "")}`;
}

export function greeting() {
  const h = new Date().getHours();
  if (h < 5) return "Up late";
  if (h < 12) return "Good morning";
  if (h < 18) return "Good afternoon";
  return "Good evening";
}

export function isNitro(user) {
  if (!user?.nitro_active) return false;
  return !user.nitro_until || new Date(user.nitro_until).getTime() > Date.now();
}
