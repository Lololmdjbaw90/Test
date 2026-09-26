import React, { useRef, useState } from "react";
import { Smile } from "lucide-react";
import Popover from "@/components/common/Popover";

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
  const current = CATEGORIES.find((c) => c.id === cat);
  return (
    <>
      <button ref={ref} type="button" onClick={() => setOpen((o) => !o)} className={buttonClassName} aria-label={label} aria-expanded={open}><Smile className="w-[18px] h-[18px]" /></button>
      <Popover open={open} onClose={() => setOpen(false)} anchorRef={ref} placement={align === "right" ? "top-end" : "top-start"} width={316} label="Emoji picker">
        <div className="flex gap-1 p-2 border-b" style={{ borderColor: "var(--border-c)" }}>
          {CATEGORIES.map((c) => (
            <button key={c.id} type="button" onClick={() => setCat(c.id)} className="flex-1 h-9 rounded-xl text-lg transition-colors" style={cat === c.id ? { background: "var(--pink-soft)" } : undefined} aria-label={c.id}>{c.icon}</button>
          ))}
        </div>
        <div className="grid grid-cols-8 gap-0.5 p-2 h-56 overflow-y-auto scroll">
          {current.emojis.map((e, i) => (
            <button key={`${e}-${i}`} type="button" onClick={() => onPick(e)} className="h-9 rounded-lg text-xl flex items-center justify-center transition-[transform,background-color] hover:scale-125 hover:bg-[var(--surface-2)] active:scale-95">{e}</button>
          ))}
        </div>
      </Popover>
    </>
  );
}
