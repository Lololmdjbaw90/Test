"""Render Sugerly UI WAVs offline. Requires Earshot 0.3.0, numpy, scipy, soundfile.
Upstream: https://github.com/Leonxlnx/earshot
Pinned source: 925ebe56a1b755e5d354ab642bb8f344440cfa9c
Run with that checkout on PYTHONPATH. No models, external recordings, or API keys.
"""
import json
from pathlib import Path
import numpy as np
import soundfile as sf
from earshot.forge import bank

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "native/Sugerly/Resources/Sounds"
CHOICES = {
    "toggle": "toggle/on", "toggleOff": "toggle/off",
    "like": "pro_pop/double", "send": "pro_pop/chirp",
    "receive": "pro_notify/ding_1930", "chime": "pluck/kalimba_soft",
    "error": "pro_pop/thup", "reward": "pluck/kalimba_ring",
}

def main():
    OUT.mkdir(parents=True, exist_ok=True)
    reports = {}
    for name, sound in CHOICES.items():
        wave, meta = bank.render(sound, peak_db=-12 if name == "reward" else -16, checks=True)
        cap = {"chime": .65, "reward": 1.0}.get(name)
        if cap:
            n = min(len(wave), int(cap * 48000))
            wave = wave[:n]
            fade = np.minimum(1, np.arange(n - 1, -1, -1) / 2400)
            fade *= np.exp(-(8 if name == "chime" else 6) * np.arange(n) / 48000)
            wave = wave * (fade[:, None] if wave.ndim == 2 else fade)
        assert np.isfinite(wave).all() and np.max(np.abs(wave)) < .3
        sf.write(OUT / f"{name}.wav", wave, 48000, subtype="PCM_16")
        reports[name] = {"sound": sound, "duration": len(wave) / 48000,
                         "source_audit": meta["checks"]["summary"]}
    print(json.dumps(reports, indent=2))

if __name__ == "__main__":
    main()
