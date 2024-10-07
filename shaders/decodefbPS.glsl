#version 430

layout(binding = 0, r32ui) uniform uimage3D fb;

in vec2 outUv;
out vec4 fragColor;

void main() {
    uvec2 id = uvec2(outUv * vec2(imageSize(fb).xy));
    fragColor = vec4(pow(vec3(uvec3(
        imageLoad(fb, ivec3(id, 0)).x,
        imageLoad(fb, ivec3(id, 1)).x,
        imageLoad(fb, ivec3(id, 2)).x
    ) & 0xffu) / 255.0, vec3(0.4545)), 1.0);
}