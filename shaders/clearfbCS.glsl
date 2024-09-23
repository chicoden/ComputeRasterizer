#version 430

layout(local_size_x = 16, local_size_y = 16) in;
layout(binding = 0, r32ui) uniform uimage3D fb;

void main() {
    imageStore(fb, ivec3(gl_GlobalInvocationID.xy, 0), uvec4(0xffffff00u));
    imageStore(fb, ivec3(gl_GlobalInvocationID.xy, 1), uvec4(0xffffff00u));
    imageStore(fb, ivec3(gl_GlobalInvocationID.xy, 2), uvec4(0xffffff00u));
}