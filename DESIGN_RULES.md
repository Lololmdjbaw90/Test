# Sugerly design rules (from the owner — always follow these)

1. **Gradients go top to bottom only.** Never left→right, right→left or
   diagonal (`.leading`/`.trailing`/`.topLeading`/`.bottomTrailing`…). Use
   `startPoint: .top, endPoint: .bottom`. (Moving shines and the menu's edge
   shadow are not colour gradients and are the only exceptions.)
2. **Backgrounds must be clearly visible.** Never wash page backgrounds,
   wallpapers or patterns out to near-white. Keep the page tint, the colour
   glows and the pattern strong enough to see at a glance.
3. **Clouds and sparkles never touch or overlap** — not each other, and not
   the icons or text next to them. Give each its own space (rows, columns,
   cells) so this holds even while they move.
4. **Titles use the Sugerly logo style**: round chunky letters, mostly white
   with a soft hint of colour, a dark berry outline and a small edge below.
5. **No lag.** Prefer still pictures and Core Animation over redrawing every
   frame; no soft shadows in long scrolling lists and menus; switching tabs,
   plans or pickers must be instant.
