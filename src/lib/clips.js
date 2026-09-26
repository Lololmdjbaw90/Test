// Video cuts.
// -----------------------------------------------------------------------------
// A reel's video is never re-encoded. Instead `edits.clips` lists the parts of
// the original file to play, in order: [{ id, start, end }] (seconds in the
// source video). Splitting, deleting, reordering and trimming just change
// this list, and the player jumps from the end of one clip to the start of
// the next. "Output time" is time in the finished reel (before speed).
// Older reels only have trim_start / trim_end, which is a single clip.
// -----------------------------------------------------------------------------
export const MIN_CLIP = 0.3;
const uid = () => `c${Math.random().toString(36).slice(2, 9)}`;

export function clipsOf(edits = {}, sourceDuration = 0) {
  const list = (edits.clips || []).filter((c) => c && c.end - c.start >= 0.05);
  if (list.length) return list;
  const start = edits.trim_start || 0;
  const end = edits.trim_end && edits.trim_end > start ? edits.trim_end : sourceDuration || start + 1;
  return [{ id: "c0", start, end }];
}

export const clipLength = (c) => Math.max(0, c.end - c.start);
export const totalLength = (clips) => clips.reduce((s, c) => s + clipLength(c), 0);

// Output time → which clip and where in the source.
export function locate(clips, t) {
  let acc = 0;
  for (let i = 0; i < clips.length; i++) {
    const len = clipLength(clips[i]);
    if (t < acc + len || i === clips.length - 1) {
      return { index: i, source: Math.min(clips[i].end, clips[i].start + Math.max(0, t - acc)), offset: acc };
    }
    acc += len;
  }
  return { index: 0, source: clips[0]?.start || 0, offset: 0 };
}
// Clip index + source time → output time.
export function outputTime(clips, index, source) {
  let acc = 0;
  for (let i = 0; i < index; i++) acc += clipLength(clips[i]);
  const c = clips[index];
  return c ? acc + Math.min(clipLength(c), Math.max(0, source - c.start)) : acc;
}

// Split the clip under output time `t` into two.
export function splitAt(clips, t) {
  const { index, source } = locate(clips, t);
  const c = clips[index];
  if (!c || source - c.start < MIN_CLIP || c.end - source < MIN_CLIP) return { clips, index: -1 };
  const left = { ...c, end: source };
  const right = { id: uid(), start: source, end: c.end };
  return { clips: [...clips.slice(0, index), left, right, ...clips.slice(index + 1)], index: index + 1 };
}
export const removeClip = (clips, i) => (clips.length > 1 ? clips.filter((_, k) => k !== i) : clips);
export const duplicateClip = (clips, i) => [...clips.slice(0, i + 1), { ...clips[i], id: uid() }, ...clips.slice(i + 1)];
export function moveClip(clips, i, dir) {
  const j = i + dir;
  if (j < 0 || j >= clips.length) return clips;
  const next = clips.slice();
  [next[i], next[j]] = [next[j], next[i]];
  return next;
}
export function trimClip(clips, i, { start, end }, sourceDuration) {
  return clips.map((c, k) => {
    if (k !== i) return c;
    // Only the dragged edge moves; it stops MIN_CLIP from the other one.
    let s = c.start, e = c.end;
    if (start != null) s = Math.max(0, Math.min(start, e - MIN_CLIP));
    if (end != null) e = Math.min(sourceDuration || end, Math.max(end, s + MIN_CLIP));
    return { ...c, start: s, end: e };
  });
}
// Keep at most `max` seconds of output (the reel length limit).
export function capLength(clips, max) {
  const out = [];
  let left = max;
  for (const c of clips) {
    if (left <= 0.05) break;
    const len = Math.min(clipLength(c), left);
    out.push({ ...c, end: c.start + len });
    left -= len;
  }
  return out.length ? out : clips.slice(0, 1);
}
export const newClip = (start, end) => ({ id: uid(), start, end });
