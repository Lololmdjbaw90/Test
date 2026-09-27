import React, { useEffect, useRef } from "react";
import { Loader2 } from "lucide-react";

// Put at the end of a list: loads the next page as it scrolls into view,
// with a "Show more" button as a fallback.
export default function LoadMore({ onMore, hasMore, loading = false, label = "Show more" }) {
  const ref = useRef(null);
  const more = useRef(onMore);
  more.current = onMore;
  useEffect(() => {
    const el = ref.current;
    if (!el || !hasMore || loading || typeof IntersectionObserver === "undefined") return undefined;
    const io = new IntersectionObserver((entries) => { if (entries[0].isIntersecting) more.current?.(); }, { rootMargin: "600px 0px" });
    io.observe(el);
    return () => io.disconnect();
  }, [hasMore, loading]);
  if (!hasMore && !loading) return null;
  return (
    <div ref={ref} className="flex justify-center py-4">
      {loading ? <Loader2 className="w-5 h-5 animate-spin" style={{ color: "var(--text-muted)" }} /> : <button type="button" onClick={() => onMore?.()} className="btn-outline">{label}</button>}
    </div>
  );
}
