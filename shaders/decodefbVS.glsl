#version 430

layout(location = 0) in vec2 pos;
layout(location = 1) in vec2 uv;

layout(binding = 0, r32ui) uniform uimage3D fb;
uniform vec2 uResolution;

out vec2 outUv;

void main() {
    vec2 res = vec2(imageSize(fb).xy);
    gl_Position = vec4(pos, 0.0, 1.0);
    gl_Position.x *= uResolution.y / uResolution.x;
    gl_Position.x *= res.x / res.y;
    outUv = uv;
}