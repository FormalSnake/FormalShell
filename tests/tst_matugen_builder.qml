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
}
