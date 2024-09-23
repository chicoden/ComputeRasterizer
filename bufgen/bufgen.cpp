#include <iostream>
#include <fstream>
#include <cstdint>
#include <cstring>
#include <array>

#define MAX_VERTICES 4
#define MAX_TRIANGLES 2

struct Vertex {
    float pos[3];
    float pad1;
    float normal[3];
    float pad2;
    float uv[2];
    float pad3[2];
};

struct Indices3 {
    uint32_t indices[3];
    uint32_t pad1;
};

std::array<Vertex, MAX_VERTICES> vertices{0};
std::array<Indices3, MAX_TRIANGLES> indices{0};

std::array<std::array<float, 8>, 4> vertexData{
    -1.0f, -1.0f, 0.0f,    0.0f, 0.0f, 1.0f,    0.0f, 0.0f,
    +1.0f, -1.0f, 0.0f,    0.0f, 0.0f, 1.0f,    1.0f, 0.0f,
    +1.0f, +1.0f, 0.0f,    0.0f, 0.0f, 1.0f,    1.0f, 1.0f,
    -1.0f, +1.0f, 0.0f,    0.0f, 0.0f, 1.0f,    0.0f, 1.0f
};

std::array<std::array<uint32_t, 3>, 2> indexData{
    0, 1, 2,
    2, 3, 0
};

int main() {
    for (int i = 0; i < vertexData.size(); i++) {
        memcpy(&vertices[i].pos,    &vertexData[i][0], sizeof(((Vertex*)0)->pos   ));
        memcpy(&vertices[i].normal, &vertexData[i][3], sizeof(((Vertex*)0)->normal));
        memcpy(&vertices[i].uv,     &vertexData[i][6], sizeof(((Vertex*)0)->uv    ));
    }

    for (int i = 0; i < indexData.size(); i++) {
        memcpy(&indices[i].indices, &indexData[i][0], sizeof(((Indices3*)0)->indices));
    }

    char* vbuf = reinterpret_cast<char*>(&vertices);
    char* ibuf = reinterpret_cast<char*>(&indices);

    for (int i = 0; i < sizeof(vertices); i++) {
        std::cout << (uint32_t)(uint8_t)vbuf[i] << " ";
        if (i % 4 == 3) std::cout << std::endl;
    }

    std::cout << "\n" << std::endl;

    for (int i = 0; i < sizeof(indices); i++) {
        std::cout << (uint32_t)(uint8_t)ibuf[i] << " ";
        if (i % 4 == 3) std::cout << std::endl;
    }

    std::ofstream vfile;
    vfile.open("C:\\Users\\Pytho\\Projects\\ComputeRasterizer\\buffers\\vertices.buf", std::ios::binary);
    vfile.write(vbuf, sizeof(vertices));
    vfile.close();

    std::ofstream ifile;
    ifile.open("C:\\Users\\Pytho\\Projects\\ComputeRasterizer\\buffers\\indices.buf", std::ios::binary);
    ifile.write(ibuf, sizeof(indices));
    ifile.close();

    return 0;
}

