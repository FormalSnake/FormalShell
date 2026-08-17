# CLAUDE-troubleshooting.md

Proven issues and fixes for FormalShell. Not committed (repo rule) —
local reference only.

## Canvas putImageData silently fails under Wayland/Quickshell (2026-08-09)

`Context2D.putImageData()` composites nothing when run under the real
`qs` binary in a Wayland session (probe-verified in the VM during M20
Task 3: canvas kept showing the raw un-dithered source, no error). The
offscreen qmltestrunner path can behave differently, so tests alone
won't catch it. Working write path: per-pixel/per-run `ctx.fillRect`,
the idiom `DitherFill.qml`, `DogEar.qml`, and `DitherImage.qml` all use.
`ctx.drawImage(<Image item>, …)` and `getImageData` both work fine —
only the putImageData write-back is broken. When building any new
Canvas-based pixel effect, probe with a real nested-session run
(throwaway Quickshell config + `qs` in the smoke rig), not just
qmltestrunner.

## Canvas cannot read image://qspixmap sources (2026-08-09)

`Canvas.drawImage()` reads only transparent black from Quickshell's
`image://qspixmap/…` provider (SNI tray icons delivered as IconPixmap
bytes — Discord/Steam-style, and `dev/sni-stub.py`), even though the
`Image` reports `Ready` with correct painted size. Probe-verified in
M20 Task 5. Workaround (same as `AnimatedAlbumArt.qml` uses for Video):
render through a normal invisible `IconImage`, hand the Canvas a
`grabToImage()` result url instead of the raw source.

## Repeater on a .values-derived array churns delegates (2026-08-09)

Quickshell re-notifies `SystemTray.items.values` far more often than the
item set changes; a `Repeater` bound to a plain-array slice of it treats
every notification as a full model reset (measured: each delegate
destroyed/recreated 4-7 times with a static 6-item tray, killing any
Canvas state before it painted). Bind the `Repeater` to the live
`ObjectModel` (`SystemTray.items`) for real add/remove diffing and do
cutoffs per-delegate via `index`, never by slicing the model array.

## Canvas first paint can sample a blank Image (2026-08-09)

`Canvas.drawImage(<Image item>)` can land in the async decode gap even
with `Image.status === Ready`: the first `getImageData` read returns an
all-zero buffer. Duotone/mask modes failed silently-plausibly (all-dark
or all-transparent); retro mode made it visible (solid black cover in
the `--visualizer` smoke). Fix shipped in `DitherImage.qml` and
`ArtPalette.qml` (M20 Task 5b): treat an all-zero buffer as not-ready
and self-retry bounded (20 x 16ms) before publishing a paint. Any new
Canvas-reads-Image component needs the same guard. Note: genuinely
transparent PNGs carry nonzero RGB bytes at alpha 0, so all-zero is a
safe not-ready signal.

## AppleMusicArtService cannot be exercised in the VM (2026-08-09)

`animatedArtUrl` only populates via live `music.apple.com`/iTunes
lookups; the isolated test VM has no network, so the animated-art path
never triggers for smoke fixture tracks regardless of shell code. The
grab-timer dither path (`AnimatedAlbumArt.qml`) was proven with a real
generated test video through `Video.grabToImage` instead. Verifying the
real Apple Music flow needs a networked host session.
