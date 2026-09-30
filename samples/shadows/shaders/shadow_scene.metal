#include <metal_stdlib>
using namespace metal;

struct VertexIn {
  float3 position [[attribute(0)]];
  float3 normal [[attribute(1)]];
  float4 color [[attribute(2)]];
};

struct Matrix {
  float4 row0;
  float4 row1;
  float4 row2;
  float4 row3;
};

// Must match objectUniformBytes() in main.do.
struct Uniforms {
  Matrix model;
  Matrix viewProjection;
  Matrix lightViewProjection;
  float4 lightDirection;  // xyz: direction the light travels, w: normal offset (world units)
  float4 lightColor;      // rgb: sun color, w: ambient strength
  float4 cameraPosition;  // xyz: eye position, w: fog density
  float4 fogColor;        // rgb: fog / horizon color
  float4 shadow;          // x: min bias, y: strength, z: slope bias, w: PCF radius in texels
  float4 material;        // x: specular, y: shininess, z: emissive, w: checker amount
};

struct VertexOut {
  float4 position [[position]];
  float3 world;
  float3 normal;
  float4 color;
  float4 lightClip;
};

constant float3 SKY_AMBIENT = float3(0.46, 0.58, 0.78);
constant float3 GROUND_AMBIENT = float3(0.30, 0.25, 0.20);

constant float2 POISSON_DISK[16] = {
  float2(-0.942, -0.399), float2(0.945, -0.769), float2(-0.094, -0.929), float2(0.345, 0.294),
  float2(-0.915, 0.458), float2(-0.382, 0.276), float2(0.975, 0.756), float2(0.443, -0.975),
  float2(0.537, -0.474), float2(-0.264, -0.418), float2(0.792, 0.191), float2(-0.242, 0.998),
  float2(-0.814, -0.855), float2(0.199, 0.786), float2(-0.601, -0.112), float2(0.084, -0.307),
};

float4 mul_matrix(Matrix matrix, float4 value) {
  return float4(
    dot(matrix.row0, value),
    dot(matrix.row1, value),
    dot(matrix.row2, value),
    dot(matrix.row3, value)
  );
}

// Receiver-plane depth bias: how shadow-map depth changes per unit of uv, so
// wide PCF kernels on sloped surfaces don't self-shadow.
float2 shadow_depth_gradient(float2 uv, float depth) {
  float2 dx = dfdx(uv);
  float2 dy = dfdy(uv);
  float dzdx = dfdx(depth);
  float dzdy = dfdy(depth);
  float determinant = dx.x * dy.y - dx.y * dy.x;
  if (abs(determinant) < 0.0000001) {
    return float2(0.0);
  }
  return float2(
    (dy.y * dzdx - dx.y * dzdy) / determinant,
    (dx.x * dzdy - dy.x * dzdx) / determinant
  );
}

// Returns 0 (fully shadowed) .. 1 (fully lit).
float shadow_visibility(
  depth2d<float> shadowMap,
  float3 projected,
  float3 normal,
  float3 lightDir,
  constant Uniforms& uniforms
) {
  float2 uv = float2(projected.x * 0.5 + 0.5, 1.0 - (projected.y * 0.5 + 0.5));
  // Derivatives must be taken before any non-uniform early return.
  float2 depthGradient = shadow_depth_gradient(uv, projected.z);
  if (!all(uv >= float2(0.0)) || !all(uv <= float2(1.0)) || projected.z < 0.0 || projected.z > 1.0) {
    return 1.0;
  }

  float normalLight = max(dot(normal, lightDir), 0.0);
  float bias = max(uniforms.shadow.x, uniforms.shadow.z * (1.0 - normalLight));
  float2 texel = 1.0 / float2(float(shadowMap.get_width()), float(shadowMap.get_height()));
  float radius = max(uniforms.shadow.w, 0.0);
  constexpr sampler compareSampler(
    coord::normalized,
    filter::linear,
    address::clamp_to_edge,
    compare_func::less_equal
  );

  float lit = 0.0;
  for (int i = 0; i < 16; i++) {
    float2 offset = POISSON_DISK[i] * texel * radius;
    float tapDepth = projected.z + dot(depthGradient, offset) - bias;
    lit += shadowMap.sample_compare(compareSampler, uv + offset, tapDepth);
  }
  return lit / 16.0;
}

// Box-filtered checkerboard (1 unit tiles) that stays alias-free at grazing angles.
float filtered_checker(float2 p) {
  float2 w = max(fwidth(p), float2(0.0001));
  float2 i = 2.0 * (abs(fract((p - 0.5 * w) * 0.5) - 0.5) - abs(fract((p + 0.5 * w) * 0.5) - 0.5)) / w;
  return 0.5 - 0.5 * i.x * i.y;
}

vertex VertexOut shadow_scene_vertex(VertexIn in [[stage_in]], constant Uniforms& uniforms [[buffer(1)]]) {
  float4 world = mul_matrix(uniforms.model, float4(in.position, 1.0));
  VertexOut out;
  out.position = mul_matrix(uniforms.viewProjection, world);
  out.world = world.xyz;
  // Scene models only use rotation, translation and uniform scale.
  float3 normal = normalize(mul_matrix(uniforms.model, float4(in.normal, 0.0)).xyz);
  out.normal = normal;
  out.color = in.color;
  // Normal-offset bias: look up the shadow map from slightly above the surface,
  // more so at grazing light angles, to avoid acne on thin or sloped faces.
  float grazing = 1.0 - saturate(dot(normal, normalize(-uniforms.lightDirection.xyz)));
  float3 offsetWorld = world.xyz + normal * uniforms.lightDirection.w * (0.25 + grazing);
  out.lightClip = mul_matrix(uniforms.lightViewProjection, float4(offsetWorld, 1.0));
  return out;
}

fragment float4 shadow_scene_fragment(
  VertexOut in [[stage_in]],
  constant Uniforms& uniforms [[buffer(0)]],
  depth2d<float> shadowMap [[texture(0)]]
) {
  float3 n = normalize(in.normal);
  float3 lightDir = normalize(-uniforms.lightDirection.xyz);
  float3 viewDir = normalize(uniforms.cameraPosition.xyz - in.world);

  float3 base = in.color.rgb;
  float checker = filtered_checker(in.world.xz);
  base *= mix(1.0, 0.86, checker * uniforms.material.w);

  float3 projected = in.lightClip.xyz / max(in.lightClip.w, 0.0001);
  float visibility = shadow_visibility(shadowMap, projected, n, lightDir, uniforms);
  float shadowFactor = mix(1.0, visibility, uniforms.shadow.y);

  if (uniforms.material.z > 0.0) {
    return float4(base * uniforms.material.z, in.color.a);
  }

  float3 ambient = mix(GROUND_AMBIENT, SKY_AMBIENT, n.y * 0.5 + 0.5) * uniforms.lightColor.w;
  float diffuse = max(dot(n, lightDir), 0.0);
  float3 halfway = normalize(lightDir + viewDir);
  float specular = pow(max(dot(n, halfway), 0.0), max(uniforms.material.y, 1.0))
    * uniforms.material.x
    * step(0.0, dot(n, lightDir));
  float rim = pow(1.0 - max(dot(n, viewDir), 0.0), 3.0) * 0.12;

  float3 color = base * (ambient + uniforms.lightColor.rgb * diffuse * shadowFactor)
    + uniforms.lightColor.rgb * specular * shadowFactor
    + SKY_AMBIENT * rim;

  float distance = length(uniforms.cameraPosition.xyz - in.world);
  float fog = 1.0 - exp(-pow(distance * uniforms.cameraPosition.w, 2.0));
  color = mix(color, uniforms.fogColor.rgb, saturate(fog));
  return float4(color, in.color.a);
}
