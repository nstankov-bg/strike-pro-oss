#!/usr/bin/env -S python3 -I
"""strike-check — read-only preflight for WAV samples before importing them into the Strike editor.

The editor only says "not a valid .wav file" or "One or more samples cannot be auto-mapped".
This names the file and the reason.

  python3 -I tools/strike-check.py <folder or module drive>
  python3 -I tools/strike-check.py <folder> --reference /Volumes/<module>/SAMPLES   # flag formats the module's own samples don't use
  python3 -I tools/strike-check.py <folder> --clean        # delete macOS ._* / .DS_Store litter (asks first)
  python3 -I tools/strike-check.py <folder> --fix <outdir> # write 16-bit/44.1 kHz PCM copies of flagged files via afconvert

Checks: RIFF/WAVE structure, truncated data chunks, non-PCM encodings, format outliers,
folders over the editor's 255-sample limit, duplicate audio, and macOS metadata files.
Nothing on the source is modified unless --clean is given and confirmed.
"""
import argparse
import collections
import hashlib
import os
import struct
import subprocess
import sys

MAX_SAMPLES = 255  # editor message MAX_ZONE_ERROR: "Maximum Number of Samples (255) Reached"
PCM, FLOAT, EXTENSIBLE = 1, 3, 0xFFFE


def parse_wav(path):
    """Returns (format dict, problems list). Reads chunk headers only, plus the data for hashing."""
    problems = []
    size = os.path.getsize(path)
    with open(path, "rb") as f:
        header = f.read(12)
        if len(header) < 12 or header[:4] != b"RIFF" or header[8:12] != b"WAVE":
            return None, ["not a RIFF/WAVE file"]
        riff_size = struct.unpack("<I", header[4:8])[0]
        if riff_size + 8 > size:
            problems.append(f"truncated: RIFF says {riff_size + 8} bytes, file has {size}")
        fmt, data_hash, data_len = None, None, None
        while True:
            chunk = f.read(8)
            if len(chunk) < 8:
                break
            cid, clen = chunk[:4], struct.unpack("<I", chunk[4:])[0]
            start = f.tell()
            if cid == b"fmt ":
                body = f.read(clen)
                if len(body) < 16:
                    problems.append("fmt chunk too short")
                    break
                tag, ch, rate, _, _, bits = struct.unpack("<HHIIHH", body[:16])
                if tag == EXTENSIBLE and len(body) >= 26:
                    tag = struct.unpack("<H", body[24:26])[0]  # first 2 bytes of the SubFormat GUID
                fmt = {"tag": tag, "channels": ch, "rate": rate, "bits": bits}
            elif cid == b"data":
                remaining = size - start
                data_len = clen
                if clen > remaining:
                    problems.append(f"truncated: data chunk says {clen} bytes, only {remaining} present")
                data_hash = hashlib.sha1(f.read(min(clen, remaining))).hexdigest()
            f.seek(start + clen + (clen & 1))
        if fmt is None:
            problems.append("no fmt chunk")
        elif fmt["tag"] not in (PCM, FLOAT):
            problems.append(f"unsupported encoding (format tag {fmt['tag']}); use PCM")
        elif fmt["tag"] == FLOAT:
            problems.append("32-bit float; the module's factory samples are integer PCM")
        if data_len is None:
            problems.append("no data chunk")
        elif data_len == 0:
            problems.append("empty data chunk (silent sample)")
    if fmt is not None:
        fmt["hash"] = data_hash
    return fmt, problems


def describe(fmt):
    return f"{fmt['rate']} Hz/{fmt['bits']}-bit/{'mono' if fmt['channels'] == 1 else str(fmt['channels']) + 'ch'}"


def walk(root):
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = [d for d in dirnames if d not in (".Spotlight-V100", ".fseventsd", ".Trashes", ".TemporaryItems")]
        for name in filenames:
            yield dirpath, name


def reference_formats(root):
    """Counter of format descriptions used by the known-good samples under `root`."""
    allowed = collections.Counter()
    for d, n in walk(root):
        if n.lower().endswith(".wav") and not n.startswith("._"):
            fmt, _ = parse_wav(os.path.join(d, n))
            if fmt:
                allowed[describe(fmt)] += 1
    return allowed


def scan(root, allowed=None):
    """Checks every WAV under `root`. Returns a dict with flagged, per_dir, formats, duplicates, litter."""
    litter, flagged, per_dir = [], {}, collections.Counter()
    formats, by_hash = collections.Counter(), collections.defaultdict(list)
    for d, n in walk(root):
        p = os.path.join(d, n)
        if n.startswith("._") or n == ".DS_Store":
            litter.append(p)
            continue
        if not n.lower().endswith(".wav"):
            continue
        per_dir[d] += 1
        fmt, problems = parse_wav(p)
        if fmt:
            formats[describe(fmt)] += 1
            if fmt.get("hash"):
                by_hash[fmt["hash"]].append(p)
            if allowed is not None and describe(fmt) not in allowed:
                problems.append(f"format {describe(fmt)} not used by any reference sample")
        if problems:
            flagged[p] = problems
    duplicates = [paths for paths in by_hash.values() if len(paths) > 1]
    return {"flagged": flagged, "per_dir": per_dir, "formats": formats, "duplicates": duplicates, "litter": litter}


def report(result, out=print):
    per_dir = result["per_dir"]
    out(f"\nscanned {sum(per_dir.values())} WAV files in {len(per_dir)} folders; formats: {dict(result['formats'])}")
    for p, problems in sorted(result["flagged"].items()):
        out(f"  BAD  {p}\n       - " + "\n       - ".join(problems))
    for d, n in per_dir.items():
        if n > MAX_SAMPLES:
            out(f"  WARN {d}: {n} samples; the editor accepts at most {MAX_SAMPLES} per instrument")
    for paths in result["duplicates"]:
        out("  DUP  identical audio:\n       " + "\n       ".join(paths))
    if result["litter"]:
        out(f"  INFO {len(result['litter'])} macOS metadata files (._*, .DS_Store); remove with --clean")


def clean_litter(litter, confirm=input, out=print):
    """Deletes macOS metadata files after confirmation. Returns how many were removed."""
    if not litter or confirm(f"delete {len(litter)} metadata files? [y/N] ").strip().lower() != "y":
        return 0
    for p in litter:
        os.remove(p)
    out("  cleaned")
    return len(litter)


def fix_files(paths, outdir, out=print, afconvert="/usr/bin/afconvert"):
    """Writes 16-bit/44.1 kHz PCM copies of `paths` into `outdir`. Returns the paths that converted."""
    os.makedirs(outdir, exist_ok=True)
    fixed = []
    for p in paths:
        dest = os.path.join(outdir, os.path.basename(p))
        r = subprocess.run([afconvert, "-f", "WAVE", "-d", "LEI16@44100", p, dest], capture_output=True, text=True)
        if r.returncode == 0:
            fixed.append(dest)
        out(f"  {'fixed' if r.returncode == 0 else 'FAILED'} {dest}" + (f": {r.stderr.strip()}" if r.returncode else ""))
    return fixed


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("path")
    ap.add_argument("--reference", help="folder of known-good samples (e.g. the module's own SAMPLES)")
    ap.add_argument("--clean", action="store_true", help="delete ._* and .DS_Store files after confirmation")
    ap.add_argument("--fix", metavar="OUTDIR", help="write 16-bit/44.1 kHz PCM copies of flagged files here")
    args = ap.parse_args(argv)

    allowed = None
    if args.reference:
        allowed = reference_formats(args.reference)
        print(f"reference formats: {dict(allowed)}")
    result = scan(args.path, allowed)
    report(result)
    if args.clean:
        clean_litter(result["litter"])
    if args.fix and result["flagged"]:
        fix_files(result["flagged"], args.fix)
    return 1 if result["flagged"] else 0


if __name__ == "__main__":
    sys.exit(main())
