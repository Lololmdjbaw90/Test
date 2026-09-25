import React, { useMemo, useState } from "react";
import { useNavigate, useSearchParams } from "react-router-dom";
import { AnimatePresence, motion } from "framer-motion";
import { ArrowRight, Check, Compass, Crown, ImagePlus, Loader2, LogIn, Plus, Server, Users } from "lucide-react";
import { base44 } from "@/api/base44Client";
import { useAuth } from "@/lib/AuthContext";
import { useLiveQuery } from "@/lib/useLiveQuery";
import { SERVER_TEMPLATES, createServer, joinServer } from "@/lib/servers";
import { toast } from "@/lib/toast";
import { Page, PageHeader, EmptyState } from "@/components/common/Page";
import { SearchInput, Segmented } from "@/components/common/Controls";
import Modal from "@/components/common/Modal";
import ImageCropper from "@/components/common/ImageCropper";
import Avatar from "@/components/common/Avatar";

const EMOJIS = ["🌸", "🎨", "🎮", "🎧", "🌙", "🍓", "🦋", "🔥", "✨", "🐱", "📚", "🌊"];

function CreateServerModal({ open, onClose }) {
  const navigate = useNavigate();
  const { user } = useAuth();
  const [step, setStep] = useState(0);
  const [template, setTemplate] = useState("art");
  const [form, setForm] = useState({ name: "", description: "", icon_emoji: "🌸", welcome_message: "" });
  const [iconFile, setIconFile] = useState(null);
  const [iconPreview, setIconPreview] = useState(null);
  const [cropSrc, setCropSrc] = useState(null);
  const [busy, setBusy] = useState(false);

  const reset = () => { setStep(0); setForm({ name: "", description: "", icon_emoji: "🌸", welcome_message: "" }); setIconFile(null); setIconPreview(null); };
  const create = async () => {
    setBusy(true);
    try {
      const icon_url = iconFile ? (await base44.integrations.Core.UploadFile({ file: iconFile })).file_url : "";
      const c = await createServer({ me: user, ...form, name: form.name.trim(), description: form.description.trim(), welcome_message: form.welcome_message.trim(), icon_url, template });
      toast.success(`${c.name} is ready!`);
      reset();
      onClose();
      navigate(`/CommunityChat?id=${c.id}`);
    } catch (e) { toast.error(e?.message || "Could not create server."); }
    setBusy(false);
  };

  return (
    <Modal open={open} onClose={onClose} title={step === 0 ? "Create a server" : "Customize your server"} subtitle={step === 0 ? "Pick a starting point — you can change channels later." : "Give it a name and an icon."} size="lg"
      footer={step === 0 ? <button className="btn" onClick={() => setStep(1)}>Next <ArrowRight className="w-4 h-4" /></button> : <><button className="btn-ghost" onClick={() => setStep(0)}>Back</button><button className="btn" disabled={busy || !form.name.trim()} onClick={create}>{busy ? <Loader2 className="w-4 h-4 animate-spin" /> : "Create server"}</button></>}>
      <AnimatePresence mode="wait">
        {step === 0 ? (
          <motion.div key="t" initial={{ opacity: 0, x: -16 }} animate={{ opacity: 1, x: 0 }} exit={{ opacity: 0, x: -16 }} className="space-y-2">
            {SERVER_TEMPLATES.map((t) => (
              <button key={t.id} onClick={() => setTemplate(t.id)} className="w-full card-sm p-4 flex items-center gap-4 text-left" style={template === t.id ? { borderColor: "var(--accent-rose)", boxShadow: "0 0 0 3px rgb(var(--accent-rgb) / 0.15)" } : undefined}>
                <span className="w-12 h-12 rounded-2xl flex items-center justify-center text-2xl" style={{ background: "var(--pink-soft)" }}>{t.emoji}</span>
                <span className="flex-1">
                  <span className="block text-sm font-bold" style={{ color: "var(--text-primary)" }}>{t.label}</span>
                  <span className="block text-xs mt-0.5" style={{ color: "var(--text-muted)" }}>{t.channels.map((c) => (c.type === "voice" ? `🔊 ${c.name}` : `#${c.name}`)).join("  ·  ")}</span>
                </span>
                {template === t.id && <Check className="w-5 h-5" style={{ color: "var(--accent-rose)" }} />}
              </button>
            ))}
          </motion.div>
        ) : cropSrc ? (
          <ImageCropper imageSrc={cropSrc} onCrop={(f, url) => { setIconFile(f); setIconPreview(url); setCropSrc(null); }} onCancel={() => setCropSrc(null)} />
        ) : (
          <motion.div key="f" initial={{ opacity: 0, x: 16 }} animate={{ opacity: 1, x: 0 }} exit={{ opacity: 0, x: 16 }} className="space-y-4">
            <div className="flex items-center gap-4">
              <label className="relative w-20 h-20 rounded-3xl flex items-center justify-center text-4xl cursor-pointer overflow-hidden flex-shrink-0 group" style={{ background: "var(--pink-soft)" }}>
                {iconPreview ? <img src={iconPreview} alt="" className="w-full h-full object-cover" /> : form.icon_emoji}
                <span className="absolute inset-0 flex items-center justify-center text-white opacity-0 group-hover:opacity-100 transition-opacity" style={{ background: "rgb(20 8 14 / 0.45)" }}><ImagePlus className="w-5 h-5" /></span>
                <input type="file" accept="image/*" className="hidden" onChange={(e) => { const f = e.target.files?.[0]; if (f) setCropSrc(URL.createObjectURL(f)); e.target.value = ""; }} />
              </label>
              <div className="flex flex-wrap gap-1">
                {EMOJIS.map((e) => <button key={e} onClick={() => { setForm((f) => ({ ...f, icon_emoji: e })); setIconFile(null); setIconPreview(null); }} className="w-9 h-9 rounded-xl text-lg hover:bg-[var(--surface-2)]" style={form.icon_emoji === e && !iconPreview ? { background: "var(--pink-soft)" } : undefined}>{e}</button>)}
              </div>
            </div>
            <div><label className="label" htmlFor="sv-name">Server name</label><input id="sv-name" className="input" placeholder={`${user?.display_name || "My"}'s server`} value={form.name} onChange={(e) => setForm((f) => ({ ...f, name: e.target.value }))} maxLength={40} autoFocus /></div>
            <div><label className="label" htmlFor="sv-desc">Description</label><textarea id="sv-desc" className="input resize-none" rows={2} placeholder="What's it about?" value={form.description} onChange={(e) => setForm((f) => ({ ...f, description: e.target.value }))} maxLength={160} /></div>
            <div><label className="label" htmlFor="sv-welcome">Welcome message</label><input id="sv-welcome" className="input" placeholder="Shown to new members" value={form.welcome_message} onChange={(e) => setForm((f) => ({ ...f, welcome_message: e.target.value }))} maxLength={160} /></div>
          </motion.div>
        )}
      </AnimatePresence>
    </Modal>
  );
}

export default function CommunitiesPage() {
  const navigate = useNavigate();
  const { user } = useAuth();
  const [params, setParams] = useSearchParams();
  const [tab, setTab] = useState("discover");
  const [search, setSearch] = useState("");
  const [busy, setBusy] = useState(null);
  const { data: servers, loading } = useLiveQuery("Community", null, { sort: "-created_date" });
  const { data: users } = useLiveQuery("User", null, { live: false });
  const usersByEmail = useMemo(() => Object.fromEntries(users.map((u) => [u.email, u])), [users]);

  const filtered = servers.filter((c) => {
    if (search.trim() && ![c.name, c.description].some((f) => String(f || "").toLowerCase().includes(search.trim().toLowerCase()))) return false;
    if (tab === "joined") return c.member_emails?.includes(user.email);
    if (tab === "mine") return c.owner_email === user.email;
    return true;
  }).sort((a, b) => (tab === "discover" ? (b.member_emails?.length || 0) - (a.member_emails?.length || 0) : 0));

  const join = async (e, c) => {
    e.stopPropagation();
    setBusy(c.id);
    try { await joinServer(c, user); toast.success(`Welcome to ${c.name}!`); navigate(`/CommunityChat?id=${c.id}`); }
    catch (err) { toast.error(err?.message || "Could not join."); }
    setBusy(null);
  };

  return (
    <Page width="max-w-6xl">
      <PageHeader
        eyebrow="Chat, voice & roles"
        title="Servers"
        subtitle={`${servers.length} communities · ${servers.filter((s) => s.member_emails?.includes(user.email)).length} joined`}
        icon={Server}
        actions={<button className="btn" onClick={() => setParams({ create: "1" })}><Plus className="w-4 h-4" /> New server</button>}
      >
        <div className="flex flex-col sm:flex-row gap-3 sm:items-center">
          <Segmented options={[{ id: "discover", label: "Discover", icon: Compass }, { id: "joined", label: "Joined", icon: LogIn }, { id: "mine", label: "Owned", icon: Crown }]} value={tab} onChange={setTab} size="sm" />
          <SearchInput value={search} onChange={setSearch} placeholder="Search servers…" className="sm:w-64 sm:ml-auto" />
        </div>
      </PageHeader>

      {loading ? (
        <div className="grid sm:grid-cols-2 lg:grid-cols-3 gap-5">{Array.from({ length: 6 }).map((_, i) => <div key={i} className="skeleton h-64 !rounded-3xl" />)}</div>
      ) : filtered.length === 0 ? (
        <EmptyState icon={Server} title={tab === "mine" ? "You don't own a server yet" : tab === "joined" ? "You haven't joined any servers" : "No servers found"} text="Servers have text channels, voice rooms and roles." action={<button className="btn" onClick={() => setParams({ create: "1" })}>Create a server</button>} />
      ) : (
        <div className="grid sm:grid-cols-2 lg:grid-cols-3 gap-5">
          {filtered.map((c, i) => {
            const member = c.member_emails?.includes(user.email);
            return (
              <motion.div key={c.id} initial={{ opacity: 0, y: 20 }} animate={{ opacity: 1, y: 0 }} transition={{ delay: Math.min(i, 9) * 0.05 }} whileHover={{ y: -4 }} onClick={() => navigate(`/CommunityChat?id=${c.id}`)} className="card !rounded-3xl overflow-hidden cursor-pointer group" role="link" tabIndex={0} onKeyDown={(e) => { if (e.key === "Enter") navigate(`/CommunityChat?id=${c.id}`); }}>
                <div className="h-28 relative overflow-hidden" style={{ background: "var(--accent-grad)" }}>
                  {c.banner_url && <img src={c.banner_url} alt="" className="w-full h-full object-cover transition-transform duration-700 group-hover:scale-110" />}
                  {c.owner_email === user.email && <span className="absolute top-3 right-3 badge-pink glass"><Crown className="w-3 h-3" /> Owner</span>}
                </div>
                <div className="px-5 pb-5 -mt-8 relative">
                  <div className="w-16 h-16 rounded-2xl flex items-center justify-center text-3xl overflow-hidden mb-3" style={{ background: "var(--surface)", boxShadow: "0 0 0 4px var(--surface), var(--shadow-md)" }}>
                    {c.icon_url ? <img src={c.icon_url} alt="" className="w-full h-full object-cover" /> : c.icon_emoji || "💬"}
                  </div>
                  <h3 className="font-display text-xl font-semibold truncate" style={{ color: "var(--text-primary)" }}>{c.name}</h3>
                  <p className="text-sm line-clamp-2 mt-1 min-h-[2.5rem]" style={{ color: "var(--text-muted)" }}>{c.description || "A cozy place to hang out."}</p>
                  <div className="flex items-center gap-3 mt-4">
                    <div className="flex -space-x-2">
                      {(c.member_emails || []).slice(0, 4).map((e) => <Avatar key={e} src={usersByEmail[e]?.profile_picture} name={usersByEmail[e]?.display_name || e} size={28} style={{ boxShadow: "0 0 0 2px var(--surface)", borderRadius: 9999 }} />)}
                    </div>
                    <span className="text-xs font-semibold flex items-center gap-1 flex-1" style={{ color: "var(--text-muted)" }}><Users className="w-3.5 h-3.5" /> {c.member_emails?.length || 0}</span>
                    {member ? (
                      <span className="btn-outline text-xs !min-h-[2rem] !py-1">Open <ArrowRight className="w-3.5 h-3.5" /></span>
                    ) : (
                      <button onClick={(e) => join(e, c)} disabled={busy === c.id} className="btn text-xs !min-h-[2rem] !py-1">{busy === c.id ? <Loader2 className="w-3.5 h-3.5 animate-spin" /> : "Join"}</button>
                    )}
                  </div>
                </div>
              </motion.div>
            );
          })}
        </div>
      )}
      <CreateServerModal open={params.get("create") === "1"} onClose={() => setParams({})} />
    </Page>
  );
}
