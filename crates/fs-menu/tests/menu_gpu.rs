// The gpu/gpu.mode routes and the offload action Shift+Enter runs on an app
// row. The card records are the ones the GPU service builds for the hybrid
// fixture (tests/fixtures/gpu-hybrid.txt): an NVIDIA RTX 5070 with HDMI-A-1
// connected and an Intel iGPU with eDP-1. The fixture parser itself belongs to
// the monitor crate.

use fs_menu::node::Kind;
use fs_menu::providers::{GpuCard, GpuOutput, gpu_launch_action, gpu_mode_entry, gpu_provider};

fn output(name: &str, connected: bool) -> GpuOutput {
    GpuOutput { name: name.into(), connected }
}

fn hybrid_cards() -> Vec<GpuCard> {
    vec![
        GpuCard {
            card: "card0".into(),
            name: "NVIDIA GeForce RTX 5070 Laptop GPU".into(),
            discrete: true,
            driver: "nvidia".into(),
            outputs: vec![output("DP-3", false), output("eDP-2", false), output("HDMI-A-1", true)],
        },
        GpuCard {
            card: "card1".into(),
            name: "Intel Graphics".into(),
            discrete: false,
            driver: "i915".into(),
            outputs: vec![output("DP-1", false), output("DP-2", false), output("eDP-1", true)],
        },
    ]
}

#[test]
fn gpu_provider_one_note_row_per_card() {
    let rows = gpu_provider(&hybrid_cards());
    assert_eq!(rows.len(), 2);
    assert_eq!(rows[0].id, "gpu.card.card0");
    assert_eq!(rows[0].kind, Kind::Note);
    assert_eq!(rows[0].label, "NVIDIA GeForce RTX 5070 Laptop GPU");
    let desc = rows[0].desc.as_deref().unwrap();
    assert!(desc.contains("Discrete"));
    assert!(desc.contains("nvidia"));
    assert!(desc.contains("HDMI-A-1"));
    assert_eq!(rows[1].id, "gpu.card.card1");
    let desc = rows[1].desc.as_deref().unwrap();
    assert!(desc.contains("Integrated"));
    assert!(desc.contains("eDP-1"));
}

#[test]
fn gpu_provider_no_cards_yields_honest_no_gpu_row() {
    let rows = gpu_provider(&[]);
    assert_eq!(rows.len(), 1);
    assert_eq!(rows[0].id, "gpu.empty");
    assert_eq!(rows[0].kind, Kind::Note);
    assert_eq!(rows[0].dim, Some(true));
    assert_eq!(rows[0].label, "No GPU");
}

// There is no "gpu.launch" route to test: the app list mirrored under it
// doubled every app in a root search, and the accelerator below is the whole
// of the feature now.
#[test]
fn gpu_launch_action_targets_the_discrete_card() {
    let cards = hybrid_cards();
    let card = cards.iter().find(|c| c.discrete).expect("a discrete card");
    assert_eq!(card.card, "card0");
    assert_eq!(
        gpu_launch_action("formalshell-ipc", "firefox", &card.card),
        "formalshell-ipc call monitor launch 'firefox' 'card0'"
    );
}

// A desktop id carrying a single quote must not break the sh -c string it
// lands in: the same close/escape/reopen the compositor backend's quoting and
// the tray rows already rely on.
#[test]
fn gpu_launch_action_shell_quotes_a_tricky_desktop_id() {
    assert_eq!(
        gpu_launch_action("formalshell-ipc", "it's-an-app", "card0"),
        "formalshell-ipc call monitor launch 'it'\\''s-an-app' 'card0'"
    );
}

#[test]
fn gpu_mode_entry_absent_when_unsupported() {
    assert_eq!(gpu_mode_entry("formalshell-ipc", false).len(), 0);
}

#[test]
fn gpu_mode_entry_present_and_shell_quoted_when_supported() {
    let entries = gpu_mode_entry("formalshell-ipc", true);
    assert!(entries.contains_key("gpu.mode"));
    assert_eq!(
        entries["gpu.mode.integrated"].action.as_deref(),
        Some("formalshell-ipc call monitor mode integrated")
    );
    assert_eq!(
        entries["gpu.mode.hybrid"].action.as_deref(),
        Some("formalshell-ipc call monitor mode hybrid")
    );
}
