import QtQuick
import QtQuick.Effects

// One of Box's casts. RectangularShadow arrived in Qt 6.9, so it lives in a
// file of its own that Box reaches through cast.js: on Qt 6.8 (Debian
// trixie) this file fails to load and Box draws without its casts, where
// the same type in Box itself would fail every surface built on a Box.
RectangularShadow {}
