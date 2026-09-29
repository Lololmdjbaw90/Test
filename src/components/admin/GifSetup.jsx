import React, { useEffect, useState } from "react";
import { CheckCircle2, ExternalLink, Loader2, Save } from "lucide-react";
import { base44 } from "@/api/base44Client";
import { useLiveQuery } from "@/lib/useLiveQuery";
import { fetchGifs } from "@/lib/gifs";
import { toast } from "@/lib/toast";

// Admin → Site: the GIPHY key that powers GIF search in comments and chats.
export default function GifSetupCard() {
  const { data } = useLiveQuery("SiteConfig", { key: "global" });
  const config = data[0];
  const [key, setKey] = useState("");
  const [busy, setBusy] = useState(false);
  useEffect(() => { setKey(config?.giphy_key || ""); }, [config?.id, config?.giphy_key]);
  const envKey = import.meta.env.VITE_GIPHY_KEY;

  const save = async () => {
    setBusy(true);
    try {
      const k = key.trim();
      if (k) await fetchGifs(k, "", { limit: 1 }); // check it works first
      if (config) await base44.entities.SiteConfig.update(config.id, { giphy_key: k });
      else await base44.entities.SiteConfig.create({ key: "global", giphy_key: k });
      toast.success(k ? "GIFs are on ✨" : "GIF search turned off");
    } catch (e) {
      toast.error(e?.message || "Could not save the key.");
    }
    setBusy(false);
  };

  return (
    <div className="card p-5 space-y-3" id="gifs">
      <div className="flex items-center gap-3">
        <span className="w-10 h-8 rounded-lg flex items-center justify-center text-[11px] font-black text-white" style={{ background: "var(--accent-grad)" }}>GIF</span>
        <div className="flex-1 min-w-0">
          <p className="font-display text-lg" style={{ color: "var(--text-primary)" }}>GIFs</p>
          <p className="text-xs" style={{ color: "var(--text-muted)" }}>{envKey || config?.giphy_key ? "GIF search is on in comments, DMs and server chats." : "Add a free GIPHY key to search GIFs in comments, DMs and server chats."}</p>
        </div>
        {(envKey || config?.giphy_key) && <CheckCircle2 className="w-6 h-6 flex-shrink-0" style={{ color: "var(--success)" }} />}
      </div>
      {envKey ? (
        <p className="text-xs" style={{ color: "var(--text-muted)" }}>The key comes from the app build (VITE_GIPHY_KEY).</p>
      ) : (
        <>
          <ol className="text-sm list-decimal pl-5 space-y-1" style={{ color: "var(--text-secondary)" }}>
            <li>Open <a href="https://developers.giphy.com/dashboard/?create=true" target="_blank" rel="noreferrer" className="font-semibold underline inline-flex items-center gap-1">GIPHY Developers <ExternalLink className="w-3 h-3" /></a> and sign up (free).</li>
            <li>Create an app → choose <strong>API</strong> → copy the API key.</li>
            <li>Paste it here and tap Save.</li>
          </ol>
          <div className="flex gap-2">
            <input className="input flex-1" value={key} onChange={(e) => setKey(e.target.value)} placeholder="GIPHY API key" aria-label="GIPHY API key" autoCapitalize="off" autoCorrect="off" spellCheck={false} />
            <button onClick={save} disabled={busy} className="btn">{busy ? <Loader2 className="w-4 h-4 animate-spin" /> : <Save className="w-4 h-4" />} Save</button>
          </div>
        </>
      )}
    </div>
  );
}
