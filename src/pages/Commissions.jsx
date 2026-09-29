import React, { useEffect, useMemo, useState } from "react";
import { Link, useNavigate, useSearchParams } from "react-router-dom";
import { AnimatePresence, motion } from "framer-motion";
import { doc, getDoc, setDoc } from "firebase/firestore";
import {
  Banknote, Check, CheckCircle2, Clock, CreditCard, Hand, ImagePlus, Loader2, Lock, MessageSquare, Package,
  Paintbrush, Pencil, Plus, Send, ShieldCheck, ShoppingBag, Sparkles, Star, Store, Trash2, Undo2, X,
} from "lucide-react";
import { base44 } from "@/api/base44Client";
import { useAuth } from "@/lib/AuthContext";
import { useLiveQuery } from "@/lib/useLiveQuery";
import { checkText } from "@/lib/moderation";
import { toast } from "@/lib/toast";
import { displayName, profileLink } from "@/lib/format";
import { CURRENCIES, ORDER_STATUS, callPayments, earnings, isActiveOrder, money } from "@/lib/payments";
import { Page, PageHeader, EmptyState } from "@/components/common/Page";
import { SearchInput, Segmented, Toggle } from "@/components/common/Controls";
import Modal, { useConfirm } from "@/components/common/Modal";
import Avatar from "@/components/common/Avatar";

// Commissions: artists open a shop, buyers send a request, the artist accepts,
// the buyer pays by card (Stripe, through the payment server), the artist
// delivers and the buyer approves with a review. Only the payment server can
// mark an order paid.

const minPrice = (c) => (c.tiers?.length ? Math.min(...c.tiers.map((t) => Number(t.price) || 0)) : null);
const isOpen = (c) => c.is_open ?? c.status === "open";
const rating = (c) => (Number(c.rating_count) > 0 ? Number(c.rating_sum) / Number(c.rating_count) : null);
const byNewest = (a, b) => String(b.updated_date || "").localeCompare(String(a.updated_date || ""));
const upload = (file) => base44.integrations.Core.UploadFile({ file }).then((r) => r.file_url);

// Sugerly's cut, set by admins (Admin → Site in the app); the payment server uses the same number.
function useFeePercent() {
  const { data } = useLiveQuery("SiteConfig", { key: "global" }, { live: false });
  const fee = Number(data[0]?.commission_fee_percent);
  return Number.isFinite(fee) ? fee : 10;
}

function StatusPill({ open }) {
  return (
    <span className="inline-flex items-center gap-1.5 text-[11px] font-bold px-2.5 py-1 rounded-full" style={{ background: "var(--surface)", color: open ? "var(--success)" : "var(--text-muted)", border: "1px solid var(--border-c)" }}>
      <span className="w-1.5 h-1.5 rounded-full" style={{ background: open ? "var(--success)" : "var(--text-muted)" }} />{open ? "Open" : "Closed"}
    </span>
  );
}

function OrderBadge({ status }) {
  const s = ORDER_STATUS[status] || ORDER_STATUS.requested;
  return <span className="inline-flex items-center text-[11px] font-bold px-2.5 py-1 rounded-full" style={{ color: s.color, background: `${s.color}1f` }}>{s.label}</span>;
}

function Stars({ value, onChange, size = 18 }) {
  return (
    <div className="flex gap-1">
      {[1, 2, 3, 4, 5].map((i) => (
        <button key={i} type="button" disabled={!onChange} onClick={() => onChange?.(i)} aria-label={`${i} star${i === 1 ? "" : "s"}`}>
          <Star style={{ width: size, height: size, color: "#f0a020", fill: i <= value ? "#f0a020" : "none" }} />
        </button>
      ))}
    </div>
  );
}

function Thumbs({ files, setFiles, max }) {
  return (
    <div className="flex gap-2 flex-wrap">
      {files.map((s, i) => (
        <div key={s.url} className="relative w-20 h-20">
          <img src={s.url} alt="" className="w-full h-full rounded-2xl object-cover" />
          <button onClick={() => setFiles((x) => x.filter((_, j) => j !== i))} className="absolute -top-1.5 -right-1.5 w-6 h-6 rounded-full flex items-center justify-center text-white" style={{ background: "var(--text-primary)" }} aria-label="Remove"><X className="w-3 h-3" /></button>
        </div>
      ))}
      {files.length < max && (
        <label className="w-20 h-20 rounded-2xl flex items-center justify-center cursor-pointer" style={{ border: "2px dashed var(--border-strong)", color: "var(--text-muted)" }}>
          <ImagePlus className="w-5 h-5" />
          <input type="file" accept="image/*" multiple className="hidden" onChange={(e) => { const picked = [...(e.target.files || [])].slice(0, max - files.length); setFiles((x) => [...x, ...picked.map((file) => ({ file, url: URL.createObjectURL(file) }))]); e.target.value = ""; }} />
        </label>
      )}
    </div>
  );
}

// ---- opening / editing a shop listing ---------------------------------------

function ListingModal({ open, existing, onClose }) {
  const { user } = useAuth();
  const fee = useFeePercent();
  const blank = { title: "", description: "", is_open: true, tags: "", currency: "usd" };
  const [form, setForm] = useState(blank);
  const [tiers, setTiers] = useState([{ name: "Sketch", price: "", description: "", delivery_days: "" }, { name: "Full colour", price: "", description: "", delivery_days: "" }]);
  const [oldSamples, setOldSamples] = useState([]);
  const [samples, setSamples] = useState([]);
  const [busy, setBusy] = useState(false);
  useEffect(() => {
    if (!open) return;
    if (existing) {
      setForm({ title: existing.title || "", description: existing.description || "", is_open: isOpen(existing), tags: (existing.tags || []).join(", "), currency: existing.currency || "usd" });
      setTiers((existing.tiers || []).map((t) => ({ name: t.name || "", price: String(t.price ?? ""), description: t.description || "", delivery_days: t.delivery_days ? String(t.delivery_days) : "" })));
      setOldSamples(existing.samples || []);
    } else {
      setForm(blank);
      setOldSamples([]);
    }
    setSamples([]);
  }, [open, existing?.id]); // eslint-disable-line react-hooks/exhaustive-deps
  const setTier = (i, k, v) => setTiers((t) => t.map((x, j) => (j === i ? { ...x, [k]: v } : x)));
  const valid = tiers.filter((t) => t.name.trim() && Number(t.price) >= 1);
  const submit = async () => {
    if (!form.title.trim() || !valid.length) return;
    setBusy(true);
    try {
      const mod = await checkText(`${form.title} ${form.description} ${valid.map((t) => `${t.name} ${t.description}`).join(" ")}`, { user, where: "commission", kind: "caption" });
      if (!mod.safe) { toast.error("Listing blocked", { description: mod.reason }); setBusy(false); return; }
      const urls = [...oldSamples, ...(await Promise.all(samples.map((s) => upload(s.file))))];
      const data = {
        title: form.title.trim(), description: form.description.trim(), is_open: form.is_open, currency: form.currency,
        tags: form.tags.split(",").map((t) => t.trim().toLowerCase()).filter(Boolean).slice(0, 6),
        tiers: valid.map((t) => ({ name: t.name.trim(), price: Number(t.price), description: t.description.trim(), delivery_days: t.delivery_days ? Number(t.delivery_days) : null })),
        samples: urls, artist_display_name: displayName(user), artist_profile_picture: user.profile_picture || "",
      };
      if (existing) await base44.entities.Commission.update(existing.id, data);
      else await base44.entities.Commission.create({ ...data, artist_email: user.email });
      toast.success(existing ? "Listing saved" : "Your shop is open!");
      onClose();
    } catch (e) { toast.error(e?.message || "Could not save."); }
    setBusy(false);
  };
  return (
    <Modal open={open} onClose={onClose} title={existing ? "Edit listing" : "Open your shop"} subtitle="What you draw, your prices and a few samples. Buyers pay by card." size="lg"
      footer={<><button className="btn-ghost" onClick={onClose}>Cancel</button><button className="btn" disabled={busy || !form.title.trim() || !valid.length} onClick={submit}>{busy ? <Loader2 className="w-4 h-4 animate-spin" /> : existing ? "Save" : "Publish"}</button></>}>
      <div className="space-y-4">
        <div><label className="label" htmlFor="cm-title">Title</label><input id="cm-title" className="input" placeholder="e.g. Cute pet portraits" value={form.title} onChange={(e) => setForm((f) => ({ ...f, title: e.target.value }))} maxLength={80} /></div>
        <div><label className="label" htmlFor="cm-desc">About</label><textarea id="cm-desc" className="input resize-none" rows={3} placeholder="Your style, what's included, how you work…" value={form.description} onChange={(e) => setForm((f) => ({ ...f, description: e.target.value }))} maxLength={800} /></div>
        <div>
          <p className="label">Samples</p>
          <div className="flex gap-2 flex-wrap">
            {oldSamples.map((url) => (
              <div key={url} className="relative w-20 h-20">
                <img src={url} alt="" className="w-full h-full rounded-2xl object-cover" />
                <button onClick={() => setOldSamples((x) => x.filter((u) => u !== url))} className="absolute -top-1.5 -right-1.5 w-6 h-6 rounded-full flex items-center justify-center text-white" style={{ background: "var(--text-primary)" }} aria-label="Remove sample"><X className="w-3 h-3" /></button>
              </div>
            ))}
            <Thumbs files={samples} setFiles={setSamples} max={Math.max(0, 6 - oldSamples.length)} />
          </div>
        </div>
        <div>
          <div className="flex items-center justify-between">
            <p className="label">Prices</p>
            <select className="input !w-auto !min-h-[2rem] !py-1 text-xs font-bold" value={form.currency} onChange={(e) => setForm((f) => ({ ...f, currency: e.target.value }))} aria-label="Currency">
              {CURRENCIES.map((c) => <option key={c} value={c}>{c.toUpperCase()}</option>)}
            </select>
          </div>
          <div className="space-y-2">
            {tiers.map((t, i) => (
              <div key={i} className="card-sm p-3 grid grid-cols-[1fr_90px_80px_auto] gap-2 items-center">
                <input className="input !min-h-[2.2rem] !py-1.5" placeholder="Size name (e.g. Headshot)" value={t.name} onChange={(e) => setTier(i, "name", e.target.value)} />
                <input className="input !min-h-[2.2rem] !py-1.5" placeholder="Price" type="number" min="1" value={t.price} onChange={(e) => setTier(i, "price", e.target.value)} />
                <input className="input !min-h-[2.2rem] !py-1.5" placeholder="Days" type="number" min="1" value={t.delivery_days} onChange={(e) => setTier(i, "delivery_days", e.target.value)} />
                <button onClick={() => setTiers((x) => (x.length > 1 ? x.filter((_, j) => j !== i) : x))} className="icon-btn w-8 h-8" aria-label="Remove size" disabled={tiers.length === 1}><X className="w-4 h-4" /></button>
                <input className="input !min-h-[2.2rem] !py-1.5 col-span-4" placeholder="What's included (optional)" value={t.description} onChange={(e) => setTier(i, "description", e.target.value)} />
              </div>
            ))}
          </div>
          {tiers.length < 5 && <button className="btn-ghost text-xs mt-2" onClick={() => setTiers((x) => [...x, { name: "", price: "", description: "", delivery_days: "" }])}><Plus className="w-3.5 h-3.5" /> Add a size</button>}
        </div>
        <div><label className="label" htmlFor="cm-tags">Tags</label><input id="cm-tags" className="input" placeholder="portrait, anime, pets" value={form.tags} onChange={(e) => setForm((f) => ({ ...f, tags: e.target.value }))} /></div>
        <div className="card-sm p-3.5"><Toggle checked={form.is_open} onChange={(v) => setForm((f) => ({ ...f, is_open: v }))} label="Open for orders" description="Close it any time you're busy." /></div>
        <p className="text-xs flex gap-2" style={{ color: "var(--text-muted)" }}><Banknote className="w-4 h-4 flex-shrink-0" /> Buyers pay by card through Stripe. You get paid out after they approve your art, minus Sugerly's {fee}% fee. Add your payout details in My shop.</p>
      </div>
    </Modal>
  );
}

// ---- a listing, with the request form -----------------------------------------

function ListingDetail({ commission, onClose, onEdit, onOrdered }) {
  const navigate = useNavigate();
  const { user } = useAuth();
  const confirm = useConfirm();
  const [idx, setIdx] = useState(0);
  const [tier, setTier] = useState(0);
  const [requesting, setRequesting] = useState(false);
  const [brief, setBrief] = useState("");
  const [refs, setRefs] = useState([]);
  const [busy, setBusy] = useState(false);
  const mine = user?.email === commission.artist_email;
  const owner = mine || user?.role === "admin";
  const open = isOpen(commission);
  const currency = commission.currency || "usd";
  const picked = commission.tiers?.[tier];
  const r = rating(commission);

  const toggle = () => base44.entities.Commission.update(commission.id, { is_open: !open }).then(() => toast.success(open ? "Your shop is closed" : "Your shop is open")).catch((e) => toast.error(e?.message || "Could not update."));
  const del = async () => {
    if (!(await confirm({ title: "Delete listing?", message: "Orders already placed stay as they are.", confirmLabel: "Delete", danger: true }))) return;
    try { await base44.entities.Commission.delete(commission.id); toast.success("Listing deleted"); onClose(); } catch (e) { toast.error(e?.message || "Could not delete."); }
  };
  const send = async () => {
    if (brief.trim().length < 10 || !picked) return;
    setBusy(true);
    try {
      const mod = await checkText(brief, { user, where: "commission request", kind: "post" });
      if (!mod.safe) { toast.error("Request blocked", { description: mod.reason }); setBusy(false); return; }
      const urls = await Promise.all(refs.map((s) => upload(s.file)));
      const created = await base44.entities.CommissionOrder.create({
        commission_id: commission.id, commission_title: commission.title, tier_name: picked.name, cover_url: commission.samples?.[0] || "",
        price: Number(picked.price), currency, brief: brief.trim(), references: urls,
        buyer_email: user.email, buyer_name: displayName(user), artist_email: commission.artist_email, artist_name: commission.artist_display_name, artist_uid: "",
        status: "requested",
      });
      await base44.entities.Notification.create({
        to_email: commission.artist_email, from_email: user.email, from_display_name: displayName(user), from_profile_picture: user.profile_picture || "",
        type: "commission", message: `${displayName(user)} sent you a commission request for "${commission.title}"`, link: `/Commissions?order=${created.id}`, is_read: false,
      }).catch(() => {});
      toast.success("Request sent!");
      onOrdered(created.id);
    } catch (e) { toast.error(e?.message || "Could not send the request."); }
    setBusy(false);
  };

  return (
    <Modal open onClose={onClose} size="xl" padded={false} hideHeader autoFocus={false}>
      {commission.samples?.length > 0 && (
        <div className="relative h-64 sm:h-80 overflow-hidden" style={{ background: "var(--surface-2)" }}>
          <AnimatePresence mode="wait"><motion.img key={idx} src={commission.samples[idx]} alt="" initial={{ opacity: 0 }} animate={{ opacity: 1 }} exit={{ opacity: 0 }} className="absolute inset-0 w-full h-full object-cover" /></AnimatePresence>
          <div className="absolute top-4 left-4"><StatusPill open={open} /></div>
          {commission.samples.length > 1 && <div className="absolute bottom-3 inset-x-0 flex justify-center gap-1.5">{commission.samples.map((s, i) => <button key={s} onClick={() => setIdx(i)} className="w-12 h-12 rounded-xl overflow-hidden" style={{ boxShadow: i === idx ? "0 0 0 2px #fff" : "none" }}><img src={s} alt="" className="w-full h-full object-cover" /></button>)}</div>}
        </div>
      )}
      <div className="p-5 sm:p-7 space-y-5">
        <div>
          <h2 className="font-display text-3xl font-semibold pr-10" style={{ color: "var(--text-primary)" }}>{commission.title}</h2>
          <Link to={profileLink(commission.artist_email)} onClick={onClose} className="flex items-center gap-2 mt-2 w-fit group flex-wrap">
            <Avatar src={commission.artist_profile_picture} name={commission.artist_display_name} size={28} />
            <span className="text-sm font-semibold group-hover:underline" style={{ color: "var(--text-secondary)" }}>{commission.artist_display_name}</span>
            {r != null && <span className="text-xs font-bold flex items-center gap-1" style={{ color: "#f0a020" }}><Star className="w-3.5 h-3.5 fill-current" />{r.toFixed(1)} ({commission.rating_count})</span>}
            {Number(commission.orders_completed) > 0 && <span className="text-xs font-semibold" style={{ color: "var(--text-muted)" }}>· {commission.orders_completed} sold</span>}
          </Link>
        </div>
        {commission.description && <p className="text-sm leading-relaxed whitespace-pre-wrap" style={{ color: "var(--text-secondary)" }}>{commission.description}</p>}
        {commission.tags?.length > 0 && <div className="flex flex-wrap gap-1.5">{commission.tags.map((t) => <span key={t} className="badge-pink">#{t}</span>)}</div>}
        {commission.tiers?.length > 0 && (
          <div className="grid sm:grid-cols-2 gap-3">
            {commission.tiers.map((t, i) => (
              <button key={i} onClick={() => setTier(i)} className="card-sm p-4 text-left" style={i === tier ? { borderColor: "var(--accent-rose)", boxShadow: "0 0 0 3px rgb(var(--accent-rgb) / 0.15)" } : undefined}>
                <div className="flex items-start justify-between gap-2">
                  <p className="font-bold flex items-center gap-2" style={{ color: "var(--text-primary)" }}>{i === tier ? <CheckCircle2 className="w-4 h-4" style={{ color: "var(--accent-rose)" }} /> : <span className="w-4 h-4 rounded-full" style={{ border: "2px solid var(--border-strong)" }} />}{t.name}</p>
                  <p className="font-display text-2xl font-semibold gradient-text">{money(t.price, currency)}</p>
                </div>
                {t.description && <p className="text-xs mt-1" style={{ color: "var(--text-muted)" }}>{t.description}</p>}
                {t.delivery_days && <p className="text-[11px] mt-2 flex items-center gap-1" style={{ color: "var(--text-muted)" }}><Clock className="w-3 h-3" /> Ready in about {t.delivery_days} day{Number(t.delivery_days) === 1 ? "" : "s"}</p>}
              </button>
            ))}
          </div>
        )}
        {requesting && picked && (
          <div className="card-sm p-4 space-y-3">
            <label className="label" htmlFor="req-brief">What would you like? ({picked.name} · {money(picked.price, currency)})</label>
            <textarea id="req-brief" className="input resize-none" rows={4} placeholder="Describe it: who or what, pose, colours, mood, where you'll use it…" value={brief} onChange={(e) => setBrief(e.target.value)} maxLength={1500} />
            <p className="label">References (optional)</p>
            <Thumbs files={refs} setFiles={setRefs} max={4} />
            <ol className="text-xs space-y-1" style={{ color: "var(--text-secondary)" }}>
              <li>1. The artist accepts (they can adjust the price)</li>
              <li>2. You pay by card, safely through Stripe</li>
              <li>3. They make your art and deliver it here</li>
              <li>4. You approve it, and then the artist gets paid</li>
            </ol>
            <button className="btn w-full" disabled={busy || brief.trim().length < 10} onClick={send}>{busy ? <Loader2 className="w-4 h-4 animate-spin" /> : <><Send className="w-4 h-4" /> Send request</>}</button>
          </div>
        )}
        <div className="flex flex-wrap gap-2">
          {!mine && open && picked && !requesting && <button onClick={() => setRequesting(true)} className="btn flex-1"><Send className="w-4 h-4" /> Request · {money(picked.price, currency)}</button>}
          {!mine && !open && <span className="btn-outline flex-1 pointer-events-none"><Lock className="w-4 h-4" /> This shop is closed right now</span>}
          {!mine && <button onClick={() => { onClose(); navigate(`/DirectMessages?with=${encodeURIComponent(commission.artist_email)}`); }} className="btn-outline"><MessageSquare className="w-4 h-4" /> Ask the artist</button>}
          {owner && <button onClick={toggle} className="btn-outline flex-1">{open ? "Close shop" : "Open shop"}</button>}
          {owner && <button onClick={() => onEdit(commission)} className="btn-outline"><Pencil className="w-4 h-4" /> Edit</button>}
          {owner && <button onClick={del} className="btn-outline" style={{ color: "var(--danger)" }}><Trash2 className="w-4 h-4" /> Delete</button>}
        </div>
        <p className="text-xs flex gap-2" style={{ color: "var(--text-muted)" }}><ShieldCheck className="w-4 h-4 flex-shrink-0" /> Pay safely by card through Stripe. The artist only gets paid once you approve your art.</p>
      </div>
    </Modal>
  );
}

// ---- one order ----------------------------------------------------------------

const STEPS = [["Sent", Send], ["Accepted", Hand], ["Paid", CreditCard], ["Working", Paintbrush], ["Delivered", Package], ["Done", Star]];

function OrderModal({ order, onClose }) {
  const { user, isAdmin } = useAuth();
  const navigate = useNavigate();
  const confirm = useConfirm();
  const [busy, setBusy] = useState(false);
  const [quote, setQuote] = useState(String(order.price ?? ""));
  const [currency, setCurrency] = useState(order.currency || "usd");
  const [note, setNote] = useState("");
  const [files, setFiles] = useState([]);
  const [deliverNote, setDeliverNote] = useState("");
  const [stars, setStars] = useState(5);
  const [review, setReview] = useState("");
  const [payoutsReady, setPayoutsReady] = usePayoutsReady();
  const isBuyer = order.buyer_email === user.email;
  const isArtist = order.artist_email === user.email;
  const st = ORDER_STATUS[order.status] || ORDER_STATUS.requested;
  const other = isBuyer ? order.artist_email : order.buyer_email;
  // Started paying but it still says "waiting for payment": ask Stripe, in
  // case the "payment done" page was closed before it could confirm.
  const checkPaid = isBuyer && order.status === "accepted" && !!order.stripe_session_id;
  useEffect(() => {
    if (!checkPaid) return;
    callPayments("commission-confirm", { orderId: order.id })
      .then((r) => { if (r?.status === "paid") toast.success("Payment done! The artist has been told."); })
      .catch(() => {});
  }, [checkPaid, order.id]);

  const tell = (to, message) => base44.entities.Notification.create({
    to_email: to, from_email: user.email, from_display_name: displayName(user), from_profile_picture: user.profile_picture || "",
    type: "commission", message, link: `/Commissions?order=${order.id}`, is_read: false,
  }).catch(() => {});
  const update = async (fields, message) => {
    setBusy(true);
    try {
      await base44.entities.CommissionOrder.update(order.id, fields);
      if (message) tell(other, message);
      return true;
    } catch (e) { toast.error(e?.message || "Could not update the order."); return false; }
    finally { setBusy(false); }
  };
  const accept = async () => {
    const price = Number(String(quote).replace(",", "."));
    if (!(price >= 1)) { toast.error("Enter a price of at least 1."); return; }
    if (await update({ status: "accepted", price: Math.round(price * 100) / 100, currency, quote_note: note.trim() }, `${displayName(user)} accepted your commission "${order.commission_title}" for ${money(price, currency)}. Pay to get started!`)) toast.success("Accepted!");
  };
  const ask = async (kind) => {
    const labels = { decline: ["Decline this request?", "Decline"], cancel: ["Cancel this order?", "Cancel order"], refund: ["Ask for a refund?", "Ask for refund"] };
    if (!(await confirm({ title: labels[kind][0], message: kind === "refund" ? "The Sugerly team will look at it and refund you if it's fair." : "This can't be undone.", confirmLabel: labels[kind][1], danger: true }))) return;
    if (kind === "decline") update({ status: "declined" }, `${displayName(user)} declined your commission request "${order.commission_title}"`);
    if (kind === "cancel") update({ status: "cancelled" }, `${displayName(user)} cancelled the commission "${order.commission_title}"`);
    if (kind === "refund") update({ status: "refund_requested" }, `${displayName(user)} asked for a refund on "${order.commission_title}"`);
  };
  const pay = async () => {
    setBusy(true);
    try {
      const { url } = await callPayments("commission-checkout", { orderId: order.id });
      window.location.href = url;
    } catch (e) { toast.error(e?.message || "Couldn't open the payment page."); setBusy(false); }
  };
  const deliver = async () => {
    if (!files.length) return;
    setBusy(true);
    try {
      const urls = await Promise.all(files.map((s) => upload(s.file)));
      await base44.entities.CommissionOrder.update(order.id, { status: "delivered", delivery_urls: urls, delivery_note: deliverNote.trim(), delivered_at: new Date().toISOString() });
      tell(order.buyer_email, `${displayName(user)} delivered your commission "${order.commission_title}"! Take a look.`);
      setFiles([]);
      toast.success("Delivered!");
    } catch (e) { toast.error(e?.message || "Could not deliver."); }
    setBusy(false);
  };
  const approve = async () => {
    setBusy(true);
    try {
      if (review.trim()) {
        const mod = await checkText(review, { user, where: "review", kind: "comment" });
        if (!mod.safe) { toast.error("Review blocked", { description: mod.reason }); setBusy(false); return; }
      }
      await base44.entities.CommissionOrder.update(order.id, { status: "completed", rating: stars, review: review.trim(), completed_at: new Date().toISOString() });
      await callPayments("commission-review", { orderId: order.id }).catch(() => {});
      toast.success("Approved! Thank you");
    } catch (e) { toast.error(e?.message || "Could not approve."); }
    setBusy(false);
  };
  const refund = async () => {
    setBusy(true);
    try { await callPayments("commission-refund", { orderId: order.id }); toast.success("Refunded"); } catch (e) { toast.error(e?.message || "Could not refund."); }
    setBusy(false);
  };

  return (
    <Modal open onClose={onClose} title={order.commission_title || "Commission"} subtitle={`${order.tier_name ? `${order.tier_name} · ` : ""}${money(order.price, order.currency)}`} size="lg">
      <div className="space-y-5">
        <div className="flex items-center gap-3 flex-wrap">
          <OrderBadge status={order.status} />
          <span className="text-xs" style={{ color: "var(--text-muted)" }}>{isBuyer ? `by ${order.artist_name}` : `for ${order.buyer_name}`}</span>
          <button className="btn-ghost text-xs ml-auto" onClick={() => { onClose(); navigate(`/DirectMessages?with=${encodeURIComponent(other)}`); }}><MessageSquare className="w-3.5 h-3.5" /> Message</button>
        </div>
        {st.step >= 0 ? (
          <div className="grid grid-cols-6 gap-1">
            {STEPS.map(([label, Icon], i) => (
              <div key={label} className="flex flex-col items-center gap-1">
                <span className="w-8 h-8 rounded-full flex items-center justify-center" style={i <= st.step ? { background: "var(--accent-grad)", color: "#fff" } : { background: "var(--surface-2)", color: "var(--text-muted)" }}><Icon className="w-3.5 h-3.5" /></span>
                <span className="text-[10px] font-bold" style={{ color: i <= st.step ? "var(--text-primary)" : "var(--text-muted)" }}>{label}</span>
              </div>
            ))}
          </div>
        ) : <p className="card-sm p-3 text-sm" style={{ color: "var(--text-secondary)" }}>{order.status === "refunded" ? "This order was refunded." : order.status === "declined" ? "The artist declined this request." : "This order was cancelled."}</p>}
        <div className="card-sm p-4 space-y-2">
          <p className="text-xs font-bold" style={{ color: "var(--accent-rose)" }}>The request</p>
          <p className="text-sm whitespace-pre-wrap" style={{ color: "var(--text-secondary)" }}>{order.brief}</p>
          {order.references?.length > 0 && <div className="flex gap-2 flex-wrap">{order.references.map((u) => <a key={u} href={u} target="_blank" rel="noopener noreferrer"><img src={u} alt="" className="w-20 h-20 rounded-xl object-cover" /></a>)}</div>}
          {order.quote_note && <p className="text-sm p-3 rounded-xl" style={{ background: "var(--pink-soft)", color: "var(--text-secondary)" }}><b>From the artist:</b> {order.quote_note}</p>}
        </div>
        {(order.delivery_urls?.length > 0 || order.delivery_note) && (
          <div className="card-sm p-4 space-y-2">
            <p className="text-xs font-bold" style={{ color: "#e8457c" }}>Your art</p>
            <div className="grid grid-cols-2 sm:grid-cols-3 gap-2">{(order.delivery_urls || []).map((u) => <a key={u} href={u} target="_blank" rel="noopener noreferrer"><img src={u} alt="" className="w-full h-36 rounded-xl object-cover" /></a>)}</div>
            {order.delivery_note && <p className="text-sm" style={{ color: "var(--text-secondary)" }}>{order.delivery_note}</p>}
          </div>
        )}
        {order.status === "completed" && order.rating > 0 && <div className="card-sm p-4 space-y-1"><Stars value={order.rating} />{order.review && <p className="text-sm" style={{ color: "var(--text-secondary)" }}>“{order.review}”</p>}</div>}

        {order.status === "requested" && isArtist && (
          <div className="space-y-2">
            <p className="label">Set your price</p>
            <div className="flex gap-2">
              <select className="input !w-24" value={currency} onChange={(e) => setCurrency(e.target.value)} aria-label="Currency">{CURRENCIES.map((c) => <option key={c} value={c}>{c.toUpperCase()}</option>)}</select>
              <input className="input" type="number" min="1" value={quote} onChange={(e) => setQuote(e.target.value)} aria-label="Price" />
            </div>
            <textarea className="input resize-none" rows={2} placeholder="A note for the buyer (optional)" value={note} onChange={(e) => setNote(e.target.value)} />
            {payoutsReady === false && <><SetUpPayoutsNotice /><PayoutDetails onSaved={() => setPayoutsReady(true)} /></>}
            <div className="flex gap-2"><button className="btn flex-1" disabled={busy || payoutsReady !== true} onClick={accept}><Hand className="w-4 h-4" /> Accept request</button><button className="btn-outline" onClick={() => ask("decline")}>Decline</button></div>
          </div>
        )}
        {order.status === "requested" && isBuyer && <button className="btn-outline w-full" onClick={() => ask("cancel")}>Cancel request</button>}
        {order.status === "accepted" && isBuyer && (
          <div className="space-y-2">
            <button className="btn w-full" disabled={busy} onClick={pay}>{busy ? <Loader2 className="w-4 h-4 animate-spin" /> : <><CreditCard className="w-4 h-4" /> Pay {money(order.price, order.currency)} by card</>}</button>
            <p className="text-xs text-center" style={{ color: "var(--text-muted)" }}>Card, Apple Pay, Google Pay and more · secured by Stripe</p>
            <button className="btn-ghost w-full text-xs" onClick={() => ask("cancel")}>Cancel order</button>
          </div>
        )}
        {order.status === "accepted" && isArtist && <p className="card-sm p-3 text-sm" style={{ color: "var(--text-secondary)" }}>Waiting for the buyer to pay. You'll get a notification.</p>}
        {["paid", "in_progress", "delivered"].includes(order.status) && isArtist && (
          <div className="space-y-2">
            {order.status === "paid" && <button className="btn-outline w-full" disabled={busy} onClick={() => update({ status: "in_progress" }, `${displayName(user)} started working on "${order.commission_title}"`)}><Paintbrush className="w-4 h-4" /> Start working</button>}
            <p className="label">{order.status === "delivered" ? "Send a new version" : "Deliver the art"}</p>
            <Thumbs files={files} setFiles={setFiles} max={8} />
            <textarea className="input resize-none" rows={2} placeholder="A note for the buyer (optional)" value={deliverNote} onChange={(e) => setDeliverNote(e.target.value)} />
            <button className="btn w-full" disabled={busy || !files.length} onClick={deliver}>{busy ? <Loader2 className="w-4 h-4 animate-spin" /> : <><Package className="w-4 h-4" /> Deliver</>}</button>
          </div>
        )}
        {["paid", "in_progress"].includes(order.status) && isBuyer && (
          <div className="space-y-2"><p className="card-sm p-3 text-sm" style={{ color: "var(--text-secondary)" }}>Paid! The artist is making your art.</p><button className="btn-ghost w-full text-xs" onClick={() => ask("refund")}><Undo2 className="w-3.5 h-3.5" /> Something wrong? Ask for a refund</button></div>
        )}
        {order.status === "delivered" && isBuyer && (
          <div className="space-y-2">
            <p className="label">How did {order.artist_name} do?</p>
            <Stars value={stars} onChange={setStars} size={28} />
            <textarea className="input resize-none" rows={2} placeholder="Say something nice about your art (optional)" value={review} onChange={(e) => setReview(e.target.value)} />
            <button className="btn w-full" disabled={busy} onClick={approve}><Star className="w-4 h-4" /> Approve and review</button>
            <button className="btn-ghost w-full text-xs" onClick={() => ask("refund")}><Undo2 className="w-3.5 h-3.5" /> Not right? Ask for a refund</button>
          </div>
        )}
        {order.status === "completed" && isArtist && <p className="card-sm p-3 text-sm" style={{ color: "var(--text-secondary)" }}>{order.payout_status === "paid_out" ? `Sugerly sent you ${money(earnings(order), order.currency)} by PayPal. Check your PayPal account.` : `Approved! Sugerly will send you ${money(earnings(order), order.currency)} by PayPal, to the email in My shop → Payout details.`}</p>}
        {order.status === "refund_requested" && <p className="card-sm p-3 text-sm" style={{ color: "var(--text-secondary)" }}>A refund was asked for. The Sugerly team will sort it out.</p>}
        {isAdmin && ["refund_requested", "paid", "in_progress", "delivered"].includes(order.status) && <button className="btn-outline w-full" disabled={busy} onClick={refund}><Undo2 className="w-4 h-4" /> Admin: refund the buyer</button>}
        <p className="text-xs flex gap-2" style={{ color: "var(--text-muted)" }}><ShieldCheck className="w-4 h-4 flex-shrink-0" />{order.fee_percent != null ? `Paid by card through Stripe. Sugerly keeps ${order.fee_percent}% to run the app; the artist gets the rest once the buyer approves.` : "Payments go through Stripe. The artist only gets paid once the buyer approves the art."}</p>
      </div>
    </Modal>
  );
}

function OrderRow({ order, asBuyer, onOpen }) {
  const needsMe = asBuyer ? ["accepted", "delivered"].includes(order.status) : ["requested", "paid", "in_progress"].includes(order.status);
  return (
    <button onClick={onOpen} className="card-sm p-3 flex items-center gap-3 w-full text-left" style={needsMe ? { borderColor: "rgb(var(--accent-rgb) / 0.45)" } : undefined}>
      {order.cover_url ? <img src={order.cover_url} alt="" className="w-16 h-16 rounded-2xl object-cover flex-shrink-0" /> : <span className="w-16 h-16 rounded-2xl flex-shrink-0" style={{ background: "var(--accent-grad)" }} />}
      <div className="min-w-0 flex-1">
        <div className="flex items-center gap-2"><p className="font-bold truncate" style={{ color: "var(--text-primary)" }}>{order.commission_title || "Commission"}</p><span className="ml-auto font-bold text-sm" style={{ color: "var(--accent-rose)" }}>{money(order.price, order.currency)}</span></div>
        <p className="text-xs truncate" style={{ color: "var(--text-muted)" }}>{asBuyer ? `by ${order.artist_name}` : `for ${order.buyer_name}`}{order.tier_name ? ` · ${order.tier_name}` : ""}</p>
        <div className="mt-1"><OrderBadge status={order.status} /></div>
      </div>
    </button>
  );
}

// ---- artist money --------------------------------------------------------------

function Earnings({ orders }) {
  const fee = useFeePercent();
  const currency = orders.find((o) => o.amount_paid != null)?.currency || "usd";
  const sum = (list) => list.reduce((n, o) => n + earnings(o), 0);
  const pending = sum(orders.filter((o) => ["paid", "in_progress", "delivered"].includes(o.status)));
  const ready = sum(orders.filter((o) => o.status === "completed" && o.payout_status !== "paid_out"));
  const paid = sum(orders.filter((o) => o.status === "completed" && o.payout_status === "paid_out"));
  return (
    <div className="card p-5 space-y-3">
      <p className="font-bold flex items-center gap-2" style={{ color: "var(--text-primary)" }}><Banknote className="w-4 h-4" style={{ color: "var(--success)" }} /> Your earnings</p>
      <div className="grid grid-cols-3 gap-2">
        {[[pending, "In progress", "#2f80e0"], [ready, "To be paid", "#17a673"], [paid, "Paid out", "#86707c"]].map(([v, l, c]) => (
          <div key={l} className="rounded-2xl p-3 text-center" style={{ background: `${c}14` }}><p className="font-bold" style={{ color: c }}>{money(v, currency)}</p><p className="text-[11px] font-semibold" style={{ color: "var(--text-muted)" }}>{l}</p></div>
        ))}
      </div>
      <p className="text-xs" style={{ color: "var(--text-muted)" }}>Buyers pay by card. When they approve your art, Sugerly pays you out (minus Sugerly's {fee}% fee) to your payout details.</p>
    </div>
  );
}

// Artists need payout details before they can take paid orders, so Sugerly
// knows where to send their money. null while loading; local mode has no
// payouts, so it's always ready there.
function usePayoutsReady() {
  const { user } = useAuth();
  const db = base44.firebase?.db;
  const [ready, setReady] = useState(db ? null : true);
  useEffect(() => {
    if (!db || !user?.id) return;
    getDoc(doc(db, "PayoutInfo", user.id))
      .then((snap) => setReady(snap.exists() && String(snap.data().paypal_email || "").includes("@")))
      .catch(() => setReady(false));
  }, [db, user?.id]);
  return [ready, setReady];
}

function SetUpPayoutsNotice() {
  return (
    <div className="rounded-3xl p-4 flex gap-3" style={{ background: "rgb(240 160 32 / 0.1)", boxShadow: "inset 0 0 0 1px rgb(240 160 32 / 0.35)" }}>
      <span className="w-10 h-10 rounded-xl flex items-center justify-center text-white flex-shrink-0" style={{ background: "linear-gradient(135deg,#ffb38a,#f0a020)" }}><Banknote className="w-5 h-5" /></span>
      <div>
        <p className="font-bold text-sm" style={{ color: "var(--text-primary)" }}>Set up payouts first</p>
        <p className="text-xs" style={{ color: "var(--text-muted)" }}>Add the PayPal email where Sugerly should send your money. You can accept paid requests once it's saved.</p>
      </div>
    </div>
  );
}

function PayoutDetails({ onSaved }) {
  const { user } = useAuth();
  const [form, setForm] = useState({ paypal_email: "", full_name: "" });
  const [saving, setSaving] = useState(false);
  const db = base44.firebase?.db;
  useEffect(() => {
    if (!db || !user?.id) return;
    getDoc(doc(db, "PayoutInfo", user.id)).then((snap) => { if (snap.exists()) setForm({ paypal_email: snap.data().paypal_email || "", full_name: snap.data().full_name || "" }); }).catch(() => {});
  }, [db, user?.id]);
  if (!db) return null;
  const save = async () => {
    setSaving(true);
    try {
      await setDoc(doc(db, "PayoutInfo", user.id), { paypal_email: form.paypal_email.trim().toLowerCase(), full_name: form.full_name.trim(), email: user.email, updated_date: new Date().toISOString() }, { merge: true });
      toast.success("Payout details saved");
      onSaved?.();
    } catch (e) { toast.error(e?.message || "Could not save."); }
    setSaving(false);
  };
  return (
    <div className="card p-5 space-y-3">
      <p className="font-bold flex items-center gap-2" style={{ color: "var(--text-primary)" }}><Lock className="w-4 h-4" style={{ color: "var(--accent-rose)" }} /> Payout details</p>
      <p className="text-xs" style={{ color: "var(--text-muted)" }}>Where Sugerly sends your money. Only you and the Sugerly team can see this.</p>
      <div className="grid sm:grid-cols-2 gap-2">
        <input className="input" type="email" placeholder="PayPal email" value={form.paypal_email} onChange={(e) => setForm((f) => ({ ...f, paypal_email: e.target.value }))} />
        <input className="input" placeholder="Your full name" value={form.full_name} onChange={(e) => setForm((f) => ({ ...f, full_name: e.target.value }))} />
      </div>
      <button className="btn" disabled={saving || !form.paypal_email.includes("@")} onClick={save}>{saving ? <Loader2 className="w-4 h-4 animate-spin" /> : <><Check className="w-4 h-4" /> Save payout details</>}</button>
    </div>
  );
}

function AdminPayouts({ onOpen }) {
  const { user } = useAuth();
  const { data: completed } = useLiveQuery("CommissionOrder", { status: "completed" });
  const { data: refunds } = useLiveQuery("CommissionOrder", { status: "refund_requested" });
  const [payouts, setPayouts] = useState({});
  const owed = completed.filter((o) => o.payout_status !== "paid_out");
  const groups = owed.reduce((m, o) => ({ ...m, [o.artist_email]: [...(m[o.artist_email] || []), o] }), {});
  const db = base44.firebase?.db;
  useEffect(() => {
    if (!db) return;
    Promise.all(Object.keys(groups).map(async (email) => {
      const users = await base44.entities.User.filter({ email }, null, 1).catch(() => []);
      const uid = users[0]?.id;
      if (!uid) return [email, ""];
      const snap = await getDoc(doc(db, "PayoutInfo", uid)).catch(() => null);
      return [email, snap?.exists() ? snap.data().paypal_email || "" : ""];
    })).then((pairs) => setPayouts(Object.fromEntries(pairs)));
  }, [db, Object.keys(groups).join(",")]); // eslint-disable-line react-hooks/exhaustive-deps
  const markPaid = async (list) => {
    const now = new Date().toISOString();
    const artist = list[0].artist_email;
    const total = money(list.reduce((n, o) => n + earnings(o), 0), list[0].currency);
    try {
      await Promise.all(list.map((o) => base44.entities.CommissionOrder.update(o.id, { payout_status: "paid_out", payout_at: now })));
      // Tell the artist where the money went, so they know to check.
      await base44.entities.Notification.create({
        to_email: artist, from_email: user.email, from_display_name: "Sugerly", from_profile_picture: "",
        type: "commission", link: "/Commissions",
        message: `Sugerly sent you ${total} for ${list.length} commission${list.length === 1 ? "" : "s"}${payouts[artist] ? ` to your PayPal (${payouts[artist]})` : " by PayPal"}. Check your PayPal account!`,
        is_read: false, created_by: user.email, created_date: now, updated_date: now,
      }).catch(() => {});
      toast.success("Marked as paid out · the artist has been told");
    } catch (e) { toast.error(e?.message || "Could not update."); }
  };
  return (
    <div className="card p-5 space-y-3">
      <p className="font-bold flex items-center gap-2" style={{ color: "var(--text-primary)" }}><ShieldCheck className="w-4 h-4" style={{ color: "#7c5cf0" }} /> Admin · payouts</p>
      {!owed.length && !refunds.length && <p className="text-sm" style={{ color: "var(--text-muted)" }}>Nothing to pay out or refund right now.</p>}
      {Object.entries(groups).map(([email, list]) => (
        <div key={email} className="card-sm p-3 flex items-center gap-3 flex-wrap">
          <div className="min-w-0 flex-1"><p className="font-bold truncate" style={{ color: "var(--text-primary)" }}>{list[0].artist_name || email}</p><p className="text-xs select-all" style={{ color: "var(--text-muted)" }}>{payouts[email] ? `PayPal: ${payouts[email]}` : "No payout details yet"}</p></div>
          <span className="font-bold" style={{ color: "var(--success)" }}>{money(list.reduce((n, o) => n + earnings(o), 0), list[0].currency)}</span>
          <button className="btn-outline text-xs" onClick={() => markPaid(list)}><Check className="w-3.5 h-3.5" /> Mark {list.length} paid out</button>
        </div>
      ))}
      {refunds.map((o) => <OrderRow key={o.id} order={o} asBuyer={false} onOpen={() => onOpen(o.id)} />)}
    </div>
  );
}

// ---- the page ------------------------------------------------------------------

export default function CommissionsPage() {
  const { user, isAdmin } = useAuth();
  const [params, setParams] = useSearchParams();
  const [search, setSearch] = useState("");
  const [tab, setTab] = useState(params.get("order") ? "orders" : "explore");
  const [filter, setFilter] = useState("all");
  const [editing, setEditing] = useState(null);
  const { data: commissions, loading } = useLiveQuery("Commission", null, { sort: "-created_date" });
  const { data: buyingRaw } = useLiveQuery("CommissionOrder", { buyer_email: user.email });
  const { data: sellingRaw } = useLiveQuery("CommissionOrder", { artist_email: user.email });
  const buying = useMemo(() => [...buyingRaw].sort(byNewest), [buyingRaw]);
  const selling = useMemo(() => [...sellingRaw].sort(byNewest), [sellingRaw]);
  const [loose, setLoose] = useState(null);
  const [payoutsReady, setPayoutsReady] = usePayoutsReady();
  const orderId = params.get("order");
  const order = buying.find((o) => o.id === orderId) || selling.find((o) => o.id === orderId) || (loose?.id === orderId ? loose : null);
  useEffect(() => {
    if (!orderId || order) return;
    base44.entities.CommissionOrder.get(orderId).then((o) => o && setLoose(o)).catch(() => {});
  }, [orderId, !!order]); // eslint-disable-line react-hooks/exhaustive-deps

  const filtered = useMemo(() => {
    const q = search.trim().toLowerCase();
    let list = commissions.filter((c) => !q || [c.title, c.description, c.artist_display_name, ...(c.tags || [])].some((f) => String(f || "").toLowerCase().includes(q)));
    if (filter === "open") list = list.filter(isOpen);
    if (filter === "budget") list = list.filter((c) => (minPrice(c) ?? 0) < 50);
    if (filter === "top") list = list.filter((c) => rating(c) != null).sort((a, b) => rating(b) - rating(a));
    else list = [...list].sort((a, b) => Number(isOpen(b)) - Number(isOpen(a)));
    return list;
  }, [commissions, search, filter]);
  const mine = commissions.filter((c) => c.artist_email === user.email);
  const selected = commissions.find((c) => c.id === params.get("c")) || null;
  const openOrder = (id) => setParams({ order: id });
  const needBuy = buying.filter((o) => ["accepted", "delivered"].includes(o.status)).length;
  const needSell = selling.filter((o) => ["requested", "paid", "in_progress"].includes(o.status)).length;

  return (
    <Page width="max-w-6xl">
      <PageHeader eyebrow="Hire an artist" title="Commissions" subtitle="Hire artists you love · pay safely by card" icon={Store}
        actions={<button className="btn" onClick={() => setParams({ create: "1" })}><Plus className="w-4 h-4" /> {mine.length ? "New listing" : "Open your shop"}</button>}>
        <Segmented options={[{ id: "explore", label: "Explore" }, { id: "orders", label: `My orders${needBuy ? ` (${needBuy})` : ""}` }, { id: "shop", label: `My shop${needSell ? ` (${needSell})` : ""}` }]} value={tab} onChange={setTab} size="sm" />
      </PageHeader>

      {tab === "explore" && (
        <>
          <div className="flex flex-col sm:flex-row gap-3 sm:items-center mb-5">
            <Segmented options={[{ id: "all", label: "All" }, { id: "open", label: "Open now" }, { id: "budget", label: "Under 50" }, { id: "top", label: "Top rated" }]} value={filter} onChange={setFilter} size="sm" />
            <SearchInput value={search} onChange={setSearch} placeholder="Search styles, artists, tags…" className="sm:w-72 sm:ml-auto" />
          </div>
          {loading ? (
            <div className="grid sm:grid-cols-2 lg:grid-cols-3 gap-5">{Array.from({ length: 6 }).map((_, i) => <div key={i} className="skeleton h-80 !rounded-3xl" />)}</div>
          ) : filtered.length === 0 ? (
            <EmptyState icon={Store} title="No shops here yet" text="Be the first artist to open a shop." action={<button className="btn" onClick={() => setParams({ create: "1" })}>Open your shop</button>} />
          ) : (
            <div className="grid sm:grid-cols-2 lg:grid-cols-3 gap-5">
              {filtered.map((c, i) => {
                const price = minPrice(c);
                const r = rating(c);
                return (
                  <motion.button key={c.id} whileHover={{ y: -5 }} onClick={() => setParams({ c: c.id })} className="enter card !rounded-3xl overflow-hidden text-left group" style={{ "--d": `${Math.min(i, 9) * 50}ms`, "--enter-y": "20px" }}>
                    <div className="relative h-52 overflow-hidden" style={{ background: "var(--surface-2)" }}>
                      {c.samples?.[0] ? <img src={c.samples[0]} alt="" loading="lazy" className="w-full h-full object-cover transition-transform duration-700 group-hover:scale-110" /> : <div className="w-full h-full flex items-center justify-center" style={{ background: "var(--accent-grad)" }}><Paintbrush className="w-8 h-8 text-white" /></div>}
                      <div className="absolute top-3 left-3"><StatusPill open={isOpen(c)} /></div>
                      {price !== null && <span className="absolute bottom-3 left-3 rounded-full px-3 py-1 text-xs font-extrabold" style={{ background: "var(--surface)", color: "var(--accent-rose)" }}>from {money(price, c.currency || "usd")}</span>}
                    </div>
                    <div className="p-4">
                      <p className="font-display text-lg font-semibold truncate" style={{ color: "var(--text-primary)" }}>{c.title}</p>
                      <div className="flex items-center gap-2 mt-2">
                        <Avatar src={c.artist_profile_picture} name={c.artist_display_name} size={24} />
                        <span className="text-xs font-semibold truncate" style={{ color: "var(--text-secondary)" }}>{c.artist_display_name}</span>
                        <span className="text-xs ml-auto font-bold flex items-center gap-1" style={{ color: r != null ? "#f0a020" : "var(--accent-rose)" }}>{r != null ? <><Star className="w-3 h-3 fill-current" />{r.toFixed(1)}</> : Number(c.orders_completed) > 0 ? `${c.orders_completed} sold` : <><Sparkles className="w-3 h-3" />New</>}</span>
                      </div>
                    </div>
                  </motion.button>
                );
              })}
            </div>
          )}
        </>
      )}

      {tab === "orders" && (
        <div className="space-y-3 max-w-3xl">
          {buying.length === 0 && <EmptyState icon={ShoppingBag} title="No orders yet" text="Find an artist you love in Explore and send them a request." action={<button className="btn" onClick={() => setTab("explore")}>Explore shops</button>} />}
          {buying.filter(isActiveOrder).length > 0 && <p className="label">Going on</p>}
          {buying.filter(isActiveOrder).map((o) => <OrderRow key={o.id} order={o} asBuyer onOpen={() => openOrder(o.id)} />)}
          {buying.filter((o) => !isActiveOrder(o)).length > 0 && <p className="label pt-2">Past orders</p>}
          {buying.filter((o) => !isActiveOrder(o)).map((o) => <OrderRow key={o.id} order={o} asBuyer onOpen={() => openOrder(o.id)} />)}
        </div>
      )}

      {tab === "shop" && (
        <div className="grid lg:grid-cols-2 gap-5 items-start">
          <div className="space-y-5">
            {payoutsReady === false && <><SetUpPayoutsNotice /><PayoutDetails onSaved={() => setPayoutsReady(true)} /></>}
            <Earnings orders={selling} />
            {selling.filter((o) => o.status === "requested").length > 0 && <div className="space-y-2"><p className="label">New requests</p>{selling.filter((o) => o.status === "requested").map((o) => <OrderRow key={o.id} order={o} asBuyer={false} onOpen={() => openOrder(o.id)} />)}</div>}
            {selling.filter((o) => ["accepted", "paid", "in_progress", "delivered", "refund_requested"].includes(o.status)).length > 0 && (
              <div className="space-y-2"><p className="label">Your work</p>{selling.filter((o) => ["accepted", "paid", "in_progress", "delivered", "refund_requested"].includes(o.status)).map((o) => <OrderRow key={o.id} order={o} asBuyer={false} onOpen={() => openOrder(o.id)} />)}</div>
            )}
            {payoutsReady !== false && <PayoutDetails />}
            {isAdmin && <AdminPayouts onOpen={openOrder} />}
          </div>
          <div className="space-y-3">
            <p className="label">Your listings</p>
            {mine.length === 0 ? <EmptyState icon={Store} title="Open your shop" text="List what you draw, your prices and a few samples." action={<button className="btn" onClick={() => setParams({ create: "1" })}>Open your shop</button>} /> : mine.map((c) => (
              <button key={c.id} onClick={() => setParams({ c: c.id })} className="card-sm p-3 flex items-center gap-3 w-full text-left">
                {c.samples?.[0] ? <img src={c.samples[0]} alt="" className="w-14 h-14 rounded-2xl object-cover" /> : <span className="w-14 h-14 rounded-2xl" style={{ background: "var(--accent-grad)" }} />}
                <div className="min-w-0 flex-1"><p className="font-bold truncate" style={{ color: "var(--text-primary)" }}>{c.title}</p><p className="text-xs" style={{ color: "var(--text-muted)" }}>{c.tiers?.length || 0} size{c.tiers?.length === 1 ? "" : "s"} · from {money(minPrice(c) ?? 0, c.currency || "usd")}</p></div>
                <StatusPill open={isOpen(c)} />
              </button>
            ))}
            {selling.filter((o) => o.status === "completed").length > 0 && <div className="space-y-2 pt-2"><p className="label">Finished</p>{selling.filter((o) => o.status === "completed").slice(0, 20).map((o) => <OrderRow key={o.id} order={o} asBuyer={false} onOpen={() => openOrder(o.id)} />)}</div>}
          </div>
        </div>
      )}

      <ListingModal open={params.get("create") === "1" || !!editing} existing={editing} onClose={() => { setEditing(null); setParams({}); }} />
      {selected && <ListingDetail key={selected.id} commission={selected} onClose={() => setParams({})} onEdit={(c) => { setParams({}); setEditing(c); }} onOrdered={(id) => { setTab("orders"); setParams({ order: id }); }} />}
      {order && <OrderModal key={order.id + order.status} order={order} onClose={() => setParams({})} />}
    </Page>
  );
}
