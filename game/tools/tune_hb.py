#!/usr/bin/env python3
"""Tune H_B (section 17.4): run the average bot, nudge each board's H_B toward the target band, repeat.

Usage: python3 tools/tune_hb.py [iterations] [seeds]   (run from game/)
Edits balance/balance.gd in place and prints each round.
"""
import re, subprocess, sys

ITER = int(sys.argv[1]) if len(sys.argv) > 1 else 4
SEEDS = sys.argv[2] if len(sys.argv) > 2 else "4"
TARGET = 0.22  # middle of the 10-35% band
PATH = "balance/balance.gd"
RX = re.compile(r"const H_B: Array\[float\] = \[([^\]]*)\]")


def read_hb():
    return [float(x) for x in RX.search(open(PATH).read()).group(1).split(",")]


def write_hb(hb):
    s = open(PATH).read()
    s = RX.sub("const H_B: Array[float] = [%s]" % ", ".join("%.1f" % v for v in hb), s)
    open(PATH, "w").write(s)


def run():
    out = subprocess.run(["godot", "--headless", "--path", ".", "--", "--bots", "--skill", "average", "--seeds", SEEDS, "--jobs", "4", "--mode", "normal"],
                         capture_output=True, text=True).stdout
    rows = []
    for line in out.splitlines():
        m = re.match(r"\s*(\d)\s*\|\s*(\d+)\s*\|\s*(\d+)%\s*\|\s*(\d+)%\s*\|\s*(\d+)%", line)
        if m:
            rows.append((int(m.group(1)), float(m.group(3)) / 100, float(m.group(4)) / 100, float(m.group(5)) / 100))
    return rows


for it in range(ITER):
    hb = read_hb()
    rows = run()
    print("round %d  H_B %s" % (it + 1, [round(v) for v in hb]), flush=True)
    for b, clear, lost, danger in rows:
        print("  board %d clear %3d%%  lost %3d%%  danger %3d%%" % (b, clear * 100, lost * 100, danger * 100), flush=True)
        f = ((TARGET + 0.05) / (lost + 0.05)) ** 0.6
        if clear < 0.8:
            f = min(f, 0.85)
        hb[b - 1] *= max(0.7, min(1.5, f))
    write_hb(hb)
print("final H_B", [round(v) for v in read_hb()], flush=True)
