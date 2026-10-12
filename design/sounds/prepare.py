"""Turns a raw field recording into a seamless loop for Atmospherics.

    python3 -I prepare.py input.(ogg|flac|wav|mp3) ../../Atmospherics/Sounds/<kind>.m4a [--start S] [--length L]

Takes L seconds from S, then blends the 3 s just after the loop into its first 3 s, so the end
flows straight back into the start. Loudness is normalised to about -16 LUFS (level with the synthesized sounds), and the result is
encoded as 96 kbps stereo AAC at 44.1 kHz. Only needs ffmpeg.
"""
import argparse
import os
import subprocess

FADE = 3.0


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("src")
    ap.add_argument("dst")
    ap.add_argument("--start", type=float, default=0)
    ap.add_argument("--length", type=float, default=60)
    a = ap.parse_args()
    L, F = a.length, FADE

    graph = (
        f"[0:a]aformat=sample_rates=44100:channel_layouts=stereo,asplit=3[a][b][c];"
        f"[a]atrim=0:{F},asetpts=PTS-STARTPTS,afade=t=in:d={F}:curve=qsin[head];"
        f"[b]atrim={F}:{L},asetpts=PTS-STARTPTS[mid];"
        f"[c]atrim={L}:{L + F},asetpts=PTS-STARTPTS,afade=t=out:d={F}:curve=qsin[tail];"
        f"[head][tail]amix=inputs=2:normalize=0[seam];"
        f"[seam][mid]concat=n=2:v=0:a=1,loudnorm=I=-16:TP=-1.5:LRA=11,aresample=44100[out]"
    )
    subprocess.run(
        ["ffmpeg", "-nostdin", "-v", "error", "-y", "-ss", str(a.start), "-t", str(L + F), "-i", a.src,
         "-filter_complex", graph, "-map", "[out]", "-c:a", "aac", "-b:a", "96k", a.dst],
        check=True)
    probe = subprocess.run(
        ["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", a.dst],
        check=True, capture_output=True, text=True).stdout.strip()
    print(f"{a.dst}: {float(probe):.1f} s, {os.path.getsize(a.dst) // 1024} KB")


if __name__ == "__main__":
    main()
