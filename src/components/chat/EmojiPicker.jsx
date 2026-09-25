import React, { useEffect, useRef, useState } from "react";
import { AnimatePresence, motion } from "framer-motion";
import { Smile } from "lucide-react";

const CATEGORIES = [
  { id: "smileys", icon: "😊", emojis: "😀 😃 😄 😁 😆 🥹 😅 😂 🤣 🥲 😊 😇 🙂 😉 😌 😍 🥰 😘 😗 😙 😚 😋 😛 😝 😜 🤪 🤨 🧐 🤓 😎 🥸 🤩 🥳 😏 😒 😞 😔 😟 😕 🙁 😣 😖 😫 😩 🥺 😢 😭 😤 😠 😡 🤯 😳 🥵 🥶 😱 😨 😰 😥 😓 🤗 🤔 🫣 🤭 🫢 🤫 🤥 😶 😐 😑 😬 🙄 😯 😦 😧 😮 😲 🥱 😴 🤤 😪 😵 🤐 🥴 🤢 🤮 🤧 😷 🤒 🤕 🤠 😈 👻 💀 👽 🤖 🎃 😺 😸 😹 😻 😼 😽 🙀 😿 😾".split(" ") },
  { id: "hearts", icon: "💖", emojis: "❤️ 🩷 🧡 💛 💚 💙 🩵 💜 🤎 🖤 🩶 🤍 💔 ❣️ 💕 💞 💓 💗 💖 💘 💝 💟 ✨ ⭐ 🌟 💫 🔥 💥 💯 🎉 🎊 🎈 🎁 🏆 🥇 👑".split(" ") },
  { id: "hands", icon: "👍", emojis: "👍 👎 👊 ✊ 🤛 🤜 👏 🙌 🫶 👐 🤲 🤝 🙏 ✌️ 🤞 🫰 🤟 🤘 👌 🤌 🤏 👈 👉 👆 👇 ☝️ ✋ 🤚 🖐️ 🖖 👋 🤙 💪 ✍️ 💅".split(" ") },
  { id: "art", icon: "🎨", emojis: "🎨 🖌️ 🖍️ ✏️ 🖊️ 🖋️ 📐 📏 🖼️ 📷 📸 🎬 🎭 🎤 🎧 🎼 🎹 🥁 🎷 🎺 🎸 🪕 🎻 🎮 🕹️ 🧩 🧸 🪄 💡 📚 📖 ✂️ 🧵 🧶 🪡".split(" ") },
  { id: "nature", icon: "🌸", emojis: "🌸 💮 🏵️ 🌹 🥀 🌺 🌻 🌼 🌷 🌱 🪴 🌲 🌳 🌴 🌵 🍀 🍁 🍂 🍃 🍄 🌙 🌛 ⭐ ☀️ 🌈 ☁️ ⛅ 🌧️ ❄️ ☃️ 🌊 🐱 🐶 🐰 🦊 🐻 🐼 🐨 🐸 🐣 🦋 🐝 🐞 🐢 🐙 🦄 🐉".split(" ") },
  { id: "food", icon: "🍓", emojis: "🍓 🍒 🍑 🥭 🍍 🥥 🥝 🍅 🍉 🍇 🍋 🍊 🍎 🍏 🍐 🍌 🥑 🍞 🥐 🧇 🥞 🧀 🍕 🍔 🍟 🌭 🌮 🍣 🍜 🍙 🍡 🍦 🍧 🍨 🍩 🍪 🎂 🍰 🧁 🍫 🍬 🍭 🍮 🍯 ☕ 🍵 🧋 🥤".split(" ") },
];

export const QUICK_REACTIONS = ["❤️", "😂", "😮", "😢", "👍", "🎉", "🔥", "✨"];

export default function EmojiPicker({ onPick, align = "left", buttonClassName = "icon-btn", label = "Add emoji" }) {
  const [open, setOpen] = useState(false);
  const [cat, setCat] = useState(CATEGORIES[0].id);
  const ref = useRef(null);
  useEffect(() => {
    if (!open) return undefined;
    const h = (e) => { if (ref.current && !ref.current.contains(e.target)) setOpen(false); };
    document.addEventListener("mousedown", h);
    return () => document.removeEventListener("mousedown", h);
  }, [open]);
  const current = CATEGORIES.find((c) => c.id === cat);
  return (
    <div ref={ref} className="relative">
      <button type="button" onClick={() => setOpen((o) => !o)} className={buttonClassName} aria-label={label} aria-expanded={open}><Smile className="w-[18px] h-[18px]" /></button>
      <AnimatePresence>
        {open && (
          <motion.div
            initial={{ opacity: 0, y: 8, scale: 0.95 }}
            animate={{ opacity: 1, y: 0, scale: 1 }}
            exit={{ opacity: 0, y: 8, scale: 0.95 }}
            transition={{ type: "spring", stiffness: 420, damping: 30 }}
            className={`absolute bottom-12 ${align === "right" ? "right-0" : "left-0"} z-50 w-[300px] rounded-3xl overflow-hidden`}
            style={{ background: "var(--surface)", border: "1px solid var(--border-c)", boxShadow: "var(--shadow-lg)" }}
          >
            <div className="flex gap-1 p-2 border-b" style={{ borderColor: "var(--border-c)" }}>
              {CATEGORIES.map((c) => (
                <button key={c.id} type="button" onClick={() => setCat(c.id)} className="flex-1 h-9 rounded-xl text-lg transition-colors" style={cat === c.id ? { background: "var(--pink-soft)" } : undefined} aria-label={c.id}>{c.icon}</button>
              ))}
            </div>
            <div className="grid grid-cols-8 gap-0.5 p-2 h-56 overflow-y-auto scroll">
              {current.emojis.map((e, i) => (
                <motion.button key={`${e}-${i}`} type="button" whileHover={{ scale: 1.3 }} whileTap={{ scale: 0.9 }} onClick={() => onPick(e)} className="h-9 rounded-lg text-xl flex items-center justify-center hover:bg-[var(--surface-2)]">{e}</motion.button>
              ))}
            </div>
          </motion.div>
        )}
      </AnimatePresence>
    </div>
  );
}
