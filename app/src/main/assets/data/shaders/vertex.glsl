// DImGui - VERTEX SHADER
// Copyright Danny Arends 2021
// Distributed under the GNU General Public License, Version 3
// See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html

#version 460

struct Light {
  vec4 position;
  vec4 intensity;
  vec4 direction;
  vec4 properties;    // [ambient, attenuation, angle]
};

struct Bone {
  mat4 offset;
};

layout(std140, binding = 0) uniform UniformBufferObject {
    vec4 position;    // Scene Camera Position
    mat4 scene;       // Scene Camera adjustment
    mat4 view;        // View matrix
    mat4 proj;        // Projection matrix
    mat4 ori;         // Screen orientation
    Light[4] lights;  // Scene lights
    uint nlights;     // Number of actual lights
} ubo;

layout (std140, binding = 1) readonly buffer BoneMatrices {
    Bone transforms[];
} boneSSBO;

/*
layout(binding = 2) uniform sampler2D texureSampler[];
layout(binding = 3) uniform sampler2DShadow shadowMap;
*/

layout(std140, binding = 4) uniform LightSpaceMatrices {
    mat4 lightProjView;
} lightUbo;


// Per Vertex attributes
layout(location = 0) in vec3 inPosition;          /// Vertex position
layout(location = 1) in vec4 inColor;             /// Color
layout(location = 2) in vec3 inNormal;            /// Normal
layout(location = 3) in vec2 inTexCoord;          /// Texture coordinate
layout(location = 4) in vec3 inTangent;           /// Tangent vector
layout(location = 5) in uvec4 inBones;            /// assimp: BoneIDs
layout(location = 6) in vec4 inWeights;           /// assimp: BoneWeights
layout(location = 7) in int Tid;                  /// Texture ID
layout(location = 8) in int Nid;                  /// Normal Map ID

// Per Instance attributes
layout(location = 9) in mat4 instance;

// Output to Fragment shader
layout(location = 0) out vec3 fragPosWorld;       /// Fragment world position
layout(location = 1) out vec4 fragPosLightSpace;  /// Fragment lightspace position
layout(location = 2) out vec4 fragColor;          /// Fragment color
layout(location = 3) out vec3 fragNormal;         /// Fragment normal
layout(location = 4) out vec2 fragTexCoord;       /// Texture coordinate
layout(location = 5) flat out int fragTid;        /// Texture ID
layout(location = 6) flat out int fragNid;        /// Normal Map ID
layout(location = 7) out mat3 fragTBN;            /// Tangent, Bitangent, Normal matrix

vec3 illuminate(Light light, vec4 position, vec3 normal) {
  float attenuation = 1.0;
  vec3 s;
  if (light.position.w == 0.0) {
    // Directional lighting
    s = normalize( light.position.xyz );
  } else {
    // Point lighting
    s = normalize( light.position.xyz - position.xyz );
    float l = abs(length( light.position.xyz - position.xyz ));
    attenuation = 1.0 / (1.0 + light.properties[1] * pow(l, 2.0));

    // Cone lighting
    float lAngle = degrees(acos(dot(-s, normalize(light.direction.xyz))));
    if (lAngle >= light.properties[2] - 1.0f) { attenuation = 0.3; }
    if (lAngle >= light.properties[2]) { attenuation = 0.0; }
  }
  vec3 r = reflect( -s, normal );
  float sDotN = max( dot( s, normal ), 0.0 );

  vec3 ambientCol = light.intensity.rgb * inColor.rgb * light.properties[0];
  vec3 diffuseCol = light.intensity.rgb * inColor.rgb * sDotN;
  vec3 specularCol = vec3( 0.0 );
  if (sDotN > 0.0 && light.position.w > 0.0) {
    specularCol = light.intensity.rgb * inColor.rgb * pow(max(dot(s, r), 0.0), inColor[3]);
  }
  return ambientCol + attenuation * (diffuseCol + specularCol);
}

void main() {
  /// Compute bone effects on vertex
  bool hasbone = false;
  vec4 bonepos = vec4(0.0f, 0.0f, 0.0f, 0.0f);
  for (int i = 0; i < 4; i++) {
    float weight = inWeights[i];
    if(weight > 0.0f) {
      uint boneID = inBones[i];
      mat4 boneTransform = boneSSBO.transforms[boneID].offset;
      bonepos += (boneTransform * vec4(inPosition, 1.0f)) * weight;
      hasbone = true;
    }
  }
  vec4 finalPosition = vec4(inPosition, 1.0f);
  if(hasbone){ finalPosition = bonepos; }

  /// Compute our model matrix
  mat4 model = ubo.scene * instance;
  // Calculate the world-space normal and tangent
  vec3 N = normalize(mat3(instance) * inNormal);
  vec3 T = normalize(mat3(instance) * inTangent);
  vec3 B = normalize(cross(N, T));
  mat4 nMatrix = transpose(inverse(instance));

  /// World position & point size
  vec4 worldPos = model * finalPosition;
  gl_Position = (ubo.ori * (ubo.proj * ubo.view * model)) * finalPosition;
  gl_PointSize = 2.0f;

  /// Lighting
  vec3 transformedNormal = normalize(vec3(nMatrix * vec4(inNormal, 0.0)));
  vec3 fcol = vec3( 0 );
  for(int i=0; i < ubo.nlights; ++i) {
    fcol += illuminate(ubo.lights[i], worldPos, transformedNormal);
  }

  /// Transfer data to fragment shader
  fragPosWorld = worldPos.xyz;
  fragPosLightSpace = lightUbo.lightProjView * worldPos;

  fragColor = vec4(fcol, 1.0f);
  fragNormal = inNormal;
  fragTexCoord = inTexCoord;
  fragTid = Tid;
  fragNid = Nid;
  fragTBN = mat3(T, B, N); 
}

