#version 440

// Levels for a near-infrared frame: a gain that brings the frame's mean
// (its smallest mip level) up to `target`, never below 1 and never past
// `maxGain`, then a gamma under 1 that opens the shadows, where a face lit
// only by the emitter sits.

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float target;
    float maxGain;
    float gamma;
};

layout(binding = 1) uniform sampler2D source;

void main() {
    float mean = texture(source, vec2(0.5), 16.0).r;
    float gain = clamp(target / max(mean, 0.001), 1.0, maxGain);
    float v = pow(clamp(texture(source, qt_TexCoord0).r * gain, 0.0, 1.0), gamma);
    fragColor = vec4(v, v, v, 1.0) * qt_Opacity;
}
