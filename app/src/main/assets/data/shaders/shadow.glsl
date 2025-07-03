#version 460

layout(location = 0) in vec3 inPosition; // Vertex position in model space

layout(set = 0, binding = 0) uniform LightSpaceMatrices {
  mat4 lightProjView; // Combined light's projection * light's view matrix
} light;

void main() {
 gl_Position = light.lightProjView * vec4(inPosition, 1.0);
}
