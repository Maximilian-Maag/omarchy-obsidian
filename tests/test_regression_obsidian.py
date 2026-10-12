"""Regression tests — one per real bug class this plugin is written against.

Each test fails if the fix is reverted, and names the bug it pins.
"""

import importlib.machinery
import importlib.util
import json
import os
import pathlib
import re
import subprocess
import sys
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parent.parent
CLI = ROOT / "bin/omarchy-obsidian"

_loader = importlib.machinery.SourceFileLoader("omarchy_obsidian_reg", str(CLI))
_spec = importlib.util.spec_from_loader("omarchy_obsidian_reg", _loader)
obs = importlib.util.module_from_spec(_spec)
try:
    _loader.exec_module(obs)
except SystemExit as exc:                       # pragma: no cover - guard
    raise ImportError("omarchy-obsidian exited at import time: %r" % (exc,))


class HookClobberRegression(unittest.TestCase):
    """BUG: `omarchy hook install <type> <file>` names the installed hook after the
    file's BASENAME, so a plugin shipping `hooks/theme-set` silently overwrites every
    other plugin's theme hook. The hook must carry a unique name and install under it.
    """

    def test_hook_file_is_uniquely_named(self):
        self.assertTrue((ROOT / "hooks" / "obsidian-theme-set").is_file())
        self.assertFalse((ROOT / "hooks" / "theme-set").exists())

    def test_install_script_installs_the_unique_hook_name(self):
        text = (ROOT / "install.sh").read_text()
        self.assertIn("hooks/obsidian-theme-set", text)


class HookSelfLocateRegression(unittest.TestCase):
    """BUG: an installed hook cannot find its plugin with
    $(dirname $BASH_SOURCE)/.. — that resolves to the hooks directory. The hook must
    self-locate, so it keeps working once copied into ~/.config/omarchy/hooks/.
    """

    def test_hook_does_not_derive_plugin_dir_from_bash_source(self):
        text = (ROOT / "hooks" / "obsidian-theme-set").read_text()
        self.assertNotIn("dirname", text)

    def test_hook_searches_the_override_and_installed_dirs(self):
        text = (ROOT / "hooks" / "obsidian-theme-set").read_text()
        self.assertIn("OMARCHY_OBSIDIAN_DIR", text)
        self.assertIn("omarchy/plugins/Maximilian-Maag.obsidian", text)

    def test_installed_hook_still_invokes_the_cli(self):
        # copy the hook somewhere that is NOT the plugin, then run it.
        with tempfile.TemporaryDirectory() as d:
            root = pathlib.Path(d)
            installed = root / "hooks" / "obsidian-theme-set"
            installed.parent.mkdir(parents=True)
            installed.write_text((ROOT / "hooks" / "obsidian-theme-set").read_text())

            fake = root / "plugin"
            (fake / "bin").mkdir(parents=True)
            marker = root / "marker"
            stub = fake / "bin" / "omarchy-obsidian"
            stub.write_text('#!/bin/bash\nprintf "%s\\n" "$*" >> "' + str(marker) + '"\n')
            stub.chmod(0o755)

            env = dict(os.environ)
            env["OMARCHY_OBSIDIAN_DIR"] = str(fake)
            env["HOME"] = str(root / "home")
            env["XDG_STATE_HOME"] = str(root / "state")
            subprocess.run(["bash", str(installed), "Hackerman"], env=env,
                           capture_output=True)
            self.assertTrue(marker.is_file())
            self.assertIn("--theme hackerman", marker.read_text())


class MomentFormatRegression(unittest.TestCase):
    """BUG: translating Obsidian's moment format by naive replacement mangles
    month names — replacing `MM` first turns `MMMM` into `%m%m` instead of `%B`.
    """

    def test_month_name_survives_translation(self):
        self.assertEqual(obs.moment_to_strftime("MMMM D, YYYY"), "%B %d, %Y")

    def test_short_month_and_month_number_both_correct(self):
        self.assertEqual(obs.moment_to_strftime("MMM"), "%b")
        self.assertEqual(obs.moment_to_strftime("MM"), "%m")


class SnippetSymlinkRegression(unittest.TestCase):
    """BUG: writing a generated file through a symlink overwrites the link TARGET
    (e.g. the plugin's own source). write_snippet must swap the link, not follow it.
    """

    def test_snippet_write_swaps_symlink_and_leaves_target(self):
        with tempfile.TemporaryDirectory() as d:
            target = pathlib.Path(d) / "plugin-source.css"
            target.write_text("SOURCE")
            link = pathlib.Path(d) / "snippet.css"
            link.symlink_to(target)
            obs.write_snippet(link, "GENERATED")
            self.assertFalse(link.is_symlink())
            self.assertEqual(target.read_text(), "SOURCE")


class NoBakedPaletteRegression(unittest.TestCase):
    """BUG class: baking a colour palette into the plugin. The theme command must read
    the applied theme's colors.toml at runtime, so the source must hold no hex colour.
    """

    def test_source_has_no_hardcoded_hex_colour(self):
        text = CLI.read_text()
        # allow the 6-digit-hex colour form only inside the docstring-free code paths;
        # a literal like "#82FB9C" anywhere is the bug.
        offenders = re.findall(r"#[0-9A-Fa-f]{6}\b", text)
        self.assertEqual(offenders, [])


class TodayNoCreateRegression(unittest.TestCase):
    """BUG: `today --no-create` still created the note (a flag documented but ignored).
    """

    def test_today_no_create_leaves_no_file(self):
        with tempfile.TemporaryDirectory() as d:
            root = pathlib.Path(d)
            vault = root / "vault"
            vault.mkdir()
            oj = root / "obsidian.json"
            oj.write_text(json.dumps({"vaults": {"x": {"path": str(vault), "open": True}}}))
            r = subprocess.run([sys.executable, str(CLI), "--obsidian-json", str(oj),
                                "--config", str(root / "cfg.json"),
                                "today", "--print", "--no-create"],
                               capture_output=True, text=True)
            self.assertEqual(r.returncode, 0, r.stderr)
            self.assertEqual(list(vault.iterdir()), [])   # nothing created


if __name__ == "__main__":
    unittest.main()
