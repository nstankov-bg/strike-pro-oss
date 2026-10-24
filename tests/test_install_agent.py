import os
import subprocess

from helpers import ROOT, TempDirTestCase, run_zsh

SCRIPT = "tools/install-backup-agent.sh"
LABEL = "io.github.strike-pro-oss.backup"


class InstallAgentTest(TempDirTestCase):
    def setUp(self):
        super().setUp()
        self.calls = self.path("launchctl.calls")
        stub = self.write("launchctl", f'#!/bin/sh\necho "$@" >> "{self.calls}"\n')
        os.chmod(stub, 0o755)
        self.agents = self.path("LaunchAgents")
        self.plist = os.path.join(self.agents, f"{LABEL}.plist")
        self.env = {"LAUNCH_AGENTS_DIR": self.agents, "LAUNCHCTL": stub}

    def launchctl_calls(self):
        if not os.path.exists(self.calls):
            return []
        with open(self.calls) as f:
            return [l.split()[0] for l in f]

    def test_plist_xml(self):
        out = self.write("agent.plist", run_zsh(SCRIPT, 'plist_xml /opt/x/backup.sh /tmp/b.log', self.env).stdout)
        self.assertEqual(subprocess.run(["plutil", "-lint", "-s", out]).returncode, 0)
        args = subprocess.run(["plutil", "-extract", "ProgramArguments", "json", "-o", "-", out],
                              capture_output=True, text=True).stdout
        self.assertEqual(args.strip(), '["\\/bin\\/zsh","\\/opt\\/x\\/backup.sh","--if-present"]')
        mount = subprocess.run(["plutil", "-extract", "StartOnMount", "raw", out], capture_output=True, text=True).stdout
        self.assertEqual(mount.strip(), "true")

    def test_remove_agent(self):
        os.makedirs(self.agents)
        open(self.plist, "w").close()
        self.assertEqual(run_zsh(SCRIPT, "remove_agent", self.env).returncode, 0)
        self.assertFalse(os.path.exists(self.plist))
        self.assertEqual(self.launchctl_calls(), ["bootout"])

    def test_install_agent(self):
        r = run_zsh(SCRIPT, "install_agent", self.env)
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertTrue(os.path.isfile(self.plist))
        self.assertEqual(self.launchctl_calls(), ["bootout", "bootstrap"])
        with open(self.plist) as f:
            self.assertIn(os.path.join(ROOT, "tools", "strike-backup.sh"), f.read())

    def test_main(self):
        r = run_zsh(SCRIPT, "main", self.env)
        self.assertIn(f"installed {LABEL}", r.stdout)
        r = run_zsh(SCRIPT, "main --remove", self.env)
        self.assertIn(f"removed {LABEL}", r.stdout)
        self.assertFalse(os.path.exists(self.plist))
