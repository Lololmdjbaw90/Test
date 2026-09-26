import React, { useEffect, useState } from "react";
import { Loader2, Megaphone, Save } from "lucide-react";
import { base44 } from "@/api/base44Client";
import { useLiveQuery } from "@/lib/useLiveQuery";
import { ACCENTS } from "@/lib/theme";
import { toast } from "@/lib/toast";
import { Toggle } from "@/components/common/Controls";

// Site-wide settings stored in SiteConfig { key: "global" }.
export default function AdminSiteSettings() {
  const { data } = useLiveQuery("SiteConfig", { key: "global" });
  const config = data[0];
  const [form, setForm] = useState({ announcement: "", announcement_active: false, announcement_color: "#d9577f", default_accent: "rose" });
  const [saving, setSaving] = useState(false);

  useEffect(() => { if (config) setForm((f) => ({ ...f, ...config })); }, [config?.id, config?.updated_date]);

  const save = async () => {
    setSaving(true);
    const { id, created_date, updated_date, created_by, ...payload } = form;
    try {
      if (config) await base44.entities.SiteConfig.update(config.id, payload);
      else await base44.entities.SiteConfig.create({ ...payload, key: "global" });
      toast.success("Site settings saved");
    } catch (e) { toast.error(e?.message || "Could not save settings."); }
    setSaving(false);
  };

  return (
    <div className="card p-5 sm:p-6 space-y-5">
      <div className="flex items-center gap-3">
        <span className="w-10 h-10 rounded-2xl flex items-center justify-center text-white" style={{ background: "var(--accent-grad)" }}><Megaphone className="w-5 h-5" /></span>
        <div>
          <p className="font-display text-lg font-semibold" style={{ color: "var(--text-primary)" }}>Site settings</p>
          <p className="text-xs" style={{ color: "var(--text-muted)" }}>Applies to everyone on Sugerly.</p>
        </div>
      </div>
      <div>
        <label className="label" htmlFor="site-ann">Announcement banner</label>
        <input id="site-ann" className="input" placeholder="e.g. Art jam this Saturday in the Music Lounge!" value={form.announcement || ""} onChange={(e) => setForm((f) => ({ ...f, announcement: e.target.value }))} maxLength={160} />
      </div>
      <div className="flex flex-wrap items-center gap-4">
        <div className="flex-1 min-w-[220px]"><Toggle checked={!!form.announcement_active} onChange={(v) => setForm((f) => ({ ...f, announcement_active: v }))} label="Show banner" description="Visible at the top of every page until dismissed." /></div>
        <label className="flex items-center gap-2 text-xs font-semibold" style={{ color: "var(--text-secondary)" }}>
          Banner color <input type="color" value={form.announcement_color || "#d9577f"} onChange={(e) => setForm((f) => ({ ...f, announcement_color: e.target.value }))} className="w-9 h-9 rounded-xl cursor-pointer border-0 bg-transparent" />
        </label>
      </div>
      <div>
        <p className="label">Default accent for new members</p>
        <div className="flex gap-2 flex-wrap">
          {ACCENTS.map((a) => (
            <button key={a.id} onClick={() => setForm((f) => ({ ...f, default_accent: a.id }))} className="chip" data-active={form.default_accent === a.id}>
              <span className="w-3.5 h-3.5 rounded-full" style={{ background: a.swatch }} />{a.label}
            </button>
          ))}
        </div>
      </div>
      <button onClick={save} disabled={saving} className="btn">{saving ? <Loader2 className="w-4 h-4 animate-spin" /> : <><Save className="w-4 h-4" /> Save site settings</>}</button>
    </div>
  );
}
