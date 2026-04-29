#version 450
#extension GL_ARB_separate_shader_objects : enable

layout(location = 0) out vec2 fragTexCoord;

void main() {
  if (gl_VertexIndex == 0) {
    gl_Position = vec4(-1.0, 3.0, 0.0, 1.0);
    fragTexCoord = vec2(0.0, 2.0);
  } else if (gl_VertexIndex == 1) {
    gl_Position = vec4(-1.0, -1.0, 0.0, 1.0);
    fragTexCoord = vec2(0.0, 0.0);
  } else {
    gl_Position = vec4(3.0, -1.0, 0.0, 1.0);
    fragTexCoord = vec2(2.0, 0.0);
  }
}