#version 320 es
precision highp float;
// @duration 0.20

in vec2 v_texcoord;
out vec4 fragColor;
uniform sampler2D tex;
uniform float progress;

void main() {
    float amount = smoothstep(0.0, 1.0, clamp(progress, 0.0, 1.0));
    fragColor = texture(tex, v_texcoord) * amount;
}
