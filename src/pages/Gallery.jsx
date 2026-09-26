import React, { useCallback, useMemo, useState } from "react";
import { Link, useSearchParams } from "react-router-dom";
import { AnimatePresence } from "framer-motion";
import { Bookmark, Download, Grid2X2, Plus } from "lucide-react";
import { base44 } from "@/api/base44Client";
import { useAuth } from "@/lib/AuthContext";
import { useLiveQuery } from "@/lib/useLiveQuery";
import { toast } from "@/lib/toast";
import { displayName } from "@/lib/format";
import { exportToCsv } from "@/utils/exportCsv";
import { notify } from "@/utils/notifications";
import { Page, PageHeader, EmptyState } from "@/components/common/Page";
import { ChipRow, SearchInput, Segmented } from "@/components/common/Controls";
import { useConfirm } from "@/components/common/Modal";
import ArtworkCard from "@/components/gallery/ArtworkCard";
import ArtworkViewer from "@/components/gallery/ArtworkViewer";
import PingInbox from "@/components/gallery/PingInbox";
import { feedback } from "@/lib/feedback";

const MEDIA = [
  { id: "all", label: "All" },
  { id: "painting", label: "Painting" },
  { id: "digital", label: "Digital" },
  { id: "drawing", label: "Drawing" },
  { id: "photography", label: "Photography" },
  { id: "sculpture", label: "Sculpture" },
  { id: "mixed_media", label: "Mixed media" },
  { id: "other", label: "Other" },
];
const SORTS = [{ id: "new", label: "Newest" }, { id: "liked", label: "Most liked" }, { id: "featured", label: "Featured" }];

export default function Gallery() {
  const { user, isAdmin, updateMe } = useAuth();
  const confirm = useConfirm();
  const [params, setParams] = useSearchParams();
  const [medium, setMedium] = useState("all");
  const [sort, setSort] = useState("new");
  const [search, setSearch] = useState("");
  const [savedOnly, setSavedOnly] = useState(false);
  const { data: artworks, setData, loading } = useLiveQuery("Artwork", null, { sort: "-created_date" });
  const saved = user?.saved_artworks || [];

  const filtered = useMemo(() => {
    const q = search.trim().toLowerCase();
    let list = artworks.filter((a) =>
      (medium === "all" || (a.medium || "other") === medium) &&
      (!savedOnly || saved.includes(a.id)) &&
      (!q || [a.title, a.description, a.user_display_name, a.medium].some((f) => String(f || "").toLowerCase().includes(q))));
    if (sort === "liked") list = [...list].sort((a, b) => (b.likes?.length || 0) - (a.likes?.length || 0));
    if (sort === "featured") list = [...list].sort((a, b) => Number(!!b.featured) - Number(!!a.featured));
    return list;
  }, [artworks, medium, search, sort, savedOnly, saved]);

  const openId = params.get("art");
  const openIndex = filtered.findIndex((a) => a.id === openId);
  const open = openIndex >= 0 ? filtered[openIndex] : artworks.find((a) => a.id === openId) || null;
  const setOpen = useCallback((id) => {
    setParams((p) => { const n = new URLSearchParams(p); if (id) n.set("art", id); else n.delete("art"); return n; }, { replace: !!openId });
  }, [setParams, openId]);

  const like = async (art) => {
    if (!user) return;
    const likes = art.likes || [];
    const liked = likes.includes(user.email);
    const next = liked ? likes.filter((e) => e !== user.email) : [...likes, user.email];
    setData((list) => list.map((a) => (a.id === art.id ? { ...a, likes: next } : a)));
    try {
      await base44.entities.Artwork.update(art.id, { likes: next });
      const owner = art.user_email || art.created_by;
      if (!liked && owner && owner !== user.email) await notify({ to_email: owner, from_email: user.email, from_display_name: displayName(user), from_profile_picture: user.profile_picture, type: "like", message: `${displayName(user)} liked "${art.title}"`, link: `/Gallery?art=${art.id}`, entity_id: art.id });
    } catch (e) {
      setData((list) => list.map((a) => (a.id === art.id ? { ...a, likes } : a)));
      toast.error(e?.message || "Could not like artwork.");
    }
  };

  const toggleSave = async (art) => {
    feedback("save");
    const next = saved.includes(art.id) ? saved.filter((id) => id !== art.id) : [...saved, art.id];
    try {
      await updateMe({ saved_artworks: next });
      toast.success(next.includes(art.id) ? "Saved to your collection" : "Removed from saved");
    } catch (e) { toast.error(e?.message || "Could not save."); }
  };

  const toggleFeatured = async (art) => {
    try { await base44.entities.Artwork.update(art.id, { featured: !art.featured }); } catch (e) { toast.error(e?.message || "Could not update."); }
  };

  const remove = async (art) => {
    const ok = await confirm({ title: "Delete artwork?", message: `"${art.title}" will be permanently removed.`, confirmLabel: "Delete", danger: true });
    if (!ok) return;
    try {
      await base44.entities.Artwork.delete(art.id);
      base44.entities.Log.create({ action: "artwork_deleted", details: `Deleted: "${art.title}"`, user_email: user.email }).catch(() => {});
      setOpen(null);
      toast.success("Artwork deleted");
    } catch (e) { toast.error(e?.message || "Could not delete."); }
  };

  return (
    <Page width="max-w-7xl">
      <PageHeader
        eyebrow="Curated showcase"
        title="Gallery"
        subtitle={`${artworks.length} artworks · ${artworks.filter((a) => a.featured).length} featured`}
        icon={Grid2X2}
        actions={<>
          <PingInbox />
          <button onClick={() => exportToCsv(filtered.map((a) => ({ title: a.title, artist: a.user_display_name || "", medium: a.medium, year: a.year, likes: a.likes?.length || 0 })), "gallery")} className="icon-btn icon-btn-bordered" title="Export CSV" aria-label="Export CSV"><Download className="w-4 h-4" /></button>
          {isAdmin && <Link to="/Upload" className="btn"><Plus className="w-4 h-4" /> Add artwork</Link>}
        </>}
      >
        <div className="flex flex-col lg:flex-row gap-3 lg:items-center">
          <SearchInput value={search} onChange={setSearch} placeholder="Search titles, artists, mediums…" className="lg:w-80" />
          <Segmented options={SORTS} value={sort} onChange={setSort} size="sm" />
          <button className="chip self-start lg:self-auto" data-active={savedOnly} onClick={() => setSavedOnly((v) => !v)}><Bookmark className={`w-3.5 h-3.5 ${savedOnly ? "fill-current" : ""}`} /> Saved {saved.length ? `(${saved.length})` : ""}</button>
        </div>
        <ChipRow className="mt-3" options={MEDIA} value={medium} onChange={setMedium} />
      </PageHeader>

      {loading ? (
        <div className="columns-2 sm:columns-3 lg:columns-4 gap-4">
          {Array.from({ length: 8 }).map((_, i) => <div key={i} className="skeleton mb-4 break-inside-avoid" style={{ height: 180 + (i % 3) * 70 }} />)}
        </div>
      ) : filtered.length === 0 ? (
        <EmptyState icon={savedOnly ? Bookmark : Grid2X2} title={savedOnly ? "Nothing saved yet" : "No artworks found"} text={savedOnly ? "Tap the bookmark on any piece to keep it here." : "Try a different filter or search term."} action={isAdmin && !savedOnly ? <Link to="/Upload" className="btn">Upload artwork</Link> : null} />
      ) : (
        <div className="columns-2 sm:columns-3 lg:columns-4 gap-4">
          <AnimatePresence>
            {filtered.map((a, i) => (
              <div key={a.id} className="break-inside-avoid mb-4">
                <ArtworkCard
                  artwork={a}
                  index={i}
                  onOpen={() => setOpen(a.id)}
                  liked={!!user && (a.likes || []).includes(user.email)}
                  likeCount={a.likes?.length || 0}
                  onLike={() => like(a)}
                  saved={saved.includes(a.id)}
                  onSave={() => toggleSave(a)}
                />
              </div>
            ))}
          </AnimatePresence>
        </div>
      )}

      <ArtworkViewer
        artwork={open}
        onClose={() => setOpen(null)}
        position={openIndex >= 0 ? { index: openIndex + 1, total: filtered.length } : null}
        onPrev={openIndex > 0 ? () => setOpen(filtered[openIndex - 1].id) : null}
        onNext={openIndex >= 0 && openIndex < filtered.length - 1 ? () => setOpen(filtered[openIndex + 1].id) : null}
        liked={!!open && !!user && (open.likes || []).includes(user.email)}
        likeCount={open?.likes?.length || 0}
        onLike={() => open && like(open)}
        saved={!!open && saved.includes(open.id)}
        onSave={() => open && toggleSave(open)}
        isAdmin={isAdmin}
        onToggleFeatured={() => open && toggleFeatured(open)}
        onDelete={() => open && remove(open)}
      />
    </Page>
  );
}
