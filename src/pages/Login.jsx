import React, { useState } from "react";
import { base44, backendMode } from "@/api/base44Client";
import { Eye, EyeOff, Loader2, Lock, Mail, UserPlus } from "lucide-react";
import { useNavigate } from "react-router-dom";
import { useAuth } from "@/lib/AuthContext";

export default function LoginPage() {
  const [mode, setMode] = useState("login");
  const [showPassword, setShowPassword] = useState(false);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState("");
  const [form, setForm] = useState({ email: "", password: "", display_name: "" });
  const navigate = useNavigate();
  const { checkUserAuth } = useAuth();

  const submit = async (e) => {
    e.preventDefault();
    setError("");
    setLoading(true);
    try {
      if (mode === "register") {
        await base44.auth.register(form);
        await checkUserAuth();
        navigate("/Onboarding");
      } else {
        await base44.auth.login(form);
        await checkUserAuth();
        navigate("/");
      }
    } catch (err) {
      setError(err?.message || "Login failed.");
    } finally {
      setLoading(false);
    }
  };

  return (
    <div className="min-h-screen flex items-center justify-center p-4" style={{ background: "linear-gradient(135deg, #fff7fb, #ffe8f0)" }}>
      <div className="w-full max-w-md rounded-[28px] shadow-xl border p-6" style={{ background: "rgba(255,255,255,0.9)", borderColor: "rgba(212,112,138,0.25)" }}>
        <div className="text-center mb-6">
          <div className="w-16 h-16 mx-auto mb-3 rounded-3xl flex items-center justify-center text-white text-2xl font-bold shadow" style={{ background: "linear-gradient(135deg,#f3a6bd,#d4708a)" }}>M</div>
          <h1 className="text-xl font-bold" style={{ color: "#57333d" }}>{mode === "login" ? "Welcome back" : "Create your account"}</h1>
          <p className="text-sm mt-1" style={{ color: "#9b6575" }}>Mimi Locks saves accounts, posts, likes, follows, comments and messages{backendMode === "firebase" ? " in Firebase." : " in this browser until Firebase is configured."}</p>
        </div>

        <form onSubmit={submit} className="space-y-3">
          {mode === "register" && (
            <div className="relative">
              <UserPlus className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4" style={{ color: "#d4708a" }} />
              <input className="input pl-10" placeholder="Display name" value={form.display_name} onChange={e => setForm(f => ({ ...f, display_name: e.target.value }))} required />
            </div>
          )}
          <div className="relative">
            <Mail className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4" style={{ color: "#d4708a" }} />
            <input className="input pl-10" type="email" placeholder="Email" value={form.email} onChange={e => setForm(f => ({ ...f, email: e.target.value }))} required />
          </div>
          <div className="relative">
            <Lock className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4" style={{ color: "#d4708a" }} />
            <input className="input pl-10 pr-10" type={showPassword ? "text" : "password"} placeholder="Password" value={form.password} onChange={e => setForm(f => ({ ...f, password: e.target.value }))} minLength={6} required />
            <button type="button" className="absolute right-3 top-1/2 -translate-y-1/2" onClick={() => setShowPassword(v => !v)} style={{ color: "#9b6575" }}>{showPassword ? <EyeOff className="w-4 h-4" /> : <Eye className="w-4 h-4" />}</button>
          </div>
          {error && <div className="text-xs px-3 py-2 rounded-xl" style={{ background: "#fff0f0", color: "#c24141", border: "1px solid #ffd0d0" }}>{error}</div>}
          <button disabled={loading} className="btn w-full justify-center py-3" type="submit">{loading ? <Loader2 className="w-4 h-4 animate-spin" /> : mode === "login" ? "Log in" : "Create account"}</button>
        </form>

        <div className="mt-4 flex items-center justify-center gap-1 text-sm" style={{ color: "#9b6575" }}>
          <span>{mode === "login" ? "No account?" : "Already have one?"}</span>
          <button className="font-semibold" style={{ color: "#d4708a" }} onClick={() => { setMode(mode === "login" ? "register" : "login"); setError(""); }}>{mode === "login" ? "Create one" : "Log in"}</button>
        </div>
        {backendMode === "local" && (
          <div className="mt-4 text-[11px] leading-relaxed rounded-xl p-3" style={{ background: "#fff4f7", color: "#9b6575" }}>
            Local demo admin: <strong>admin@mimilocks.local</strong> / <strong>admin123</strong>. This appears only when Firebase is not configured.
          </div>
        )}
        {backendMode === "firebase" && (
          <div className="mt-4 text-[11px] leading-relaxed rounded-xl p-3" style={{ background: "#fff4f7", color: "#9b6575" }}>
            Firebase mode is active. Admin access comes from the user document role in Firestore.
          </div>
        )}
      </div>
    </div>
  );
}
