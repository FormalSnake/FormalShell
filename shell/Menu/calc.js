.pragma library

// Safe expression calculator behind the menu's CALC row (M12 Task 5): a
// recursive-descent parser over + - * / % ^, parentheses, unary minus and
// plain decimal numbers (no underscore separators), never eval()/Function(),
// so a search query can't execute anything. evaluate() returns a finite
// number or null; it never throws, because every keystroke in the menu's
// search field runs through it.
//
// Grammar (^ right-associative, binding tighter than unary minus, so
// -2^2 = -4 and 2^-3 works):
//   expr    := term { ("+" | "-") term }
//   term    := factor { ("*" | "/" | "%") factor }
//   factor  := "-" factor | power
//   power   := primary [ "^" factor ]
//   primary := number | "(" expr ")"

function tokenize(text) {
    var tokens = [];
    var i = 0;
    var len = text.length;
    while (i < len) {
        var c = text[i];
        if (c === " " || c === "\t") { i++; continue; }
        if ("+-*/%^()".indexOf(c) >= 0) { tokens.push(c); i++; continue; }
        if ((c >= "0" && c <= "9") || c === ".") {
            var start = i;
            while (i < len && text[i] >= "0" && text[i] <= "9") i++;
            if (i < len && text[i] === ".") {
                i++;
                while (i < len && text[i] >= "0" && text[i] <= "9") i++;
            }
            var raw = text.slice(start, i);
            if (raw === ".") return null;
            tokens.push(parseFloat(raw));
            continue;
        }
        return null;
    }
    return tokens;
}

function _expr(st) {
    var v = _term(st);
    if (v === null) return null;
    while (st.tokens[st.pos] === "+" || st.tokens[st.pos] === "-") {
        var op = st.tokens[st.pos++];
        var rhs = _term(st);
        if (rhs === null) return null;
        v = op === "+" ? v + rhs : v - rhs;
    }
    return v;
}

function _term(st) {
    var v = _factor(st);
    if (v === null) return null;
    while (st.tokens[st.pos] === "*" || st.tokens[st.pos] === "/" || st.tokens[st.pos] === "%") {
        var op = st.tokens[st.pos++];
        var rhs = _factor(st);
        if (rhs === null) return null;
        v = op === "*" ? v * rhs : op === "/" ? v / rhs : v % rhs;
    }
    return v;
}

function _factor(st) {
    if (st.tokens[st.pos] === "-") {
        st.pos++;
        var v = _factor(st);
        return v === null ? null : -v;
    }
    return _power(st);
}

function _power(st) {
    var base = _primary(st);
    if (base === null) return null;
    if (st.tokens[st.pos] === "^") {
        st.pos++;
        var exp = _factor(st);
        if (exp === null) return null;
        return Math.pow(base, exp);
    }
    return base;
}

function _primary(st) {
    var t = st.tokens[st.pos];
    if (typeof t === "number") { st.pos++; return t; }
    if (t === "(") {
        st.pos++;
        var v = _expr(st);
        if (v === null || st.tokens[st.pos] !== ")") return null;
        st.pos++;
        return v;
    }
    return null;
}

function evaluate(text) {
    var tokens = tokenize(String(text || ""));
    if (tokens === null || tokens.length === 0) return null;
    var st = { tokens: tokens, pos: 0 };
    var v = _expr(st);
    if (v === null || st.pos !== tokens.length) return null;
    return isFinite(v) ? v : null;
}

// 12 significant digits then re-parse: collapses float noise
// (0.1+0.2 -> "0.3") without freezing integers into exponent notation.
function format(n) {
    return String(parseFloat(n.toPrecision(12)));
}

// The ready-made row Menu.qml prepends to ranked results (and shows alone at
// the calc route level) when the query parses. A plain "action" node, the
// existing _activateRow action path already runs the command and closes, so
// Enter needs zero new handling (clipboardProvider's own trick). The
// formatted result is digits/./-/e/+ only, so it's shell-safe unquoted; "--"
// keeps a leading minus from reading as a wl-copy option.
function resultNode(query) {
    var value = evaluate(query);
    if (value === null) return null;
    var text = format(value);
    return {
        id: "calc.result",
        parentId: null,
        label: "= " + text,
        icon: "",
        title: "",
        aliases: [],
        kind: "action",
        action: "wl-copy -- " + text,
        meta: "CALC",
        childIds: []
    };
}
