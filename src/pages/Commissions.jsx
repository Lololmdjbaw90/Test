import React, { useMemo, useState } from "react";
import { Link, useNavigate, useSearchParams } from "react-router-dom";
import { AnimatePresence, motion } from "framer-motion";
import { Clock, ExternalLink, ImagePlus, Loader2, MessageSquare, Plus, Store, Trash2, X } from "lucide-react";
import { base44 } from "@/api/base44Client";
import { useAuth } from "@/lib/AuthContext";
import { useLiveQuery } from "@/lib/useLiveQuery";
import { checkText } from "@/lib/moderation";
import { toast } from "@/lib/toast";
import { displayName, profileLink } from "@/lib/format";
import { Page, PageHeader, EmptyState } from "@/components/common/Page";
import { SearchInput, Segmented, Toggle } from "@/components/common/Controls";
import Modal, { useConfirm } from "@/components/common/Modal";
import Avatar from "@/components/common/Avatar";

const minPrice = (c) => (c.tiers?.length ? Math.min(...c.tiers.map((t) => Number(t.price) || 0)) : null);
const isOpen = (c) => c.is_open ?? c.status === "open";

function StatusPill({ open }) {
  return (
    <span className="inline-flex items-center gap-1.5 text-[11px] font-bold px-2.5 py-1 rounded-full glass" style={{ color: open ? "var(--success)" : "var(--text-muted)", border: "1px solid var(--border-c)" }}>
      <span className="w-1.5 h-1.5 rounded-full" style={{ background: open ? "var(--success)" : "var(--text-muted)", boxShadow: open ? "0 0 0 3px rgb(23 166 115 / 0.2)" : "none" }} />{open ? "Open" : "Closed"}
    </span>
  );
}

function CreateModal({ open, onClose }) {
  const { user } = useAuth();
  const [form, setForm] = useState({ title: "", description: "", paypal_link: "", is_open: true, tags: "" });
  const [tiers, setTiers] = useState([{ name: "", price: "", description: "", delivery_days: "" }]);
  const [samples, setSamples] = useState([]);
  const [busy, setBusy] = useState(false);
  const setTier = (i, k, v) => setTiers((t) => t.map((x, j) => (j === i ? { ...x, [k]: v } : x)));
  const submit = async () => {
    if (!form.title.trim()) return;
    setBusy(true);
    try {
      const mod = await checkText(`${form.title} ${form.description}`, { user, where: "commission" });
      if (!mod.safe) { toast.error("Listing blocked", { description: mod.reason }); setBusy(false); return; }
      const urls = await Promise.all(samples.map((s) => base44.integrations.Core.UploadFile({ file: s.file }).then((r) => r.file_url)));
      const link = form.paypal_link.trim();
      await base44.entities.Commission.create({
        title: form.title.trim(), description: form.description.trim(), is_open: form.is_open,
        paypal_link: link && !/^https?:\/\//i.test(link) ? `https://${link}` : link,
        tags: form.tags.split(",").map((t) => t.trim()).filter(Boolean).slice(0, 6),
        tiers: tiers.filter((t) => t.name.trim() && t.price !== "").map((t) => ({ ...t, price: Number(t.price), delivery_days: t.delivery_days ? Number(t.delivery_days) : null })),
        samples: urls, artist_email: user.email, artist_display_name: displayName(user), artist_profile_picture: user.profile_picture || "",
      });
      toast.success("Commission listed!");
      setForm({ title: "", description: "", paypal_link: "", is_open: true, tags: "" });
      setTiers([{ name: "", price: "", description: "", delivery_days: "" }]);
      setSamples([]);
      onClose();
    } catch (e) { toast.error(e?.message || "Could not publish."); }
    setBusy(false);
  };
  return (
    <Modal open={open} onClose={onClose} title="List a commission" subtitle="Tell people what you offer and how much it costs." size="lg" footer={<><button className="btn-ghost" onClick={onClose}>Cancel</button><button className="btn" disabled={busy || !form.title.trim()} onClick={submit}>{busy ? <Loader2 className="w-4 h-4 animate-spin" /> : "Publish"}</button></>}>
      <div className="space-y-4">
        <div><label className="label" htmlFor="cm-title">Title</label><input id="cm-title" className="input" placeholder="e.g. Watercolor pet portraits" value={form.title} onChange={(e) => setForm((f) => ({ ...f, title: e.target.value }))} maxLength={80} /></div>
        <div><label className="label" htmlFor="cm-desc">Description</label><textarea id="cm-desc" className="input resize-none" rows={3} placeholder="Style, what's included, turnaround…" value={form.description} onChange={(e) => setForm((f) => ({ ...f, description: e.target.value }))} maxLength={600} /></div>
        <div>
          <p className="label">Samples</p>
          <div className="flex gap-2 flex-wrap">
            {samples.map((s, i) => (
              <motion.div key={s.url} initial={{ scale: 0.8, opacity: 0 }} animate={{ scale: 1, opacity: 1 }} className="relative w-20 h-20">
                <img loading="lazy" decoding="async" src={s.url} alt="" className="w-full h-full rounded-2xl object-cover" />
                <button onClick={() => setSamples((x) => x.filter((_, j) => j !== i))} className="absolute -top-1.5 -right-1.5 w-6 h-6 rounded-full flex items-center justify-center text-white" style={{ background: "var(--text-primary)" }} aria-label="Remove sample"><X className="w-3 h-3" /></button>
              </motion.div>
            ))}
            {samples.length < 6 && (
              <label className="w-20 h-20 rounded-2xl flex items-center justify-center cursor-pointer" style={{ border: "2px dashed var(--border-strong)", color: "var(--text-muted)" }}>
                <ImagePlus className="w-5 h-5" />
                <input type="file" accept="image/*" multiple className="hidden" onChange={(e) => { const files = [...(e.target.files || [])].slice(0, 6 - samples.length); setSamples((x) => [...x, ...files.map((file) => ({ file, url: URL.createObjectURL(file) }))]); e.target.value = ""; }} />
              </label>
            )}
          </div>
        </div>
        <div>
          <p className="label">Pricing tiers</p>
          <div className="space-y-2">
            {tiers.map((t, i) => (
              <div key={i} className="card-sm p-3 grid grid-cols-[1fr_90px_90px_auto] gap-2 items-center">
                <input className="input !min-h-[2.2rem] !py-1.5" placeholder="Tier name" value={t.name} onChange={(e) => setTier(i, "name", e.target.value)} />
                <input className="input !min-h-[2.2rem] !py-1.5" placeholder="$ price" type="number" min="0" value={t.price} onChange={(e) => setTier(i, "price", e.target.value)} />
                <input className="input !min-h-[2.2rem] !py-1.5" placeholder="days" type="number" min="1" value={t.delivery_days} onChange={(e) => setTier(i, "delivery_days", e.target.value)} />
                <button onClick={() => setTiers((x) => (x.length > 1 ? x.filter((_, j) => j !== i) : x))} className="icon-btn w-8 h-8" aria-label="Remove tier" disabled={tiers.length === 1}><X className="w-4 h-4" /></button>
                <input className="input !min-h-[2.2rem] !py-1.5 col-span-4" placeholder="What's included (optional)" value={t.description} onChange={(e) => setTier(i, "description", e.target.value)} />
              </div>
            ))}
          </div>
          <button className="btn-ghost text-xs mt-2" onClick={() => setTiers((x) => [...x, { name: "", price: "", description: "", delivery_days: "" }])}><Plus className="w-3.5 h-3.5" /> Add tier</button>
        </div>
        <div className="grid sm:grid-cols-2 gap-3">
          <div><label className="label" htmlFor="cm-link">Payment link (optional)</label><input id="cm-link" className="input" placeholder="paypal.me/you" value={form.paypal_link} onChange={(e) => setForm((f) => ({ ...f, paypal_link: e.target.value }))} /></div>
          <div><label className="label" htmlFor="cm-tags">Tags</label><input id="cm-tags" className="input" placeholder="portrait, anime, pets" value={form.tags} onChange={(e) => setForm((f) => ({ ...f, tags: e.target.value }))} /></div>
        </div>
        <div className="card-sm p-3.5"><Toggle checked={form.is_open} onChange={(v) => setForm((f) => ({ ...f, is_open: v }))} label="Open for commissions" description="You can close it any time." /></div>
      </div>
    </Modal>
  );
}

function DetailModal({ commission, onClose }) {
  const navigate = useNavigate();
  const { user } = useAuth();
  const confirm = useConfirm();
  const [idx, setIdx] = useState(0);
  if (!commission) return <Modal open={false} onClose={onClose} />;
  const owner = user?.email === commission.artist_email || user?.role === "admin";
  const open = isOpen(commission);
  const toggle = () => base44.entities.Commission.update(commission.id, { is_open: !open }).then(() => toast.success(open ? "Marked as closed" : "Open for commissions")).catch((e) => toast.error(e?.message || "Could not update."));
  const del = async () => {
    if (!(await confirm({ title: "Delete listing?", confirmLabel: "Delete", danger: true }))) return;
    try { await base44.entities.Commission.delete(commission.id); toast.success("Listing deleted"); onClose(); } catch (e) { toast.error(e?.message || "Could not delete."); }
  };
  return (
    <Modal open onClose={onClose} size="xl" padded={false} hideHeader>
      {commission.samples?.length > 0 && (
        <div className="relative h-64 sm:h-80 overflow-hidden" style={{ background: "var(--surface-2)" }}>
          <AnimatePresence mode="wait"><motion.img key={idx} src={commission.samples[idx]} alt="" initial={{ opacity: 0 }} animate={{ opacity: 1 }} exit={{ opacity: 0 }} className="absolute inset-0 w-full h-full object-cover" /></AnimatePresence>
          <div className="absolute top-4 left-4"><StatusPill open={open} /></div>
          {commission.samples.length > 1 && <div className="absolute bottom-3 inset-x-0 flex justify-center gap-1.5">{commission.samples.map((s, i) => <button key={s} onClick={() => setIdx(i)} className="w-12 h-12 rounded-xl overflow-hidden transition-transform" style={{ boxShadow: i === idx ? "0 0 0 2px #fff" : "none", transform: i === idx ? "scale(1.08)" : "none" }}><img loading="lazy" decoding="async" src={s} alt="" className="w-full h-full object-cover" /></button>)}</div>}
        </div>
      )}
      <div className="p-5 sm:p-7 space-y-5">
        <div>
          <h2 className="font-display text-3xl font-semibold pr-10" style={{ color: "var(--text-primary)" }}>{commission.title}</h2>
          <Link to={profileLink(commission.artist_email)} onClick={onClose} className="flex items-center gap-2 mt-2 w-fit group">
            <Avatar src={commission.artist_profile_picture} name={commission.artist_display_name} size={28} />
            <span className="text-sm font-semibold group-hover:underline" style={{ color: "var(--text-secondary)" }}>{commission.artist_display_name}</span>
          </Link>
        </div>
        {commission.description && <p className="text-sm leading-relaxed whitespace-pre-wrap" style={{ color: "var(--text-secondary)" }}>{commission.description}</p>}
        {commission.tags?.length > 0 && <div className="flex flex-wrap gap-1.5">{commission.tags.map((t) => <span key={t} className="badge-pink">#{t}</span>)}</div>}
        {commission.tiers?.length > 0 && (
          <div className="grid sm:grid-cols-2 gap-3">
            {commission.tiers.map((t, i) => (
              <motion.div key={i} className="enter card-sm p-4" style={{ "--d": `${Math.round((i * 0.06) * 1000)}ms`, "--enter-y": "10px" }}>
                <div className="flex items-start justify-between gap-2">
                  <p className="font-bold" style={{ color: "var(--text-primary)" }}>{t.name}</p>
                  <p className="font-display text-2xl font-semibold gradient-text">${t.price}</p>
                </div>
                {t.description && <p className="text-xs mt-1" style={{ color: "var(--text-muted)" }}>{t.description}</p>}
                {t.delivery_days && <p className="text-[11px] mt-2 flex items-center gap-1" style={{ color: "var(--text-muted)" }}><Clock className="w-3 h-3" /> {t.delivery_days}-day delivery</p>}
              </motion.div>
            ))}
          </div>
        )}
        <div className="flex flex-wrap gap-2">
          {!owner && open && commission.paypal_link && <a href={commission.paypal_link} target="_blank" rel="noopener noreferrer" className="btn flex-1"><ExternalLink className="w-4 h-4" /> Commission now</a>}
          {!owner && <button onClick={() => { onClose(); navigate(`/DirectMessages?with=${encodeURIComponent(commission.artist_email)}`); }} className={commission.paypal_link && open ? "btn-outline" : "btn flex-1"}><MessageSquare className="w-4 h-4" /> Message artist</button>}
          {owner && <button onClick={toggle} className="btn-outline flex-1">{open ? "Close commissions" : "Reopen commissions"}</button>}
          {owner && <button onClick={del} className="btn-outline" style={{ color: "var(--danger)" }}><Trash2 className="w-4 h-4" /> Delete</button>}
        </div>
      </div>
    </Modal>
  );
}

export default function CommissionsPage() {
  const { user } = useAuth();
  const [params, setParams] = useSearchParams();
  const [search, setSearch] = useState("");
  const [filter, setFilter] = useState("open");
  const { data: commissions, loading } = useLiveQuery("Commission", null, { sort: "-created_date" });
  const filtered = useMemo(() => {
    const q = search.trim().toLowerCase();
    return commissions.filter((c) => (filter === "all" || (filter === "open" ? isOpen(c) : c.artist_email === user.email)) && (!q || [c.title, c.description, c.artist_display_name, ...(c.tags || [])].some((f) => String(f || "").toLowerCase().includes(q))));
  }, [commissions, search, filter, user.email]);
  const selected = commissions.find((c) => c.id === params.get("c")) || null;

  return (
    <Page width="max-w-6xl">
      <PageHeader eyebrow="Hire an artist" title="Commissions" subtitle={`${commissions.filter(isOpen).length} artists open for work`} icon={Store} actions={<button className="btn" onClick={() => setParams({ create: "1" })}><Plus className="w-4 h-4" /> List yours</button>}>
        <div className="flex flex-col sm:flex-row gap-3 sm:items-center">
          <Segmented options={[{ id: "open", label: "Open now" }, { id: "all", label: "All" }, { id: "mine", label: "Mine" }]} value={filter} onChange={setFilter} size="sm" />
          <SearchInput value={search} onChange={setSearch} placeholder="Search styles, artists, tags…" className="sm:w-72 sm:ml-auto" />
        </div>
      </PageHeader>
      {loading ? (
        <div className="grid sm:grid-cols-2 lg:grid-cols-3 gap-5">{Array.from({ length: 6 }).map((_, i) => <div key={i} className="skeleton h-80 !rounded-3xl" />)}</div>
      ) : filtered.length === 0 ? (
        <EmptyState icon={Store} title="No commissions here" text={filter === "mine" ? "List your first commission to start getting requests." : "Try another filter."} action={<button className="btn" onClick={() => setParams({ create: "1" })}>List a commission</button>} />
      ) : (
        <div className="grid sm:grid-cols-2 lg:grid-cols-3 gap-5">
          {filtered.map((c, i) => {
            const price = minPrice(c);
            return (
              <motion.button key={c.id} whileHover={{ y: -5 }} onClick={() => setParams({ c: c.id })} className="enter card !rounded-3xl overflow-hidden text-left group" style={{ "--d": `${Math.round((Math.min(i, 9) * 0.05) * 1000)}ms`, "--enter-y": "20px" }}>
                <div className="relative h-52 overflow-hidden" style={{ background: "var(--surface-2)" }}>
                  {c.samples?.[0] ? <img src={c.samples[0]} alt="" loading="lazy" className="w-full h-full object-cover transition-transform duration-700 group-hover:scale-110" /> : <div className="w-full h-full flex items-center justify-center"><Store className="w-8 h-8" style={{ color: "var(--text-muted)" }} /></div>}
                  <div className="absolute top-3 left-3"><StatusPill open={isOpen(c)} /></div>
                  {price !== null && <div className="absolute bottom-3 right-3 glass rounded-2xl px-3 py-1.5 text-right" style={{ border: "1px solid var(--border-c)" }}><p className="text-[9px] font-bold uppercase tracking-wider" style={{ color: "var(--text-muted)" }}>from</p><p className="font-display text-xl font-semibold leading-none" style={{ color: "var(--text-primary)" }}>${price}</p></div>}
                </div>
                <div className="p-4">
                  <p className="font-display text-lg font-semibold truncate" style={{ color: "var(--text-primary)" }}>{c.title}</p>
                  <div className="flex items-center gap-2 mt-2">
                    <Avatar src={c.artist_profile_picture} name={c.artist_display_name} size={24} />
                    <span className="text-xs font-semibold truncate" style={{ color: "var(--text-secondary)" }}>{c.artist_display_name}</span>
                    <span className="text-xs ml-auto" style={{ color: "var(--text-muted)" }}>{c.tiers?.length || 0} tier{c.tiers?.length === 1 ? "" : "s"}</span>
                  </div>
                </div>
              </motion.button>
            );
          })}
        </div>
      )}
      <CreateModal open={params.get("create") === "1"} onClose={() => setParams({})} />
      {selected && <DetailModal key={selected.id} commission={selected} onClose={() => setParams({})} />}
    </Page>
  );
}
