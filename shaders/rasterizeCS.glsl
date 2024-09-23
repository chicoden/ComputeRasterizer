#version 430

#define TRIANGLE_COUNT 966
#define Z_NEAR 0.01
#define Z_FAR 1000.0

struct Vertex {
    vec3 pos;
    vec3 normal;
    vec2 uv;
};

layout(local_size_x = 256) in;

layout(binding = 0, r32ui) uniform uimage3D fb;
layout(binding = 1, std140) buffer vbuf { Vertex vertices[]; };
layout(binding = 2, std140) buffer ibuf { uvec3 indices[]; };

layout(location = 0) uniform sampler2D colorTexture;
uniform float uTime;

vec3 worldToViewSpace(vec3 p) {
    float co = cos(uTime), si = sin(uTime);
    p.xz *= mat2(co, si, -si, co);
    p -= vec3(0.0, 0.0, 3.0);
    return p;
}

vec3 viewToClipSpace(vec3 p) {
    vec2 res = vec2(imageSize(fb).xy);
    vec3 proj = vec3(p.xy, mix(-Z_NEAR, Z_FAR, (-p.z - Z_NEAR) / (Z_FAR - Z_NEAR))) / -p.z;
    proj.x *= res.y / res.x;
    return proj;
}

ivec2 ndcToScreenSpace(vec2 p) {
    return ivec2((0.5 + 0.5 * p) * vec2(imageSize(fb).xy));
}

vec3 shadePixel(vec3 pos, vec3 normal, vec2 uv) {
    float diffuse = max(0.1, dot(normal, normalize(vec3(-1.0, 1.0, -1.0))));
    return texture(colorTexture, uv).rgb * diffuse;
}

void drawTriangle(uvec3 indices) {
    Vertex v0 = vertices[indices[0]];
    Vertex v1 = vertices[indices[1]];
    Vertex v2 = vertices[indices[2]];

    mat3 matPos = mat3(v0.pos, v1.pos, v2.pos);
    mat3 matNormal = mat3(v0.normal, v1.normal, v2.normal);
    mat3x2 matUv = mat3x2(v0.uv, v1.uv, v2.uv);

    // Transform to view space
    mat3 viewSpaceVerts = mat3(
        worldToViewSpace(v0.pos),
        worldToViewSpace(v1.pos),
        worldToViewSpace(v2.pos)
    );

    // Transform to clip space
    // TODO: actually clip triangles against frustum
    mat3 clipSpaceVerts = mat3(
        viewToClipSpace(viewSpaceVerts[0]),
        viewToClipSpace(viewSpaceVerts[1]),
        viewToClipSpace(viewSpaceVerts[2])
    );

    // Cull backfacing triangles
    vec3 perp = cross(clipSpaceVerts[1] - clipSpaceVerts[0], clipSpaceVerts[2] - clipSpaceVerts[0]);
    if (perp.z < 0.0) return;

    // Map to screen space and hold onto the index of the vertex
    ivec3 screenA = ivec3(ndcToScreenSpace(clipSpaceVerts[0].xy), 0);
    ivec3 screenB = ivec3(ndcToScreenSpace(clipSpaceVerts[1].xy), 1);
    ivec3 screenC = ivec3(ndcToScreenSpace(clipSpaceVerts[2].xy), 2);

    // Depth values remapped to [0...1] range
    vec3 depths = 0.5 + 0.5 * transpose(clipSpaceVerts)[2];

    // Sort vertices in screen space by y coordinate
    if (screenA.y > screenC.y) { ivec3 tmp = screenA; screenA = screenC; screenC = tmp; }
    if (screenA.y > screenB.y) { ivec3 tmp = screenA; screenA = screenB; screenB = tmp; }
    if (screenB.y > screenC.y) { ivec3 tmp = screenB; screenB = screenC; screenC = tmp; }

    // Prepare barycentric coordinates for perspective correct interpolation
    vec4 baryA = vec4(0.0, 0.0, 0.0, 1.0 / viewSpaceVerts[screenA[2]].z);
    vec4 baryB = vec4(0.0, 0.0, 0.0, 1.0 / viewSpaceVerts[screenB[2]].z);
    vec4 baryC = vec4(0.0, 0.0, 0.0, 1.0 / viewSpaceVerts[screenC[2]].z);
    baryA[screenA[2]] = baryA.w;
    baryB[screenB[2]] = baryB.w;
    baryC[screenC[2]] = baryC.w;

    if (screenC.y > screenA.y) {
        vec2 deltaBA = vec2(screenB.xy - screenA.xy);
        vec2 deltaCB = vec2(screenC.xy - screenB.xy);
        vec2 deltaCA = vec2(screenC.xy - screenA.xy);

        // Left edge
        float leftX = float(screenA.x);
        float leftDeltaX = deltaCA.x / deltaCA.y;
        vec4 leftBary = baryA;
        vec4 leftDeltaBary = (baryC - baryA) / deltaCA.y;

        // Right edge
        float rightX;
        float rightDeltaX;
        vec4 rightBary;
        vec4 rightDeltaBary;

        // Sort first edge pair
        bool swapEdgePair = int(leftX + leftDeltaX * deltaBA.y) > screenB.x;
        if (swapEdgePair) {
            rightX = leftX;
            rightDeltaX = leftDeltaX;
            rightBary = leftBary;
            rightDeltaBary = leftDeltaBary;
        }

        if (screenB.y > screenA.y) {
            // Set short edge to edge A->B
            if (swapEdgePair) {
                leftX = float(screenA.x);
                leftDeltaX = deltaBA.x / deltaBA.y;
                leftBary = baryA;
                leftDeltaBary = (baryB - baryA) / deltaBA.y;
            } else {
                rightX = float(screenA.x);
                rightDeltaX = deltaBA.x / deltaBA.y;
                rightBary = baryA;
                rightDeltaBary = (baryB - baryA) / deltaBA.y;
            }

            // Draw upper half
            for (int y = screenA.y; y < screenB.y; y++) {
                vec4 bary = leftBary;
                vec4 deltaBary = (rightBary - leftBary) / (rightX - leftX);
                for (int x = int(leftX); x < int(rightX); x++) {
                    vec3 worldBary = bary.xyz / bary.w;
                    uint depthBits = uint(dot(depths, worldBary) * float(0xffffff)) << 8;
                    vec3 shade = shadePixel(matPos * worldBary, matNormal * worldBary, matUv * worldBary);
                    imageAtomicMin(fb, ivec3(x, y, 0), depthBits | uint(shade.r * float(0xff)));
                    imageAtomicMin(fb, ivec3(x, y, 1), depthBits | uint(shade.g * float(0xff)));
                    imageAtomicMin(fb, ivec3(x, y, 2), depthBits | uint(shade.b * float(0xff)));
                    bary += deltaBary;
                }

                leftX += leftDeltaX;
                rightX += rightDeltaX;
                leftBary += leftDeltaBary;
                rightBary += rightDeltaBary;
            }
        }

        if (screenC.y > screenB.y) {
            // Set short edge to edge B->C
            if (swapEdgePair) {
                leftX = float(screenB.x);
                leftDeltaX = deltaCB.x / deltaCB.y;
                leftBary = baryB;
                leftDeltaBary = (baryC - baryB) / deltaCB.y;
            } else {
                rightX = float(screenB.x);
                rightDeltaX = deltaCB.x / deltaCB.y;
                rightBary = baryB;
                rightDeltaBary = (baryC - baryB) / deltaCB.y;
            }

            // Draw lower half
            for (int y = screenB.y; y < screenC.y; y++) {
                vec4 bary = leftBary;
                vec4 deltaBary = (rightBary - leftBary) / (rightX - leftX);
                for (int x = int(leftX); x < int(rightX); x++) {
                    vec3 worldBary = bary.xyz / bary.w;
                    uint depthBits = uint(dot(depths, worldBary) * float(0xffffff)) << 8;
                    vec3 shade = shadePixel(matPos * worldBary, matNormal * worldBary, matUv * worldBary);
                    imageAtomicMin(fb, ivec3(x, y, 0), depthBits | uint(shade.r * float(0xff)));
                    imageAtomicMin(fb, ivec3(x, y, 1), depthBits | uint(shade.g * float(0xff)));
                    imageAtomicMin(fb, ivec3(x, y, 2), depthBits | uint(shade.b * float(0xff)));
                    bary += deltaBary;
                }

                leftX += leftDeltaX;
                rightX += rightDeltaX;
                leftBary += leftDeltaBary;
                rightBary += rightDeltaBary;
            }
        }
    }
}

void main() {
    uint index = gl_GlobalInvocationID.x;
    if (index >= TRIANGLE_COUNT) return;
    drawTriangle(indices[index]);
}