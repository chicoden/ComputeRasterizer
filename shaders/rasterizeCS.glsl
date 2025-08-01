#version 460

#define TRIANGLE_COUNT 966
#define Z_NEAR 0.01
#define Z_FAR 1000.0

struct Vertex {
    vec3 pos;
    vec3 normal;
    vec2 uv;
};

layout(local_size_x = 256) in;

layout(r32ui, binding = 0) uniform uimage3D fb;
layout(std430, binding = 1) buffer VertexBuffer { Vertex vertices[]; };
layout(std430, binding = 2) buffer IndexBuffer { uvec3 indices[]; };

layout(location = 0) uniform sampler2D colorTexture;
uniform float uTime;

vec4 worldToClipSpace(vec3 worldSpacePos) {
    float co = cos(uTime), si = sin(uTime);
    mat3 spin = mat3(co, 0.0, si, 0.0, 1.0, 0.0, -si, 0.0, co);
    vec3 viewSpacePos = spin * worldSpacePos + vec3(0.0, 0.0, -3.0);
    float aspectRatio = float(imageSize(fb).x) / float(imageSize(fb).y);
    return vec4(
        viewSpacePos.x / aspectRatio,
        viewSpacePos.y,
        (viewSpacePos.z + Z_NEAR) * Z_FAR / (Z_NEAR - Z_FAR),
        -viewSpacePos.z
    );
}

ivec2 ndcToScreenSpace(vec2 ndc) {
    return ivec2((0.5 + 0.5 * ndc) * vec2(imageSize(fb).xy));
}

vec3 shadeFragment(vec3 pos, vec3 normal, vec2 uv) {
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

    // Transform to clip space
    // TODO: actually clip triangles against frustum
    mat3x4 clipSpaceVerts = mat3x4(
        worldToClipSpace(v0.pos),
        worldToClipSpace(v1.pos),
        worldToClipSpace(v2.pos)
    );

    vec3 perspFactor = 1.0 / vec3(
        clipSpaceVerts[0].w,
        clipSpaceVerts[1].w,
        clipSpaceVerts[2].w
    );

    // Transform to NDC (Normalized Device Coordinates)
    mat3 ndc = mat3(
        clipSpaceVerts[0].xyz * perspFactor[0],
        clipSpaceVerts[1].xyz * perspFactor[1],
        clipSpaceVerts[2].xyz * perspFactor[2]
    );

    // Map to screen space and hold onto the index of the vertex
    ivec3 screenA = ivec3(ndcToScreenSpace(ndc[0].xy), 0);
    ivec3 screenB = ivec3(ndcToScreenSpace(ndc[1].xy), 1);
    ivec3 screenC = ivec3(ndcToScreenSpace(ndc[2].xy), 2);

    // Cull backfacing triangles
    ivec2 deltaBA = screenB.xy - screenA.xy;
    ivec2 deltaCA = screenC.xy - screenA.xy;
    if (deltaBA.x * deltaCA.y < deltaBA.y * deltaCA.x) return;

    // Sort vertices in screen space by y coordinate
    if (screenA.y > screenC.y) { ivec3 tmp = screenA; screenA = screenC; screenC = tmp; }
    if (screenA.y > screenB.y) { ivec3 tmp = screenA; screenA = screenB; screenB = tmp; }
    if (screenB.y > screenC.y) { ivec3 tmp = screenB; screenB = screenC; screenC = tmp; }

    // Prepare barycentric coordinates for perspective correct interpolation
    vec4 baryA = vec4(0.0);
    vec4 baryB = vec4(0.0);
    vec4 baryC = vec4(0.0);
    baryA.w = perspFactor[screenA[2]];
    baryB.w = perspFactor[screenB[2]];
    baryC.w = perspFactor[screenC[2]];
    baryA[screenA[2]] = baryA.w;
    baryB[screenB[2]] = baryB.w;
    baryC[screenC[2]] = baryC.w;

    vec3 depths = vec3(ndc[0].z, ndc[1].z, ndc[2].z);

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
                    vec3 shade = shadeFragment(matPos * worldBary, matNormal * worldBary, matUv * worldBary);
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
                    vec3 shade = shadeFragment(matPos * worldBary, matNormal * worldBary, matUv * worldBary);
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