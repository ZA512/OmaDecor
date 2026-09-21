#version 320 es
precision highp float;
// @duration 0.24
// @overlay

in vec2 v_texcoord;
out vec4 fragColor;
uniform sampler2D tex;
uniform float progress;

void main() {
    vec4 source = texture(tex, v_texcoord);
    float pulse = sin(clamp(progress, 0.0, 1.0) * 3.14159265);
    source.rgb = min(source.rgb + vec3(0.10 * pulse) * source.a, vec3(source.a));
    fragColor = source;
}
