import ctypes

class Vertex(ctypes.Structure):
    _fields_ = [
        ("pos", ctypes.c_float * 3),
        ("pad1", ctypes.c_float),
        ("normal", ctypes.c_float * 3),
        ("pad2", ctypes.c_float),
        ("uv", ctypes.c_float * 2),
        ("pad3", ctypes.c_float * 2)
    ]

class Indices3(ctypes.Structure):
    _fields_ = [
        ("indices", ctypes.c_uint32 * 3),
        ("pad1", ctypes.c_uint32)
    ]

with open(r"C:\Users\Pytho\3DModels\Suzanne\suzanne.obj", "r") as file:
    obj_text = file.read()

vertices = []
normals = []
uvs = []
faces = []
for line in obj_text.split("\n"):
    chunks = line.split()
    if len(chunks) == 0:
        continue

    if chunks[0] == "v":
        vertices.append([*map(float, chunks[1:4])])

    elif chunks[0] == "vn":
        normals.append([*map(float, chunks[1:4])])

    elif chunks[0] == "vt":
        uvs.append([*map(float, chunks[1:3])])

    elif chunks[0] == "f":
        faces.append([[-1 if index == "" else int(index) - 1 for index in chunk.split("/")] for chunk in chunks[1:4]])

unique_vertices = []
new_face_indices = []
for face in faces:
    new_indices = []
    for vertex in face:
        if vertex not in unique_vertices:
            unique_vertices.append(vertex)

        new_indices.append(unique_vertices.index(vertex))

    new_face_indices.append(new_indices)

vertex_data = (Vertex * len(unique_vertices))()
index_data = (Indices3 * len(new_face_indices))()

for i in range(len(unique_vertices)):
    v, vt, vn = unique_vertices[i]
    vertex_data[i].pos    = (ctypes.c_float * 3)(*vertices[v])
    vertex_data[i].normal = (ctypes.c_float * 3)(*normals[vn])
    vertex_data[i].uv     = (ctypes.c_float * 2)(*uvs[vt])

for i in range(len(new_face_indices)):
    index_data[i].indices = (ctypes.c_uint32 * 3)(*new_face_indices[i])

with open(r"..\buffers\vertices.buf", "wb") as file:
    file.write(bytes(vertex_data))

with open(r"..\buffers\indices.buf", "wb") as file:
    file.write(bytes(index_data))
