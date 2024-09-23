#version 430

layout(location = 0) in vec2 pos;
layout(location = 1) in vec2 uv;

uniform vec2 uResolution;

out vec2 outUv;

void main() {
    gl_Position = vec4(pos, 0.0, 1.0);
    gl_Position.x *= uResolution.y / uResolution.x;
    outUv = uv;
}