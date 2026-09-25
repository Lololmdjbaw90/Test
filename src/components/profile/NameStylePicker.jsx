import React, { useRef, useState } from "react";
import { Check, Lock, Palette, Sparkles } from "lucide-react";
import { useAuth } from "@/lib/AuthContext";
import { toast } from "@/lib/toast";
import { isNitro } from "@/lib/format";
import Popover from "@/components/common/Popover";

const base = { fontFamily: "var(--font-display)", fontWeight: 600 };
export const NAME_STYLES = [
  { id: "default", label: "Classic", preview: () => ({ ...base, color: "var(--text-primary)" }) },
  { id: "glow-pink", label: "Pink glow", preview: () => ({ ...base, color: "#e86d98", textShadow: "0 0 14px rgba(232,109,152,0.65)" }) },
  { id: "glow-purple", label: "Violet glow", preview: () => ({ ...base, color: "#a67cf7", textShadow: "0 0 14px rgba(166,124,247,0.65)" }) },
  { id: "italic-serif", label: "Editorial", preview: () => ({ ...base, fontStyle: "italic", color: "var(--text-primary)" }) },
  { id: "bold-serif", label: "Rose serif", preview: () => ({ ...base, fontWeight: 800, color: "var(--accent-rose)" }) },
  { id: "glow-gold", label: "Gold", premium: true, preview: () => ({ ...base, color: "#e6a31c", textShadow: "0 0 16px rgba(240,160,32,0.6)" }) },
  { id: "aurora", label: "Aurora", premium: true, preview: () => ({ ...base, fontWeight: 700, background: "linear-gradient(90deg,#ee8fae,#b19cff,#7cbeff,#ee8fae)", backgroundSize: "200% auto", WebkitBackgroundClip: "text", backgroundClip: "text", WebkitTextFillColor: "transparent", animation: "gradient-pan 5s linear infinite" }) },
  { id: "neon", label: "Neon", premium: true, preview: () => ({ ...base, fontWeight: 700, color: "#fff", textShadow: "0 0 4px #fff, 0 0 14px #ee8fae, 0 0 30px #d9577f, 0 0 50px #d9577f" }) },
];

export function getNameStyle(styleId) {
  return NAME_STYLES.find((s) => s.id === styleId) || NAME_STYLES[0];
}

export default function NameStylePicker({ currentStyle, name, onSave }) {
  const { user, updateMe } = useAuth();
  const [open, setOpen] = useState(false);
  const ref = useRef(null);
  const nitro = isNitro(user);
  const pick = async (style) => {
    if (style.premium && !nitro) { toast("MimiNitro style", { description: "Get Nitro from the shop on your profile to unlock this.", icon: <Sparkles className="w-5 h-5" /> }); return; }
    try {
      await updateMe({ name_style: style.id });
      onSave?.(style.id);
      setOpen(false);
    } catch (e) { toast.error(e?.message || "Could not save style."); }
  };
  return (
    <>
      <button ref={ref} onClick={() => setOpen((o) => !o)} className="chip !py-1.5" aria-expanded={open}><Palette className="w-3.5 h-3.5" /> Name style</button>
      <Popover open={open} onClose={() => setOpen(false)} anchorRef={ref} placement="bottom-start" width={300} label="Name style">
        <p className="eyebrow px-4 pt-4 pb-2">Choose a name style</p>
        <div className="p-2 pt-0 max-h-80 overflow-y-auto scroll">
          {NAME_STYLES.map((style) => {
            const active = (currentStyle || "default") === style.id;
            const locked = style.premium && !nitro;
            return (
              <button key={style.id} onClick={() => pick(style)} className="w-full flex items-center gap-3 px-3 py-2.5 rounded-2xl text-left transition-colors hover:bg-[var(--surface-2)]" style={active ? { background: "var(--pink-soft)" } : undefined}>
                <span className="flex-1 min-w-0 truncate text-lg" style={style.preview()}>{name}</span>
                <span className="text-[10px] font-bold flex items-center gap-1" style={{ color: "var(--text-muted)" }}>{style.premium && (locked ? <Lock className="w-3 h-3" /> : <Sparkles className="w-3 h-3" style={{ color: "#a67cf7" }} />)}{style.label}</span>
                {active && <Check className="w-4 h-4" style={{ color: "var(--accent-rose)" }} />}
              </button>
            );
          })}
        </div>
      </Popover>
    </>
  );
}
