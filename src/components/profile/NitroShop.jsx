import React, { useState } from "react";
import { motion } from "framer-motion";
import { Check, Coins, Crown, Gift, Loader2, Palette, Sparkles, Zap } from "lucide-react";
import { useAuth } from "@/lib/AuthContext";
import { toast } from "@/lib/toast";
import { isNitro } from "@/lib/format";
import Confetti from "@/components/common/Confetti";

const NITRO_COST = 800;
const XP_BOOST_COST = 150;
const PERKS = [
  { icon: Palette, text: "Premium name styles (Gold, Aurora, Neon)" },
  { icon: Crown, text: "Animated avatar ring & profile badge" },
  { icon: Sparkles, text: "Animated banner on your profile" },
];

// Coin shop: MimiNitro and small boosts, all paid with coins earned on the site.
export default function NitroShop() {
  const { user, updateMe } = useAuth();
  const [busy, setBusy] = useState(null);
  const [burst, setBurst] = useState(false);
  const coins = user?.coins || 0;
  const nitro = isNitro(user);

  const buy = async (id, cost, patch, message) => {
    if (coins < cost) { toast.error(`You need ${cost - coins} more coins`, { description: "Earn coins with daily rewards and by posting." }); return; }
    setBusy(id);
    try {
      await updateMe({ coins: coins - cost, ...patch });
      setBurst(true);
      setTimeout(() => setBurst(false), 1800);
      toast.success(message);
    } catch (e) { toast.error(e?.message || "Purchase failed."); }
    setBusy(null);
  };
  const buyNitro = () => {
    const from = nitro ? new Date(user.nitro_until).getTime() : Date.now();
    return buy("nitro", NITRO_COST, { nitro_active: true, nitro_until: new Date(from + 30 * 86400000).toISOString() }, nitro ? "Nitro extended by 30 days ✨" : "Welcome to MimiNitro ✨");
  };

  return (
    <div className="space-y-5 relative">
      {burst && <Confetti />}
      <div className="rounded-3xl p-6 relative overflow-hidden text-white grain" style={{ background: "linear-gradient(135deg,#8b5cf6,#c084fc 45%,#ee8fae)", boxShadow: "0 20px 50px rgb(139 92 246 / 0.3)" }}>
        <div className="orb w-64 h-64 -right-16 -top-16" style={{ background: "rgb(255 255 255 / 0.3)" }} />
        <div className="relative flex flex-col sm:flex-row sm:items-center gap-5">
          <motion.div animate={{ rotate: [0, 8, -8, 0] }} transition={{ duration: 4, repeat: Infinity }} className="w-16 h-16 rounded-2xl flex items-center justify-center flex-shrink-0" style={{ background: "rgb(255 255 255 / 0.2)" }}><Sparkles className="w-8 h-8" /></motion.div>
          <div className="flex-1">
            <p className="font-display text-2xl font-semibold">{nitro ? "MimiNitro is active" : "MimiNitro"}</p>
            <p className="text-sm opacity-90">{nitro ? `Renews until ${new Date(user.nitro_until).toLocaleDateString()}` : "30 days of premium perks, paid with coins."}</p>
            <ul className="mt-3 space-y-1">{PERKS.map((p) => <li key={p.text} className="text-xs flex items-center gap-2 opacity-95"><p.icon className="w-3.5 h-3.5" />{p.text}</li>)}</ul>
          </div>
          <button onClick={buyNitro} disabled={busy === "nitro"} className="px-5 py-3 rounded-full bg-white font-bold text-sm flex items-center gap-2 justify-center disabled:opacity-60" style={{ color: "#7c3aed" }}>
            {busy === "nitro" ? <Loader2 className="w-4 h-4 animate-spin" /> : <><Coins className="w-4 h-4" /> {nitro ? "Extend" : "Get"} · {NITRO_COST}</>}
          </button>
        </div>
      </div>

      <div className="grid sm:grid-cols-2 gap-4">
        <div className="card p-5 flex items-center gap-4">
          <span className="w-12 h-12 rounded-2xl flex items-center justify-center text-white" style={{ background: "linear-gradient(135deg,#ffd166,#f0a020)" }}><Coins className="w-6 h-6" /></span>
          <div>
            <p className="font-display text-2xl font-semibold" style={{ color: "var(--text-primary)" }}>{coins.toLocaleString()}</p>
            <p className="text-xs" style={{ color: "var(--text-muted)" }}>MimiCoins balance</p>
          </div>
        </div>
        <div className="card p-5 flex items-center gap-4">
          <span className="w-12 h-12 rounded-2xl flex items-center justify-center text-white" style={{ background: "var(--accent-grad)" }}><Zap className="w-6 h-6" /></span>
          <div className="flex-1">
            <p className="text-sm font-bold" style={{ color: "var(--text-primary)" }}>XP boost</p>
            <p className="text-xs" style={{ color: "var(--text-muted)" }}>+100 XP instantly</p>
          </div>
          <button className="btn-outline text-xs" disabled={busy === "xp"} onClick={() => buy("xp", XP_BOOST_COST, { xp: (user?.xp || 0) + 100 }, "+100 XP")}>{busy === "xp" ? <Loader2 className="w-3.5 h-3.5 animate-spin" /> : <>{XP_BOOST_COST} <Coins className="w-3.5 h-3.5" /></>}</button>
        </div>
      </div>

      <div className="card p-5">
        <p className="eyebrow mb-3">How to earn coins</p>
        <div className="grid sm:grid-cols-3 gap-3 text-sm">
          {[{ icon: Gift, t: "Daily reward", d: "25–55 coins, bigger with streaks" }, { icon: Sparkles, t: "Post to Community", d: "+5 coins per post" }, { icon: Check, t: "Finish onboarding", d: "+50 coins once" }].map((x) => (
            <div key={x.t} className="flex items-start gap-3 p-3 rounded-2xl" style={{ background: "var(--surface-2)" }}>
              <x.icon className="w-4 h-4 mt-0.5 flex-shrink-0" style={{ color: "var(--accent-rose)" }} />
              <span><span className="block font-semibold" style={{ color: "var(--text-primary)" }}>{x.t}</span><span className="block text-xs" style={{ color: "var(--text-muted)" }}>{x.d}</span></span>
            </div>
          ))}
        </div>
      </div>
    </div>
  );
}
