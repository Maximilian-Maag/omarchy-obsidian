"""Unit tests for omarchy-obsidian's pure logic.

The shipped CLI has no ``.py`` extension (it is installed as ``omarchy-obsidian``),
so it is loaded with a SourceFileLoader rather than imported by name. A stray
``sys.exit`` at import time is re-raised as ImportError so a broken
``if __name__ == "__main__"`` guard can never make the test process pass silently.
"""

import datetime
import importlib.machinery
import importlib.util
import os
import pathlib
import sys
import tempfile
import unittest
import unittest.mock

ROOT = pathlib.Path(__file__).resolve().parent.parent
CLI = ROOT / "bin/omarchy-obsidian"

_loader = importlib.machinery.SourceFileLoader("omarchy_obsidian", str(CLI))
_spec = importlib.util.spec_from_loader("omarchy_obsidian", _loader)
obs = importlib.util.module_from_spec(_spec)
try:
    _loader.exec_module(obs)
except SystemExit as exc:                       # pragma: no cover - guard
    raise ImportError("omarchy-obsidian exited at import time: %r" % (exc,))


class HelperTests(unittest.TestCase):
    def test_expand_expands_user(self):
        self.assertEqual(obs.expand("~/x"), pathlib.Path(os.path.expanduser("~/x")))

    def test_read_json_missing_returns_default(self):
        self.assertEqual(obs.read_json(pathlib.Path("/no/such/file.json"), {"d": 1}), {"d": 1})

    def test_read_json_bad_json_returns_default(self):
        with tempfile.TemporaryDirectory() as d:
            p = pathlib.Path(d) / "x.json"
            p.write_text("{not json")
            self.assertIsNone(obs.read_json(p, None))

    def test_read_json_valid(self):
        with tempfile.TemporaryDirectory() as d:
            p = pathlib.Path(d) / "x.json"
            p.write_text('{"a": 2}')
            self.assertEqual(obs.read_json(p, {}), {"a": 2})

    def test_slug_theme_lowercases_and_hyphenates(self):
        self.assertEqual(obs.slug_theme("Tokyo Night"), "tokyo-night")

    def test_slug_theme_strips_surrounding_space(self):
        self.assertEqual(obs.slug_theme("  Hackerman "), "hackerman")


class VaultTests(unittest.TestCase):
    def _write(self, d, payload):
        p = pathlib.Path(d) / "obsidian.json"
        p.write_text(payload)
        return p

    def test_list_vaults_reads_ids_paths_open(self):
        with tempfile.TemporaryDirectory() as d:
            p = self._write(d, '{"vaults": {"a": {"path": "/v/a", "open": true},'
                               ' "b": {"path": "/v/b"}}}')
            vs = obs.list_vaults(p)
            self.assertEqual([v["id"] for v in vs], ["a", "b"])
            self.assertTrue(vs[0]["open"])
            self.assertFalse(vs[1]["open"])        # open defaults to False

    def test_list_vaults_missing_file_is_empty(self):
        self.assertEqual(obs.list_vaults(pathlib.Path("/no/such.json")), [])

    def test_list_vaults_malformed_vaults_key_is_empty(self):
        with tempfile.TemporaryDirectory() as d:
            self.assertEqual(obs.list_vaults(self._write(d, '{"vaults": []}')), [])

    def test_list_vaults_skips_non_dict_entries(self):
        with tempfile.TemporaryDirectory() as d:
            p = self._write(d, '{"vaults": {"a": 3, "b": {"path": "/v/b"}}}')
            self.assertEqual([v["id"] for v in obs.list_vaults(p)], ["b"])

    def test_select_vault_none_when_empty(self):
        self.assertIsNone(obs.select_vault([], None))

    def test_select_vault_prefers_open(self):
        vs = [{"id": "a", "path": "/v/a", "open": False},
              {"id": "b", "path": "/v/b", "open": True}]
        self.assertEqual(obs.select_vault(vs, None)["id"], "b")

    def test_select_vault_falls_back_to_first(self):
        vs = [{"id": "a", "path": "/v/a", "open": False},
              {"id": "b", "path": "/v/b", "open": False}]
        self.assertEqual(obs.select_vault(vs, None)["id"], "a")

    def test_select_vault_by_id_even_when_path_differs(self):
        vs = [{"id": "a", "path": "/v/a", "open": False},
              {"id": "b", "path": "/v/b", "open": True}]
        self.assertEqual(obs.select_vault(vs, "a")["id"], "a")

    def test_select_vault_by_folder_name(self):
        vs = [{"id": "a", "path": "/srv/me/Notes", "open": False}]
        self.assertEqual(obs.select_vault(vs, "Notes")["id"], "a")

    def test_select_vault_by_trailing_slash_path(self):
        vs = [{"id": "a", "path": "/v/a", "open": False}]
        self.assertEqual(obs.select_vault(vs, "/v/a/")["id"], "a")

    def test_select_vault_unknown_returns_none(self):
        vs = [{"id": "a", "path": "/v/a", "open": True}]
        self.assertIsNone(obs.select_vault(vs, "nope"))


class DailyTests(unittest.TestCase):
    def test_moment_to_strftime_iso(self):
        self.assertEqual(obs.moment_to_strftime("YYYY-MM-DD"), "%Y-%m-%d")

    def test_moment_to_strftime_month_name_not_split(self):
        # MMMM must not be mangled by the MM rule
        self.assertEqual(obs.moment_to_strftime("MMMM"), "%B")

    def test_moment_to_strftime_short_year(self):
        self.assertEqual(obs.moment_to_strftime("YY"), "%y")

    def test_daily_config_defaults_when_file_absent(self):
        with tempfile.TemporaryDirectory() as d:
            cfg = obs.daily_config(pathlib.Path(d))
            self.assertEqual(cfg["folder"], "")
            self.assertEqual(cfg["format"], "YYYY-MM-DD")

    def test_daily_config_reads_folder_and_format(self):
        with tempfile.TemporaryDirectory() as d:
            (pathlib.Path(d) / ".obsidian").mkdir()
            (pathlib.Path(d) / ".obsidian" / "daily-notes.json").write_text(
                '{"folder": "Journal", "format": "YYYY/MM/DD", "template": "T"}')
            cfg = obs.daily_config(pathlib.Path(d))
            self.assertEqual(cfg["folder"], "Journal")
            self.assertEqual(cfg["format"], "YYYY/MM/DD")
            self.assertEqual(cfg["template"], "T")

    def test_daily_config_empty_format_falls_back(self):
        with tempfile.TemporaryDirectory() as d:
            (pathlib.Path(d) / ".obsidian").mkdir()
            (pathlib.Path(d) / ".obsidian" / "daily-notes.json").write_text('{"format": ""}')
            self.assertEqual(obs.daily_config(pathlib.Path(d))["format"], "YYYY-MM-DD")

    def test_daily_note_path_root(self):
        vault = pathlib.Path("/v")
        cfg = {"folder": "", "format": "YYYY-MM-DD", "template": ""}
        self.assertEqual(obs.daily_note_path(vault, datetime.date(2026, 10, 12), cfg),
                         pathlib.Path("/v/2026-10-12.md"))

    def test_daily_note_path_with_folder(self):
        vault = pathlib.Path("/v")
        cfg = {"folder": "Journal", "format": "YYYY-MM-DD", "template": ""}
        self.assertEqual(obs.daily_note_path(vault, datetime.date(2026, 1, 2), cfg),
                         pathlib.Path("/v/Journal/2026-01-02.md"))

    def test_note_uri(self):
        uri = obs.note_uri(pathlib.Path("/v/My Vault"), pathlib.Path("/v/My Vault/2026-10-12.md"))
        self.assertIn("obsidian://open", uri)
        self.assertIn("My%20Vault", uri)
        self.assertIn("file=2026-10-12", uri)


class CaptureTests(unittest.TestCase):
    def test_append_creates_note_with_heading(self):
        with tempfile.TemporaryDirectory() as d:
            note = pathlib.Path(d) / "sub" / "2026-10-12.md"
            created = obs.append_capture(note, datetime.date(2026, 10, 12), "hello")
            self.assertTrue(created)
            self.assertEqual(note.read_text(), "# 2026-10-12\n\nhello\n")

    def test_append_to_existing_with_trailing_newline(self):
        with tempfile.TemporaryDirectory() as d:
            note = pathlib.Path(d) / "n.md"
            note.write_text("body\n")
            created = obs.append_capture(note, datetime.date(2026, 10, 12), "more")
            self.assertFalse(created)
            self.assertEqual(note.read_text(), "body\nmore\n")

    def test_append_to_existing_without_trailing_newline(self):
        with tempfile.TemporaryDirectory() as d:
            note = pathlib.Path(d) / "n.md"
            note.write_text("body")
            obs.append_capture(note, datetime.date(2026, 10, 12), "more")
            self.assertEqual(note.read_text(), "body\nmore\n")

    def test_append_to_empty_file_adds_no_leading_blank(self):
        with tempfile.TemporaryDirectory() as d:
            note = pathlib.Path(d) / "n.md"
            note.write_text("")
            obs.append_capture(note, datetime.date(2026, 10, 12), "x")
            self.assertEqual(note.read_text(), "x\n")


class ColorTests(unittest.TestCase):
    def test_parse_colors_reads_quoted_values(self):
        c = obs.parse_colors('accent = "#82FB9C"\nbackground = "#0B0C16"\n')
        self.assertEqual(c["accent"], "#82FB9C")
        self.assertEqual(c["background"], "#0B0C16")

    def test_parse_colors_skips_comments_and_blanks(self):
        # a comment line that itself contains "=" must still be skipped
        c = obs.parse_colors("# a comment = not a key\n\naccent = \"#111111\"\n")
        self.assertEqual(c, {"accent": "#111111"})

    def test_parse_colors_skips_empty_key(self):
        self.assertEqual(obs.parse_colors('= "#abc"\n'), {})

    def test_parse_colors_skips_empty_value(self):
        self.assertEqual(obs.parse_colors('accent =\n'), {})

    def test_pick_returns_first_present(self):
        self.assertEqual(obs.pick({"b": "2", "a": "1"}, "a", "b"), "1")

    def test_pick_falls_through_to_fallback(self):
        self.assertEqual(obs.pick({"b": "2"}, "a", "b"), "2")

    def test_pick_empty_when_none_present(self):
        self.assertEqual(obs.pick({}, "a", "b"), "")

    def test_render_snippet_uses_theme_values(self):
        colors = {"background": "#000001", "foreground": "#000002",
                  "accent": "#000003", "muted": "#000004", "red": "#000005",
                  "green": "#000006", "yellow": "#000007", "blue": "#000008",
                  "magenta": "#000009", "cyan": "#00000a", "selection": "#00000b"}
        css = obs.render_snippet(colors, "demo")
        self.assertIn("--background-primary: #000001;", css)
        self.assertIn("--text-normal: #000002;", css)
        self.assertIn("--interactive-accent: #000003;", css)
        self.assertIn("Applied theme: demo", css)

    def test_render_snippet_falls_back_to_sibling_keys(self):
        # no `background`/`foreground`/`selection` — the sibling keys must be used
        css = obs.render_snippet({"dark_background": "#0a0a0a",
                                  "bright_foreground": "#fafafa",
                                  "muted": "#222222", "accent": "#333333"}, "x")
        self.assertIn("--background-primary: #0a0a0a;", css)
        self.assertIn("--text-normal: #fafafa;", css)
        self.assertIn("--text-selection: #222222;", css)

    def test_snippet_path(self):
        self.assertEqual(obs.snippet_path(pathlib.Path("/v"), "omarchy-theme"),
                         pathlib.Path("/v/.obsidian/snippets/omarchy-theme.css"))

    def test_write_snippet_creates_nested_dirs(self):
        with tempfile.TemporaryDirectory() as d:
            path = pathlib.Path(d) / "a" / "b" / "s.css"
            obs.write_snippet(path, "body{}")
            self.assertEqual(path.read_text(), "body{}")

    def test_write_snippet_replaces_a_symlink_without_touching_target(self):
        with tempfile.TemporaryDirectory() as d:
            target = pathlib.Path(d) / "real.css"
            target.write_text("KEEP")
            link = pathlib.Path(d) / "link.css"
            link.symlink_to(target)
            obs.write_snippet(link, "NEW")
            self.assertEqual(link.read_text(), "NEW")
            self.assertEqual(target.read_text(), "KEEP")   # never written through


class OpenTests(unittest.TestCase):
    def test_open_uri_uses_explicit_opener(self):
        with unittest.mock.patch.object(obs.subprocess, "run") as run:
            run.return_value = unittest.mock.Mock(returncode=0)
            rc = obs.open_uri("obsidian://x", opener="/bin/echo")
            self.assertEqual(rc, 0)
            self.assertEqual(run.call_args[0][0], ["/bin/echo", "obsidian://x"])

    def test_open_uri_env_override(self):
        with unittest.mock.patch.object(obs.subprocess, "run") as run:
            run.return_value = unittest.mock.Mock(returncode=0)
            with unittest.mock.patch.dict(os.environ, {"OMARCHY_OBSIDIAN_OPENER": "/bin/true"}):
                obs.open_uri("obsidian://x")
            self.assertEqual(run.call_args[0][0][0], "/bin/true")

    def test_open_uri_defaults_to_xdg_open(self):
        with unittest.mock.patch.object(obs.subprocess, "run") as run:
            run.return_value = unittest.mock.Mock(returncode=0)
            with unittest.mock.patch.dict(os.environ, {}, clear=True):
                obs.open_uri("obsidian://x")
            self.assertEqual(run.call_args[0][0][0], "xdg-open")

    def test_open_uri_missing_program_returns_1(self):
        self.assertEqual(obs.open_uri("obsidian://x", opener="no-such-program-xyz"), 1)


class DateTests(unittest.TestCase):
    def test_parse_date_iso(self):
        self.assertEqual(obs._parse_date("2026-10-12"), datetime.date(2026, 10, 12))

    def test_parse_date_none_is_today(self):
        self.assertEqual(obs._parse_date(None), datetime.date.today())

    def test_parse_date_bad_raises(self):
        with self.assertRaises(SystemExit):
            obs._parse_date("12/10/2026")


class BindingsTests(unittest.TestCase):
    def test_bindings_text_reads_the_lua_module(self):
        text = obs.bindings_text()
        self.assertIn("o.bind", text)
        self.assertIn("omarchy-obsidian", text)

    def test_bindings_file_sits_next_to_the_cli(self):
        self.assertEqual(obs.bindings_file().parent, CLI.parent)


if __name__ == "__main__":
    unittest.main()
