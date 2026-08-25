import QtQuick

// A SectionLabel under the name 51 surfaces still call it by; M45 renames
// the call sites and deletes this file.
//
// `colon` is inert: a label carries no trailing colon any more (DESIGN.md
// §5), and 25 call sites still set it.
SectionLabel {
    property bool colon: false
}
