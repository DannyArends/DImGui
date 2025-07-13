#version 450
#extension GL_ARB_separate_shader_objects : enable

layout (binding = 0) uniform sampler2D hdrSampler;  // Binds your resolved HDR texture from the first pass
layout (location = 0) out vec4 outColor;            // Output to the swapchain image

// Basic ACES Tonemapping operator
vec3 tonemapACES(vec3 x) {
    float a = 2.51;
    float b = 0.03;
    float c = 2.43;
    float d = 0.59;
    float e = 0.14;
    return (x * (a * x + b)) / (x * (c * x + d) + e);
}

void main() {
    vec3 hdrColor = texture(hdrSampler, gl_FragCoord.xy / vec2(textureSize(hdrSampler, 0))).rgb;
    vec3 tonemappedColor = tonemapACES(hdrColor);
    vec3 finalColor = pow(tonemappedColor, vec3(1.0 / 2.2));
    outColor = vec4(finalColor, 1.0); // Output the final LDR color
}
