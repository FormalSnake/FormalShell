.pragma library

// BoxCast.qml's component, created once for every Box: a Loader given the
// file by URL would print the Qt 6.8 load failure once per box.
var _component;

function component() {
    if (_component === undefined) {
        _component = Qt.createComponent("BoxCast.qml");
        if (_component.errorString() !== "") {
            console.warn("Box casts unavailable, drawing without them:", _component.errorString());
            _component = null;
        }
    }
    return _component;
}
