import React, { useEffect, useRef, useState } from "react";
import { AnimatePresence, motion } from "framer-motion";
import { Check, ImagePlus, Loader2, Lock, Pencil, Reply, Send, X } from "lucide-react";
import EmojiPicker from "./EmojiPicker";
import { haptic } from "@/lib/native";

// Shared message input: autosizing textarea, emoji picker, image attachment,
// @mention suggestions, reply/edit banners. Enter sends, Shift+Enter = newline.
export default function ChatComposer({ placeholder, onSend, editing, onCancelEdit, replyTo, onCancelReply, disabledReason, mentionCandidates = [], allowAttachments = true }) {
  const [text, setText] = useState("");
  const [file, setFile] = useState(null);
  const [preview, setPreview] = useState(null);
  const [sending, setSending] = useState(false);
  const [mention, setMention] = useState(null);
  const [mentionIndex, setMentionIndex] = useState(0);
  const taRef = useRef(null);
  const fileRef = useRef(null);

  useEffect(() => { if (editing) { setText(editing.content || ""); taRef.current?.focus(); } }, [editing?.id]);
  useEffect(() => { if (replyTo) taRef.current?.focus(); }, [replyTo?.id]);
  useEffect(() => {
    const ta = taRef.current;
    if (!ta) return;
    ta.style.height = "0px";
    ta.style.height = `${Math.min(160, ta.scrollHeight)}px`;
  }, [text]);

  const suggestions = mention !== null ? mentionCandidates.filter((c) => c.name.toLowerCase().startsWith(mention.toLowerCase())).slice(0, 6) : [];

  const onChange = (e) => {
    const val = e.target.value;
    setText(val);
    const m = val.slice(0, e.target.selectionStart).match(/@([\w.-]*)$/);
    setMention(m ? m[1] : null);
    setMentionIndex(0);
  };
  const insertMention = (name) => {
    setText((t) => t.replace(/@[\w.-]*$/, `@${name.replace(/\s+/g, "")} `));
    setMention(null);
    taRef.current?.focus();
  };
  const clearFile = () => { setFile(null); setPreview(null); };

  const submit = async (e) => {
    e?.preventDefault();
    if (sending || (!text.trim() && !file)) return;
    setSending(true);
    const ok = await onSend({ text: text.trim(), file });
    setSending(false);
    if (ok !== false) { haptic(); setText(""); clearFile(); setMention(null); }
    taRef.current?.focus();
  };

  const onKeyDown = (e) => {
    if (suggestions.length) {
      if (e.key === "ArrowDown") { e.preventDefault(); setMentionIndex((i) => (i + 1) % suggestions.length); return; }
      if (e.key === "ArrowUp") { e.preventDefault(); setMentionIndex((i) => (i - 1 + suggestions.length) % suggestions.length); return; }
      if (e.key === "Enter" || e.key === "Tab") { e.preventDefault(); insertMention(suggestions[mentionIndex].name); return; }
    }
    if (e.key === "Escape") { if (editing) { onCancelEdit?.(); setText(""); } else if (replyTo) onCancelReply?.(); }
    if (e.key === "Enter" && !e.shiftKey && !e.nativeEvent.isComposing) submit(e);
  };

  if (disabledReason) {
    return (
      <div className="px-4 pb-4 pt-2">
        <div className="flex items-center justify-center gap-2 rounded-2xl px-4 py-3.5 text-sm" style={{ background: "var(--surface-2)", color: "var(--text-muted)", border: "1px solid var(--border-c)" }}><Lock className="w-4 h-4" />{disabledReason}</div>
      </div>
    );
  }

  return (
    <form onSubmit={submit} className="px-3 sm:px-4 pb-[max(0.75rem,env(safe-area-inset-bottom))] sm:pb-4 pt-2 relative">
      <AnimatePresence>
        {suggestions.length > 0 && (
          <motion.div initial={{ opacity: 0, y: 6 }} animate={{ opacity: 1, y: 0 }} exit={{ opacity: 0, y: 6 }} className="absolute bottom-full left-4 right-4 mb-1 rounded-2xl overflow-hidden z-20" style={{ background: "var(--surface)", border: "1px solid var(--border-c)", boxShadow: "var(--shadow-lg)" }}>
            <p className="eyebrow px-3 pt-2.5 pb-1">Mention</p>
            {suggestions.map((s, i) => (
              <button key={s.name} type="button" onMouseDown={(e) => { e.preventDefault(); insertMention(s.name); }} className="w-full flex items-center gap-2 px-3 py-2 text-sm text-left" style={i === mentionIndex ? { background: "var(--pink-soft)" } : undefined}>
                <span className="w-2.5 h-2.5 rounded-full" style={{ background: s.color || "var(--accent-rose)" }} />
                <span className="font-semibold" style={{ color: s.color || "var(--text-primary)" }}>@{s.name.replace(/\s+/g, "")}</span>
                {s.hint && <span className="text-xs" style={{ color: "var(--text-muted)" }}>{s.hint}</span>}
              </button>
            ))}
          </motion.div>
        )}
      </AnimatePresence>
      <AnimatePresence>
        {(editing || replyTo) && (
          <motion.div initial={{ opacity: 0, height: 0 }} animate={{ opacity: 1, height: "auto" }} exit={{ opacity: 0, height: 0 }} className="overflow-hidden">
            <div className="flex items-center gap-2 px-3 py-2 mb-1.5 rounded-xl text-xs" style={{ background: editing ? "rgb(240 160 32 / 0.12)" : "var(--pink-soft)", color: editing ? "#b7770f" : "var(--text-secondary)" }}>
              {editing ? <Pencil className="w-3.5 h-3.5" /> : <Reply className="w-3.5 h-3.5" />}
              <span className="flex-1 truncate">{editing ? "Editing message — Esc to cancel" : <>Replying to <strong>{replyTo.user_display_name}</strong>: {replyTo.content?.slice(0, 60) || "image"}</>}</span>
              <button type="button" onClick={() => { if (editing) { onCancelEdit?.(); setText(""); } else onCancelReply?.(); }} aria-label="Cancel"><X className="w-3.5 h-3.5" /></button>
            </div>
          </motion.div>
        )}
      </AnimatePresence>
      <AnimatePresence>
        {preview && (
          <motion.div initial={{ opacity: 0, scale: 0.9 }} animate={{ opacity: 1, scale: 1 }} exit={{ opacity: 0, scale: 0.9 }} className="relative w-fit mb-2">
            <img src={preview} alt="" className="h-24 rounded-2xl object-cover" style={{ border: "1px solid var(--border-c)" }} />
            <button type="button" onClick={clearFile} className="absolute -top-2 -right-2 w-6 h-6 rounded-full flex items-center justify-center text-white" style={{ background: "var(--text-primary)" }} aria-label="Remove image"><X className="w-3.5 h-3.5" /></button>
          </motion.div>
        )}
      </AnimatePresence>
      <div className="flex items-end gap-1.5 rounded-[1.4rem] p-1.5 transition-shadow focus-within:shadow-[0_0_0_4px_rgb(var(--accent-rgb)/0.12)]" style={{ background: "var(--surface-2)", border: "1px solid var(--border-c)" }}>
        {!editing && (
          <>
            {allowAttachments && <button type="button" onClick={() => fileRef.current?.click()} className="icon-btn" aria-label="Attach image"><ImagePlus className="w-[18px] h-[18px]" /></button>}
            <input ref={fileRef} type="file" accept="image/*" className="hidden" onChange={(e) => { const f = e.target.files?.[0]; if (f) { setFile(f); setPreview(URL.createObjectURL(f)); } e.target.value = ""; }} />
          </>
        )}
        <EmojiPicker onPick={(e) => { setText((t) => t + e); taRef.current?.focus(); }} />
        <textarea
          ref={taRef}
          rows={1}
          value={text}
          onChange={onChange}
          onKeyDown={onKeyDown}
          placeholder={placeholder}
          className="flex-1 bg-transparent outline-none resize-none text-sm py-2.5 px-1 min-w-0 max-h-40"
          style={{ color: "var(--text-primary)" }}
          maxLength={2000}
          aria-label="Message"
        />
        <motion.button whileTap={{ scale: 0.9 }} type="submit" disabled={sending || (!text.trim() && !file)} className="w-10 h-10 rounded-2xl flex items-center justify-center text-white flex-shrink-0 disabled:opacity-40 transition-opacity" style={{ background: "var(--accent-grad)" }} aria-label={editing ? "Save edit" : "Send"}>
          {sending ? <Loader2 className="w-4 h-4 animate-spin" /> : editing ? <Check className="w-4 h-4" /> : <Send className="w-4 h-4" />}
        </motion.button>
      </div>
    </form>
  );
}
