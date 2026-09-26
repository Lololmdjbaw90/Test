import React, { useState } from "react";
import { AlertTriangle, Check, CheckCircle2, Copy, ExternalLink, Loader2, RefreshCw, ShieldAlert } from "lucide-react";
import Modal from "@/components/common/Modal";
import { checkRules, consoleLinks, firestoreRules, resetRulesCheck, storageRules, useRulesCheck } from "@/lib/setupCheck";
import { toast } from "@/lib/toast";
import { feedback } from "@/lib/feedback";

function CopyButton({ text, label }) {
  const [done, setDone] = useState(false);
  const copy = async () => {
    try { await navigator.clipboard.writeText(text); } catch {
      // Older iOS: fall back to a hidden textarea.
      const ta = document.createElement("textarea"); ta.value = text; document.body.appendChild(ta); ta.select(); document.execCommand("copy"); ta.remove();
    }
    feedback("success");
    setDone(true);
    setTimeout(() => setDone(false), 2000);
  };
  return <button type="button" onClick={copy} className="btn !min-h-0 !py-2 text-xs">{done ? <Check className="w-4 h-4" /> : <Copy className="w-4 h-4" />} {done ? "Copied!" : label}</button>;
}

// Step-by-step: publish this version's security rules in the Firebase console.
export function RulesSteps() {
  return (
    <ol className="space-y-4 text-sm" style={{ color: "var(--text-secondary)" }}>
      <li className="flex gap-3">
        <span className="w-6 h-6 rounded-full flex items-center justify-center text-xs font-bold text-white flex-shrink-0" style={{ background: "var(--accent-grad)" }}>1</span>
        <div className="space-y-2 min-w-0">
          <p><strong style={{ color: "var(--text-primary)" }}>Database rules.</strong> Copy them, open the Firebase console, select all the text in the editor, paste, then tap <strong>Publish</strong>.</p>
          <div className="flex flex-wrap gap-2">
            <CopyButton text={firestoreRules} label="Copy database rules" />
            <a href={consoleLinks.firestore} target="_blank" rel="noreferrer" className="btn-outline !min-h-0 !py-2 text-xs"><ExternalLink className="w-4 h-4" /> Open Firestore rules</a>
          </div>
        </div>
      </li>
      <li className="flex gap-3">
        <span className="w-6 h-6 rounded-full flex items-center justify-center text-xs font-bold text-white flex-shrink-0" style={{ background: "var(--accent-grad)" }}>2</span>
        <div className="space-y-2 min-w-0">
          <p><strong style={{ color: "var(--text-primary)" }}>Storage rules</strong> (for reel videos and pictures). In the console open <strong>Storage → Rules</strong>, paste and <strong>Publish</strong>.</p>
          <div className="flex flex-wrap gap-2">
            <CopyButton text={storageRules} label="Copy storage rules" />
            <a href={consoleLinks.storage} target="_blank" rel="noreferrer" className="btn-outline !min-h-0 !py-2 text-xs"><ExternalLink className="w-4 h-4" /> Open Storage</a>
          </div>
        </div>
      </li>
      <li className="flex gap-3">
        <span className="w-6 h-6 rounded-full flex items-center justify-center text-xs font-bold text-white flex-shrink-0" style={{ background: "var(--accent-grad)" }}>3</span>
        <p>Come back and tap <strong style={{ color: "var(--text-primary)" }}>Check again</strong>. (With a computer you can instead run <code className="px-1 rounded" style={{ background: "var(--surface-2)" }}>npx firebase-tools deploy --only firestore:rules,storage</code>.)</p>
      </li>
    </ol>
  );
}

// Card for Admin → Site: shows whether the rules are up to date.
export function RulesSetupCard() {
  const [nonce, setNonce] = useState(0);
  const status = useRulesCheck(true, nonce);
  const [checking, setChecking] = useState(false);
  const recheck = async () => {
    setChecking(true);
    resetRulesCheck();
    const r = await checkRules();
    setChecking(false);
    setNonce((n) => n + 1);
    if (r.ok) toast.success("Rules are up to date"); else toast.error("Still out of date", { description: "Make sure you pressed Publish in the console." });
  };
  if (status?.local) return null;
  return (
    <div className="card p-5 space-y-4" id="setup">
      <div className="flex items-center gap-3">
        {!status ? <Loader2 className="w-5 h-5 animate-spin" /> : status.ok ? <CheckCircle2 className="w-6 h-6" style={{ color: "var(--success)" }} /> : <ShieldAlert className="w-6 h-6" style={{ color: "var(--danger)" }} />}
        <div className="flex-1 min-w-0">
          <p className="font-display text-lg" style={{ color: "var(--text-primary)" }}>Database security rules</p>
          <p className="text-xs" style={{ color: "var(--text-muted)" }}>{!status ? "Checking…" : status.ok ? "Up to date for this version of Sugerly." : `Out of date — ${status.missing.join(" and ")} can't be saved yet.`}</p>
        </div>
        <button onClick={recheck} disabled={checking} className="btn-outline !min-h-0 !py-2 text-xs">{checking ? <Loader2 className="w-4 h-4 animate-spin" /> : <RefreshCw className="w-4 h-4" />} Check again</button>
      </div>
      {status && !status.ok && <RulesSteps />}
    </div>
  );
}

// Banner for admins when the rules are out of date.
export function RulesBanner() {
  const status = useRulesCheck(true);
  const [open, setOpen] = useState(false);
  if (!status || status.ok) return null;
  return (
    <>
      <div className="flex-shrink-0 flex items-center gap-3 px-4 py-2 text-sm font-semibold" style={{ background: "rgb(239 68 68 / 0.12)", color: "var(--danger)", borderBottom: "1px solid rgb(239 68 68 / 0.25)" }}>
        <AlertTriangle className="w-4 h-4 flex-shrink-0" />
        <span className="flex-1 min-w-0 truncate">Database rules are out of date — reels and updates can't be saved</span>
        <button onClick={() => setOpen(true)} className="btn !min-h-0 !py-1.5 text-xs">Fix it</button>
      </div>
      <Modal open={open} onClose={() => setOpen(false)} title="Publish the new rules" subtitle="About 2 minutes, from any device" size="lg" autoFocus={false}>
        <p className="text-sm mb-4" style={{ color: "var(--text-secondary)" }}>This version of Sugerly added Reels and app updates. Your Firebase project still has the older security rules, so it answers “insufficient permissions” when anyone saves them.</p>
        <RulesSteps />
        <div className="flex justify-end mt-5"><button className="btn" onClick={async () => { resetRulesCheck(); const r = await checkRules(); if (r.ok) { toast.success("All set — rules are up to date"); setOpen(false); window.location.reload(); } else toast.error("Still out of date", { description: "Make sure you pressed Publish." }); }}><RefreshCw className="w-4 h-4" /> Check again</button></div>
      </Modal>
    </>
  );
}
