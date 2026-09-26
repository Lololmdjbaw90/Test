// Site owners are always admins and are the only people who can make or
// remove other admins (Admin panel → Users). Keep this list in sync with
// siteOwners() in firestore.rules.
export const SITE_OWNERS = ["paologionfriddo90@gmail.com"];

export const isSiteOwner = (email) => SITE_OWNERS.includes(String(email || "").trim().toLowerCase());
