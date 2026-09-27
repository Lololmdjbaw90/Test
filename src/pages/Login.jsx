import React, { useState } from "react";
import { useNavigate, useSearchParams, Link } from "react-router-dom";
import { AnimatePresence, motion } from "framer-motion";
import { ArrowRight, Eye, EyeOff, Heart, Loader2, Lock, Mail, Music2, Palette, Sparkles, UserRound, Users } from "lucide-react";
import { base44, backendMode } from "@/api/base44Client";
import { useAuth } from "@/lib/AuthContext";
import { Segmented } from "@/components/common/Controls";
import { toast } from "@/lib/toast";
import { BrandLogo } from "@/components/common/Brand";

const TILES = [
  { x: "8%", y: "12%", r: -8, w: 150, h: 190, g: "linear-gradient(160deg,#ffd1dc,#ee8fae)", icon: Palette, d: 0 },
  { x: "52%", y: "6%", r: 6, w: 170, h: 130, g: "linear-gradient(160deg,#d9c8ff,#9b7cf5)", icon: Music2, d: 0.6 },
  { x: "30%", y: "40%", r: -3, w: 190, h: 150, g: "linear-gradient(160deg,#ffe2c7,#ffaa80)", icon: Heart, d: 1.2 },
  { x: "62%", y: "46%", r: 9, w: 140, h: 180, g: "linear-gradient(160deg,#c6f1e3,#5fd3b0)", icon: Users, d: 1.8 },
  { x: "70%", y: "74%", r: 4, w: 160, h: 120, g: "linear-gradient(160deg,#cfe6ff,#7cbeff)", icon: Sparkles, d: 2.4 },
];

function ArtCollage() {
  return (
    <div className="relative hidden lg:flex flex-1 overflow-hidden grain" style={{ background: "linear-gradient(145deg, rgb(var(--accent-2-rgb) / 0.35), rgb(var(--accent-rgb) / 0.15) 50%, transparent), var(--surface-2)" }}>
      <div className="orb orb-a w-96 h-96 -top-20 -left-20" />
      <div className="orb orb-b w-[28rem] h-[28rem] bottom-0 right-0" />
      <div className="orb orb-c w-72 h-72 top-1/3 left-1/3" />
      {TILES.map((t, i) => (
        <div key={i} className="absolute enter-fade" style={{ left: t.x, top: t.y, width: t.w, height: t.h, rotate: `${t.r}deg`, "--d": `${t.d * 250}ms`, animationDuration: "600ms" }}>
          <div className="anim-bob w-full h-full rounded-[28px] flex items-end p-4 text-white" style={{ background: t.g, boxShadow: "0 30px 60px rgb(42 22 32 / 0.18)", animationDuration: `${6 + i}s` }}>
            <t.icon className="w-6 h-6 opacity-90" />
          </div>
        </div>
      ))}
      <div className="relative mt-auto p-12 max-w-lg">
        <motion.p initial={{ opacity: 0, y: 10 }} animate={{ opacity: 1, y: 0 }} transition={{ delay: 0.4 }} className="eyebrow mb-3">A cozy corner of the internet</motion.p>
        <motion.h2 initial={{ opacity: 0, y: 10 }} animate={{ opacity: 1, y: 0 }} transition={{ delay: 0.5 }} className="font-display text-5xl font-semibold leading-[1.05]" style={{ color: "var(--text-primary)" }}>
          Share your art, <em className="gradient-text">find your people.</em>
        </motion.h2>
        <motion.p initial={{ opacity: 0, y: 10 }} animate={{ opacity: 1, y: 0 }} transition={{ delay: 0.6 }} className="mt-4 text-sm leading-relaxed" style={{ color: "var(--text-secondary)" }}>
          Gallery, community feed, music, servers with voice chat, DMs and commissions — all in one soft, friendly place.
        </motion.p>
      </div>
    </div>
  );
}

export default function LoginPage() {
  const [mode, setMode] = useState("login");
  const [showPassword, setShowPassword] = useState(false);
  const [agreed, setAgreed] = useState(false);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState("");
  const [form, setForm] = useState({ email: "", password: "", display_name: "" });
  const navigate = useNavigate();
  const [params] = useSearchParams();
  const { checkUserAuth } = useAuth();
  const next = params.get("next") || "/";

  const set = (k) => (e) => setForm((f) => ({ ...f, [k]: e.target.value }));

  const submit = async (e) => {
    e.preventDefault();
    setError("");
    if (mode === "register" && !agreed) { setError("Please agree to the Terms and Community Guidelines to sign up."); return; }
    setLoading(true);
    try {
      if (mode === "reset") {
        await base44.auth.resetPassword(form.email);
        toast.success("Check your inbox", { description: `We sent a reset link to ${form.email}.` });
        setMode("login");
      } else if (mode === "register") {
        await base44.auth.register(form);
        await checkUserAuth();
        navigate("/Onboarding", { replace: true });
      } else {
        await base44.auth.login(form);
        await checkUserAuth();
        navigate(next, { replace: true });
      }
    } catch (err) {
      setError(err?.message || "Something went wrong.");
    } finally {
      setLoading(false);
    }
  };

  const titles = {
    login: ["Welcome back", "Log in to pick up where you left off."],
    register: ["Create your account", "Join the community in under a minute."],
    reset: ["Reset password", "We'll email you a link to choose a new one."],
  };

  return (
    <div className="min-h-[100dvh] flex app-shell safe-top safe-x">
      <ArtCollage />
      <div className="flex-1 lg:max-w-[560px] flex items-center justify-center p-5 sm:p-10 relative">
        <div className="orb orb-a w-72 h-72 -top-10 -right-10 lg:hidden" />
        <motion.div initial={{ opacity: 0, y: 20 }} animate={{ opacity: 1, y: 0 }} transition={{ type: "spring", stiffness: 200, damping: 24 }} className="relative w-full max-w-md">
          <div className="flex items-center gap-3 mb-8">
            <motion.div initial={{ rotate: -8, scale: 0.7, opacity: 0 }} animate={{ rotate: 0, scale: 1, opacity: 1 }} transition={{ type: "spring", stiffness: 300, damping: 16 }}><BrandLogo height={64} /></motion.div>
          </div>

          <AnimatePresence mode="wait">
            <motion.div key={mode} initial={{ opacity: 0, x: 12 }} animate={{ opacity: 1, x: 0 }} exit={{ opacity: 0, x: -12 }} transition={{ duration: 0.2 }}>
              <h1 className="font-display text-4xl font-semibold" style={{ color: "var(--text-primary)" }}>{titles[mode][0]}</h1>
              <p className="text-sm mt-2 mb-6" style={{ color: "var(--text-muted)" }}>{titles[mode][1]}</p>
            </motion.div>
          </AnimatePresence>

          {mode !== "reset" && (
            <Segmented stretch className="mb-5" value={mode} onChange={(m) => { setMode(m); setError(""); }} options={[{ id: "login", label: "Log in" }, { id: "register", label: "Sign up" }]} />
          )}

          <form onSubmit={submit} className="space-y-3">
            <AnimatePresence initial={false}>
              {mode === "register" && (
                <motion.div initial={{ opacity: 0, height: 0 }} animate={{ opacity: 1, height: "auto" }} exit={{ opacity: 0, height: 0 }} className="overflow-hidden">
                  <div className="relative">
                    <UserRound className="absolute left-3.5 top-1/2 -translate-y-1/2 w-4 h-4" style={{ color: "var(--accent-rose)" }} />
                    <input className="input pl-10" placeholder="Display name" value={form.display_name} onChange={set("display_name")} required autoComplete="nickname" />
                  </div>
                </motion.div>
              )}
            </AnimatePresence>
            <div className="relative">
              <Mail className="absolute left-3.5 top-1/2 -translate-y-1/2 w-4 h-4" style={{ color: "var(--accent-rose)" }} />
              <input className="input pl-10" type="email" placeholder="Email" value={form.email} onChange={set("email")} required autoComplete="email" />
            </div>
            {mode !== "reset" && (
              <div className="relative">
                <Lock className="absolute left-3.5 top-1/2 -translate-y-1/2 w-4 h-4" style={{ color: "var(--accent-rose)" }} />
                <input className="input pl-10 pr-11" type={showPassword ? "text" : "password"} placeholder="Password" value={form.password} onChange={set("password")} minLength={6} required autoComplete={mode === "register" ? "new-password" : "current-password"} />
                <button type="button" className="absolute right-3 top-1/2 -translate-y-1/2 icon-btn w-8 h-8" onClick={() => setShowPassword((v) => !v)} aria-label={showPassword ? "Hide password" : "Show password"}>{showPassword ? <EyeOff className="w-4 h-4" /> : <Eye className="w-4 h-4" />}</button>
              </div>
            )}
            {mode === "login" && (
              <div className="flex justify-end">
                <button type="button" onClick={() => { setMode("reset"); setError(""); }} className="text-xs font-semibold hover:underline" style={{ color: "var(--accent-rose)" }}>Forgot password?</button>
              </div>
            )}
            <AnimatePresence>
              {error && (
                <motion.div initial={{ opacity: 0, y: -6 }} animate={{ opacity: 1, y: 0, x: [0, -6, 6, -4, 4, 0] }} exit={{ opacity: 0 }} className="text-xs font-semibold px-3.5 py-2.5 rounded-xl" style={{ background: "rgb(224 82 107 / 0.1)", color: "var(--danger)", border: "1px solid rgb(224 82 107 / 0.25)" }} role="alert">
                  {error}
                </motion.div>
              )}
            </AnimatePresence>
            {mode === "register" && (
              <label className="flex items-start gap-2.5 text-xs leading-snug cursor-pointer" style={{ color: "var(--text-secondary)" }}>
                <input type="checkbox" checked={agreed} onChange={(e) => setAgreed(e.target.checked)} className="mt-0.5 w-4 h-4 accent-[rgb(var(--accent-rgb))]" aria-label="I agree to the Terms and Community Guidelines" />
                <span>I'm at least 13 and I agree to the <Link to="/Legal/terms" className="font-bold underline">Terms</Link> and <Link to="/Legal/guidelines" className="font-bold underline">Community Guidelines</Link>, and I've read the <Link to="/Legal/privacy" className="font-bold underline">Privacy Policy</Link>. No bullying, hate or explicit content — it gets removed.</span>
              </label>
            )}
            <button disabled={loading} className="btn w-full py-3 text-sm" type="submit">
              {loading ? <Loader2 className="w-4 h-4 animate-spin" /> : <>{mode === "login" ? "Log in" : mode === "register" ? "Create account" : "Send reset link"} <ArrowRight className="w-4 h-4" /></>}
            </button>
            {mode === "reset" && <button type="button" onClick={() => setMode("login")} className="btn-ghost w-full">Back to log in</button>}
          </form>

          {backendMode === "local" && mode === "login" && (
            <motion.div initial={{ opacity: 0 }} animate={{ opacity: 1 }} transition={{ delay: 0.3 }} className="mt-6 card-sm p-4 flex items-center gap-3">
              <Sparkles className="w-5 h-5 flex-shrink-0" style={{ color: "var(--accent-rose)" }} />
              <div className="flex-1 min-w-0 text-xs leading-relaxed" style={{ color: "var(--text-secondary)" }}>
                Demo mode — data stays in this browser. Admin: <strong>admin@mimilocks.local</strong> / <strong>admin123</strong>
              </div>
              <button type="button" className="btn-outline text-xs" onClick={() => setForm((f) => ({ ...f, email: "admin@mimilocks.local", password: "admin123" }))}>Fill</button>
            </motion.div>
          )}
        </motion.div>
      </div>
    </div>
  );
}
