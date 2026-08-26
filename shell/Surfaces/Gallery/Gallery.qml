import QtQuick
import Quickshell
import qs.Core
import qs.Components

// The dev gallery (reference: omarchy's own shell/plugins/dev-gallery/
// GalleryPanel.qml, read per CLAUDE.md's read-reference rule, the ledger
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
// are all this surface's own, straight out of Panel.qml. Every other
// popout takes the same route for the same reason.
//
// Tooltip paints here like everything else since M44: the card no longer
// suppresses itself while a panel is open, and it anchors to the row that
// owns it rather than to the bar. The TOOLTIP row carries a real
// `tooltipText`, so hovering it drives the real component through Cell.qml's
// own lazy Loader rather than standing a lookalike card in its place.
Panel {
    id: root

    panelTitle: "DEV GALLERY"

    // Nearly the whole output: fitting every specimen into one screenshot
    // is the entire point of the surface. Panel caps its content at 60% of
    // the screen height, so the sheet below spends that budget across
    // columns rather than on one long scroll.
    panelWidth: root.screen
        ? Math.round(root.screen.width - Theme.space.panelPadding * 2)
        : 960

    // Nothing below exists until the surface is actually summoned, the
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

        // Every gap on the sheet is the ladder (DESIGN.md §1 Separation) and
        // nothing else: `sectionGap` between one specimen group and the next,
        // `rowGap` between a group's label and its specimens, and no rule
        // anywhere. Under the retro preset a rule and a Cell's own border are
        // the same 1px at radius 0, so on the one surface that is nothing but
        // bordered specimens a rule would read as another specimen. Space is
        // the only mark left that cannot be mistaken for one.
        Column {
            id: sheetColumn
            width: sheetLoader.width
            spacing: Theme.space.sectionGap

            Row {
                id: topRow
                width: sheetColumn.width
                spacing: Theme.space.sectionGap

                // AuthPrompt sizes itself off the type-scale root and is by
                // far the tallest and widest specimen here, so it takes the
                // width it needs and the token columns share what is left,
                // minus the three gaps between the four columns.
                readonly property real _flex: Math.max(0, (topRow.width - authColumn.width - topRow.spacing * 3) / 3)

                Column {
                    id: authColumn
                    width: authCell.implicitWidth
                    spacing: Theme.space.rowGap

                    SectionLabel {
                        leftPadding: Theme.space.controlPaddingX
                        text: "AUTHPROMPT / IDLE"
                    }

                    // inputEnabled: false is the component's own way of
                    // standing down, not a gallery-only hack: the panel's
                    // backdrop owns keyboard focus (Panel.qml's focus
                    // prime), and a live TextInput here would take it and
                    // leave Escape dead. Everything else, the display
                    // clock, the date meta row, the dividing rule, the 3px
                    // field outline, the centred placeholder, is the
                    // surface the lock screen and the greeter both render.
                    Cell {
                        id: authCell
                        ghost: true

                        AuthPrompt { inputEnabled: false }
                    }
                }

                Column {
                    id: cellColumn
                    width: topRow._flex
                    spacing: Theme.space.sectionGap

                    Column {
                        width: parent.width
                        spacing: Theme.space.rowGap

                        SectionLabel {
                            leftPadding: Theme.space.controlPaddingX
                            text: "CELL"
                        }

                        Repeater {
                            // One row per state Cell.qml renders differently
                            // (DESIGN.md §2), driven as data rather than as one
                            // hand-written delegate each. The one block on the
                            // sheet that keeps its resting border: rest is one
                            // of the seven states it is here to show, and every
                            // other specimen went flat around it.
                            model: [
                                { label: "Rest",        selected: false, active: false, destructive: false, warning: false, cursor: false, hovered: false },
                                { label: "Hovered",     selected: false, active: false, destructive: false, warning: false, cursor: false, hovered: true  },
                                { label: "Cursor",      selected: false, active: false, destructive: false, warning: false, cursor: true,  hovered: false },
                                { label: "Selected",    selected: true,  active: false, destructive: false, warning: false, cursor: false, hovered: false },
                                { label: "Active",      selected: false, active: true,  destructive: false, warning: false, cursor: false, hovered: false },
                                { label: "Destructive", selected: false, active: false, destructive: true,  warning: false, cursor: false, hovered: false },
                                { label: "Warning",     selected: false, active: false, destructive: false, warning: true,  cursor: false, hovered: false }
                            ]

                            delegate: Cell {
                                id: stateCell
                                required property var modelData

                                width: cellColumn.width
                                selected: stateCell.modelData.selected
                                active: stateCell.modelData.active
                                destructive: stateCell.modelData.destructive
                                warning: stateCell.modelData.warning
                                cursor: stateCell.modelData.cursor
                                hovered: stateCell.modelData.hovered

                                Text {
                                    text: stateCell.modelData.label
                                    color: stateCell.foreground
                                    font.family: Theme.fontFamilySans
                                    font.pixelSize: Theme.fontSize.body
                                    font.weight: Theme.weight.medium
                                }
                            }
                        }
                    }

                    // The honest-unavailable state every surface in the
                    // shell falls back to (NO ADAPTER, NO DEVICES, NO
                    // LOCATION): a bare label in SectionLabel's own
                    // mutedForeground, no box and no Cell flag. A state that
                    // says nothing is here should not be the most heavily
                    // chromed thing on the surface. Its own specimen rather
                    // than an eighth state, so it takes `sectionGap` off the
                    // grid above instead of falling in line with it.
                    SectionLabel {
                        leftPadding: Theme.space.controlPaddingX
                        text: "DIM / UNAVAILABLE"
                    }
                }

                Column {
                    id: typeColumn
                    width: topRow._flex
                    spacing: Theme.space.rowGap

                    SectionLabel {
                        leftPadding: Theme.space.controlPaddingX
                        text: "TYPE SCALE"
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
                            ghost: true

                            Row {
                                spacing: Theme.space.md

                                SectionLabel {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: typeCell.modelData + " " + Theme.fontSize[typeCell.modelData]
                                }

                                Text {
                                    text: "Aa"
                                    color: typeCell.foreground
                                    font.family: Theme.fontFamilySans
                                    font.pixelSize: Theme.fontSize[typeCell.modelData]
                                }
                            }
                        }
                    }
                }

                Column {
                    id: tokenColumn
                    width: topRow._flex
                    spacing: Theme.space.sectionGap

                    // The separation ladder's rung 4 (DESIGN.md §1), drawn
                    // both ways round. A rule is the only primitive whose
                    // whole appearance is one line of border ink, so the
                    // specimen is the line itself and the `inset` variant
                    // beside it: the difference between a seam that divides
                    // a surface and one that divides the rows on it is the
                    // only decision a caller makes.
                    Column {
                        width: parent.width
                        spacing: Theme.space.rowGap

                        SectionLabel {
                            leftPadding: Theme.space.controlPaddingX
                            text: "SEPARATOR"
                        }

                        // Each variant is its own caption over its own rule
                        // at `rowGap`, with `sectionGap` between the three.
                        // A rule sitting equidistant between two captions
                        // reads as belonging to neither, which is the same
                        // ambiguity the ladder's own "never directly under a
                        // SectionLabel" clause is about.
                        Repeater {
                            model: [
                                { name: "FULL BLEED", inset: 0, vertical: false },
                                { name: "INSET", inset: Theme.space.controlPaddingX, vertical: false },
                                { name: "VERTICAL", inset: 0, vertical: true }
                            ]

                            delegate: Column {
                                id: sepSpec
                                required property var modelData

                                width: parent.width
                                topPadding: sepSpec.modelData.name === "FULL BLEED" ? 0 : Theme.space.sectionGap - Theme.space.rowGap
                                spacing: Theme.space.rowGap

                                SectionLabel {
                                    leftPadding: Theme.space.controlPaddingX
                                    text: sepSpec.modelData.name
                                }

                                Separator {
                                    width: sepSpec.modelData.vertical ? undefined : sepSpec.width
                                    height: sepSpec.modelData.vertical ? Theme.space.controlHeight : undefined
                                    vertical: sepSpec.modelData.vertical
                                    inset: sepSpec.modelData.inset
                                    x: sepSpec.modelData.vertical ? Theme.space.controlPaddingX : 0
                                }
                            }
                        }
                    }

                    Column {
                        width: parent.width
                        spacing: Theme.space.rowGap

                        SectionLabel {
                            leftPadding: Theme.space.controlPaddingX
                            text: "COLOR TOKENS"
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
                                ghost: true

                                Row {
                                    spacing: Theme.space.md

                                    // The one thing a Cell cannot be: a fill
                                    // picked by palette role rather than by
                                    // interactive state. Bordered in `rule` so
                                    // `background` still reads as a swatch
                                    // against the panel's own fill.
                                    // primitive-exempt: a colour swatch. The fill IS the token being
                                    // shown, so no primitive can own it.
                                    Rectangle {
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: Theme.space.huge + Theme.space.xl
                                        height: Theme.fontSize.caption + Theme.space.sm
                                        radius: Theme.radius
                                        color: Theme.color[swatchCell.modelData]
                                        border.width: Theme.borderWidth
                                        border.color: Theme.color.border
                                    }

                                    SectionLabel {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: swatchCell.modelData + " " + Theme.color[swatchCell.modelData]
                                    }
                                }
                            }
                        }
                    }

                    // A second group in this column, not a swatch that lost
                    // its colour: the three name themselves, so the group
                    // takes `sectionGap` off the swatches and no heading of
                    // its own.
                    Column {
                        width: parent.width
                        spacing: Theme.space.rowGap

                        SectionLabel {
                            leftPadding: Theme.space.controlPaddingX
                            text: "METALABEL"
                        }

                        SectionLabel {
                            leftPadding: Theme.space.controlPaddingX
                            text: "METALABEL / CAPTION"
                        }

                        // The wider variant the lock/greeter date row uses.
                        SectionLabel {
                            leftPadding: Theme.space.controlPaddingX
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
                spacing: Theme.space.sectionGap

                readonly property real _flex: (bottomRow.width - bottomRow.spacing * 2) / 3

                Column {
                    id: spacingColumn
                    width: bottomRow._flex
                    spacing: Theme.space.rowGap

                    SectionLabel {
                        leftPadding: Theme.space.controlPaddingX
                        text: "SPACING SCALE"
                    }

                    Grid {
                        width: parent.width
                        columns: 3

                        Repeater {
                            // tokens.js's SPACING_BASE steps, named here
                            // rather than taken from Object.keys(Theme.space):
                            // that object also carries the semantic tokens
                            // (controlHeight, panelPadding, popupRowHeight,
                            // …), which are DESIGN.md §1.3's second table,
                            // derived from the same spacingScale root, but
                            // not steps of this scale.
                            model: ["xxs", "xs", "sm", "md", "lg", "xl", "xxl", "huge"]

                            delegate: Cell {
                                id: stepCell
                                required property string modelData

                                width: spacingColumn.width / 3
                                ghost: true

                                Row {
                                    spacing: Theme.space.md

                                    SectionLabel {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: stepCell.modelData + " " + Theme.space[stepCell.modelData]
                                    }

                                    // Drawn at the token's own value, so the
                                    // scale is a picture rather than a list
                                    // of numbers.
                                    // primitive-exempt: a spacing step drawn at its own value, so the
                                    // scale reads as a picture. The bar IS the number.
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
                    spacing: Theme.space.rowGap

                    SectionLabel {
                        leftPadding: Theme.space.controlPaddingX
                        text: "MARQUEETEXT"
                    }

                    Cell {
                        id: fitsCell
                        width: parent.width
                        ghost: true

                        Column {
                            spacing: Theme.space.xxs

                            SectionLabel { text: "FITS / NEVER MOVES" }

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
                        ghost: true

                        Column {
                            spacing: Theme.space.xxs

                            SectionLabel { text: "OVERFLOWS / SCROLLS" }

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
                    spacing: Theme.space.rowGap

                    SectionLabel {
                        leftPadding: Theme.space.controlPaddingX
                        text: "SURFACES"
                    }

                    SectionLabel {
                        leftPadding: Theme.space.controlPaddingX
                        text: "PANEL / THIS SURFACE"
                    }

                    // Panel.qml holds one DismissTwins for this surface,
                    // which maps one click catcher per output other than
                    // the one it opened on, so a single-output session
                    // honestly reports none rather than an invented one.
                    SectionLabel {
                        leftPadding: Theme.space.controlPaddingX
                        text: "DISMISSTWINS / " + Math.max(0, Quickshell.screens.length - 1) + " TWINS"
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
                        tooltipText: "TOOLTIP / THE REAL CARD, LOADED BY THIS CELL"

                        interactive: true

                        SectionLabel {
                            text: "TOOLTIP / REAL TOOLTIPTEXT"
                            color: tooltipCell.foreground
                        }
                    }

                    SectionLabel {
                        leftPadding: Theme.space.controlPaddingX
                        text: "TOOLTIP OPENS UNDER THE ROW ABOVE, OVER THIS PANEL"
                    }
                }
            }
        }
    }
}
