import { useEffect, useRef } from "react";

// Chats: when the message list gets shorter (the keyboard opening) or taller,
// stay on the newest message if you were already there — like iMessage.
export function useStickToBottom(ref, atBottom) {
  const stick = useRef(atBottom);
  stick.current = atBottom;
  useEffect(() => {
    const el = ref.current;
    if (!el || typeof ResizeObserver === "undefined") return undefined;
    let last = el.clientHeight;
    const ro = new ResizeObserver(() => {
      if (el.clientHeight !== last && stick.current) el.scrollTop = el.scrollHeight;
      last = el.clientHeight;
    });
    ro.observe(el);
    return () => ro.disconnect();
  }, [ref]);
}
