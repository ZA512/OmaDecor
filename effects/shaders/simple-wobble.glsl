#version 320 es
precision highp float;

in vec2 v_texcoord;
out vec4 fragColor;
uniform sampler2D tex;
uniform float time;
uniform vec2 surface_size;
uniform vec2 velocity;
uniform vec2 size_velocity;
uniform vec2 peak_velocity;
uniform vec2 peak_size_velocity;
uniform float settle;
uniform float is_resizing;

void main() {
    vec2 motion = mix(velocity, size_velocity, clamp(is_resizing, 0.0, 1.0));
    vec2 peak = mix(peak_velocity, peak_size_velocity, clamp(is_resizing, 0.0, 1.0));
    if (length(motion) < 1.0) motion = peak * (1.0 - clamp(settle, 0.0, 1.0));
    vec2 direction = length(motion) > 0.01 ? normalize(motion) : vec2(1.0, 0.0);
    float strength = min(length(motion) / 24000.0, 0.012) * (1.0 - clamp(settle, 0.0, 1.0));
    float wave = sin((v_texcoord.y * 2.0 - 1.0) * 6.2831853 + time * 18.0);
    vec2 uv = clamp(v_texcoord + direction * wave * strength, vec2(0.0), vec2(1.0));
    fragColor = texture(tex, uv);
}
