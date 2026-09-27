import React, { useState } from "react";
import { CheckCircle2, ExternalLink, Loader2, Sparkles, XCircle } from "lucide-react";
import { aiAvailable, testAI } from "@/lib/ai";
import { projectId } from "@/lib/setupCheck";
import { feedback } from "@/lib/feedback";

// Admin → Site: turn on and test the AI features (Gemini via Firebase AI Logic).
export default function AISetupCard() {
  const [state, setState] = useState({ status: "idle" }); // idle | testing | ok | error
  if (!aiAvailable) return null;
  const test = async () => {
    setState({ status: "testing" });
    try {
      await testAI();
      setState({ status: "ok" });
      feedback("success");
    } catch (e) {
      setState({ status: "error", error: e });
      feedback("error");
    }
  };
  const showSteps = state.status === "error" || state.status === "idle";
  return (
    <div className="card p-5 space-y-4" id="ai">
      <div className="flex items-center gap-3">
        {state.status === "ok" ? <CheckCircle2 className="w-6 h-6" style={{ color: "var(--success)" }} /> : state.status === "error" ? <XCircle className="w-6 h-6" style={{ color: "var(--danger)" }} /> : <Sparkles className="w-6 h-6" style={{ color: "rgb(var(--accent-rgb))" }} />}
        <div className="flex-1 min-w-0">
          <p className="font-display text-lg" style={{ color: "var(--text-primary)" }}>AI features</p>
          <p className="text-xs" style={{ color: "var(--text-muted)" }}>
            {state.status === "ok" ? "AI is on — people can use “Write with AI” for captions and hashtags."
              : state.status === "error" ? state.error?.message
                : "“Write with AI” writes captions and hashtags from a picture, in Community and Reels."}
          </p>
        </div>
        <button onClick={test} disabled={state.status === "testing"} className="btn-outline !min-h-0 !py-2 text-xs">{state.status === "testing" ? <Loader2 className="w-4 h-4 animate-spin" /> : <Sparkles className="w-4 h-4" />} Test AI</button>
      </div>
      {state.status === "error" && state.error?.appCheck && (
        <div className="text-sm space-y-1.5 rounded-2xl p-3" style={{ background: "var(--surface-2)", color: "var(--text-secondary)" }}>
          <p className="font-bold" style={{ color: "var(--text-primary)" }}>App Check is blocking AI</p>
          <p>Firebase now switches on App Check for AI Logic. The iPhone/iPad app is installed outside the App Store, so it can't prove itself with Apple's App Attest.</p>
          <p>To use AI anyway: Firebase console → <strong>Security → App Check → APIs</strong> → <strong>Firebase AI Logic</strong> → <strong>Unenforce</strong>. (For a public App Store release, register the app with App Attest instead.)</p>
        </div>
      )}
      {showSteps && !state.error?.appCheck && (
        <ol className="space-y-2 text-sm list-decimal pl-5" style={{ color: "var(--text-secondary)" }}>
          <li>Open the <a href={`https://console.firebase.google.com/project/${projectId}/overview`} target="_blank" rel="noreferrer" className="font-semibold underline inline-flex items-center gap-1">Firebase console <ExternalLink className="w-3 h-3" /></a>.</li>
          <li>In the menu open <strong>AI Services → AI Logic</strong> and tap <strong>Get started</strong>.</li>
          <li>Pick <strong>Gemini Developer API</strong> (free to start, no card needed) and enable it. Skip the “add the SDK” steps — Sugerly already has it.</li>
          <li>Come back and tap <strong>Test AI</strong>.</li>
        </ol>
      )}
    </div>
  );
}
