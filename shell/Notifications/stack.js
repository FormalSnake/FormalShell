.pragma library

// The sonner depth stack's geometry, pure (M34 Task 2's contract, extracted
// in M44 Task 1 so it can be asserted without a compositor):
// Toasts.qml owns the slot pool, the freeze-on-exit bookkeeping and the
// Behaviors, this owns where every card lands in both modes.
//
// COLLAPSED is the depth stack: the front card at full width, each level
// behind it a real card SIZED narrower by one `peekInset` per side per
// level (never a fractional `transform: scale`, which rasterizes a 1px
// border blurry), horizontally centred on the front card, offset toward
// the anchored edge by `peekOffset` so only its edge sliver shows. At most
// `maxPeekLevels` levels peek; deeper cards take the last level's geometry
// and sit behind it. EXPANDED is the plain list: every card full width,
// `gap` apart, in the order the caller hands them over.
//
// Keys are opaque (Toasts.qml passes pool indices). A null key means an
// entry with no slot of its own: it draws nothing, but it still consumes
// its rank, so the cards around it keep the level they would have had.
function layout(params) {
    var frameWidth = params.frameWidth;
    var peekInset = params.peekInset;
    var peekOffset = params.peekOffset;
    var maxPeekLevels = params.maxPeekLevels;
    var gap = params.gap;
    var top = params.top === true;
    var heights = params.heights || {};
    var collapsed = params.collapsed || [];
    var expanded = params.expanded || [];

    var byKey = {};
    function slotFor(key) {
        if (byKey[key] === undefined)
            byKey[key] = {};
        return byKey[key];
    }

    for (var r = 0; r < collapsed.length; r++) {
        if (collapsed[r] === null || collapsed[r] === undefined)
            continue;
        var level = Math.min(r, maxPeekLevels);
        var inset = level * peekInset;
        slotFor(collapsed[r]).collapsed = {
            x: inset,
            width: frameWidth - inset * 2,
            // The reveal recedes AWAY from the anchored edge: that edge
            // already carries the front card flush against it, so a peek
            // can only sit further from it.
            y: top ? level * peekOffset : (maxPeekLevels - level) * peekOffset,
            z: collapsed.length - r,
            contentVisible: r === 0
        };
    }

    var y = 0;
    for (var i = 0; i < expanded.length; i++) {
        var key = expanded[i];
        if (key === null || key === undefined)
            continue;
        slotFor(key).expanded = {
            x: 0,
            width: frameWidth,
            y: y,
            z: expanded.length - i,
            contentVisible: true
        };
        y += (heights[key] || 0) + gap;
    }

    var frontKey = collapsed.length > 0 ? collapsed[0] : null;
    var frontHeight = frontKey === null || frontKey === undefined ? 0 : (heights[frontKey] || 0);

    return {
        byKey: byKey,
        // Every peek level pokes out past the front card by its own offset,
        // so the pile is that much taller than the card in front of it.
        collapsedHeight: frontHeight + maxPeekLevels * peekOffset,
        expandedHeight: y > 0 ? y - gap : 0
    };
}
