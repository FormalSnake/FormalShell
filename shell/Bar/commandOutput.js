.pragma library

// Pure resolver for a `command` module's completed run (DESIGN.md §Bar,
// spec §Surfaces-1, M10 Task 3). Takes the process exit code and raw
// stdout in, returns the state CommandModule.qml renders out, no
// Quickshell/Process access, so the three failure paths (non-zero exit,
// malformed JSON, a `text` field that isn't a string) are testable head-on
// without spawning a real process. A timeout is a Process-level concern
// (CommandModule.qml kills the process and calls errorState() directly)
// and isn't modeled here.

function errorState() {
    return { text: "MODULE ERROR", tooltip: "", "class": "" };
}

function resolve(exitCode, rawOutput) {
    if (exitCode !== 0)
        return errorState();
    var parsed;
    try {
        parsed = JSON.parse(rawOutput);
    } catch (e) {
        return errorState();
    }
    if (!parsed || typeof parsed.text !== "string")
        return errorState();
    return {
        text: parsed.text,
        tooltip: typeof parsed.tooltip === "string" ? parsed.tooltip : "",
        "class": typeof parsed["class"] === "string" ? parsed["class"] : ""
    };
}
