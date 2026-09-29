#version 440

// One decision per decoded IR frame (Surfaces/Menu/views/IrFeed.qml). The
// newest frame is kept when its mean is at least `litRatio` of the previous
// frame's, which an emitter lighting every other frame always is and an
// unlit frame or the same frame captured twice never is. Otherwise the last
// kept frame is held, its alpha spending `holdStep` per frame, so a stream
// that stops alternating (no emitter, a scene change) still moves once the
// alpha runs out. The means are each texture's smallest mip level.

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float phase;
    float litRatio;
    float holdStep;
};

layout(binding = 1) uniform sampler2D slotA;
layout(binding = 2) uniform sampler2D slotB;
layout(binding = 3) uniform sampler2D held;

void main() {
    bool aIsNew = phase < 0.5;
    float meanA = texture(slotA, vec2(0.5), 16.0).r;
    float meanB = texture(slotB, vec2(0.5), 16.0).r;
    float meanNew = aIsNew ? meanA : meanB;
    float meanOld = aIsNew ? meanB : meanA;
    vec4 kept = texture(held, qt_TexCoord0);
    bool lit = meanNew >= meanOld * litRatio && meanNew > 0.0;
    if (lit || kept.a < holdStep * 0.5) {
        vec3 c = aIsNew ? texture(slotA, qt_TexCoord0).rgb : texture(slotB, qt_TexCoord0).rgb;
        fragColor = vec4(c, 1.0);
    } else {
        fragColor = vec4(kept.rgb, kept.a - holdStep);
    }
}
