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

struct Uniforms {
  Matrix viewProjection;
  Matrix lightViewProjection;
  float4 lightDirection;
  float4 shadow;
};

struct VertexOut {
  float4 position [[position]];
  float3 world;
  float3 normal;
  float4 color;
  float4 lightClip;
};

float4 mul_matrix(Matrix matrix, float4 value) {
  return float4(
    dot(matrix.row0, value),
    dot(matrix.row1, value),
    dot(matrix.row2, value),
    dot(matrix.row3, value)
  );
}

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

float shadow_tap(
  depth2d<float> shadowMap,
  sampler compareSampler,
  float2 uv,
  float depth,
  float2 offset,
  float2 depthGradient,
  float bias
) {
  float tapDepth = depth + dot(depthGradient, offset) - bias;
  return shadowMap.sample_compare(compareSampler, uv + offset, tapDepth);
}

float shadow_visibility(
  depth2d<float> shadowMap,
  sampler shadowSampler,
  float3 projected,
  float3 normal,
  float3 lightDir,
  constant Uniforms& uniforms
) {
  float2 uv = float2(projected.x * 0.5 + 0.5, 1.0 - (projected.y * 0.5 + 0.5));
  if (!all(uv >= float2(0.0)) || !all(uv <= float2(1.0)) || projected.z < 0.0 || projected.z > 1.0) {
    return 1.0;
  }

  float normalLight = max(dot(normal, lightDir), 0.0);
  float bias = max(uniforms.shadow.x, uniforms.shadow.z * (1.0 - normalLight));
  float2 texel = 1.0 / float2(float(shadowMap.get_width()), float(shadowMap.get_height()));
  float radius = max(uniforms.shadow.w, 0.0);
  float2 depthGradient = shadow_depth_gradient(uv, projected.z);
  constexpr sampler compareSampler(
    coord::normalized,
    filter::linear,
    address::clamp_to_edge,
    compare_func::less_equal
  );

  float lit = 0.0;
  lit += shadow_tap(shadowMap, compareSampler, uv, projected.z, float2(-0.942, -0.399) * texel * radius, depthGradient, bias);
  lit += shadow_tap(shadowMap, compareSampler, uv, projected.z, float2(0.945, -0.769) * texel * radius, depthGradient, bias);
  lit += shadow_tap(shadowMap, compareSampler, uv, projected.z, float2(-0.094, -0.929) * texel * radius, depthGradient, bias);
  lit += shadow_tap(shadowMap, compareSampler, uv, projected.z, float2(0.345, 0.294) * texel * radius, depthGradient, bias);
  lit += shadow_tap(shadowMap, compareSampler, uv, projected.z, float2(-0.915, 0.458) * texel * radius, depthGradient, bias);
  lit += shadow_tap(shadowMap, compareSampler, uv, projected.z, float2(-0.382, 0.276) * texel * radius, depthGradient, bias);
  lit += shadow_tap(shadowMap, compareSampler, uv, projected.z, float2(0.975, 0.756) * texel * radius, depthGradient, bias);
  lit += shadow_tap(shadowMap, compareSampler, uv, projected.z, float2(0.443, -0.975) * texel * radius, depthGradient, bias);
  lit += shadow_tap(shadowMap, compareSampler, uv, projected.z, float2(0.537, -0.474) * texel * radius, depthGradient, bias);
  lit += shadow_tap(shadowMap, compareSampler, uv, projected.z, float2(-0.264, -0.418) * texel * radius, depthGradient, bias);
  lit += shadow_tap(shadowMap, compareSampler, uv, projected.z, float2(0.792, 0.191) * texel * radius, depthGradient, bias);
  lit += shadow_tap(shadowMap, compareSampler, uv, projected.z, float2(-0.242, 0.998) * texel * radius, depthGradient, bias);
  lit += shadow_tap(shadowMap, compareSampler, uv, projected.z, float2(-0.814, -0.855) * texel * radius, depthGradient, bias);
  lit += shadow_tap(shadowMap, compareSampler, uv, projected.z, float2(0.199, 0.786) * texel * radius, depthGradient, bias);
  lit += shadow_tap(shadowMap, compareSampler, uv, projected.z, float2(-0.601, -0.112) * texel * radius, depthGradient, bias);
  lit += shadow_tap(shadowMap, compareSampler, uv, projected.z, float2(0.084, -0.307) * texel * radius, depthGradient, bias);

  return mix(1.0 - uniforms.shadow.y, 1.0, lit / 16.0);
}

vertex VertexOut shadow_scene_vertex(VertexIn in [[stage_in]], constant Uniforms& uniforms [[buffer(1)]]) {
  float4 world = float4(in.position, 1.0);
  VertexOut out;
  out.position = mul_matrix(uniforms.viewProjection, world);
  out.world = in.position;
  out.normal = normalize(in.normal);
  out.color = in.color;
  out.lightClip = mul_matrix(uniforms.lightViewProjection, world);
  return out;
}

fragment float4 shadow_scene_fragment(
  VertexOut in [[stage_in]],
  constant Uniforms& uniforms [[buffer(0)]],
  depth2d<float> shadowMap [[texture(0)]],
  sampler shadowSampler [[sampler(0)]]
) {
  float3 n = normalize(in.normal);
  float3 lightDir = normalize(-uniforms.lightDirection.xyz);
  float diffuse = max(dot(n, lightDir), 0.0);

  float3 projected = in.lightClip.xyz / max(in.lightClip.w, 0.0001);
  float shadowFactor = shadow_visibility(shadowMap, shadowSampler, projected, n, lightDir, uniforms);

  float lightAmount = 0.28 + diffuse * 0.78 * shadowFactor;
  float3 color = in.color.rgb * lightAmount;
  return float4(color, in.color.a);
}
