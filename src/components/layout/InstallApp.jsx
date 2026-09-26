import React, { useEffect, useState } from "react";
import { AnimatePresence, motion } from "framer-motion";
import { Check, Download, Share, SquarePlus, X } from "lucide-react";
import { useInstallApp } from "@/lib/pwa";

const DISMISS_KEY = "mimilocks:__install_dismissed";
const VISITS_KEY = "mimilocks:__visits";

// The iPhone / iPad steps: Share → Add to Home Screen.
export function IOSSteps({ compact }) {
  return (
    <ol className={`${compact ? "text-xs" : "text-sm"} space-y-1.5`} style={{ color: "var(--text-secondary)" }}>
      <li className="flex items-center gap-2"><span className="w-5 h-5 rounded-full flex items-center justify-center text-[10px] font-bold text-white flex-shrink-0" style={{ background: "var(--accent-grad)" }}>1</span>Tap <Share className="w-4 h-4 inline" style={{ color: "#2f80e0" }} aria-label="Share" /> <strong>Share</strong> in Safari's toolbar</li>
      <li className="flex items-center gap-2"><span className="w-5 h-5 rounded-full flex items-center justify-center text-[10px] font-bold text-white flex-shrink-0" style={{ background: "var(--accent-grad)" }}>2</span>Choose <SquarePlus className="w-4 h-4 inline" aria-label="" /> <strong>Add to Home Screen</strong></li>
    </ol>
  );
}

// One-time, dismissible tip shown from the second visit on phones and tablets.
export function InstallBanner() {
  const { installed, canPrompt, ios, prompt } = useInstallApp();
  const [dismissed, setDismissed] = useState(() => { try { return !!localStorage.getItem(DISMISS_KEY); } catch { return true; } });
  const [visits, setVisits] = useState(0);
  useEffect(() => {
    try {
      let n = Number(localStorage.getItem(VISITS_KEY) || 0);
      if (!sessionStorage.getItem(VISITS_KEY)) { n += 1; localStorage.setItem(VISITS_KEY, String(n)); sessionStorage.setItem(VISITS_KEY, "1"); }
      setVisits(n);
    } catch { /* ignore */ }
  }, []);
  const dismiss = () => { try { localStorage.setItem(DISMISS_KEY, "1"); } catch { /* ignore */ } setDismissed(true); };
  const show = !installed && !dismissed && visits >= 2 && (ios || canPrompt);

  return (
    <AnimatePresence initial={false}>
      {show && (
        <motion.div initial={{ height: 0, opacity: 0 }} animate={{ height: "auto", opacity: 1 }} exit={{ height: 0, opacity: 0 }} className="flex-shrink-0 overflow-hidden">
          <div className="flex items-start gap-3 px-4 py-3" style={{ background: "var(--pink-soft)", borderBottom: "1px solid var(--border-c)" }}>
            <img src="/icons/icon-192.png" alt="" className="w-10 h-10 rounded-xl flex-shrink-0" />
            <div className="flex-1 min-w-0">
              <p className="text-sm font-bold" style={{ color: "var(--text-primary)" }}>Get the Mimi Locks app</p>
              {ios ? <div className="mt-1.5"><IOSSteps compact /></div> : <p className="text-xs mt-0.5" style={{ color: "var(--text-secondary)" }}>Full screen, faster, and on your home screen.</p>}
            </div>
            {canPrompt && <button onClick={async () => { if (await prompt()) dismiss(); }} className="btn !py-1.5 !px-3 text-xs flex-shrink-0"><Download className="w-3.5 h-3.5" /> Install</button>}
            <button onClick={dismiss} className="icon-btn w-8 h-8 flex-shrink-0 -mr-1" aria-label="Dismiss"><X className="w-4 h-4" /></button>
          </div>
        </motion.div>
      )}
    </AnimatePresence>
  );
}

// Settings card: always available, explains each platform.
export function InstallCard() {
  const { installed, canPrompt, ios, prompt } = useInstallApp();
  if (installed) {
    return <p className="text-sm flex items-center gap-2" style={{ color: "var(--success)" }}><Check className="w-4 h-4" /> You're using the installed app.</p>;
  }
  return (
    <div className="space-y-3">
      <div className="flex items-center gap-3">
        <img src="/icons/icon-192.png" alt="" className="w-12 h-12 rounded-2xl" />
        <p className="text-sm flex-1" style={{ color: "var(--text-secondary)" }}>Install Mimi Locks on your iPhone, iPad, Android phone or computer. It opens full screen, starts faster and works offline.</p>
      </div>
      {canPrompt && <button onClick={prompt} className="btn"><Download className="w-4 h-4" /> Install app</button>}
      {ios && <IOSSteps />}
      {!canPrompt && !ios && <p className="text-xs" style={{ color: "var(--text-muted)" }}>On iPhone or iPad: open this site in Safari, tap Share, then "Add to Home Screen". On Android or a computer: use Chrome or Edge and choose "Install app" from the menu.</p>}
    </div>
  );
}
