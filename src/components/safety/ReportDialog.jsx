import React, { useEffect, useState } from "react";
import { Check, Flag, Loader2 } from "lucide-react";
import Modal from "@/components/common/Modal";
import { useAuth } from "@/lib/AuthContext";
import { toast } from "@/lib/toast";
import { REPORT_REASONS, fileReport, onOpenReport } from "@/lib/safety";

const NOUN = { post: "post", comment: "comment", track: "track", message: "message", user: "account" };

// Mounted once in the app shell; any screen can call openReport(target).
export default function ReportHost() {
  const { user } = useAuth();
  const [target, setTarget] = useState(null);
  const [reason, setReason] = useState("");
  const [details, setDetails] = useState("");
  const [busy, setBusy] = useState(false);
  useEffect(() => onOpenReport((t) => { setTarget(t); setReason(""); setDetails(""); }), []);
  const close = () => setTarget(null);

  const submit = async () => {
    if (!reason || !user) return;
    setBusy(true);
    try {
      await fileReport(user, target, reason, details);
      toast.success("Thanks — our moderators will take a look", { icon: <Flag className="w-5 h-5" /> });
      close();
    } catch (e) { toast.error(e?.message || "Could not send the report."); }
    setBusy(false);
  };

  const noun = NOUN[target?.type] || "content";
  return (
    <Modal
      open={!!target}
      onClose={close}
      title={`Report this ${noun}`}
      subtitle="Reports are private. The person won't know who reported them."
      size="sm"
      footer={<><button className="btn-ghost" onClick={close}>Cancel</button><button className="btn" disabled={!reason || busy} onClick={submit}>{busy ? <Loader2 className="w-4 h-4 animate-spin" /> : <><Flag className="w-4 h-4" /> Send report</>}</button></>}
    >
      <div className="space-y-4">
        {target?.preview && <p className="text-sm rounded-2xl px-3.5 py-2.5 line-clamp-3" style={{ background: "var(--surface-2)", color: "var(--text-secondary)" }}>“{target.preview}”</p>}
        <div className="grid gap-1.5" role="radiogroup" aria-label="Reason">
          {REPORT_REASONS.map((r) => (
            <button key={r} role="radio" aria-checked={reason === r} onClick={() => setReason(r)} className="flex items-center gap-3 px-3.5 py-2.5 rounded-2xl text-sm font-semibold text-left transition-colors" style={reason === r ? { background: "var(--pink-soft)", color: "var(--accent-rose)", boxShadow: "inset 0 0 0 1px rgb(var(--accent-rgb) / 0.35)" } : { background: "var(--surface-2)", color: "var(--text-primary)" }}>
              <span className="w-5 h-5 rounded-full flex items-center justify-center flex-shrink-0" style={reason === r ? { background: "var(--accent-grad)", color: "#fff" } : { boxShadow: "inset 0 0 0 2px var(--border-strong)" }}>{reason === r && <Check className="w-3 h-3" />}</span>
              {r}
            </button>
          ))}
        </div>
        <textarea className="input resize-none" rows={2} placeholder="Anything else we should know? (optional)" value={details} onChange={(e) => setDetails(e.target.value)} maxLength={1000} />
      </div>
    </Modal>
  );
}
