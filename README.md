# Compute Rasterizer
This is a 3D triangle rasterizer written in GLSL compute shaders. This project was created and run with [SHADERed](https://shadered.org/).
## To do
- Implement z and frustum clipping
- Implement **non-glitchy** texture filtering with screen space UV derivatives
- Only transform vertices once then cache to reduce redundancy (maybe not a problem due to parallel execution?)