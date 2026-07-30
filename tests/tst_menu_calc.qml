import QtQuick
import QtTest
import "../shell/Menu/calc.js" as C

TestCase {
    name: "MenuCalc"

    function test_precedence() {
        compare(C.evaluate("2+2*3"), 8);
        compare(C.evaluate("2*3+2"), 8);
        compare(C.evaluate("10-4/2"), 8);
        compare(C.evaluate("10%3"), 1);
        compare(C.evaluate("7%4*2"), 6);
    }

    function test_parentheses() {
        compare(C.evaluate("(2+2)*3"), 12);
        compare(C.evaluate("2*(3+(4-1))"), 12);
    }

    function test_unary_minus() {
        compare(C.evaluate("-5+3"), -2);
        compare(C.evaluate("2*-3"), -6);
        compare(C.evaluate("-(2+3)"), -5);
        // ^ binds tighter than unary minus (math convention).
        compare(C.evaluate("-2^2"), -4);
    }

    function test_power() {
        compare(C.evaluate("2^10"), 1024);
        // Right-associative: 2^(3^2), not (2^3)^2 = 64.
        compare(C.evaluate("2^3^2"), 512);
        compare(C.evaluate("2^-1"), 0.5);
    }

    function test_decimals_and_whitespace() {
        compare(C.evaluate("1.5*2"), 3);
        compare(C.evaluate(".5+.5"), 1);
        compare(C.evaluate(" 2 + 2 * 3 "), 8);
    }

    function test_invalid_returns_null() {
        verify(C.evaluate("") === null);
        verify(C.evaluate("firefox") === null);
        verify(C.evaluate("2+") === null);
        verify(C.evaluate("(2") === null);
        verify(C.evaluate("2 2") === null);
        verify(C.evaluate("1.2.3") === null);
        verify(C.evaluate(".") === null);
        verify(C.evaluate("2$3") === null);
        verify(C.evaluate("1_000+1") === null);
    }

    function test_nonfinite_returns_null() {
        verify(C.evaluate("1/0") === null);
        verify(C.evaluate("0/0") === null);
        verify(C.evaluate("5%0") === null);
    }

    function test_format_trims_float_noise() {
        compare(C.format(0.1 + 0.2), "0.3");
        compare(C.format(8), "8");
        compare(C.format(-2.5), "-2.5");
    }

    function test_result_node() {
        var node = C.resultNode("2+2*3");
        compare(node.label, "= 8");
        compare(node.kind, "action");
        compare(node.meta, "CALC");
        compare(node.action, "wl-copy -- 8");
        verify(C.resultNode("not math") === null);
    }
}
