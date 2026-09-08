#!/usr/bin/env python3
"""生成第一批可玩占位 wav：短 mono 22050Hz，正式录音按同名覆盖即可。"""

from __future__ import annotations

import math
import random
import struct
import wave
from pathlib import Path

RATE = 22050
OUT = Path(__file__).resolve().parents[1] / "godot" / "assets" / "audio" / "sfx"


def write_wav(name: str, samples: list[float]) -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    path = OUT / f"{name}.wav"
    frames = b"".join(
        struct.pack("<h", max(-32767, min(32767, int(sample * 32767))))
        for sample in samples
    )
    with wave.open(str(path), "w") as handle:
        handle.setnchannels(1)
        handle.setsampwidth(2)
        handle.setframerate(RATE)
        handle.writeframes(frames)
    print(path)


def env(index: int, total: int, attack: float = 0.006, release: float = 0.03) -> float:
    t = index / RATE
    dur = total / RATE
    if t < attack:
        return t / attack
    if t > dur - release:
        return max(0.0, (dur - t) / release)
    return 1.0


def tone(freq: float, dur: float, amp: float = 0.32, kind: str = "square") -> list[float]:
    total = int(RATE * dur)
    samples: list[float] = []
    for i in range(total):
        t = i / RATE
        phase = math.sin(2 * math.pi * freq * t)
        wave_v = phase if kind == "sine" else (1.0 if phase >= 0 else -1.0)
        samples.append(wave_v * amp * env(i, total))
    return samples


def noise(dur: float, amp: float = 0.22, rng: random.Random | None = None) -> list[float]:
    rng = rng or random.Random(7)
    total = int(RATE * dur)
    return [rng.uniform(-1.0, 1.0) * amp * env(i, total, 0.002, 0.04) for i in range(total)]


def slide(start: float, end: float, dur: float, amp: float = 0.3) -> list[float]:
    total = int(RATE * dur)
    samples: list[float] = []
    for i in range(total):
        t = i / RATE
        freq = start + (end - start) * (i / max(1, total - 1))
        wave_v = 1.0 if math.sin(2 * math.pi * freq * t) >= 0 else -1.0
        samples.append(wave_v * amp * env(i, total))
    return samples


def mix(*parts: list[float]) -> list[float]:
    length = max((len(part) for part in parts), default=0)
    out = [0.0] * length
    for part in parts:
        for i, value in enumerate(part):
            out[i] += value
    peak = max((abs(value) for value in out), default=1.0)
    if peak > 0.95:
        out = [value * 0.95 / peak for value in out]
    return out


def concat(*parts: list[float]) -> list[float]:
    merged: list[float] = []
    for part in parts:
        merged.extend(part)
    return merged


def silence(dur: float) -> list[float]:
    return [0.0] * int(RATE * dur)


def main() -> None:
    rng = random.Random(20260908)
    write_wav("ui_click", tone(880, 0.055, 0.28))
    write_wav("ui_toggle", concat(tone(660, 0.04, 0.26), tone(880, 0.05, 0.26)))
    write_wav("ui_deny", concat(tone(220, 0.07, 0.3), tone(160, 0.09, 0.28)))
    write_wav("ui_open", concat(tone(523, 0.05, 0.24), tone(659, 0.05, 0.24), tone(784, 0.07, 0.26)))
    write_wav("ui_close", concat(tone(784, 0.05, 0.24), tone(659, 0.05, 0.24), tone(523, 0.07, 0.26)))
    write_wav("ui_confirm", concat(tone(523, 0.06, 0.26, "sine"), tone(784, 0.1, 0.28, "sine")))
    write_wav("ui_save", concat(tone(659, 0.05, 0.24, "sine"), tone(988, 0.12, 0.3, "sine")))
    write_wav(
        "shop_open",
        mix(slide(180, 420, 0.22, 0.16), concat(silence(0.12), noise(0.12, 0.2, rng))),
    )
    write_wav(
        "shop_close",
        mix(slide(360, 140, 0.24, 0.16), concat(silence(0.08), noise(0.14, 0.18, rng))),
    )
    write_wav(
        "pc_on",
        concat(tone(196, 0.08, 0.18), tone(392, 0.1, 0.22), mix(tone(980, 0.06, 0.16), noise(0.08, 0.1, rng))),
    )
    write_wav("pc_off", concat(tone(392, 0.07, 0.2), tone(196, 0.12, 0.22)))
    write_wav("pc_clean", mix(noise(0.18, 0.22, rng), slide(900, 600, 0.16, 0.08)))
    write_wav(
        "pc_repair",
        concat(tone(1400, 0.03, 0.18), silence(0.03), tone(1100, 0.03, 0.18), silence(0.03), tone(1600, 0.05, 0.2)),
    )
    write_wav("seat_down", mix(tone(90, 0.09, 0.28, "sine"), noise(0.07, 0.12, rng)))
    write_wav(
        "checkout_coin",
        concat(tone(1760, 0.04, 0.22, "sine"), tone(2340, 0.08, 0.24, "sine")),
    )
    write_wav("decor_place", mix(tone(140, 0.08, 0.26, "sine"), concat(silence(0.04), tone(220, 0.05, 0.18))))
    print(f"generated {len(list(OUT.glob('*.wav')))} wavs in {OUT}")


if __name__ == "__main__":
    main()
