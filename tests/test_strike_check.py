import contextlib
import io
import os

from helpers import TempDirTestCase, load_module, wav_bytes

check = load_module("tools/strike-check.py", "strike_check_under_test")


class StrikeCheckTest(TempDirTestCase):
    def test_parse_wav(self):
        fmt, problems = check.parse_wav(self.write("good.wav", wav_bytes()))
        self.assertEqual((fmt["rate"], fmt["bits"], fmt["channels"], fmt["tag"]), (44100, 16, 1, 1))
        self.assertEqual(problems, [])

        cases = {
            "fake.wav": (b"not audio", "not a RIFF/WAVE file"),
            "float.wav": (wav_bytes(bits=32, tag=3), "32-bit float"),
            "adpcm.wav": (wav_bytes(tag=2), "unsupported encoding"),
            "empty.wav": (wav_bytes(data=b""), "empty data chunk"),
            "trunc.wav": (wav_bytes(frames=1000)[:300], "truncated"),
        }
        for name, (data, expected) in cases.items():
            _, problems = check.parse_wav(self.write(name, data))
            self.assertTrue(any(expected in p for p in problems), f"{name}: {problems}")

    def test_describe(self):
        self.assertEqual(check.describe({"rate": 48000, "bits": 24, "channels": 1}), "48000 Hz/24-bit/mono")
        self.assertEqual(check.describe({"rate": 44100, "bits": 16, "channels": 2}), "44100 Hz/16-bit/2ch")

    def test_walk(self):
        self.write("a/x.wav", b"")
        self.write("a/.fseventsd/y.wav", b"")
        self.write(".Spotlight-V100/z", b"")
        found = sorted(os.path.relpath(os.path.join(d, n), self.tmp) for d, n in check.walk(self.tmp))
        self.assertEqual(found, ["a/x.wav"])

    def test_reference_formats(self):
        self.write("ref/a.wav", wav_bytes())
        self.write("ref/b.wav", wav_bytes(frames=50))
        self.write("ref/._a.wav", b"junk")
        self.write("ref/notes.txt", b"x")
        self.assertEqual(dict(check.reference_formats(self.path("ref"))), {"44100 Hz/16-bit/mono": 2})

    def test_scan(self):
        self.write("in/good.wav", wav_bytes())
        self.write("in/dup.wav", wav_bytes())
        self.write("in/odd.wav", wav_bytes(rate=22050, data=b"\x01\x02" * 10))
        self.write("in/fake.wav", b"nope")
        self.write("in/._good.wav", b"")
        self.write("in/.DS_Store", b"")
        r = check.scan(self.path("in"), allowed={"44100 Hz/16-bit/mono": 1})
        self.assertEqual(sorted(os.path.basename(p) for p in r["flagged"]), ["fake.wav", "odd.wav"])
        self.assertIn("not used by any reference sample", " ".join(r["flagged"][self.path("in/odd.wav")]))
        self.assertEqual([sorted(map(os.path.basename, d)) for d in r["duplicates"]], [["dup.wav", "good.wav"]])
        self.assertEqual(len(r["litter"]), 2)
        self.assertEqual(sum(r["per_dir"].values()), 4)

    def test_report(self):
        lines = []
        many = {self.tmp: check.MAX_SAMPLES + 1}
        check.report({"flagged": {"/x/bad.wav": ["truncated"]}, "per_dir": many, "formats": {},
                      "duplicates": [["/a.wav", "/b.wav"]], "litter": ["/._a"]}, lines.append)
        text = "\n".join(lines)
        for expected in ("BAD  /x/bad.wav", "- truncated", "WARN", f"at most {check.MAX_SAMPLES}", "DUP", "INFO 1 macOS"):
            self.assertIn(expected, text)

    def test_clean_litter(self):
        a, b = self.write("._a", b""), self.write(".DS_Store", b"")
        self.assertEqual(check.clean_litter([a, b], confirm=lambda _: "n", out=lambda _: None), 0)
        self.assertTrue(os.path.exists(a))
        self.assertEqual(check.clean_litter([a, b], confirm=lambda _: "y", out=lambda _: None), 2)
        self.assertFalse(os.path.exists(a) or os.path.exists(b))
        self.assertEqual(check.clean_litter([], confirm=lambda _: "y"), 0)

    def test_fix_files(self):
        good = self.write("in/float.wav", wav_bytes(bits=32, tag=3, rate=48000))
        bad = self.write("in/fake.wav", b"nope")
        lines = []
        fixed = check.fix_files([good, bad], self.path("out"), out=lines.append)
        self.assertEqual(fixed, [self.path("out/float.wav")])
        fmt, problems = check.parse_wav(fixed[0])
        self.assertEqual((fmt["rate"], fmt["bits"], problems), (44100, 16, []))
        self.assertTrue(any(l.strip().startswith("FAILED") for l in lines))

    def test_main(self):
        self.write("ok/a.wav", wav_bytes())
        self.write("bad/a.wav", b"nope")
        with contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(check.main([self.path("ok")]), 0)
        with contextlib.redirect_stdout(io.StringIO()) as out:
            self.assertEqual(check.main([self.path("bad"), "--reference", self.path("ok")]), 1)
        self.assertIn("reference formats", out.getvalue())
