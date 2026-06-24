#include <metal_stdlib>
using namespace metal;

struct VertexIn {
  float3 position [[attribute(0)]];
  float3 normal [[attribute(1)]];
  float seed [[attribute(2)]];
  float4 centerRadius [[attribute(3)]];
  float4 axisSpin [[attribute(4)]];
  float4 orbitSeedColorR [[attribute(5)]];
  float4 colorGb [[attribute(6)]];
};

struct Uniforms {
  float4 row0;
  float4 row1;
  float4 row2;
  float4 row3;
  float4 params;
};

struct VertexOut {
  float4 position [[position]];
  float3 worldNormal;
  float3 localNormal;
  float3 color;
  float seed;
};

float hash31(float3 p) {
  p = fract(p * 0.1031);
  p += dot(p, p.yzx + 33.33);
  return fract((p.x + p.y) * p.z);
}

float valueNoise(float3 p) {
  float3 i = floor(p);
  float3 f = smoothstep(0.0, 1.0, fract(p));
  float n000 = hash31(i + float3(0.0, 0.0, 0.0));
  float n100 = hash31(i + float3(1.0, 0.0, 0.0));
  float n010 = hash31(i + float3(0.0, 1.0, 0.0));
  float n110 = hash31(i + float3(1.0, 1.0, 0.0));
  float n001 = hash31(i + float3(0.0, 0.0, 1.0));
  float n101 = hash31(i + float3(1.0, 0.0, 1.0));
  float n011 = hash31(i + float3(0.0, 1.0, 1.0));
  float n111 = hash31(i + float3(1.0, 1.0, 1.0));
  return mix(
    mix(mix(n000, n100, f.x), mix(n010, n110, f.x), f.y),
    mix(mix(n001, n101, f.x), mix(n011, n111, f.x), f.y),
    f.z
  );
}

float3 rotateAxis(float3 p, float3 axis, float angle) {
  float s = sin(angle);
  float c = cos(angle);
  return p * c + cross(axis, p) * s + axis * dot(axis, p) * (1.0 - c);
}

vertex VertexOut asteroid_vertex(VertexIn in [[stage_in]], constant Uniforms& uniforms [[buffer(2)]]) {
  float t = uniforms.params.x;
  float3 axis = normalize(in.axisSpin.xyz);
  float spin = t * in.axisSpin.w + in.orbitSeedColorR.x;
  float seed = in.orbitSeedColorR.y + in.seed;
  float lumpy = valueNoise(in.position * 2.6 + seed) * 0.42 + valueNoise(in.position * 6.7 + seed * 1.7) * 0.16;
  float3 localNormal = normalize(in.normal + (valueNoise(in.position * 8.0 + seed) - 0.5) * 0.36);
  float3 local = in.position * in.centerRadius.w * (0.82 + lumpy);
  float3 spun = rotateAxis(local, axis, spin);
  float orbit = in.orbitSeedColorR.x + t * 0.08;
  float3 center = in.centerRadius.xyz + float3(cos(orbit) * 0.22, sin(orbit * 1.7) * 0.12, sin(orbit) * 0.22);
  float4 world = float4(center + spun, 1.0);

  VertexOut out;
  out.position = float4(
    dot(uniforms.row0, world),
    dot(uniforms.row1, world),
    dot(uniforms.row2, world),
    dot(uniforms.row3, world)
  );
  out.worldNormal = rotateAxis(localNormal, axis, spin);
  out.localNormal = in.normal;
  out.color = float3(in.orbitSeedColorR.z, in.colorGb.x, in.colorGb.y);
  out.seed = seed;
  return out;
}

fragment float4 asteroid_fragment(VertexOut in [[stage_in]], constant Uniforms& uniforms [[buffer(0)]]) {
  float3 n = normalize(in.worldNormal + (valueNoise(in.localNormal * 10.0 + in.seed) - 0.5) * 0.28);
  float3 light = normalize(float3(0.36, 0.62, 0.70));
  float diffuse = max(dot(n, light), 0.0);
  float rim = pow(1.0 - max(dot(n, normalize(float3(0.0, 0.0, 1.0))), 0.0), 2.0);
  float mineral = valueNoise(in.localNormal * 18.0 + in.seed * 2.4);
  float3 iron = float3(0.72, 0.50, 0.38);
  float3 slate = float3(0.35, 0.38, 0.42);
  float3 base = mix(in.color, mix(slate, iron, mineral), 0.42);
  float lighting = 0.18 + diffuse * 0.86 + rim * 0.20;
  return float4(base * lighting, 1.0);
}
