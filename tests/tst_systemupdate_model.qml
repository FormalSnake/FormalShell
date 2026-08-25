import QtQuick
import QtTest
import "../shell/SystemUpdate/model.js" as SystemUpdate

TestCase {
    name: "SystemUpdateModel"

    // Node shapes lifted verbatim from this repo's own flake.lock, not
    // invented: a github node carries owner/repo/rev in `locked` and its
    // branch as `ref` in `original`; a git node carries url/ref/rev all in
    // `locked` and only url in `original`. `nixpkgs_2` is a transitive
    // input of quickshell and must never surface.
    readonly property string lockFixture: JSON.stringify({
        nodes: {
            root: { inputs: { nixpkgs: "nixpkgs", quickshell: "quickshell" } },
            nixpkgs: {
                locked: {
                    lastModified: 1785090369,
                    narHash: "sha256-m0pDuRJG7EDo9ri+4Ksu83VsI+PlxNC9lNBfydejce4=",
                    owner: "NixOS",
                    repo: "nixpkgs",
                    rev: "624af665418d3c65d544145b4d34ad696439570e",
                    type: "github"
                },
                original: { owner: "NixOS", ref: "nixos-unstable", repo: "nixpkgs", type: "github" }
            },
            quickshell: {
                inputs: { nixpkgs: "nixpkgs_2" },
                locked: {
                    lastModified: 1785134238,
                    narHash: "sha256-bv5gar+ZAXZCJH7UOv0eRFILKt5RKA/3px/XbVR98Cg=",
                    ref: "refs/heads/master",
                    rev: "43d4fa9e883cb03239b3d578c9c57070f4fbd281",
                    revCount: 834,
                    type: "git",
                    url: "https://git.outfoxxed.me/quickshell/quickshell"
                },
                original: { type: "git", url: "https://git.outfoxxed.me/quickshell/quickshell" }
            },
            nixpkgs_2: {
                locked: {
                    owner: "NixOS",
                    repo: "nixpkgs",
                    rev: "0000000000000000000000000000000000000000",
                    type: "github"
                },
                original: { owner: "NixOS", repo: "nixpkgs", type: "github" }
            }
        },
        root: "root",
        version: 7
    })

    readonly property string nixpkgsRev: "624af665418d3c65d544145b4d34ad696439570e"
    readonly property string quickshellRev: "43d4fa9e883cb03239b3d578c9c57070f4fbd281"
    readonly property string upstreamRev: "1111111111111111111111111111111111111111"

    function _input(name) {
        var parsed = SystemUpdate.parseLock(lockFixture);
        for (var i = 0; i < parsed.inputs.length; i++)
            if (parsed.inputs[i].name === name)
                return parsed.inputs[i];
        return null;
    }

    function test_parse_lock_reads_only_the_roots_direct_inputs() {
        var parsed = SystemUpdate.parseLock(lockFixture);
        compare(parsed.ok, true);
        compare(parsed.inputs.length, 2);
        compare(parsed.inputs[0].name, "nixpkgs");
        compare(parsed.inputs[1].name, "quickshell");
    }

    function test_parse_lock_github_node_shape() {
        var input = _input("nixpkgs");
        compare(input.type, "github");
        compare(input.owner, "NixOS");
        compare(input.repo, "nixpkgs");
        compare(input.ref, "nixos-unstable");
        compare(input.rev, nixpkgsRev);
        compare(input.lastModified, 1785090369);
    }

    function test_parse_lock_github_node_without_ref_leaves_ref_empty() {
        var fixture = JSON.stringify({
            root: "root",
            nodes: {
                root: { inputs: { home: "home" } },
                home: {
                    locked: { owner: "nix-community", repo: "home-manager", rev: nixpkgsRev, type: "github" },
                    original: { owner: "nix-community", repo: "home-manager", type: "github" }
                }
            }
        });
        var parsed = SystemUpdate.parseLock(fixture);
        compare(parsed.inputs[0].ref, "");
    }

    function test_parse_lock_git_node_shape() {
        var input = _input("quickshell");
        compare(input.type, "git");
        compare(input.url, "https://git.outfoxxed.me/quickshell/quickshell");
        compare(input.ref, "refs/heads/master");
        compare(input.rev, quickshellRev);
    }

    function test_parse_lock_malformed_text_is_ok_false_never_throws() {
        compare(SystemUpdate.parseLock("").ok, false);
        compare(SystemUpdate.parseLock("not json at all").ok, false);
        compare(SystemUpdate.parseLock(JSON.stringify({ version: 7 })).ok, false);
        compare(SystemUpdate.parseLock(JSON.stringify({ root: "root", nodes: {} })).ok, false);
        compare(SystemUpdate.parseLock("not json at all").inputs.length, 0);
    }

    function test_probe_command_github_uses_the_commits_api_with_the_sha_accept_header() {
        var probe = SystemUpdate.probeCommand(_input("nixpkgs"));
        compare(probe.kind, "github");
        compare(probe.argv[0], "curl");
        compare(probe.argv.indexOf("Accept: application/vnd.github.sha") !== -1, true);
        compare(probe.argv[probe.argv.length - 1],
                "https://api.github.com/repos/NixOS/nixpkgs/commits/nixos-unstable");
    }

    function test_probe_command_github_without_a_ref_asks_for_head() {
        var probe = SystemUpdate.probeCommand({ type: "github", owner: "nix-community", repo: "home-manager", ref: "" });
        compare(probe.argv[probe.argv.length - 1],
                "https://api.github.com/repos/nix-community/home-manager/commits/HEAD");
    }

    function test_probe_command_git_uses_ls_remote_with_the_locked_ref() {
        var probe = SystemUpdate.probeCommand(_input("quickshell"));
        compare(probe.kind, "git");
        compare(probe.argv[0], "sh");
        compare(probe.argv[2].indexOf("git ls-remote") !== -1, true);
        compare(probe.argv[2].indexOf("command -v git") !== -1, true);
        // url and ref ride as positional arguments, never interpolated into
        // the script, so nothing out of the lock file is parsed as shell.
        compare(probe.argv[probe.argv.length - 2], "https://git.outfoxxed.me/quickshell/quickshell");
        compare(probe.argv[probe.argv.length - 1], "refs/heads/master");
    }

    function test_probe_command_path_and_tarball_types_are_kind_none() {
        compare(SystemUpdate.probeCommand({ type: "path", url: "/etc/nixos" }).kind, "none");
        compare(SystemUpdate.probeCommand({ type: "tarball", url: "https://example.invalid/x.tar.gz" }).kind, "none");
        compare(SystemUpdate.probeCommand({ type: "indirect" }).kind, "none");
        compare(SystemUpdate.probeCommand({ type: "path" }).argv.length, 0);
    }

    function test_parse_probe_github_takes_the_bare_sha() {
        compare(SystemUpdate.parseProbe("github", 0, upstreamRev + "\n").rev, upstreamRev);
    }

    function test_parse_probe_git_takes_the_sha_before_the_tab() {
        var stdout = upstreamRev + "\trefs/heads/master\n";
        compare(SystemUpdate.parseProbe("git", 0, stdout).rev, upstreamRev);
    }

    function test_parse_probe_gitlab_takes_the_commit_id() {
        var stdout = JSON.stringify({ id: upstreamRev, short_id: "1111111" });
        compare(SystemUpdate.parseProbe("gitlab", 0, stdout).rev, upstreamRev);
    }

    function test_parse_probe_nonzero_exit_or_empty_stdout_is_empty_rev() {
        compare(SystemUpdate.parseProbe("github", 22, upstreamRev).rev, "");
        compare(SystemUpdate.parseProbe("git", 127, "").rev, "");
        compare(SystemUpdate.parseProbe("github", 0, "").rev, "");
        compare(SystemUpdate.parseProbe("github", 0, "API rate limit exceeded").rev, "");
        compare(SystemUpdate.parseProbe("none", 0, upstreamRev).rev, "");
    }

    function test_count_behind_counts_only_resolved_heads() {
        var inputs = SystemUpdate.parseLock(lockFixture).inputs;
        var heads = {};
        heads["nixpkgs"] = upstreamRev;
        heads["quickshell"] = quickshellRev;
        var counts = SystemUpdate.countBehind(inputs, heads);
        compare(counts.behind, 1);
        compare(counts.current, 1);
        compare(counts.unknown, 0);
        compare(counts.behindNames.length, 1);
        compare(counts.behindNames[0], "nixpkgs");
    }

    function test_count_behind_unresolved_head_is_unknown_never_current() {
        var inputs = SystemUpdate.parseLock(lockFixture).inputs;
        var heads = {};
        heads["nixpkgs"] = "";
        var counts = SystemUpdate.countBehind(inputs, heads);
        compare(counts.unknown, 2);
        compare(counts.current, 0);
        compare(counts.behind, 0);
    }

    function test_row_status_agrees_with_the_aggregate_count() {
        var heads = {};
        heads["nixpkgs"] = upstreamRev;
        heads["quickshell"] = quickshellRev;
        compare(SystemUpdate.rowStatus(_input("nixpkgs"), heads), "BEHIND");
        compare(SystemUpdate.rowStatus(_input("quickshell"), heads), "CURRENT");
        compare(SystemUpdate.rowStatus(_input("nixpkgs"), {}), "?");
    }

    function test_short_rev_is_the_first_seven_characters() {
        compare(SystemUpdate.shortRev(nixpkgsRev), "624af66");
        compare(SystemUpdate.shortRev(""), "");
    }

    function test_summary_label_never_says_up_to_date_while_unknown_is_nonzero() {
        compare(SystemUpdate.summaryLabel("ok", { behind: 0, current: 3, unknown: 2 }), "2 ?");
    }

    function test_summary_label_honest_states() {
        compare(SystemUpdate.summaryLabel("noflake", {}), "No flake");
        compare(SystemUpdate.summaryLabel("nolock", {}), "No lock");
        compare(SystemUpdate.summaryLabel("checking", {}), "Checking");
        compare(SystemUpdate.summaryLabel("offline", {}), "No network");
        compare(SystemUpdate.summaryLabel("ok", { behind: 0, current: 2, unknown: 0 }), "Up to date");
        compare(SystemUpdate.summaryLabel("ok", { behind: 2, current: 1, unknown: 0 }), "2 behind");
        compare(SystemUpdate.summaryLabel("ok", { behind: 2, current: 0, unknown: 1 }), "2 behind / 1 ?");
    }

    function test_summary_label_of_an_unrecognized_state_holds_at_checking() {
        compare(SystemUpdate.summaryLabel("", { behind: 0, current: 0, unknown: 0 }), "Checking");
        compare(SystemUpdate.summaryLabel("wat", { behind: 0, current: 9, unknown: 0 }), "Checking");
    }
}
