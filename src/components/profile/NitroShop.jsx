import React, { useState } from "react";
import { Check, CheckCircle2, Circle, Crown, Gift, Image as ImageIcon, Loader2, PenLine, Sparkles, Type, Users, Zap } from "lucide-react";
import { useAuth } from "@/lib/AuthContext";
import { toast } from "@/lib/toast";
import { displayName, isNitro } from "@/lib/format";
import Confetti from "@/components/common/Confetti";
import Avatar from "@/components/common/Avatar";
import NitroBadge from "@/components/profile/NitroBadge";
import { getNameStyle } from "@/components/profile/NameStylePicker";

// Same plans as the app (native/Sugerly/Views/Profile/ProfileStyle.swift).
const PLANS = [
  { id: "month", days: 30, cost: 800, title: "1 month", note: "30 days" },
  { id: "season", days: 90, cost: 2000, title: "3 months", note: "Save 400 coins" },
];
const XP_BOOST_COST = 150;
const GRADIENT = "linear-gradient(135deg,#8b5cf6,#c084fc 45%,#ee8fae)";
const PERKS = [
  { icon: Type, title: "Name styles", text: "Gold, Aurora and Neon", colors: ["#ffd166", "#f0a020"] },
  { icon: Crown, title: "Candy ring", text: "An animated ring around your picture", colors: ["#5ec8b8", "#2e9e8f"] },
  { icon: Sparkles, title: "MimiPlus badge", text: "Next to your name on your profile", colors: ["#f472b6", "#c084fc"] },
  { icon: ImageIcon, title: "GIF picture & banner", text: "Set them in the Sugerly app", colors: ["#ee8fae", "#d9577f"] },
  { icon: Zap, title: "Profile effects", text: "12 floating effects, in the app", colors: ["#b19cff", "#8b5cf6"] },
  { icon: Circle, title: "Premium frames", text: "Rainbow, Hearts and Stars, in the app", colors: ["#7cbeff", "#2f80e0"] },
];
const EARN = [
  { icon: Gift, t: "Daily reward", d: "25–55 coins, bigger with streaks" },
  { icon: Users, t: "Invite friends", d: "+400 coins when a friend joins with your code" },
  { icon: PenLine, t: "Post to Community", d: "+5 coins per post" },
  { icon: Check, t: "Finish onboarding", d: "+50 coins once" },
];

// A MimiCoin: gold with a sparkle (coins are just for fun, so no money signs).
function Coin({ size = 18 }) {
  return (
    <span aria-hidden="true" className="inline-flex items-center justify-center rounded-full text-white flex-shrink-0" style={{ width: size, height: size, background: "linear-gradient(180deg,#ffd978,#f0a020)", boxShadow: "inset 0 0 0 1.5px rgb(255 255 255 / 0.55)" }}>
      <Sparkles style={{ width: size * 0.55, height: size * 0.55 }} strokeWidth={2.6} />
    </span>
  );
}

// MimiPlus: premium looks for your profile, paid with coins you earn.
export default function NitroShop() {
  const { user, updateMe } = useAuth();
  const [busy, setBusy] = useState(null);
  const [burst, setBurst] = useState(false);
  const [planId, setPlanId] = useState(PLANS[0].id);
  const coins = user?.coins || 0;
  const nitro = isNitro(user);
  const plan = PLANS.find((p) => p.id === planId) || PLANS[0];
  const short = Math.max(0, plan.cost - coins);
  const until = nitro && user?.nitro_until ? new Date(user.nitro_until) : null;
  const daysLeft = until ? Math.max(0, Math.ceil((until.getTime() - Date.now()) / 86400000)) : 0;
  const name = displayName(user);
  const style = getNameStyle(getNameStyle(user?.name_style).premium ? user.name_style : "aurora");

  const buy = async (id, cost, patch, message) => {
    if (coins < cost) { toast.error(`You need ${cost - coins} more coins`, { description: "Earn coins with daily rewards, invites and posting." }); return; }
    setBusy(id);
    try {
      await updateMe({ coins: coins - cost, ...patch });
      setBurst(true);
      setTimeout(() => setBurst(false), 1800);
      toast.success(message);
    } catch (e) { toast.error(e?.message || "Purchase failed."); }
    setBusy(null);
  };
  const buyPlan = () => {
    const from = Math.max(Date.now(), until ? until.getTime() : 0);
    return buy("nitro", plan.cost, { nitro_active: true, nitro_until: new Date(from + plan.days * 86400000).toISOString() },
      nitro ? `MimiPlus extended by ${plan.days} days` : "Welcome to MimiPlus");
  };

  return (
    <div className="space-y-5 relative">
      {burst && <Confetti />}

      {/* Hero with a live preview of your profile */}
      <div className="rounded-[2rem] p-5 sm:p-6 relative overflow-hidden text-white grain" style={{ background: GRADIENT, boxShadow: "0 20px 50px rgb(139 92 246 / 0.3)" }}>
        <div className="orb w-72 h-72 -right-20 -top-24" style={{ "--orb": "rgb(255 255 255 / 0.3)" }} />
        <div className="orb w-64 h-64 -left-24 -bottom-24" style={{ "--orb": "rgb(124 190 255 / 0.35)" }} />
        <div className="relative flex items-start justify-between gap-3 mb-5">
          <div>
            <p className="font-display text-3xl font-semibold">MimiPlus</p>
            <p className="text-sm opacity-90">{nitro && until ? `${daysLeft} day${daysLeft === 1 ? "" : "s"} left · until ${until.toLocaleDateString()}` : "Premium looks for your profile"}</p>
          </div>
          <span className="inline-flex items-center gap-1.5 rounded-full px-3 h-8 text-xs font-bold flex-shrink-0" style={{ background: "rgb(255 255 255 / 0.22)", boxShadow: "inset 0 0 0 1px rgb(255 255 255 / 0.35)" }}>
            {nitro ? <><CheckCircle2 className="w-3.5 h-3.5" /> Active</> : <><Sparkles className="w-3.5 h-3.5" /> Paid with coins</>}
          </span>
        </div>
        <div className="relative rounded-3xl overflow-hidden" style={{ background: "var(--surface)" }}>
          <div className="h-20 relative overflow-hidden" style={{ background: GRADIENT, backgroundSize: "200% auto", animation: "gradient-pan 6s linear infinite" }}>
            {[12, 30, 52, 70, 88].map((x, i) => (
              <Sparkles key={x} className="absolute w-3.5 h-3.5 text-white/80 anim-bob" style={{ left: `${x}%`, top: `${20 + (i % 3) * 22}%`, animationDelay: `${i * -1.3}s` }} />
            ))}
          </div>
          <div className="flex flex-col items-center px-4 pb-5 -mt-10">
            <Avatar src={user?.profile_picture} name={name} size={76} nitro ring={4} />
            <div className="flex items-center gap-2 mt-2 min-w-0 max-w-full">
              <span className="text-2xl truncate" style={style.preview()}>{name}</span>
              <NitroBadge active />
            </div>
            <p className="text-xs mt-1" style={{ color: "var(--text-muted)" }}>{nitro ? "Your MimiPlus look" : "This is you with MimiPlus"}</p>
          </div>
        </div>
      </div>

      {/* Plans */}
      <div className="card p-5 space-y-4">
        <p className="font-bold" style={{ color: "var(--text-primary)" }}>{nitro ? "Add more time" : "Choose your plan"}</p>
        <div className="grid grid-cols-2 gap-3" role="radiogroup" aria-label="MimiPlus plan">
          {PLANS.map((p) => {
            const on = p.id === planId;
            return (
              <button key={p.id} role="radio" aria-checked={on} onClick={() => setPlanId(p.id)}
                className="text-left rounded-2xl p-4 transition-transform active:scale-[0.97]"
                style={{ background: on ? "rgb(var(--accent-rgb) / 0.1)" : "var(--surface)", boxShadow: `inset 0 0 0 ${on ? 2 : 1}px ${on ? "rgb(var(--accent-rgb))" : "var(--border)"}` }}>
                <span className="flex items-center justify-between font-bold" style={{ color: "var(--text-primary)" }}>
                  {p.title}
                  {on ? <CheckCircle2 className="w-5 h-5" style={{ color: "rgb(var(--accent-rgb))" }} /> : <Circle className="w-5 h-5" style={{ color: "var(--text-muted)" }} />}
                </span>
                <span className="flex items-center gap-1.5 mt-1.5 font-display text-2xl font-semibold tabular-nums" style={{ color: "var(--text-primary)" }}><Coin size={18} />{p.cost.toLocaleString()}</span>
                <span className="block text-xs font-bold mt-1" style={{ color: p.days > 30 ? "var(--success)" : "var(--text-muted)" }}>{p.note}</span>
              </button>
            );
          })}
        </div>
        {short > 0 && (
          <div>
            <div className="flex justify-between text-xs font-bold mb-1.5">
              <span className="tabular-nums" style={{ color: "var(--text-primary)" }}>{coins.toLocaleString()} / {plan.cost.toLocaleString()} coins</span>
              <span style={{ color: "var(--text-muted)" }}>{short.toLocaleString()} to go</span>
            </div>
            <div className="h-2.5 rounded-full overflow-hidden" style={{ background: "var(--surface-2)" }}>
              <div className="h-full rounded-full" style={{ width: `${Math.max(4, Math.min(100, (coins / plan.cost) * 100))}%`, background: GRADIENT }} />
            </div>
          </div>
        )}
        <button onClick={buyPlan} disabled={busy !== null || short > 0} className="btn-primary w-full justify-center h-12 disabled:opacity-60">
          {busy === "nitro" ? <Loader2 className="w-4 h-4 animate-spin" /> : short > 0 ? `Earn ${short.toLocaleString()} more coins` : <><Coin size={20} /> {nitro ? `Add ${plan.title}` : "Get MimiPlus"} · {plan.cost.toLocaleString()}</>}
        </button>
        <p className="text-[11px]" style={{ color: "var(--text-muted)" }}>Paid with MimiCoins you earn in Sugerly. Coins can't be bought, and MimiPlus never renews by itself.</p>
      </div>

      {/* Perks */}
      <div>
        <p className="eyebrow mb-3">Everything in MimiPlus</p>
        <div className="grid grid-cols-2 lg:grid-cols-3 gap-3">
          {PERKS.map((p) => (
            <div key={p.title} className="card p-4">
              <span className="w-10 h-10 rounded-xl flex items-center justify-center text-white mb-2" style={{ background: `linear-gradient(135deg,${p.colors[0]},${p.colors[1]})` }}><p.icon className="w-5 h-5" /></span>
              <p className="text-sm font-bold" style={{ color: "var(--text-primary)" }}>{p.title}</p>
              <p className="text-xs" style={{ color: "var(--text-muted)" }}>{p.text}</p>
            </div>
          ))}
        </div>
      </div>

      {/* Balance + boost */}
      <div className="grid sm:grid-cols-2 gap-4">
        <div className="card p-5 flex items-center gap-4">
          <Coin size={48} />
          <div>
            <p className="font-display text-2xl font-semibold tabular-nums" style={{ color: "var(--text-primary)" }}>{coins.toLocaleString()}</p>
            <p className="text-xs" style={{ color: "var(--text-muted)" }}>MimiCoins balance</p>
          </div>
        </div>
        <div className="card p-5 flex items-center gap-4">
          <span className="w-12 h-12 rounded-2xl flex items-center justify-center text-white" style={{ background: "var(--accent-grad)" }}><Zap className="w-6 h-6" /></span>
          <div className="flex-1">
            <p className="text-sm font-bold" style={{ color: "var(--text-primary)" }}>XP boost</p>
            <p className="text-xs" style={{ color: "var(--text-muted)" }}>+100 XP instantly</p>
          </div>
          <button className="btn-outline text-xs" disabled={busy !== null} onClick={() => buy("xp", XP_BOOST_COST, { xp: (user?.xp || 0) + 100 }, "+100 XP")}>
            {busy === "xp" ? <Loader2 className="w-3.5 h-3.5 animate-spin" /> : <><Coin size={14} /> {XP_BOOST_COST}</>}
          </button>
        </div>
      </div>

      {/* Earning */}
      <div className="card p-5">
        <p className="eyebrow mb-3">How to earn coins</p>
        <div className="grid sm:grid-cols-2 gap-3 text-sm">
          {EARN.map((x) => (
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
