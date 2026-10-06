//! Each surface reads its slices of the store; [`changed`] routes a store
//! change to the surfaces that read that slice.

pub mod bar;
pub mod panel;
pub mod shoulders;

use fs_chrome::bar::layout;
use fs_chrome::bar::workspaces::{self, SlotOpts};

use crate::services::hyprland::{Window, Workspace};
use crate::store::Topic;
use crate::theme;
use crate::wayland::App;

pub fn changed(app: &mut App, topic: Topic) {
    match topic {
        Topic::Clock => app.bar.set_clock(&app.store.clock.text),
        Topic::Config => {
            let config = &app.store.config;
            let edge = layout::position(config.str("bar.position"));
            app.bar.motion_enabled = config.bool("motion.enabled").unwrap_or(true);
            app.set_bar_edge(edge);
            bar_workspaces(app);
        }
        Topic::State => {}
        Topic::Hyprland => bar_workspaces(app),
    }
}

/// Workspaces.qml's model: the backend's rows through `Bar/workspaces.js`.
fn bar_workspaces(app: &mut App) {
    let persistent = app.store.config.f64("workspaces.persistent").map_or(theme::PERSISTENT_WORKSPACES, |n| n as i64);
    let c = &app.store.hyprland.compositor;
    let rows: Vec<workspaces::Workspace> = c.workspaces.iter().map(workspace).collect();
    let windows: Vec<workspaces::Window> = c.windows.iter().map(window).collect();
    let output = app.bar_output_name();
    let slots = workspaces::slots(&rows, &windows, &output, SlotOpts { persistent, ..SlotOpts::default() });
    app.bar.set_workspaces(&slots);
}

fn workspace(w: &Workspace) -> workspaces::Workspace {
    workspaces::Workspace {
        id: w.id.clone(),
        idx: w.idx,
        name: w.name.clone(),
        output: w.output.clone(),
        is_active: w.is_active,
        is_focused: w.is_focused,
        is_urgent: w.is_urgent,
        placeholder: false,
    }
}

fn window(w: &Window) -> workspaces::Window {
    workspaces::Window {
        id: w.id.clone(),
        workspace_id: w.workspace_id.clone(),
        app_id: w.app_id.clone(),
        initial_class: w.initial_class.clone(),
        initial_title: w.initial_title.clone(),
        pid: w.pid,
        is_focused: w.is_focused,
        is_urgent: w.is_urgent,
        is_floating: w.is_floating,
        rect: w.rect.map(|r| fs_chrome::types::Rect {
            x: r.x as f64,
            y: r.y as f64,
            width: r.width as f64,
            height: r.height as f64,
        }),
    }
}
