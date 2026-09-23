#version 320 es
precision highp float;
// @duration 0.65

in vec2 v_texcoord;
out vec4 fragColor;
uniform sampler2D tex;
uniform float progress;
uniform float seed;

float cellNoise(vec2 cell) {
    return fract(sin(dot(cell + seed * 97.0, vec2(127.1, 311.7))) * 43758.5453);
}

void main() {
    float amount = mix(1.08, -0.08, smoothstep(0.0, 1.0, clamp(progress, 0.0, 1.0)));
    float threshold = cellNoise(floor(v_texcoord * vec2(72.0, 42.0)));
    float mask = smoothstep(threshold - 0.08, threshold + 0.08, amount);
    fragColor = texture(tex, v_texcoord) * mask;
}
