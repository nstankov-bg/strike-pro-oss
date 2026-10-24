import os
import subprocess

from helpers import ROOT, TempDirTestCase, run_zsh

SCRIPT = "tools/strike-backup.sh"


class BackupTest(TempDirTestCase):
    def setUp(self):
        super().setUp()
        self.vol = self.path("vol")
        self.dest = self.path("backups")
        for i in range(25):
            self.write(f"vol/SAMPLES/s{i}.wav", os.urandom(512))
        self.write("vol/KITS/k1.skt", b"kit")
        self.write("vol/._junk", b"")
        self.write("vol/.DS_Store", b"")
        self.write("vol/.fseventsd/log", b"")
        self.env = {"STRIKE_VOLUME": self.vol, "STRIKE_BACKUP_DIR": self.dest, "STRIKE_BACKUP_KEEP": "2",
                    "STRIKE_BACKUP_LOG": self.path("backup.log"), "STRIKE_BACKUP_SETTLE": "0",
                    "STRIKE_BACKUP_NOTIFY": "true"}

    def zsh(self, code, **env):
        return run_zsh(SCRIPT, code, dict(self.env, **env))

    def snapshots(self):
        return sorted(d for d in os.listdir(self.dest) if d.startswith("20")) if os.path.isdir(self.dest) else []

    def test_log(self):
        r = self.zsh('log "hello world"')
        self.assertRegex(r.stdout, r"^\d{4}-\d\d-\d\d \d\d:\d\d:\d\d hello world")
        with open(self.path("backup.log")) as f:
            self.assertIn("hello world", f.read())

    def test_fail(self):
        r = self.zsh('fail "it broke"; print "rc=$?"')
        self.assertIn("ERROR: it broke", r.stdout)
        self.assertIn("rc=1", r.stdout)

    def test_find_volume(self):
        self.assertEqual(self.zsh("find_volume").stdout.strip(), self.vol)
        # Without an override it asks IOKit; with no module attached that yields nothing (and still succeeds).
        r = self.zsh('find_volume; print "rc=$?"', STRIKE_VOLUME="")
        self.assertTrue(r.stdout.strip().endswith("rc=0"))

    def test_content_files(self):
        r = self.zsh(f'content_files "{self.vol}" | tr "\\0" "\\n"')
        names = sorted(os.path.relpath(p, self.vol) for p in r.stdout.split())
        self.assertEqual(len(names), 26)
        self.assertFalse(any(n.startswith((".", "._")) or "/." in n for n in names))

    def test_file_count(self):
        self.assertEqual(self.zsh(f'file_count "{self.vol}"').stdout.strip(), "26")

    def test_listing(self):
        first = self.zsh(f'listing "{self.vol}"').stdout.strip()
        self.assertRegex(first, r"^[0-9a-f]{40}$")
        self.assertEqual(first, self.zsh(f'listing "{self.vol}"').stdout.strip())
        self.write("vol/KITS/k2.skt", b"new kit")
        self.assertNotEqual(first, self.zsh(f'listing "{self.vol}"').stdout.strip())

    def test_shrink_ok(self):
        cases = {("100", "10"): 0, ("5", "10"): 0, ("10", "25"): 1, ("13", "25"): 0, ("0", "200"): 1}
        for (count, prev), rc in cases.items():
            self.assertEqual(self.zsh(f"shrink_ok {count} {prev}").returncode, rc, (count, prev))

    def test_latest_snapshot(self):
        self.assertEqual(self.zsh("latest_snapshot").stdout.strip(), "")
        for name in ("2026-01-01_000000", "2026-03-01_000000", "2026-02-01_000000", ".in-progress-x"):
            os.makedirs(os.path.join(self.dest, name))
        self.assertEqual(self.zsh("latest_snapshot").stdout.strip(), os.path.join(self.dest, "2026-03-01_000000"))

    def test_prune(self):
        for m in range(1, 6):
            os.makedirs(os.path.join(self.dest, f"2026-0{m}-01_000000"))
        self.zsh("prune")
        self.assertEqual(self.snapshots(), ["2026-04-01_000000", "2026-05-01_000000"])

    def test_take_snapshot(self):
        os.makedirs(self.dest)
        first = self.zsh(f'take_snapshot "{self.vol}" "" 26 | tail -n 1').stdout.strip()
        self.assertTrue(os.path.isfile(os.path.join(first, "SAMPLES", "s0.wav")))
        self.assertFalse(os.path.exists(os.path.join(first, "._junk")))
        self.assertFalse(os.path.exists(os.path.join(first, ".fseventsd")))
        with open(os.path.join(first, ".filecount")) as f:
            self.assertEqual(f.read().strip(), "26")
        # Immediately again: a same-second run must get its own folder, not nest inside the first.
        second = self.zsh(f'take_snapshot "{self.vol}" "{first}" 26 | tail -n 1').stdout.strip()
        self.assertNotEqual(first, second)
        self.assertEqual(os.path.dirname(second), self.dest)
        self.assertEqual(len(self.snapshots()), 2)
        self.assertEqual(os.stat(os.path.join(second, "SAMPLES", "s0.wav")).st_nlink, 2, "unchanged files are hard-linked")

    def test_main(self):
        run = lambda *args, **env: subprocess.run(["/bin/zsh", os.path.join(ROOT, SCRIPT), *args],
                                                  capture_output=True, text=True, env={**os.environ, **self.env, **env})
        self.assertEqual(run().returncode, 0)
        self.assertEqual(len(self.snapshots()), 1)
        self.assertEqual(run("--bogus").returncode, 2)
        self.assertEqual(run("--if-present", STRIKE_VOLUME=self.path("missing")).returncode, 0)
        self.assertEqual(run(STRIKE_VOLUME=self.path("missing")).returncode, 1)
        for i in range(20):
            os.remove(self.path(f"vol/SAMPLES/s{i}.wav"))
        refused = run()
        self.assertEqual(refused.returncode, 1)
        self.assertIn("refusing", refused.stdout)
        self.assertEqual(run("--force").returncode, 0)
        self.assertEqual(len(self.snapshots()), 2)
