import QtQuick
import QtTest
import "../shell/Theme/matugen.js" as M

TestCase {
    name: "MatugenBuilder"
    function test_merge_order() {
        var cfg = M.buildConfig({
            shellTemplateDir: "/shell/tpl", stateDir: "/state", homeDir: "/home/u",
            userConfigText: "[config]\nreload_apps = true\n[templates.ghostty]\ninput_path = 'x'\n",
            dropInTexts: ["[templates.extra]\ninput_path = 'y'\n"]
        });
        var iCfg = cfg.indexOf("reload_apps");
        var iShell = cfg.indexOf("[templates.formalshell]");
        var iUser = cfg.indexOf("[templates.ghostty]");
        var iDrop = cfg.indexOf("[templates.extra]");
        verify(iCfg >= 0 && iShell >= 0 && iUser >= 0 && iDrop >= 0);
        verify(iCfg < iShell && iShell < iUser && iUser < iDrop);
        verify(cfg.indexOf("/state/theme.json.tmp") >= 0);
        verify(cfg.indexOf("/home/u/.config/gtk-3.0/formalshell-colors.css") >= 0);
        verify(cfg.indexOf("/home/u/.config/gtk-4.0/formalshell-colors.css") >= 0);
        verify(cfg.indexOf("/home/u/.config/qt5ct/colors/matugen.conf") >= 0);
        verify(cfg.indexOf("/home/u/.config/qt6ct/colors/matugen.conf") >= 0);
    }
    function test_no_user_config() {
        // matugen hard-rejects a config with no top-level [config] table, so
        // a fresh install (no ~/.config/matugen/config.toml) must still get
        // a bare one, ahead of the shell's own template blocks.
        var cfg = M.buildConfig({ shellTemplateDir: "/t", stateDir: "/s", homeDir: "/h", userConfigText: null, dropInTexts: [] });
        verify(cfg.indexOf("[config]") >= 0);
        verify(cfg.indexOf("[templates.formalshell]") >= 0);
        verify(cfg.indexOf("[config]") < cfg.indexOf("[templates.formalshell]"));
    }
    function test_extract_section() {
        var t = "[config]\na = 1\n[templates.x]\nb = 2\n";
        compare(M.extractSection(t, "config").indexOf("a = 1") >= 0, true);
        compare(M.extractSection(t, "templates").indexOf("b = 2") >= 0, true);
        compare(M.extractSection("", "config"), "");
    }

    // Verbatim stderr from `matugen -d image ... --dry-run` (matugen 4.1.0,
    // captured on g815 against dark/ARC - Towers.PNG), ANSI runs and all.
    readonly property string _probeStderr:
        "[2026-08-14T13:38:49.145998Z INFO  matugen::color::color] Opening image in dark/ARC - Towers.PNG\n" +
        "[2026-08-14T13:38:49.596348Z DEBUG matugen::color::color] Ranked colors:\n" +
        "[2026-08-14T13:38:49.596356Z DEBUG matugen::color::color] 0: #648db8 [37;48;2;100;141;184m  [0m\n" +
        "[2026-08-14T13:38:49.596357Z DEBUG matugen::color::color] 1: #908a61 [37;48;2;144;138;97m  [0m\n" +
        "[2026-08-14T13:38:49.596361Z DEBUG matugen::color::color] Multiple source colors found, attempting to pick a color by user preference \"Saturation\"\n" +
        "[2026-08-14T13:38:49.596362Z DEBUG matugen::color::color] Chose 1\n"

    function test_ranked_source_color() {
        compare(M.rankedSourceColor(_probeStderr), "#648db8");
    }

    function test_ranked_source_color_absent() {
        // No ranking to read means the caller falls back to a --prefer run,
        // so every one of these has to answer null rather than guess. The
        // last two are the ones a looser match would get wrong: a timestamp
        // carrying "0:", and a ranking that starts somewhere other than 0.
        compare(M.rankedSourceColor(""), null);
        compare(M.rankedSourceColor(null), null);
        compare(M.rankedSourceColor("Ranked colors:\n"), null);
        compare(M.rankedSourceColor("[2026-08-14T10:00:00.1Z INFO x] Opening image\n"), null);
        compare(M.rankedSourceColor("[x] Ranked colors:\n[x] 1: #908a61\n[x] 0: #648db8\n"), null);
    }
}
