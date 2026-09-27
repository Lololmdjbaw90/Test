import React, { useEffect, useRef } from "react";

export default function LoadMore({ hasMore, loading, error, onLoad }) {
  const ref = useRef(null);
  useEffect(() => {
    if (!hasMore || loading || error || !ref.current) return;
    const observer = new IntersectionObserver(entries => {
      if (entries.some(e => e.isIntersecting)) onLoad();
    }, { rootMargin: "400px" });
    observer.observe(ref.current);
    return () => observer.disconnect();
  }, [hasMore, loading, error, onLoad]);
  if (!hasMore && !error) return null;
  return <div ref={ref} className="py-4 text-center"><button type="button" onClick={onLoad} disabled={loading} className="btn-ghost" aria-live="polite">{loading ? "Loading…" : error ? "Try again" : "Load more"}</button></div>;
}
