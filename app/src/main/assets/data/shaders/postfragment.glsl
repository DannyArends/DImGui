#version 450
#extension GL_ARB_separate_shader_objects : enable

layout(binding = 0) uniform sampler2D hdrSampler;
layout(location = 0) in vec2 fragTexCoord;
layout(location = 0) out vec4 outColor;

vec3 tonemapACES(vec3 x) {
    float a = 2.51;
    float b = 0.03;
    float c = 2.43;
    float d = 0.59;
    float e = 0.14;
    return (x * (a * x + b)) / (x * (c * x + d) + e);
}

void main() {
    vec3 hdrColor = texture(hdrSampler, fragTexCoord).rgb;
    vec3 tonemappedColor = tonemapACES(hdrColor);
    outColor = vec4(pow(tonemappedColor, vec3(1.0 / 2.2)), 1.0);
}