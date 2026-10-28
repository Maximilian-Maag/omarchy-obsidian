"""Integration tests — the shipped CLI driven as a subprocess against a synthetic
vault (never the user's real vault). No GUI is launched.
"""

import json
import os
import pathlib
import subprocess
import sys
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parent.parent
CLI = ROOT / "bin/omarchy-obsidian"

COLORS = 'background = "#0B0C16"\nforeground = "#ddf7ff"\nselection = "#1f253a"\n' \
         'muted = "#2d3450"\naccent = "#82FB9C"\nred = "#50f872"\ngreen = "#4fe88f"\n' \
         'yellow = "#50f7d4"\nblue = "#829dd4"\nmagenta = "#86a7df"\ncyan = "#7cf8f7"\n'


class CliIntegration(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = pathlib.Path(self.tmp.name)
        self.vault = self.root / "vault"
        (self.vault / ".obsidian").mkdir(parents=True)
        self.oj = self.root / "obsidian.json"
        self.oj.write_text(json.dumps({"vaults": {
            "aaaa": {"path": str(self.vault), "open": True}}}))
        self.cfg = self.root / "config.json"
        self.colors = self.root / "colors.toml"
        self.colors.write_text(COLORS)
        # A safe opener in the environment, so NO test can ever launch the real
        # xdg-open (which would block on a live desktop).
        self._old_opener = os.environ.get("OMARCHY_OBSIDIAN_OPENER")
        safe = self.root / "safe-opener.sh"
        safe.write_text("#!/bin/bash\nexit 0\n")
        safe.chmod(0o755)
        os.environ["OMARCHY_OBSIDIAN_OPENER"] = str(safe)
        self.addCleanup(self._restore_opener)

    def _restore_opener(self):
        if self._old_opener is None:
            os.environ.pop("OMARCHY_OBSIDIAN_OPENER", None)
        else:
            os.environ["OMARCHY_OBSIDIAN_OPENER"] = self._old_opener

    def run_cli(self, *args):
        cmd = [sys.executable, str(CLI), "--obsidian-json", str(self.oj),
               "--config", str(self.cfg), *args]
        return subprocess.run(cmd, capture_output=True, text=True)

    def test_vault_json_lists_the_fixture(self):
        r = self.run_cli("vault", "--json")
        self.assertEqual(r.returncode, 0, r.stderr)
        data = json.loads(r.stdout)
        self.assertEqual(len(data), 1)
        self.assertEqual(data[0]["id"], "aaaa")
        self.assertTrue(data[0]["open"])
        # pin the two-space indent (a formatting contract, not just valid JSON)
        self.assertIn('\n  {\n    "id": "aaaa"', r.stdout)

    def test_vault_plain_marks_the_open_one(self):
        r = self.run_cli("vault")
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertIn("* aaaa", r.stdout)

    def test_vault_empty_is_a_clean_success(self):
        self.oj.write_text('{"vaults": {}}')
        r = self.run_cli("vault")
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertIn("no vaults recorded", r.stdout)
        self.assertEqual(json.loads(self.run_cli("vault", "--json").stdout), [])

    def test_capture_creates_today_note(self):
        r = self.run_cli("capture", "--date", "2026-10-12", "first thought")
        self.assertEqual(r.returncode, 0, r.stderr)
        note = self.vault / "2026-10-12.md"
        self.assertEqual(note.read_text(), "# 2026-10-12\n\nfirst thought\n")
        self.assertIn("created", r.stdout)

    def test_capture_appends_second_time(self):
        self.run_cli("capture", "--date", "2026-10-12", "one")
        r = self.run_cli("capture", "--date", "2026-10-12", "two")
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertIn("appended", r.stdout)
        self.assertEqual((self.vault / "2026-10-12.md").read_text(),
                         "# 2026-10-12\n\none\ntwo\n")

    def test_capture_json_reports_created(self):
        r = self.run_cli("capture", "--date", "2026-10-12", "--json", "x")
        data = json.loads(r.stdout)
        self.assertTrue(data["created"])
        self.assertTrue(data["path"].endswith("2026-10-12.md"))

    def test_capture_honours_nested_vault_daily_folder(self):
        # a nested folder forces mkdir(parents=True) to build an intermediate dir
        (self.vault / ".obsidian" / "daily-notes.json").write_text(
            '{"folder": "Journal/2026"}')
        r = self.run_cli("capture", "--date", "2026-10-12", "x")
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertTrue((self.vault / "Journal" / "2026" / "2026-10-12.md").is_file())

    def test_capture_empty_text_errors(self):
        r = self.run_cli("capture", "--date", "2026-10-12", "")
        self.assertEqual(r.returncode, 1)
        self.assertIn("nothing to capture", r.stderr)

    def test_today_print_returns_uri(self):
        r = self.run_cli("today", "--date", "2026-10-12", "--print")
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertIn("obsidian://open", r.stdout)
        self.assertIn("file=2026-10-12", r.stdout)

    def test_today_creates_note_by_default(self):
        self.run_cli("today", "--date", "2026-10-12", "--print")
        self.assertTrue((self.vault / "2026-10-12.md").is_file())

    def test_today_creates_nested_daily_folder(self):
        (self.vault / ".obsidian" / "daily-notes.json").write_text(
            '{"folder": "Journal/2026"}')
        r = self.run_cli("today", "--date", "2026-10-12", "--print")
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertTrue((self.vault / "Journal" / "2026" / "2026-10-12.md").is_file())

    def test_today_opener_is_invoked(self):
        rec = self.root / "opened.txt"
        opener = self.root / "opener.sh"
        opener.write_text(f'#!/bin/bash\nprintf "%s\\n" "$1" > "{rec}"\n')
        opener.chmod(0o755)
        r = self.run_cli("today", "--date", "2026-10-12", "--opener", str(opener))
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertIn("obsidian://open", rec.read_text())

    def test_theme_writes_snippet_into_the_vault(self):
        r = self.run_cli("theme", "--colors", str(self.colors), "--theme", "Tokyo Night")
        self.assertEqual(r.returncode, 0, r.stderr)
        snippet = self.vault / ".obsidian" / "snippets" / "omarchy-theme.css"
        self.assertTrue(snippet.is_file())
        css = snippet.read_text()
        self.assertIn("--background-primary: #0B0C16;", css)
        self.assertIn("--interactive-accent: #82FB9C;", css)
        self.assertIn("Applied theme: tokyo-night", css)

    def test_theme_names_the_recorded_applied_theme(self):
        state = self.root / "state" / "omarchy-obsidian"
        state.mkdir(parents=True)
        (state / "active-theme").write_text("tokyo-night\n")
        env = dict(os.environ, XDG_STATE_HOME=str(self.root / "state"))
        r = subprocess.run(
            [sys.executable, str(CLI), "--obsidian-json", str(self.oj),
             "--config", str(self.cfg), "theme", "--colors", str(self.colors), "--print"],
            capture_output=True, text=True, env=env)
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertIn("Applied theme: tokyo-night", r.stdout)

    def test_theme_never_reports_the_directory_name(self):
        # The applied theme dir is literally "theme"; the header must never echo it.
        env = dict(os.environ, XDG_STATE_HOME=str(self.root / "empty-state"))
        r = subprocess.run(
            [sys.executable, str(CLI), "--obsidian-json", str(self.oj),
             "--config", str(self.cfg), "theme", "--colors", str(self.colors), "--print"],
            capture_output=True, text=True, env=env)
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertNotIn("Applied theme: theme", r.stdout)

    def test_theme_print_does_not_write(self):
        r = self.run_cli("theme", "--colors", str(self.colors), "--print")
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertIn("--text-normal:", r.stdout)
        self.assertFalse((self.vault / ".obsidian" / "snippets").exists())

    def test_theme_snippet_name_from_config(self):
        self.cfg.write_text('{"snippet": "my-theme"}')
        self.run_cli("theme", "--colors", str(self.colors))
        self.assertTrue((self.vault / ".obsidian" / "snippets" / "my-theme.css").is_file())

    def test_theme_missing_colors_errors(self):
        r = self.run_cli("theme", "--colors", str(self.root / "nope.toml"))
        self.assertEqual(r.returncode, 1)
        self.assertIn("no applied theme", r.stderr)

    def test_theme_empty_colors_errors(self):
        empty = self.root / "empty.toml"
        empty.write_text("# nothing here\n")
        r = self.run_cli("theme", "--colors", str(empty))
        self.assertEqual(r.returncode, 1)
        self.assertIn("no colours", r.stderr)

    def test_vault_override_path(self):
        other = self.root / "other"
        other.mkdir()
        r = self.run_cli("--vault-path", str(other), "capture", "--date", "2026-10-12", "x")
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertTrue((other / "2026-10-12.md").is_file())

    def test_no_vaults_errors(self):
        self.oj.write_text('{"vaults": {}}')
        r = self.run_cli("capture", "x")
        self.assertEqual(r.returncode, 1)
        self.assertIn("no vaults found", r.stderr)

    def test_unknown_vault_errors(self):
        r = self.run_cli("--vault", "nope", "capture", "x")
        self.assertEqual(r.returncode, 1)
        self.assertIn("no vault matches", r.stderr)

    def test_bindings_prints_lua(self):
        r = self.run_cli("bindings")
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertIn("o.bind", r.stdout)
        self.assertIn("SUPER + ALT + N", r.stdout)


if __name__ == "__main__":
    unittest.main()
