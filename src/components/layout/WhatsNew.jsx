import React, { useEffect, useState } from "react";
import { Link, useLocation } from "react-router-dom";
import { RefreshCw, Sparkles } from "lucide-react";
import Modal from "@/components/common/Modal";
import { markUpdatesSeen } from "@/lib/updates";
import { useAppUpdate } from "@/lib/pwa";

// One-time "What's new" popup after an update.
export function WhatsNewPopup({ unseen }) {
  const location = useLocation();
  const [open, setOpen] = useState(false);
  const latest = unseen[0];
  useEffect(() => {
    if (!latest || location.pathname.toLowerCase() === "/updates") return undefined;
    const t = setTimeout(() => setOpen(true), 1200); // let the page settle first
    return () => clearTimeout(t);
  }, [latest?.id]); // eslint-disable-line react-hooks/exhaustive-deps
  const close = () => { setOpen(false); markUpdatesSeen(); };
  if (!latest) return null;
  return (
    <Modal open={open} onClose={close} size="md" autoFocus={false} hideHeader>
      <div className="p-6 pt-8 text-center">
        <div className="w-16 h-16 mx-auto rounded-3xl flex items-center justify-center text-3xl mb-3 anim-bob" style={{ background: "var(--accent-grad)", boxShadow: "var(--shadow-accent)" }}>{latest.emoji || "✨"}</div>
        <p className="eyebrow mb-1">What's new{latest.version ? ` · v${latest.version}` : ""}</p>
        <h2 className="font-display text-2xl mb-4" style={{ color: "var(--text-primary)" }}>{latest.title}</h2>
        {latest.items && (
          <ul className="text-left space-y-2 mb-5">
            {latest.items.map((it, i) => <li key={i} className="text-sm leading-relaxed flex gap-2.5" style={{ color: "var(--text-secondary)" }}><Sparkles className="w-4 h-4 flex-shrink-0 mt-0.5" style={{ color: "var(--accent-rose)" }} /><span>{it}</span></li>)}
          </ul>
        )}
        {latest.body && <p className="text-sm text-left whitespace-pre-line mb-5" style={{ color: "var(--text-secondary)" }}>{latest.body}</p>}
        <div className="flex gap-2">
          <Link to="/Updates" onClick={close} className="btn-outline flex-1">{unseen.length > 1 ? `See all ${unseen.length} updates` : "All updates"}</Link>
          <button onClick={close} className="btn flex-1">Got it</button>
        </div>
      </div>
    </Modal>
  );
}

// Web / installed web app: a new version has downloaded in the background.
export function UpdateReadyBar() {
  const { ready, apply } = useAppUpdate();
  if (!ready) return null;
  return (
    <div className="flex-shrink-0 flex items-center gap-3 px-4 py-2 text-sm font-semibold enter-fade" style={{ background: "var(--pink-soft)", color: "var(--accent-rose)", borderBottom: "1px solid rgb(var(--accent-rgb) / 0.2)" }}>
      <Sparkles className="w-4 h-4 flex-shrink-0" />
      <span className="flex-1 min-w-0 truncate">A new version of Sugerly is ready</span>
      <button onClick={apply} className="btn !min-h-0 !py-1.5 text-xs"><RefreshCw className="w-3.5 h-3.5" /> Update</button>
    </div>
  );
}
