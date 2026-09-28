import { checkText, hasLink } from "@/lib/moderation";
import React, { useEffect, useRef, useState } from "react";
import { useNavigate } from "react-router-dom";
import { AnimatePresence, motion } from "framer-motion";
import { ArrowLeft, ArrowRight, Camera, Check, Loader2, Moon, Monitor, Sun } from "lucide-react";
import { base44 } from "@/api/base44Client";
import { useAuth } from "@/lib/AuthContext";
import { ACCENTS, applyTheme } from "@/lib/theme";
import { toast } from "@/lib/toast";
import Avatar from "@/components/common/Avatar";
import ImageCropper from "@/components/common/ImageCropper";
import Confetti from "@/components/common/Confetti";
import { BrandLogo } from "@/components/common/Brand";

const STEPS = ["You", "Photo", "Interests", "Style"];
const INTERESTS = ["Painting", "Digital art", "Drawing", "Photography", "3D", "Pixel art", "Animation", "Music", "Lo-fi", "Writing", "Crafts", "Fashion"];

export default function OnboardingPage() {
  const navigate = useNavigate();
  const { user, updateMe } = useAuth();
  const fileRef = useRef(null);
  const [step, setStep] = useState(0);
  const [dir, setDir] = useState(1);
  const [saving, setSaving] = useState(false);
  const [done, setDone] = useState(false);
  const [form, setForm] = useState({ display_name: "", bio: "", theme: "light", accent: "rose", interests: [] });
  const [picFile, setPicFile] = useState(null);
  const [picPreview, setPicPreview] = useState(null);
  const [cropSrc, setCropSrc] = useState(null);

  useEffect(() => {
    if (!user) return;
    if (user.onboarding_completed) { navigate("/", { replace: true }); return; }
    setForm((f) => ({ ...f, display_name: user.display_name || "", bio: user.bio || "", theme: user.theme || "light", accent: user.accent || "rose", interests: user.interests || [] }));
    if (user.profile_picture && !user.profile_picture.includes("ui-avatars.com")) setPicPreview(user.profile_picture);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [user?.id]);

  const go = (n) => { setDir(n > step ? 1 : -1); setStep(n); };
  const setStyle = (patch) => { setForm((f) => ({ ...f, ...patch })); applyTheme({ theme: patch.theme ?? form.theme, accent: patch.accent ?? form.accent }); };
  const toggleInterest = (i) => setForm((f) => ({ ...f, interests: f.interests.includes(i) ? f.interests.filter((x) => x !== i) : [...f.interests, i] }));

  const finish = async () => {
    if (hasLink(form.bio)) { toast.error("Links aren't allowed in your bio"); return; }
    for (const [text, kind] of [[form.display_name, "name"], [form.bio, "profile"]]) {
      const mod = await checkText(text, { user, where: kind === "name" ? "display name" : "bio", kind, skipCooldown: true });
      if (!mod.safe) { toast.error(mod.reason); return; }
    }
    setSaving(true);
    try {
      let profile_picture = user?.profile_picture || "";
      if (picFile) profile_picture = (await base44.integrations.Core.UploadFile({ file: picFile })).file_url;
      setDone(true);
      await updateMe({ ...form, display_name: form.display_name.trim(), profile_picture, onboarding_completed: true, coins: (user?.coins || 0) + 50 });
      toast.success("Welcome to Sugerly!", { description: "You earned 50 coins for setting up your profile." });
      setTimeout(() => navigate("/", { replace: true }), 1400);
    } catch (e) {
      setDone(false);
      toast.error(e?.message || "Could not save your profile.");
      setSaving(false);
    }
  };

  const variants = {
    enter: (d) => ({ opacity: 0, x: d * 40 }),
    center: { opacity: 1, x: 0 },
    exit: (d) => ({ opacity: 0, x: d * -40 }),
  };

  return (
    <div className="h-full overflow-y-auto overscroll-contain app-shell">
    <div className="min-h-full flex items-center justify-center p-4 relative overflow-hidden safe-top safe-x">
      <div className="orb orb-a w-96 h-96 -top-24 -left-24" />
      <div className="orb orb-b w-[30rem] h-[30rem] -bottom-32 -right-32" />
      <div className="relative w-full max-w-lg">
        <div className="text-center mb-8">
          <motion.div initial={{ scale: 0.7, rotate: -8, opacity: 0 }} animate={{ scale: 1, rotate: 0, opacity: 1 }} transition={{ type: "spring", stiffness: 260, damping: 16 }} className="flex justify-center mb-3"><BrandLogo height={64} /></motion.div>
          <h1 className="font-display text-3xl sm:text-4xl font-semibold" style={{ color: "var(--text-primary)" }}>Let's set up your space</h1>
          <p className="text-sm mt-2" style={{ color: "var(--text-muted)" }}>Four quick steps — you can change everything later.</p>
        </div>

        <div className="flex items-center gap-2 mb-6 px-2">
          {STEPS.map((s, i) => (
            <div key={s} className="flex-1">
              <div className="h-1.5 rounded-full overflow-hidden" style={{ background: "var(--border-c)" }}>
                <motion.div className="h-full rounded-full" style={{ background: "var(--accent-grad)" }} initial={false} animate={{ width: i <= step ? "100%" : "0%" }} transition={{ duration: 0.4 }} />
              </div>
              <p className="text-[11px] font-semibold mt-1.5" style={{ color: i <= step ? "var(--accent-rose)" : "var(--text-muted)" }}>{s}</p>
            </div>
          ))}
        </div>

        <div className="card p-6 sm:p-8 relative overflow-hidden" style={{ boxShadow: "var(--shadow-lg)" }}>
          {done && <Confetti />}
          <AnimatePresence mode="wait" custom={dir}>
            <motion.div key={step} custom={dir} variants={variants} initial="enter" animate="center" exit="exit" transition={{ duration: 0.25 }}>
              {step === 0 && (
                <div className="space-y-4">
                  <div>
                    <label className="label" htmlFor="ob-name">Display name</label>
                    <input id="ob-name" className="input" placeholder="What should we call you?" value={form.display_name} onChange={(e) => setForm((f) => ({ ...f, display_name: e.target.value }))} maxLength={40} autoFocus />
                  </div>
                  <div>
                    <label className="label" htmlFor="ob-bio">Bio</label>
                    <textarea id="ob-bio" className="input resize-none" rows={3} placeholder="A line or two about you and your art…" value={form.bio} onChange={(e) => setForm((f) => ({ ...f, bio: e.target.value }))} maxLength={200} />
                    <p className="text-[11px] text-right mt-1" style={{ color: "var(--text-muted)" }}>{form.bio.length}/200</p>
                  </div>
                </div>
              )}

              {step === 1 && (
                <div className="flex flex-col items-center gap-5">
                  {cropSrc ? (
                    <ImageCropper imageSrc={cropSrc} onCrop={(file, url) => { setPicFile(file); setPicPreview(url); setCropSrc(null); }} onCancel={() => setCropSrc(null)} />
                  ) : (
                    <>
                      <motion.button whileHover={{ scale: 1.04 }} whileTap={{ scale: 0.97 }} onClick={() => fileRef.current?.click()} className="relative rounded-full">
                        <Avatar src={picPreview} name={form.display_name} size={132} />
                        <span className="absolute bottom-1 right-1 w-10 h-10 rounded-full flex items-center justify-center text-white" style={{ background: "var(--accent-grad)", border: "3px solid var(--surface)" }}><Camera className="w-4 h-4" /></span>
                      </motion.button>
                      <p className="text-sm" style={{ color: "var(--text-muted)" }}>Add a photo so friends recognise you.</p>
                      <button className="btn-outline" onClick={() => fileRef.current?.click()}>{picPreview ? "Choose another" : "Upload photo"}</button>
                    </>
                  )}
                  <input ref={fileRef} type="file" accept="image/*" className="hidden" onChange={(e) => { const f = e.target.files?.[0]; if (f) setCropSrc(URL.createObjectURL(f)); e.target.value = ""; }} />
                </div>
              )}

              {step === 2 && (
                <div>
                  <p className="text-sm mb-4" style={{ color: "var(--text-secondary)" }}>What are you into? Pick as many as you like.</p>
                  <div className="flex flex-wrap gap-2">
                    {INTERESTS.map((i, idx) => (
                      <motion.button key={i} whileTap={{ scale: 0.92 }} className="enter-pop chip" style={{ "--d": `${Math.round((idx * 0.025) * 1000)}ms` }} data-active={form.interests.includes(i)} onClick={() => toggleInterest(i)}>
                        {form.interests.includes(i) && <Check className="w-3.5 h-3.5" />}{i}
                      </motion.button>
                    ))}
                  </div>
                </div>
              )}

              {step === 3 && (
                <div className="space-y-5">
                  <div>
                    <p className="label">Appearance</p>
                    <div className="grid grid-cols-3 gap-2">
                      {[{ id: "light", label: "Light", icon: Sun }, { id: "dark", label: "Dark", icon: Moon }, { id: "system", label: "System", icon: Monitor }].map((t) => (
                        <button key={t.id} onClick={() => setStyle({ theme: t.id })} className="card-sm p-3 flex flex-col items-center gap-2 text-sm font-semibold" style={form.theme === t.id ? { borderColor: "var(--accent-rose)", boxShadow: "0 0 0 3px rgb(var(--accent-rgb) / 0.15)", color: "var(--accent-rose)" } : { color: "var(--text-secondary)" }}>
                          <t.icon className="w-5 h-5" />{t.label}
                        </button>
                      ))}
                    </div>
                  </div>
                  <div>
                    <p className="label">Accent color</p>
                    <div className="flex gap-3">
                      {ACCENTS.map((a) => (
                        <motion.button key={a.id} whileHover={{ y: -3 }} whileTap={{ scale: 0.9 }} onClick={() => setStyle({ accent: a.id })} className="flex flex-col items-center gap-1.5" aria-label={a.label}>
                          <span className="w-11 h-11 rounded-2xl flex items-center justify-center text-white" style={{ background: a.swatch, boxShadow: form.accent === a.id ? "0 0 0 3px var(--surface), 0 0 0 5px rgb(var(--accent-rgb))" : "none" }}>{form.accent === a.id && <Check className="w-4 h-4" />}</span>
                          <span className="text-[11px] font-semibold" style={{ color: "var(--text-muted)" }}>{a.label}</span>
                        </motion.button>
                      ))}
                    </div>
                  </div>
                </div>
              )}
            </motion.div>
          </AnimatePresence>

          {!cropSrc && (
            <div className="flex gap-2 mt-8">
              {step > 0 && <button className="btn-ghost" onClick={() => go(step - 1)}><ArrowLeft className="w-4 h-4" /> Back</button>}
              <div className="flex-1" />
              {step < STEPS.length - 1 ? (
                <button className="btn" disabled={step === 0 && !form.display_name.trim()} onClick={() => go(step + 1)}>Continue <ArrowRight className="w-4 h-4" /></button>
              ) : (
                <button className="btn" disabled={saving} onClick={finish}>{saving ? <Loader2 className="w-4 h-4 animate-spin" /> : <><Check className="w-4 h-4" /> Finish</>}</button>
              )}
            </div>
          )}
        </div>
      </div>
    </div>
    </div>
  );
}
