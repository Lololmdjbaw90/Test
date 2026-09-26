import React, { useState } from "react";
import { Link } from "react-router-dom";
import { Ban, Loader2, Trash2, UserX } from "lucide-react";
import Modal from "@/components/common/Modal";
import Avatar from "@/components/common/Avatar";
import { useAuth } from "@/lib/AuthContext";
import { useLiveQuery } from "@/lib/useLiveQuery";
import { toast } from "@/lib/toast";
import { displayName, profileLink } from "@/lib/format";
import { deleteMyAccount, setBlocked } from "@/lib/safety";

export function BlockedPeople() {
  const { user, updateMe } = useAuth();
  const blocked = user?.blocked || [];
  const { data: users } = useLiveQuery("User", null, { live: false, enabled: blocked.length > 0 });
  const byEmail = Object.fromEntries(users.map((u) => [u.email, u]));
  const unblock = async (email) => {
    try { await setBlocked({ me: user, email, updateMe, block: false }); toast.success("Unblocked"); } catch (e) { toast.error(e?.message || "Could not unblock."); }
  };
  return (
    <div className="card-sm p-4">
      <div className="flex items-center gap-3">
        <Ban className="w-5 h-5 flex-shrink-0" style={{ color: "var(--text-secondary)" }} />
        <div className="flex-1"><p className="text-sm font-semibold" style={{ color: "var(--text-primary)" }}>Blocked people</p><p className="text-xs" style={{ color: "var(--text-muted)" }}>{blocked.length ? "They can't message or call you, and you won't see their posts." : "Block someone from their profile or a post's ⋯ menu."}</p></div>
      </div>
      {blocked.length > 0 && (
        <div className="mt-3 space-y-1">
          {blocked.map((email) => {
            const u = byEmail[email] || { email };
            return (
              <div key={email} className="flex items-center gap-3 p-2 rounded-2xl" style={{ background: "var(--surface-2)" }}>
                <Link to={profileLink(email)}><Avatar src={u.profile_picture} name={displayName(u)} size={32} /></Link>
                <span className="flex-1 min-w-0 text-sm font-semibold truncate" style={{ color: "var(--text-primary)" }}>{displayName(u)}</span>
                <button onClick={() => unblock(email)} className="btn-outline text-xs !py-1.5">Unblock</button>
              </div>
            );
          })}
        </div>
      )}
    </div>
  );
}

export function DeleteAccount() {
  const { user } = useAuth();
  const [open, setOpen] = useState(false);
  const [password, setPassword] = useState("");
  const [busy, setBusy] = useState(false);
  const [step, setStep] = useState("");
  const run = async () => {
    setBusy(true);
    try {
      await deleteMyAccount(user, password, setStep);
    } catch (e) {
      toast.error(e?.message || "Could not delete your account.");
      setBusy(false);
      setStep("");
    }
  };
  return (
    <>
      <div className="card-sm p-4 flex items-center gap-3">
        <UserX className="w-5 h-5 flex-shrink-0" style={{ color: "var(--danger)" }} />
        <div className="flex-1"><p className="text-sm font-semibold" style={{ color: "var(--text-primary)" }}>Delete account</p><p className="text-xs" style={{ color: "var(--text-muted)" }}>Permanently remove your account, posts, tracks, comments and messages.</p></div>
        <button className="btn-outline text-xs" style={{ color: "var(--danger)", borderColor: "rgb(224 82 107 / 0.4)" }} onClick={() => { setOpen(true); setPassword(""); }}>Delete</button>
      </div>
      <Modal
        open={open}
        onClose={() => !busy && setOpen(false)}
        title="Delete your account?"
        subtitle="This can't be undone."
        size="sm"
        footer={<><button className="btn-ghost" disabled={busy} onClick={() => setOpen(false)}>Cancel</button><button className="btn-danger rounded-full font-bold text-sm flex items-center gap-2" disabled={busy || !password} onClick={run}>{busy ? <Loader2 className="w-4 h-4 animate-spin" /> : <Trash2 className="w-4 h-4" />} Delete forever</button></>}
      >
        <div className="space-y-3">
          <p className="text-sm" style={{ color: "var(--text-secondary)" }}>Your profile, posts, tracks, commissions, comments, messages you sent, friendships and servers you own will be deleted. You'll be signed out.</p>
          <div>
            <label className="label" htmlFor="del-pw">Enter your password to confirm</label>
            <input id="del-pw" type="password" className="input" autoComplete="current-password" value={password} onChange={(e) => setPassword(e.target.value)} disabled={busy} onKeyDown={(e) => { if (e.key === "Enter" && password && !busy) run(); }} />
          </div>
          {step && <p className="text-xs font-semibold flex items-center gap-2" style={{ color: "var(--text-muted)" }}><Loader2 className="w-3.5 h-3.5 animate-spin" /> {step}</p>}
        </div>
      </Modal>
    </>
  );
}
