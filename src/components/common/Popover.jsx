import React, { useEffect, useLayoutEffect, useRef, useState } from "react";
import { createPortal } from "react-dom";
import { motion } from "framer-motion";
import { useDelayedUnmount } from "./Modal";
import { useIsMobile } from "@/lib/useMediaQuery";

const MARGIN = 8;

// Anchored floating panel rendered in a portal (so parents with overflow
// hidden can't clip it). Flips to stay on screen, closes on outside click /
// Escape, and becomes a bottom sheet on phones.
//
// placement: "bottom-end" | "bottom-start" | "top-start" | "top-end" | "left-start" | "right-start"
export default function Popover({ open, onClose, anchorRef, placement = "bottom-end", offset = 10, width = 320, children, label, sheetOnMobile = true, className = "", panelStyle }) {
  const mounted = useDelayedUnmount(open, 180);
  const isMobile = useIsMobile();
  const sheet = sheetOnMobile && isMobile;
  const panelRef = useRef(null);
  const [pos, setPos] = useState(null);
  const lastChildren = useRef(children);
  if (open) lastChildren.current = children;

  useLayoutEffect(() => {
    if (!mounted || sheet) return undefined;
    const update = () => {
      const a = anchorRef?.current?.getBoundingClientRect();
      const panel = panelRef.current;
      if (!a || !panel) return;
      const vw = window.innerWidth, vh = window.innerHeight;
      const w = Math.min(width, vw - MARGIN * 2);
      const h = panel.offsetHeight;
      const [side, align = "start"] = placement.split("-");
      let top, left, origin;
      if (side === "left" || side === "right") {
        left = side === "left" ? a.left - offset - w : a.right + offset;
        if (side === "left" && left < MARGIN) left = a.right + offset;
        if (side === "right" && left + w > vw - MARGIN) left = a.left - offset - w;
        top = a.top;
        origin = side === "left" ? "right top" : "left top";
      } else {
        top = side === "top" ? a.top - offset - h : a.bottom + offset;
        if (side === "bottom" && top + h > vh - MARGIN && a.top - offset - h > MARGIN) top = a.top - offset - h;
        if (side === "top" && top < MARGIN && a.bottom + offset + h < vh - MARGIN) top = a.bottom + offset;
        left = align === "end" ? a.right - w : align === "center" ? a.left + a.width / 2 - w / 2 : a.left;
        origin = `${align === "end" ? "right" : "left"} ${top < a.top ? "bottom" : "top"}`;
      }
      left = Math.max(MARGIN, Math.min(left, vw - w - MARGIN));
      top = Math.max(MARGIN, Math.min(top, vh - h - MARGIN));
      setPos({ top, left, width: w, origin });
    };
    update();
    const ro = typeof ResizeObserver !== "undefined" ? new ResizeObserver(update) : null;
    if (ro && panelRef.current) ro.observe(panelRef.current);
    window.addEventListener("resize", update);
    window.addEventListener("scroll", update, true);
    return () => { ro?.disconnect(); window.removeEventListener("resize", update); window.removeEventListener("scroll", update, true); };
  }, [mounted, sheet, placement, width, offset, anchorRef]);

  useEffect(() => {
    if (!open) return undefined;
    const onKey = (e) => { if (e.key === "Escape") onClose?.(); };
    const onDown = (e) => {
      if (sheet) return; // the sheet has its own backdrop
      if (panelRef.current?.contains(e.target) || anchorRef?.current?.contains(e.target)) return;
      onClose?.();
    };
    document.addEventListener("keydown", onKey);
    document.addEventListener("pointerdown", onDown);
    return () => { document.removeEventListener("keydown", onKey); document.removeEventListener("pointerdown", onDown); };
  }, [open, onClose, anchorRef, sheet]);

  useEffect(() => { if (!mounted) setPos(null); }, [mounted]);

  if (!mounted) return null;
  const content = open ? children : lastChildren.current;

  if (sheet) {
    return createPortal(
      <motion.div className="fixed inset-0 z-[130] flex items-end" initial={{ opacity: 0 }} animate={{ opacity: open ? 1 : 0 }} transition={{ duration: 0.18 }} style={{ pointerEvents: open ? "auto" : "none" }}>
        <div className="absolute inset-0" style={{ background: "rgb(20 8 14 / 0.4)" }} onClick={onClose} />
        <motion.div
          ref={panelRef}
          role="dialog"
          aria-label={label}
          initial={{ y: "100%" }}
          animate={{ y: open ? 0 : "100%" }}
          transition={open ? { type: "spring", stiffness: 420, damping: 38 } : { duration: 0.18, ease: "easeIn" }}
          drag="y"
          dragConstraints={{ top: 0, bottom: 0 }}
          dragElastic={{ top: 0, bottom: 0.6 }}
          onDragEnd={(_, info) => { if (info.offset.y > 90 || info.velocity.y > 500) onClose?.(); }}
          className={`relative w-full max-h-[calc(88dvh-env(safe-area-inset-top))] flex flex-col rounded-t-[1.75rem] overflow-hidden safe-bottom ${className}`}
          style={{ background: "var(--surface)", boxShadow: "var(--shadow-lg)", ...panelStyle }}
        >
          <div className="flex justify-center pt-2.5 pb-1 flex-shrink-0 cursor-grab"><span className="w-10 h-1.5 rounded-full" style={{ background: "var(--border-strong)" }} /></div>
          <div className="flex-1 min-h-0 overflow-y-auto scroll">{content}</div>
        </motion.div>
      </motion.div>,
      document.body,
    );
  }

  return createPortal(
    <motion.div
      ref={panelRef}
      role="dialog"
      aria-label={label}
      initial={{ opacity: 0, scale: 0.96, y: -4 }}
      animate={open ? { opacity: pos ? 1 : 0, scale: 1, y: 0 } : { opacity: 0, scale: 0.97, y: -4 }}
      transition={open ? { type: "spring", stiffness: 480, damping: 34 } : { duration: 0.14, ease: "easeIn" }}
      className={`fixed z-[130] rounded-3xl overflow-hidden ${className}`}
      style={{
        top: pos?.top ?? 0,
        left: pos?.left ?? 0,
        width: pos?.width ?? width,
        visibility: pos ? "visible" : "hidden",
        transformOrigin: pos?.origin || "top right",
        pointerEvents: open ? "auto" : "none",
        background: "var(--surface)",
        border: "1px solid var(--border-c)",
        boxShadow: "var(--shadow-lg)",
        ...panelStyle,
      }}
    >
      {content}
    </motion.div>,
    document.body,
  );
}
