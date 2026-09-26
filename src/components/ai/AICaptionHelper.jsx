import React, { useState } from "react";
import { AnimatePresence, motion } from "framer-motion";
import { Check, Loader2, RefreshCw, Sparkles, X } from "lucide-react";
import { aiAvailable, suggestCaptions } from "@/lib/ai";
import { feedback } from "@/lib/feedback";

// "✨ Write with AI": looks at the picture (and anything already typed) and
// offers three captions with hashtags. Tap one to use it.
export default function AICaptionHelper({ kind = "post", getImage, draft = "", title = "", onPick, dark = false }) {
  const [state, setState] = useState("idle"); // idle | loading | done | error
  const [options, setOptions] = useState([]);
  const [error, setError] = useState(null);
  const [picked, setPicked] = useState(-1);
  if (!aiAvailable) return null;

  const run = async () => {
    feedback("tap");
    setState("loading");
    setError(null);
    setPicked(-1);
    try {
      const image = await getImage?.();
      const list = await suggestCaptions({ image, kind, draft, title });
      if (!list.length) throw new Error("AI didn't come up with anything — try again.");
      setOptions(list);
      setState("done");
      feedback("success");
    } catch (e) {
      setError(e);
      setState("error");
      feedback("error");
    }
  };
  const pick = (o, i) => { setPicked(i); feedback("success"); onPick(o); };

  const surface = dark ? "rgb(255 255 255 / 0.08)" : "var(--surface-2)";
  const border = dark ? "rgb(255 255 255 / 0.12)" : "var(--border-c)";
  const muted = dark ? "rgb(255 255 255 / 0.6)" : "var(--text-muted)";
  const text = dark ? "#fff" : "var(--text-primary)";

  return (
    <div className="space-y-2">
      <div className="flex items-center gap-2">
        <button
          type="button"
          onClick={run}
          disabled={state === "loading"}
          className="relative overflow-hidden inline-flex items-center gap-1.5 px-3.5 py-2 rounded-full text-xs font-bold text-white active:scale-95 transition-transform disabled:opacity-80"
          style={{ background: "linear-gradient(120deg, #ff4d7d, #b58be0, #7cbeff)", backgroundSize: "200% 100%", animation: state === "loading" ? "gradient-pan 1.6s linear infinite" : undefined, boxShadow: "0 4px 14px rgb(255 77 125 / 0.3)" }}
        >
          {state === "loading" ? <Loader2 className="w-4 h-4 animate-spin" /> : state === "done" ? <RefreshCw className="w-4 h-4" /> : <Sparkles className="w-4 h-4" />}
          {state === "loading" ? "Writing…" : state === "done" ? "New ideas" : "Write with AI"}
        </button>
        {state === "done" && (
          <button type="button" onClick={() => { setState("idle"); setOptions([]); }} className="w-8 h-8 rounded-full flex items-center justify-center" style={{ color: muted }} aria-label="Close AI ideas"><X className="w-4 h-4" /></button>
        )}
      </div>

      <AnimatePresence initial={false}>
        {state === "loading" && (
          <motion.div key="load" initial={{ opacity: 0, height: 0 }} animate={{ opacity: 1, height: "auto" }} exit={{ opacity: 0, height: 0 }} className="space-y-2 overflow-hidden">
            {[0, 1, 2].map((i) => <div key={i} className="h-12 rounded-2xl skeleton" style={dark ? { background: "linear-gradient(90deg, rgb(255 255 255 / 0.06) 25%, rgb(255 255 255 / 0.16) 45%, rgb(255 255 255 / 0.06) 65%)", backgroundSize: "400% 100%" } : undefined} />)}
          </motion.div>
        )}
        {state === "error" && (
          <motion.p key="err" initial={{ opacity: 0, y: -4 }} animate={{ opacity: 1, y: 0 }} exit={{ opacity: 0 }} className="text-xs font-semibold" style={{ color: dark ? "#ff9fb5" : "var(--danger)" }} role="alert">
            {error?.message}
          </motion.p>
        )}
        {state === "done" && (
          <motion.div key="list" initial={{ opacity: 0 }} animate={{ opacity: 1 }} exit={{ opacity: 0, height: 0 }} className="space-y-2" role="list" aria-label="AI caption ideas">
            {options.map((o, i) => (
              <button
                key={i}
                type="button"
                role="listitem"
                onClick={() => pick(o, i)}
                className="rise-in w-full text-left p-3 rounded-2xl transition-transform active:scale-[0.98] flex gap-2"
                style={{ "--d": `${i * 70}ms`, background: surface, border: `1px solid ${picked === i ? "#ff4d7d" : border}`, color: text }}
              >
                <span className="flex-1 min-w-0">
                  {o.title && kind === "post" && <span className="block text-sm font-bold">{o.title}</span>}
                  <span className="block text-sm leading-snug">{o.caption}</span>
                  {o.hashtags.length > 0 && <span className="block text-xs font-bold mt-1" style={{ color: "#ff4d7d" }}>{o.hashtags.map((h) => `#${h}`).join(" ")}</span>}
                </span>
                {picked === i && <Check className="w-4 h-4 flex-shrink-0 mt-0.5" style={{ color: "#ff4d7d" }} />}
              </button>
            ))}
            <p className="text-[11px]" style={{ color: muted }}>Tap one to use it — you can still edit it.</p>
          </motion.div>
        )}
      </AnimatePresence>
    </div>
  );
}
