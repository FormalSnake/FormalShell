.pragma library
.import "metamorphosis.js" as Metamorphosis

// Retro is metamorphosis' chrome on different scalars (M59 T1): square
// corners, one mono face, opaque surfaces with no compositor blur and the
// dither pass over content imagery. Every one of those is a key presets.js
// already owns, so the box table itself is the same one, re-exported here
// rather than copied, and a change to a shadcn box reaches retro by
// construction.
var STYLE = Metamorphosis.STYLE;
