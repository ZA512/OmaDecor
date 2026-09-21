#version 320 es
precision highp float;
// @duration 0.01
// @overlay

in vec2 v_texcoord;
out vec4 fragColor;
uniform sampler2D tex;

void main() {
    fragColor = texture(tex, v_texcoord);
}
