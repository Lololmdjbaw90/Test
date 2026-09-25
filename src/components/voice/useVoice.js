import { useEffect, useState } from "react";
import voice from "@/lib/voice";
import { formatDuration } from "@/lib/calls";

// Live snapshot of the voice/call connection.
export function useVoice() {
  const [state, setState] = useState(voice.getState);
  useEffect(() => voice.subscribe(setState), []);
  return state;
}

// "3:07" style timer since `since` (ms timestamp), ticking every second.
export function useElapsed(since) {
  const [now, setNow] = useState(Date.now());
  useEffect(() => {
    if (!since) return undefined;
    const t = setInterval(() => setNow(Date.now()), 1000);
    return () => clearInterval(t);
  }, [since]);
  return since ? formatDuration(now - since) : "0:00";
}

// Re-render every `ms` (for "is this still ringing?" style checks).
export function useNow(ms = 5000) {
  const [now, setNow] = useState(Date.now());
  useEffect(() => {
    const t = setInterval(() => setNow(Date.now()), ms);
    return () => clearInterval(t);
  }, [ms]);
  return now;
}
