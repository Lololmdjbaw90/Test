// Generates short, pleasant demo loops for seeded tracks ("demo:<name>" URLs)
// so the music player works in local demo mode without shipping audio files.
const SCALES = [
  [0, 3, 5, 7, 10],      // minor pentatonic
  [0, 2, 4, 7, 9],       // major pentatonic
  [0, 2, 3, 7, 8],       // hirajoshi-ish
];

function hash(str) {
  let h = 2166136261;
  for (let i = 0; i < str.length; i++) h = Math.imul(h ^ str.charCodeAt(i), 16777619);
  return h >>> 0;
}

function rng(seed) {
  let s = seed || 1;
  return () => { s = (Math.imul(s, 1664525) + 1013904223) >>> 0; return s / 4294967296; };
}

function writeWav(samples, rate) {
  const buffer = new ArrayBuffer(44 + samples.length * 2);
  const view = new DataView(buffer);
  const str = (o, s) => { for (let i = 0; i < s.length; i++) view.setUint8(o + i, s.charCodeAt(i)); };
  str(0, "RIFF"); view.setUint32(4, 36 + samples.length * 2, true); str(8, "WAVE");
  str(12, "fmt "); view.setUint32(16, 16, true); view.setUint16(20, 1, true); view.setUint16(22, 1, true);
  view.setUint32(24, rate, true); view.setUint32(28, rate * 2, true); view.setUint16(32, 2, true); view.setUint16(34, 16, true);
  str(36, "data"); view.setUint32(40, samples.length * 2, true);
  for (let i = 0; i < samples.length; i++) view.setInt16(44 + i * 2, Math.max(-1, Math.min(1, samples[i])) * 0x7fff, true);
  return new Blob([buffer], { type: "audio/wav" });
}

const cache = new Map();

export function demoAudioUrl(name) {
  if (cache.has(name)) return cache.get(name);
  const seed = hash(name);
  const rand = rng(seed);
  const rate = 22050;
  const bpm = 72 + Math.floor(rand() * 30);
  const beat = 60 / bpm / 2; // eighth notes
  const steps = 64;
  const scale = SCALES[seed % SCALES.length];
  const root = 196 * Math.pow(2, Math.floor(rand() * 5) / 12);
  const out = new Float32Array(Math.ceil(steps * beat * rate) + rate);
  const chords = [0, 5, 3, 4].map((d) => scale[d % scale.length]);

  for (let step = 0; step < steps; step++) {
    const start = Math.floor(step * beat * rate);
    // melody
    if (rand() > 0.28) {
      const deg = scale[Math.floor(rand() * scale.length)] + (rand() > 0.7 ? 12 : 0);
      const f = root * 2 * Math.pow(2, deg / 12);
      const len = Math.floor(beat * rate * (rand() > 0.8 ? 2 : 1.2));
      for (let i = 0; i < len && start + i < out.length; i++) {
        const t = i / rate;
        const env = Math.min(1, i / 200) * Math.exp(-t * 4);
        out[start + i] += 0.16 * env * (Math.sin(2 * Math.PI * f * t) + 0.3 * Math.sin(4 * Math.PI * f * t));
      }
    }
    // soft pad chord every bar
    if (step % 8 === 0) {
      const chordRoot = chords[(step / 8) % chords.length];
      const len = Math.floor(beat * 8 * rate);
      [0, 4, 7].forEach((iv) => {
        const f = root / 2 * Math.pow(2, (chordRoot + iv) / 12);
        for (let i = 0; i < len && start + i < out.length; i++) {
          const t = i / rate;
          const env = Math.min(1, t * 2) * Math.min(1, (len - i) / (rate * 0.6));
          out[start + i] += 0.05 * env * Math.sin(2 * Math.PI * f * t);
        }
      });
    }
    // gentle kick + hat
    if (step % 4 === 0) {
      for (let i = 0; i < rate * 0.18 && start + i < out.length; i++) {
        const t = i / rate;
        out[start + i] += 0.22 * Math.exp(-t * 18) * Math.sin(2 * Math.PI * (55 + 90 * Math.exp(-t * 30)) * t);
      }
    }
    if (step % 2 === 1) {
      for (let i = 0; i < rate * 0.03 && start + i < out.length; i++) out[start + i] += 0.03 * (rand() * 2 - 1) * Math.exp(-i / 180);
    }
  }
  const url = URL.createObjectURL(writeWav(out, rate));
  cache.set(name, url);
  return url;
}

export function resolveAudioUrl(src) {
  if (!src) return "";
  if (src.startsWith("demo:")) return demoAudioUrl(src.slice(5));
  return src;
}
