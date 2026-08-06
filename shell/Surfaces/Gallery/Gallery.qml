import QtQuick
import Quickshell
import qs.Core
import qs.Components

// The dev gallery (reference: omarchy's own shell/plugins/dev-gallery/
// GalleryPanel.qml, read per CLAUDE.md's read-reference rule — the ledger
// layout below is this shell's own language, nothing is ported). Summoned
// only by `qs ipc call gallery show|toggle`: no bar cell opens it, no
// `bar.layout` entry names it, and it is deliberately absent from
// PanelIpc's registry, so it can never appear unless someone asks for it
// by name.
//
// Maintenance discipline, adopted verbatim from that file's header: every
// section here renders the REAL component (not a copy) so the gallery
// doubles as a smoke test. When you add a new shared component, add a
// section here. This file may ONLY use imported common components, never
// inline reimplementations of them.
//
// Being a real Panel is what makes "PANEL / THIS SURFACE" below a specimen
// rather than a claim: the frame rules, the title meta row, the content
// gutter and its edge erasers, the enter/exit fade, Escape and
// click-outside, and the DismissTwins catchers the SURFACES section counts
// are all this surface's own, straight out of Panel.qml. ImagePicker.qml
// takes the same route for the same reason.
//
// The one component this surface cannot paint is Tooltip: Tooltip.qml
// hides itself for as long as `PanelRegistry.current` is non-null (its own
// `_visible`), and opening this Panel is exactly what sets that. So the
// TOOLTIP row carries a real `tooltipText` — hovering it drives the real
// component through Cell.qml's own lazy Loader — and the row under it says
// plainly that it will not show here, instead of standing a lookalike card
// in its place.
Panel {
    id: root

    panelTitle: "DEV GALLERY"

    // Nearly the whole output: fitting every specimen into one screenshot
    // is the entire point of the surface. Panel caps its content at 60% of
    // the screen height, so the sheet below spends that budget across
    // columns rather than on one long scroll.
    panelWidth: root.screen
        ? Math.round(root.screen.width - Theme.space.panelGap * 2)
        : 960

    // Nothing below exists until the surface is actually summoned — the
    // same `active:`-gated Loader MediaPanel.qml uses for its animated-art
    // overlay. A session that never calls `gallery show` pays for one
    // inactive Loader and not a single specimen, which matters here more
    // than anywhere else: the sheet holds a live marquee animation and an
    // AuthPrompt.
    Loader {
        id: sheetLoader
        width: parent.width
        active: root.isOpen
        sourceComponent: sheet
    }

    Component {
        id: sheet

        Column {
            id: sheetColumn
            width: sheetLoader.width

            Row {
                id: topRow
                width: sheetColumn.width

                // AuthPrompt sizes itself off the type-scale root and is by
                // far the tallest and widest specimen here, so it takes the
                // width it needs and the token columns share what is left.
                readonly property real _flex: Math.max(0, (topRow.width - authColumn.width) / 3)

                Column {
                    id: authColumn
                    width: authCell.implicitWidth

                    Cell {
                        width: parent.width

                        MetaLabel { text: "AUTHPROMPT / IDLE" }
                    }

                    // inputEnabled: false is the component's own way of
                    // standing down, not a gallery-only hack: the panel's
                    // backdrop owns keyboard focus (Panel.qml's focus
                    // prime), and a live TextInput here would take it and
                    // leave Escape dead. Everything else — the display
                    // clock, the date meta row, the dividing rule, the 3px
                    // field outline, the centred placeholder — is the
                    // surface the lock screen and the greeter both render.
                    Cell {
                        id: authCell

                        AuthPrompt { inputEnabled: false }
                    }
                }

                Column {
                    id: cellColumn
                    width: topRow._flex

                    Cell {
                        width: parent.width

                        MetaLabel { text: "CELL" }
                    }

                    Repeater {
                        // One row per flag combination Cell.qml actually
                        // renders differently, driven as data rather than
                        // seven hand-written delegates. `standalone` plus
                        // `hovered` earns its own row because it is not the
                        // sum of the two above it: that pair is the bar's
                        // full fg/bg inversion (DESIGN.md §1.1 amendment),
                        // not the low-alpha tint every other cell hovers
                        // with.
                        model: [
                            { label: "NORMAL",           selected: false, accent: false, urgent: false, hovered: false, standalone: false },
                            { label: "HOVERED",          selected: false, accent: false, urgent: false, hovered: true,  standalone: false },
                            { label: "SELECTED",         selected: true,  accent: false, urgent: false, hovered: false, standalone: false },
                            { label: "ACCENT",           selected: false, accent: true,  urgent: false, hovered: false, standalone: false },
                            { label: "URGENT",           selected: false, accent: false, urgent: true,  hovered: false, standalone: false },
                            { label: "STANDALONE",       selected: false, accent: false, urgent: false, hovered: false, standalone: true  },
                            { label: "STANDALONE HOVER", selected: false, accent: false, urgent: false, hovered: true,  standalone: true  }
                        ]

                        delegate: Cell {
                            id: stateCell
                            required property var modelData

                            width: cellColumn.width
                            selected: stateCell.modelData.selected
                            accent: stateCell.modelData.accent
                            urgent: stateCell.modelData.urgent
                            hovered: stateCell.modelData.hovered
                            standalone: stateCell.modelData.standalone

                            MetaLabel {
                                text: stateCell.modelData.label
                                color: stateCell.foreground
                            }
                        }
                    }

                    // The honest-unavailable state every surface in the
                    // shell falls back to (NO ADAPTER, NO DEVICES, NO
                    // LOCATION): a plain cell whose label keeps MetaLabel's
                    // own foregroundDim, not a Cell flag of its own.
                    Cell {
                        width: parent.width

                        MetaLabel { text: "DIM / UNAVAILABLE" }
                    }
                }

                Column {
                    id: typeColumn
                    width: topRow._flex

                    Cell {
                        width: parent.width

                        MetaLabel { text: "TYPE SCALE" }
                    }

                    Repeater {
                        // Read off the live token object rather than
                        // restated, so a new step in tokens.js's
                        // FONT_MULTIPLIERS appears here with no edit.
                        // `baseSize` is the rem root Theme.qml stores
                        // alongside the steps (Tokens.fontTokens), not a
                        // step of its own.
                        model: Object.keys(Theme.fontSize).filter(function (key) { return key !== "baseSize"; })

                        delegate: Cell {
                            id: typeCell
                            required property string modelData

                            width: typeColumn.width

                            Row {
                                spacing: Theme.space.md

                                MetaLabel {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: typeCell.modelData + " " + Theme.fontSize[typeCell.modelData]
                                }

                                Text {
                                    text: "Aa"
                                    color: typeCell.foreground
                                    font.family: Theme.font.family
                                    font.pixelSize: Theme.fontSize[typeCell.modelData]
                                }
                            }
                        }
                    }
                }

                Column {
                    id: tokenColumn
                    width: topRow._flex

                    Cell {
                        width: parent.width

                        MetaLabel { text: "COLOR TOKENS" }
                    }

                    Repeater {
                        // palette.js's COLOR_KEYS, taken off the live
                        // palette so a matugen run drifting one role away
                        // from the rest is visible here as a swatch, not
                        // just as a surface that looks slightly wrong.
                        // `mode` is the theme's light/dark tag, not a role.
                        model: Object.keys(Theme.color).filter(function (key) { return key !== "mode"; })

                        delegate: Cell {
                            id: swatchCell
                            required property string modelData

                            width: tokenColumn.width

                            Row {
                                spacing: Theme.space.md

                                // The one thing a Cell cannot be: a fill
                                // picked by palette role rather than by
                                // interactive state. Bordered in `rule` so
                                // `background` still reads as a swatch
                                // against the panel's own fill.
                                Rectangle {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: Theme.space.huge + Theme.space.xl
                                    height: Theme.fontSize.caption + Theme.space.sm
                                    radius: Theme.radius
                                    color: Theme.color[swatchCell.modelData]
                                    border.width: Theme.borderWidth
                                    border.color: Theme.color.rule
                                }

                                MetaLabel {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: swatchCell.modelData + " " + Theme.color[swatchCell.modelData]
                                }
                            }
                        }
                    }

                    Cell {
                        width: parent.width

                        MetaLabel { text: "METALABEL" }
                    }

                    Cell {
                        width: parent.width

                        MetaLabel { text: "METALABEL / CAPTION" }
                    }

                    Cell {
                        width: parent.width

                        // The wider variant the lock/greeter date row uses.
                        MetaLabel {
                            text: "METALABEL / SUBTITLE"
                            font.pixelSize: Theme.fontSize.subtitle
                            font.letterSpacing: Theme.letterSpacing.wide
                        }
                    }
                }
            }

            Row {
                id: bottomRow
                width: sheetColumn.width

                readonly property real _flex: bottomRow.width / 3

                Column {
                    id: spacingColumn
                    width: bottomRow._flex

                    Cell {
                        width: parent.width

                        MetaLabel { text: "SPACING SCALE" }
                    }

                    Grid {
                        width: parent.width
                        columns: 3

                        Repeater {
                            // tokens.js's SPACING_BASE steps, named here
                            // rather than taken from Object.keys(Theme.space):
                            // that object also carries the semantic tokens
                            // (controlHeight, panelPadding, popupRowHeight,
                            // …), which are DESIGN.md §1.3's second table —
                            // derived from the same spacingScale root, but
                            // not steps of this scale.
                            model: ["xxs", "xs", "sm", "md", "lg", "xl", "xxl", "xxxl", "huge"]

                            delegate: Cell {
                                id: stepCell
                                required property string modelData

                                width: spacingColumn.width / 3

                                Row {
                                    spacing: Theme.space.md

                                    MetaLabel {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: stepCell.modelData + " " + Theme.space[stepCell.modelData]
                                    }

                                    // Drawn at the token's own value, so the
                                    // scale is a picture rather than a list
                                    // of numbers.
                                    Rectangle {
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: Theme.space[stepCell.modelData]
                                        height: Theme.fontSize.caption
                                        radius: Theme.radius
                                        color: stepCell.foreground
                                    }
                                }
                            }
                        }
                    }
                }

                Column {
                    id: marqueeColumn
                    width: bottomRow._flex

                    Cell {
                        width: parent.width

                        MetaLabel { text: "MARQUEETEXT" }
                    }

                    Cell {
                        id: fitsCell
                        width: parent.width

                        Column {
                            spacing: Theme.space.xxs

                            MetaLabel { text: "FITS / NEVER MOVES" }

                            MarqueeText {
                                text: "A TITLE THAT FITS"
                                color: fitsCell.foreground
                                maxWidth: Math.max(0, marqueeColumn.width - Theme.space.lg * 2 - Theme.borderWidth)
                            }
                        }
                    }

                    Cell {
                        id: scrollsCell
                        width: parent.width

                        Column {
                            spacing: Theme.space.xxs

                            MetaLabel { text: "OVERFLOWS / SCROLLS" }

                            // Half the column on purpose: the component only
                            // scrolls once the text genuinely overruns the
                            // width it was handed, so a specimen that fits
                            // would prove nothing.
                            MarqueeText {
                                text: "A TITLE TOO LONG FOR THE WIDTH IT WAS GIVEN, WHICH IS WHAT MAKES IT SCROLL"
                                color: scrollsCell.foreground
                                maxWidth: marqueeColumn.width / 2
                            }
                        }
                    }
                }

                Column {
                    id: surfaceColumn
                    width: bottomRow._flex

                    Cell {
                        width: parent.width

                        MetaLabel { text: "SURFACES" }
                    }

                    Cell {
                        width: parent.width

                        MetaLabel { text: "PANEL / THIS SURFACE" }
                    }

                    Cell {
                        width: parent.width

                        // Panel.qml holds one DismissTwins for this surface,
                        // which maps one click catcher per output other than
                        // the one it opened on — so a single-output session
                        // honestly reports none rather than an invented one.
                        MetaLabel { text: "DISMISSTWINS / " + Math.max(0, Quickshell.screens.length - 1) + " TWINS" }
                    }

                    // A real hover source, not just a `tooltipText` string:
                    // Cell.qml only arms its tooltip Loader from its own
                    // `hovered` transition, so a row nothing ever hovers
                    // would advertise a component it never actually
                    // instantiates. The MouseArea is fill-anchored to the
                    // cell's content item, which is exactly the case Cell's
                    // _measure() skips, so it adds no width or height.
                    Cell {
                        id: tooltipCell
                        width: parent.width
                        hovered: tooltipMouse.containsMouse
                        tooltipText: "TOOLTIP / THE REAL CARD, LOADED BY THIS CELL"

                        MouseArea {
                            id: tooltipMouse
                            anchors.fill: parent
                            hoverEnabled: true
                        }

                        MetaLabel {
                            text: "TOOLTIP / REAL TOOLTIPTEXT"
                            color: tooltipCell.foreground
                        }
                    }

                    Cell {
                        width: parent.width

                        MetaLabel { text: "TOOLTIP HIDES WHILE ANY PANEL IS OPEN" }
                    }
                }
            }
        }
    }
}
