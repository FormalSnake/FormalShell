//! herdr agent state for the Spaces badges. `herdr agent
//! list` is polled per client every two seconds, since herdr has no unscoped
//! change event; which client a window has is answered by a `ps` walk down
//! from the window's pid whenever the window list changes. No herdr, an
//! unreachable remote or a window with no client in its tree carries no
//! entry: nothing here makes a badge up.

use std::collections::{BTreeMap, HashMap};
use std::sync::OnceLock;
use std::time::{Duration, Instant};

use async_io::Timer;
use fs_info::herdr::{self, Client, PollLine, PsRow};
use futures_lite::io::BufReader;
use futures_lite::{AsyncBufReadExt, FutureExt, StreamExt};

use crate::runtime::Ctx;
use crate::store;

/// A `ps` walk per burst of window changes, not per window.
const DEBOUNCE: Duration = Duration::from_millis(400);
const BASE_BACKOFF: Duration = Duration::from_secs(2);
const MAX_BACKOFF: Duration = Duration::from_secs(60);

#[derive(Clone, Debug, PartialEq)]
pub struct Window {
    pub id: String,
    pub pid: i64,
    pub title: String,
}

/// Window id and client key to "working", "blocked" or "done"; a window with
/// nothing to report is absent, a key whose last list failed reads "".
#[derive(Clone, Debug, Default, PartialEq)]
pub struct State {
    pub by_window: BTreeMap<String, String>,
    pub by_key: BTreeMap<String, String>,
}

pub struct Diff(pub State);

impl State {
    pub fn apply(&mut self, Diff(next): Diff) -> bool {
        if *self == next {
            return false;
        }
        *self = next;
        true
    }

    /// The badge a window carries, "" for none.
    pub fn of(&self, window: &str) -> &str {
        self.by_window.get(window).map_or("", String::as_str)
    }
}

static WINDOWS: OnceLock<async_channel::Sender<Vec<Window>>> = OnceLock::new();

/// The windows the Spaces cell shows; called whenever they change.
pub fn windows(list: Vec<Window>) {
    if let Some(tx) = WINDOWS.get() {
        let _ = tx.try_send(list);
    }
}

enum Event {
    Windows(Vec<Window>),
    Walk,
    Line(String, String),
}

struct Poller {
    /// Dropping it closes the receiver the poll task races, which ends it.
    _stop: async_channel::Sender<()>,
}

#[derive(Default)]
struct Service {
    windows: Vec<Window>,
    keys_by_pid: BTreeMap<i64, Vec<String>>,
    titles_by_key: HashMap<String, Vec<String>>,
    hostname_by_key: HashMap<String, String>,
    labels_by_key: HashMap<String, Vec<String>>,
    state: State,
    pollers: HashMap<String, Poller>,
}

impl Service {
    fn recompute(&mut self, ctx: &Ctx) {
        let list: Vec<herdr::Window> =
            self.windows.iter().map(|w| herdr::Window { id: w.id.clone(), pid: w.pid, title: w.title.clone() }).collect();
        let keys = herdr::window_keys(&list, &self.keys_by_pid, &self.titles_by_key);
        let mut by_window = BTreeMap::new();
        for (id, key) in keys {
            if let Some(state) = self.state.by_key.get(&key).filter(|s| !s.is_empty()) {
                by_window.insert(id, state.clone());
            }
        }
        if by_window != self.state.by_window {
            self.state.by_window = by_window;
            self.publish(ctx);
        }
    }

    fn publish(&self, ctx: &Ctx) {
        ctx.publish(store::Diff::Herdr(Diff(self.state.clone())));
    }

    /// One poller per client key the walk found; a key no window resolves to
    /// any more loses its poller and its state.
    fn reconcile(&mut self, ctx: &Ctx, tx: &async_channel::Sender<Event>, clients: &BTreeMap<String, Client>) {
        let gone: Vec<String> = self.pollers.keys().filter(|k| !clients.contains_key(*k)).cloned().collect();
        for key in gone {
            self.pollers.remove(&key);
            self.state.by_key.remove(&key);
            self.hostname_by_key.remove(&key);
            self.labels_by_key.remove(&key);
            self.titles_by_key.remove(&key);
        }
        for (key, client) in clients {
            if self.pollers.contains_key(key) {
                continue;
            }
            let (stop, stopped) = async_channel::bounded::<()>(1);
            ctx.spawn(poll(key.clone(), herdr::poll_command(client), tx.clone(), stopped));
            self.pollers.insert(key.clone(), Poller { _stop: stop });
        }
    }

    fn line(&mut self, ctx: &Ctx, key: &str, line: &str) {
        if !self.pollers.contains_key(key) {
            return;
        }
        match herdr::parse_poll_line(Some(line)) {
            PollLine::Hostname(h) => {
                self.hostname_by_key.insert(key.to_owned(), h);
                self.retitle(ctx, key);
            }
            PollLine::Labels(l) => {
                self.labels_by_key.insert(key.to_owned(), l);
                self.retitle(ctx, key);
            }
            PollLine::Agents(agents) => {
                let state = agents.map_or("", |a| herdr::aggregate(&a).as_str());
                if self.state.by_key.get(key).map(String::as_str) == Some(state) {
                    return;
                }
                self.state.by_key.insert(key.to_owned(), state.to_owned());
                self.publish(ctx);
                self.recompute(ctx);
            }
        }
    }

    fn retitle(&mut self, ctx: &Ctx, key: &str) {
        let hostname = self.hostname_by_key.get(key).map_or("", String::as_str);
        let titles = herdr::default_titles(hostname, self.labels_by_key.get(key).map(Vec::as_slice));
        if self.titles_by_key.get(key).map_or(&[][..], Vec::as_slice) == titles.as_slice() {
            return;
        }
        self.titles_by_key.insert(key.to_owned(), titles);
        self.recompute(ctx);
    }
}

/// One client's poll loop, restarted on its backoff when the child exits:
/// the loop only ends by itself when herdr leaves PATH or the link dies.
async fn poll(key: String, argv: Vec<String>, tx: async_channel::Sender<Event>, stopped: async_channel::Receiver<()>) {
    let run = async {
        let mut backoff = BASE_BACKOFF;
        loop {
            let child = crate::services::proc::command(&argv[0])
                .args(&argv[1..])
                .stdin(async_process::Stdio::piped())
                .stdout(async_process::Stdio::piped())
                .stderr(async_process::Stdio::null())
                .kill_on_drop(true)
                .spawn();
            if let Ok(mut child) = child {
                // ssh and the poll loop read stdin; herdr's own clients
                // expect it held open until the child ends.
                let _stdin = child.stdin.take();
                if let Some(out) = child.stdout.take() {
                    let mut lines = BufReader::new(out).lines();
                    while let Some(Ok(line)) = lines.next().await {
                        backoff = BASE_BACKOFF;
                        if tx.send(Event::Line(key.clone(), line)).await.is_err() {
                            return;
                        }
                    }
                }
                let _ = child.status().await;
            }
            backoff = (backoff * 2).min(MAX_BACKOFF);
            Timer::after(backoff).await;
        }
    };
    let stop = async {
        let _ = stopped.recv().await;
    };
    run.or(stop).await;
}

fn walk_rows() -> Vec<PsRow> {
    let out = crate::services::proc::std_command("ps").args(["-eo", "pid=,ppid=,args="]).output();
    match out {
        Ok(o) if o.status.success() => herdr::parse_ps_rows(Some(&String::from_utf8_lossy(&o.stdout))),
        _ => Vec::new(),
    }
}

pub async fn run(ctx: Ctx) {
    let (wtx, wrx) = async_channel::unbounded();
    let _ = WINDOWS.set(wtx);
    let (tx, rx) = async_channel::unbounded::<Event>();
    // Window lists and poll lines meet in one queue, so one task owns the state.
    let forward = tx.clone();
    ctx.spawn(async move {
        while let Ok(list) = wrx.recv().await {
            if forward.send(Event::Windows(list)).await.is_err() {
                return;
            }
        }
    });

    let mut service = Service::default();
    let mut walk_at: Option<Instant> = None;
    loop {
        let event = match walk_at {
            Some(at) => {
                let next = async { rx.recv().await.ok() };
                let due = async {
                    Timer::at(at).await;
                    Some(Event::Walk)
                };
                next.or(due).await
            }
            None => rx.recv().await.ok(),
        };
        let Some(event) = event else { return };
        match event {
            Event::Windows(list) => {
                if list == service.windows {
                    continue;
                }
                service.windows = list;
                service.recompute(&ctx);
                walk_at = Some(Instant::now() + DEBOUNCE);
            }
            Event::Walk => {
                walk_at = None;
                let pids: Vec<f64> = service.windows.iter().map(|w| w.pid as f64).collect();
                let Some(rows) = ctx.pool().run(walk_rows).await else { continue };
                let found = herdr::clients_by_window(&rows, &pids);
                service.keys_by_pid = found.by_window;
                service.reconcile(&ctx, &tx, &found.clients);
                service.recompute(&ctx);
                service.publish(&ctx);
            }
            Event::Line(key, line) => service.line(&ctx, &key, &line),
        }
    }
}
