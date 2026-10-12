"""Turns a raw field recording into a seamless loop for Atmospherics.

    python3 -I prepare.py input.(ogg|flac|wav|mp3) ../../Atmospherics/Sounds/<kind>.m4a [--start S] [--length L]

Takes L seconds from S and keeps the recording's natural dynamics: one fixed gain brings it to
-20 LUFS (the level every recording shares, so the app's per-sound presence is all that sets the
balance), a slow, gentle compressor only touches events more than 6 dB above the recording's
typical level (a peeper right by the mic, one very close bird), and a limiter catches rare pops.
All of that runs before the loop is made, so nothing stateful sits on the seam: the 3 s just
after the loop are then blended into its first 3 s, so the end flows straight back into the start.
Encoded as 96 kbps stereo AAC at 44.1 kHz. Only needs ffmpeg.
"""
import argparse
import os
import re
import subprocess
import tempfile

TARGET = -20.0      # LUFS, integrated
FADE = 3.0          # seconds of seam crossfade
PREROLL = 2.0       # seconds the compressor and limiter warm up on before the loop starts
HEADROOM = 6.0      # dB above the typical short-term loudness before the compressor acts


def run(args):
    return subprocess.run(["ffmpeg", "-nostdin", "-hide_banner", "-y", *args], check=True,
                          capture_output=True, text=True).stderr


def loudness(path, extra=()):
    """Integrated loudness, median short-term loudness and RMS level (dBFS) of a file."""
    err = run([*extra, "-i", path, "-af",
               "ebur128=framelog=info,astats=measure_perchannel=none:measure_overall=RMS_level",
               "-f", "null", "-"])
    integrated = float(re.findall(r"I:\s+(-?[\d.]+) LUFS", err)[-1])
    short = sorted(float(s) for s in re.findall(r"S:\s*(-?[\d.]+)", err)[30:] if float(s) > -70)
    rms = float(re.findall(r"RMS level dB:\s*(-?[\d.]+)", err)[-1])
    return integrated, short[len(short) // 2], rms


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("src")
    ap.add_argument("dst")
    ap.add_argument("--start", type=float, default=0)
    ap.add_argument("--length", type=float, default=60)
    a = ap.parse_args()
    L, F = a.length, FADE
    pre = min(PREROLL, a.start)
    span = ["-ss", str(a.start - pre), "-t", str(pre + L + F)]

    with tempfile.TemporaryDirectory() as tmp:
        raw = os.path.join(tmp, "raw.wav")
        run([*span, "-i", a.src, "-af", "aformat=sample_fmts=flt:sample_rates=44100:channel_layouts=stereo",
             "-c:a", "pcm_f32le", raw])
        integrated, median, rms = loudness(raw)

        # Fixed gain to the target, then tame only what stands well above the recording's own norm.
        gain = TARGET - integrated
        threshold = min(-0.5, median + gain + HEADROOM + (rms - integrated))   # dBFS; nothing to tame above full scale
        tamed = os.path.join(tmp, "tamed.wav")
        run(["-i", raw, "-af",
             f"volume={gain:.2f}dB,acompressor=threshold={10 ** (threshold / 20):.6f}:ratio=4:attack=50:release=600"
             f":knee=6:detection=rms:link=average:makeup=1", "-c:a", "pcm_f32le", tamed])

        # The compressor took a little off: bring it back to the target and limit rare peaks,
        # correcting the gain until the limited result lands on the target.
        limited = os.path.join(tmp, "limited.wav")
        gain = 0.0
        for _ in range(3):
            run(["-i", tamed, "-af", f"volume={gain:.2f}dB,alimiter=limit=0.89:attack=5:release=60:level=0:latency=1",
                 "-c:a", "pcm_f32le", limited])
            level, _, _ = loudness(limited, ("-ss", str(pre)))
            if abs(TARGET - level) < 0.2:
                break
            gain += TARGET - level
        tamed = limited

        graph = (
            f"[0:a]atrim={pre},asetpts=PTS-STARTPTS,asplit=3[a][b][c];"
            f"[a]atrim=0:{F},asetpts=PTS-STARTPTS,afade=t=in:d={F}:curve=qsin[head];"
            f"[b]atrim={F}:{L},asetpts=PTS-STARTPTS[mid];"
            f"[c]atrim={L}:{L + F},asetpts=PTS-STARTPTS,afade=t=out:d={F}:curve=qsin[tail];"
            f"[head][tail]amix=inputs=2:normalize=0[seam];"
            f"[seam][mid]concat=n=2:v=0:a=1[out]"
        )
        run(["-i", tamed, "-filter_complex", graph, "-map", "[out]", "-c:a", "aac", "-b:a", "96k", a.dst])

    final, _, _ = loudness(a.dst)
    probe = subprocess.run(
        ["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", a.dst],
        check=True, capture_output=True, text=True).stdout.strip()
    print(f"{a.dst}: {float(probe):.1f} s, {final:.1f} LUFS, {os.path.getsize(a.dst) // 1024} KB")


if __name__ == "__main__":
    main()
