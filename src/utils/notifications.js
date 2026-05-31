import { base44 } from "@/api/base44Client";
export async function notify({ to_email, from_email, from_display_name, from_profile_picture, type, message, link, entity_id }) {
  if (!to_email || to_email === from_email) return;
  try { await base44.entities.Notification.create({ to_email, from_email: from_email||"", from_display_name: from_display_name||"", from_profile_picture: from_profile_picture||"", type, message, link: link||"", entity_id: entity_id||"", is_read: false }); }
  catch (e) { console.warn("Notification failed:", e); }
}