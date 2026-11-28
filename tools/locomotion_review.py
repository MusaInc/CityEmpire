#!/usr/bin/env python3
"""Assemble real-time + slow-motion MP4 videos and contact sheets from locomotion_lab.gd frames using ffmpeg."""
import glob
import os
import subprocess
import sys


def build_contact_sheet(frames, out_path, cols=6, rows=2):
    if not frames:
        return
    total = cols * rows
    n = len(frames)
    start = min(n - 1, max(1, int(n * 0.08)))
    end = n - 1
    idxs = [start + int((end - start) * i / max(total - 1, 1)) for i in range(total)]
    # Build concat list or select filter via ffmpeg
    select_expr = "+".join(f"eq(n\\,{i})" for i in sorted(set(idxs)))
    frame_dir = os.path.dirname(frames[0])
    pattern = os.path.join(frame_dir, "f_%04d.png")
    vf = (
        f"select='{select_expr}',setpts=N/FRAME_RATE/TB,"
        f"scale=320:240,tile={cols}x{rows}:padding=2:color=0x14161a"
    )
    subprocess.run(
        ["ffmpeg", "-y", "-loglevel", "error", "-i", pattern, "-vf", vf, "-frames:v", "1", out_path],
        check=True,
    )


def encode_videos(frame_dir, name, out_root):
    pattern = os.path.join(frame_dir, "f_%04d.png")
    mp4_rt = os.path.join(out_root, f"{name}.mp4")
    mp4_slow = os.path.join(out_root, f"{name}_slow.mp4")
    subprocess.run(
        ["ffmpeg", "-y", "-loglevel", "error", "-framerate", "30", "-i", pattern,
         "-c:v", "libx264", "-pix_fmt", "yuv420p", "-crf", "20", mp4_rt],
        check=True,
    )
    subprocess.run(
        ["ffmpeg", "-y", "-loglevel", "error", "-framerate", "10", "-i", pattern,
         "-c:v", "libx264", "-pix_fmt", "yuv420p", "-crf", "20", mp4_slow],
        check=True,
    )


def main():
    out_root = sys.argv[1]
    keep_frames = "--keep-frames" in sys.argv
    dirs = sorted(d for d in glob.glob(os.path.join(out_root, "*_*")) if os.path.isdir(d))
    for d in dirs:
        name = os.path.basename(d)
        frames = sorted(glob.glob(os.path.join(d, "f_*.png")))
        if not frames:
            continue
        build_contact_sheet(frames, os.path.join(out_root, f"{name}_sheet.png"))
        encode_videos(d, name, out_root)
        if not keep_frames:
            for fp in frames:
                os.remove(fp)
            os.rmdir(d)
        print(f"PACKED {name} ({len(frames)} frames)")


if __name__ == "__main__":
    main()
