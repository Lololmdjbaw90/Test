import React, { useEffect, useRef, useState } from "react";
import { Link } from "react-router-dom";
import { motion } from "framer-motion";
import { Camera, Check, Database, Download, Smartphone, ImagePlus, Loader2, LogOut, Monitor, Moon, Palette, RotateCcw, Save, Settings as SettingsIcon, Shield, Sun, Trash2, User, Volume2 } from "lucide-react";
import { base44, backendMode } from "@/api/base44Client";
import { useAuth } from "@/lib/AuthContext";
import { ACCENTS, applyTheme } from "@/lib/theme";
import { toast } from "@/lib/toast";
import { displayName, profileLink } from "@/lib/format";
import { Page, PageHeader } from "@/components/common/Page";
import Modal, { useConfirm } from "@/components/common/Modal";
import Avatar from "@/components/common/Avatar";
import ImageCropper from "@/components/common/ImageCropper";
import AdminSiteSettings from "@/components/admin/AdminSiteSettings";
import { InstallCard } from "@/components/layout/InstallApp";
import { BlockedPeople, DeleteAccount } from "@/components/safety/AccountSafety";
import { Toggle } from "@/components/common/Controls";
import { haptic, playSound, useFeedbackPrefs } from "@/lib/feedback";

const INTERESTS = ["Painting", "Digital art", "Drawing", "Photography", "3D", "Pixel art", "Animation", "Music", "Lo-fi", "Writing", "Crafts", "Fashion"];
const SECTIONS = [
  { id: "profile", label: "Profile", icon: User },
  { id: "appearance", label: "Appearance", icon: Palette },
  { id: "feedback", label: "Sounds & haptics", icon: Volume2 },
  { id: "app", label: "Get the app", icon: Smartphone },
  { id: "account", label: "Account & data", icon: Database },
];

function Section({ id, icon: Icon, title, subtitle, children }) {
  return (
    <motion.section id={id} initial={{ opacity: 0, y: 16 }} whileInView={{ opacity: 1, y: 0 }} viewport={{ once: true, margin: "-40px" }} className="card p-5 sm:p-7 scroll-mt-24">
      <div className="flex items-center gap-3 mb-6">
        <span className="w-10 h-10 rounded-2xl flex items-center justify-center" style={{ background: "var(--pink-soft)", color: "var(--accent-rose)" }}><Icon className="w-5 h-5" /></span>
        <div>
          <h2 className="font-display text-xl font-semibold" style={{ color: "var(--text-primary)" }}>{title}</h2>
          {subtitle && <p className="text-xs" style={{ color: "var(--text-muted)" }}>{subtitle}</p>}
        </div>
      </div>
      {children}
    </motion.section>
  );
}

export default function SettingsPage() {
  const { user, isAdmin, updateMe, logout } = useAuth();
  const [fb, setFb] = useFeedbackPrefs();
  const confirm = useConfirm();
  const bannerRef = useRef(null);
  const [form, setForm] = useState({ display_name: "", bio: "", interests: [], banner_color: "", theme: "light", accent: "rose" });
  const [picFile, setPicFile] = useState(null);
  const [picPreview, setPicPreview] = useState(null);
  const [cropSrc, setCropSrc] = useState(null);
  const [bannerFile, setBannerFile] = useState(null);
  const [bannerPreview, setBannerPreview] = useState(null);
  const [saving, setSaving] = useState(false);

  useEffect(() => {
    if (!user) return;
    setForm({ display_name: user.display_name || "", bio: user.bio || "", interests: user.interests || [], banner_color: user.banner_color || "", theme: user.theme || "light", accent: user.accent || "rose" });
    setPicPreview(user.profile_picture || null);
    setBannerPreview(user.banner_url || null);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [user?.id]);

  const dirty = user && (
    form.display_name !== (user.display_name || "") || form.bio !== (user.bio || "") || form.banner_color !== (user.banner_color || "") ||
    JSON.stringify(form.interests) !== JSON.stringify(user.interests || []) || picFile || bannerFile || (bannerPreview || null) !== (user.banner_url || null) || (picPreview || null) !== (user.profile_picture || null)
  );

  const setAppearance = async (patch) => {
    setForm((f) => ({ ...f, ...patch }));
    applyTheme(patch);
    try { await updateMe(patch); } catch (e) { toast.error(e?.message || "Could not save appearance."); }
  };

  const save = async () => {
    if (!form.display_name.trim()) { toast.error("Display name can't be empty"); return; }
    setSaving(true);
    try {
      let profile_picture = picPreview ? user.profile_picture || "" : "";
      if (picFile) profile_picture = (await base44.integrations.Core.UploadFile({ file: picFile })).file_url;
      let banner_url = bannerPreview ? user.banner_url || "" : "";
      if (bannerFile) banner_url = (await base44.integrations.Core.UploadFile({ file: bannerFile })).file_url;
      await updateMe({ display_name: form.display_name.trim(), full_name: form.display_name.trim(), bio: form.bio.trim(), interests: form.interests, banner_color: form.banner_color, profile_picture, banner_url });
      setPicFile(null);
      setBannerFile(null);
      toast.success("Profile saved");
    } catch (e) { toast.error(e?.message || "Could not save."); }
    setSaving(false);
  };

  const exportData = async () => {
    const mine = { profile: user };
    const byUser = { CommunityPost: "user_email", CommunityComment: "user_email", Comment: "user_email", MusicReview: "user_email", Commission: "artist_email" };
    for (const [entity, field] of Object.entries(byUser)) {
      mine[entity] = await base44.entities[entity].filter({ [field]: user.email }).catch(() => []);
    }
    const blob = new Blob([JSON.stringify(mine, null, 2)], { type: "application/json" });
    const a = document.createElement("a");
    a.href = URL.createObjectURL(blob);
    a.download = `mimilocks-${user.email.split("@")[0]}-export.json`;
    a.click();
    URL.revokeObjectURL(a.href);
    toast.success("Your data was exported");
  };

  const resetDemo = async () => {
    const ok = await confirm({ title: "Reset demo data?", message: "Every local account, post and message in this browser will be erased and fresh demo data created.", confirmLabel: "Reset everything", danger: true });
    if (!ok) return;
    base44.resetLocalData?.();
    window.location.href = "/Login";
  };

  if (!user) return null;

  return (
    <Page width="max-w-5xl">
      <PageHeader eyebrow="Your space" title="Settings" subtitle="Make Sugerly feel like yours." icon={SettingsIcon} actions={<Link to={profileLink(user.email)} className="btn-outline">View profile</Link>} />
      <div className="grid lg:grid-cols-[200px_1fr] gap-6 items-start">
        <nav className="hidden lg:block sticky top-4 space-y-1">
          {[...SECTIONS, ...(isAdmin ? [{ id: "site", label: "Site settings", icon: Shield }] : [])].map((s) => (
            <a key={s.id} href={`#${s.id}`} className="flex items-center gap-2.5 px-3 h-10 rounded-2xl text-sm font-semibold transition-colors hover:bg-[var(--pink-soft)]" style={{ color: "var(--text-secondary)" }}><s.icon className="w-4 h-4" />{s.label}</a>
          ))}
        </nav>

        <div className="space-y-6 min-w-0">
          <Section id="profile" icon={User} title="Profile" subtitle="How others see you around the site.">
            <div className="relative h-36 mb-14">
              <div className="absolute inset-0 rounded-3xl overflow-hidden" style={{ background: bannerPreview ? undefined : `linear-gradient(120deg, ${form.banner_color || "rgb(var(--accent-2-rgb))"}, rgb(var(--accent-rgb)))` }}>
                {bannerPreview && <img loading="lazy" decoding="async" src={bannerPreview} alt="" className="absolute inset-0 w-full h-full object-cover" />}
              </div>
              <div className="absolute top-3 right-3 flex gap-2">
                <button type="button" onClick={() => bannerRef.current?.click()} className="chip glass !py-1.5"><ImagePlus className="w-3.5 h-3.5" /> {bannerPreview ? "Change" : "Upload"} banner</button>
                {bannerPreview && <button type="button" onClick={() => { setBannerPreview(null); setBannerFile(null); }} className="icon-btn glass" aria-label="Remove banner"><Trash2 className="w-4 h-4" /></button>}
                {!bannerPreview && <label className="icon-btn glass cursor-pointer relative overflow-hidden" title="Banner color"><Palette className="w-4 h-4" /><input type="color" value={form.banner_color || "#ee8fae"} onChange={(e) => setForm((f) => ({ ...f, banner_color: e.target.value }))} className="absolute inset-0 opacity-0 cursor-pointer" /></label>}
              </div>
              <input ref={bannerRef} type="file" accept="image/*" className="hidden" onChange={(e) => { const f = e.target.files?.[0]; if (f) { setBannerFile(f); setBannerPreview(URL.createObjectURL(f)); } e.target.value = ""; }} />
              <div className="absolute -bottom-12 left-6">
                <label className="relative flex cursor-pointer group rounded-full">
                  <Avatar src={picPreview} name={form.display_name} size={96} ring={5} />
                  <span className="absolute inset-0 rounded-full flex items-center justify-center text-white opacity-0 group-hover:opacity-100 transition-opacity" style={{ background: "rgb(20 8 14 / 0.45)" }}><Camera className="w-6 h-6" /></span>
                  <input type="file" accept="image/*" className="hidden" onChange={(e) => { const f = e.target.files?.[0]; if (f) setCropSrc(URL.createObjectURL(f)); e.target.value = ""; }} />
                </label>
              </div>
            </div>
            {picPreview && <button className="text-xs font-semibold mb-4 -mt-10 ml-32 block" style={{ color: "var(--danger)" }} onClick={() => { setPicPreview(null); setPicFile(null); }}>Remove photo</button>}
            <div className="grid sm:grid-cols-2 gap-4">
              <div><label className="label" htmlFor="s-name">Display name</label><input id="s-name" className="input" value={form.display_name} onChange={(e) => setForm((f) => ({ ...f, display_name: e.target.value }))} maxLength={40} /></div>
              <div><label className="label" htmlFor="s-email">Email</label><input id="s-email" className="input opacity-70" value={user.email} disabled /></div>
            </div>
            <div className="mt-4"><label className="label" htmlFor="s-bio">Bio</label><textarea id="s-bio" className="input resize-none" rows={3} value={form.bio} onChange={(e) => setForm((f) => ({ ...f, bio: e.target.value }))} maxLength={200} placeholder="A line or two about you and your art…" /></div>
            <div className="mt-4">
              <p className="label">Interests</p>
              <div className="flex flex-wrap gap-2">{INTERESTS.map((i) => <button key={i} className="chip" data-active={form.interests.includes(i)} onClick={() => setForm((f) => ({ ...f, interests: f.interests.includes(i) ? f.interests.filter((x) => x !== i) : [...f.interests, i] }))}>{form.interests.includes(i) && <Check className="w-3.5 h-3.5" />}{i}</button>)}</div>
            </div>
            <div className="flex justify-end mt-6">
              <button onClick={save} disabled={saving || !dirty} className="btn">{saving ? <Loader2 className="w-4 h-4 animate-spin" /> : <><Save className="w-4 h-4" /> Save profile</>}</button>
            </div>
          </Section>

          <Section id="appearance" icon={Palette} title="Appearance" subtitle="Changes apply instantly and follow you across devices.">
            <p className="label">Theme</p>
            <div className="grid grid-cols-3 gap-3 mb-6">
              {[{ id: "light", label: "Light", icon: Sun, bg: "#fbf7f6", fg: "#2a1620" }, { id: "dark", label: "Dark", icon: Moon, bg: "#110a0f", fg: "#f7edf2" }, { id: "system", label: "System", icon: Monitor, bg: "linear-gradient(135deg,#fbf7f6 50%,#110a0f 50%)", fg: "#9c8a93" }].map((t) => (
                <motion.button key={t.id} whileHover={{ y: -2 }} whileTap={{ scale: 0.97 }} onClick={() => setAppearance({ theme: t.id })} className="card-sm p-2 text-left" style={form.theme === t.id ? { borderColor: "var(--accent-rose)", boxShadow: "0 0 0 3px rgb(var(--accent-rgb) / 0.15)" } : undefined} aria-pressed={form.theme === t.id}>
                  <div className="h-16 rounded-xl mb-2 p-2 flex flex-col gap-1.5" style={{ background: t.bg }}>
                    <span className="h-2 w-10 rounded-full" style={{ background: "rgb(var(--accent-rgb))" }} />
                    <span className="h-1.5 w-14 rounded-full opacity-40" style={{ background: t.fg }} />
                    <span className="h-1.5 w-8 rounded-full opacity-25" style={{ background: t.fg }} />
                  </div>
                  <span className="flex items-center gap-1.5 text-sm font-semibold px-1" style={{ color: form.theme === t.id ? "var(--accent-rose)" : "var(--text-secondary)" }}><t.icon className="w-4 h-4" />{t.label}</span>
                </motion.button>
              ))}
            </div>
            <p className="label">Accent color</p>
            <div className="flex flex-wrap gap-4">
              {ACCENTS.map((a) => (
                <motion.button key={a.id} whileHover={{ y: -3 }} whileTap={{ scale: 0.9 }} onClick={() => setAppearance({ accent: a.id })} className="flex flex-col items-center gap-1.5" aria-pressed={form.accent === a.id} aria-label={`${a.label} accent`}>
                  <span className="w-12 h-12 rounded-2xl flex items-center justify-center text-white" style={{ background: a.swatch, boxShadow: form.accent === a.id ? "0 0 0 3px var(--surface), 0 0 0 5px rgb(var(--accent-rgb))" : "var(--shadow-sm)" }}>{form.accent === a.id && <Check className="w-5 h-5" />}</span>
                  <span className="text-xs font-semibold" style={{ color: "var(--text-muted)" }}>{a.label}</span>
                </motion.button>
              ))}
            </div>
          </Section>

          <Section id="feedback" icon={Volume2} title="Sounds & haptics" subtitle="Little taps and sounds when you like, save, send and get notified. Saved on this device.">
            <div className="space-y-3">
              <div className="card-sm p-3.5"><Toggle checked={fb.sounds} onChange={(v) => { setFb({ sounds: v }); if (v) setTimeout(() => playSound("success"), 30); }} label="Sounds" description="Soft pops and chimes. On iPhone and iPad they stay quiet when the silent switch is on." /></div>
              <div className="card-sm p-3.5"><Toggle checked={fb.haptics} onChange={(v) => { setFb({ haptics: v }); if (v) setTimeout(() => haptic("medium"), 30); }} label="Haptics" description="Gentle vibrations in the iPhone and iPad app." /></div>
            </div>
          </Section>

          <Section id="app" icon={Smartphone} title="Get the app" subtitle="Sugerly works like a native app on your phone, tablet or computer.">
            <InstallCard />
          </Section>

          <Section id="account" icon={Database} title="Account & data" subtitle={backendMode === "firebase" ? "Your account is stored securely in Firebase." : "Demo mode: everything is saved in this browser only."}>
            <div className="space-y-3">
              <div className="card-sm p-4 flex items-center gap-3">
                <Download className="w-5 h-5 flex-shrink-0" style={{ color: "var(--accent-rose)" }} />
                <div className="flex-1"><p className="text-sm font-semibold" style={{ color: "var(--text-primary)" }}>Export your data</p><p className="text-xs" style={{ color: "var(--text-muted)" }}>Download your profile, posts, comments and tracks as JSON.</p></div>
                <button className="btn-outline text-xs" onClick={exportData}>Export</button>
              </div>
              {backendMode === "local" && (
                <div className="card-sm p-4 flex items-center gap-3">
                  <RotateCcw className="w-5 h-5 flex-shrink-0" style={{ color: "var(--danger)" }} />
                  <div className="flex-1"><p className="text-sm font-semibold" style={{ color: "var(--text-primary)" }}>Reset demo data</p><p className="text-xs" style={{ color: "var(--text-muted)" }}>Wipe this browser's local database and start fresh.</p></div>
                  <button className="btn-outline text-xs" style={{ color: "var(--danger)", borderColor: "rgb(224 82 107 / 0.4)" }} onClick={resetDemo}>Reset</button>
                </div>
              )}
              <div className="card-sm p-4 flex items-center gap-3">
                <LogOut className="w-5 h-5 flex-shrink-0" style={{ color: "var(--text-secondary)" }} />
                <div className="flex-1"><p className="text-sm font-semibold" style={{ color: "var(--text-primary)" }}>Log out</p><p className="text-xs" style={{ color: "var(--text-muted)" }}>Signed in as {displayName(user)} ({user.email})</p></div>
                <button className="btn-outline text-xs" onClick={logout}>Log out</button>
              </div>
              <BlockedPeople />
              <DeleteAccount />
            </div>
          </Section>

          {isAdmin && <div id="site" className="scroll-mt-24"><AdminSiteSettings /></div>}
        </div>
      </div>

      <Modal open={!!cropSrc} onClose={() => setCropSrc(null)} title="Crop your photo" size="sm">
        {cropSrc && <ImageCropper imageSrc={cropSrc} onCrop={(file, url) => { setPicFile(file); setPicPreview(url); setCropSrc(null); }} onCancel={() => setCropSrc(null)} />}
      </Modal>
    </Page>
  );
}
