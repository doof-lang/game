// HLSL port of asteroid.metal for the Windows D3D11 backend. Vertex attribute N
// is read through the TEXCOORDN semantic; the scene block is register b2.

// Shared by the asteroid and backdrop pipelines. Must match sceneUniformBytes()
// in asteroid_shader.do.
cbuffer Scene : register(b2) {
  float4 row0;              // viewProjection
  float4 row1;
  float4 row2;
  float4 row3;
  float4 inverseRow0;       // inverse viewProjection, for backdrop view rays
  float4 inverseRow1;
  float4 inverseRow2;
  float4 inverseRow3;
  float4 cameraTime;        // xyz: camera position, w: time in seconds
  float4 sunDirection;      // xyz: direction toward the sun
  float4 sunColor;          // rgb: sun color, w: exposure
  float4 planet;            // xyz: planet center, w: planet radius
};

// ---------------------------------------------------------------------------
// Noise

float hash31(float3 p) {
  p = frac(p * 0.1031);
  p += dot(p, p.yzx + 33.33);
  return frac((p.x + p.y) * p.z);
}

float3 hash33(float3 p) {
  p = frac(p * float3(0.1031, 0.1030, 0.0973));
  p += dot(p, p.yxz + 33.33);
  return frac((p.xxy + p.yxx) * p.zyx);
}

float valueNoise(float3 p) {
  float3 i = floor(p);
  float3 f = smoothstep(0.0, 1.0, frac(p));
  float n000 = hash31(i + float3(0.0, 0.0, 0.0));
  float n100 = hash31(i + float3(1.0, 0.0, 0.0));
  float n010 = hash31(i + float3(0.0, 1.0, 0.0));
  float n110 = hash31(i + float3(1.0, 1.0, 0.0));
  float n001 = hash31(i + float3(0.0, 0.0, 1.0));
  float n101 = hash31(i + float3(1.0, 0.0, 1.0));
  float n011 = hash31(i + float3(0.0, 1.0, 1.0));
  float n111 = hash31(i + float3(1.0, 1.0, 1.0));
  return lerp(
    lerp(lerp(n000, n100, f.x), lerp(n010, n110, f.x), f.y),
    lerp(lerp(n001, n101, f.x), lerp(n011, n111, f.x), f.y),
    f.z
  );
}

float fbm(float3 p, int octaves) {
  float sum = 0.0;
  float amplitude = 0.5;
  for (int i = 0; i < octaves; i++) {
    sum += valueNoise(p) * amplitude;
    p = p * 2.03 + float3(1.7, 9.2, 4.1);
    amplitude *= 0.5;
  }
  return sum;
}

float3 rotateAxis(float3 p, float3 axis, float angle) {
  float s = sin(angle);
  float c = cos(angle);
  return p * c + cross(axis, p) * s + axis * dot(axis, p) * (1.0 - c);
}

float4 mulScene(float4 v) {
  return float4(dot(row0, v), dot(row1, v), dot(row2, v), dot(row3, v));
}

float4 mulInverse(float4 v) {
  return float4(dot(inverseRow0, v), dot(inverseRow1, v), dot(inverseRow2, v), dot(inverseRow3, v));
}

float3 toneMap(float3 color, float exposure) {
  return 1.0 - exp(-color * exposure);
}

// 0 when the planet fully blocks the sun, 1 when it doesn't, soft at the edge.
float planetShadow(float3 p) {
  float3 toPlanet = planet.xyz - p;
  float along = dot(toPlanet, sunDirection.xyz);
  if (along <= 0.0) {
    return 1.0;
  }
  float miss = length(toPlanet - sunDirection.xyz * along);
  float radius = planet.w;
  return smoothstep(radius * 0.96, radius * 1.04, miss);
}

// ---------------------------------------------------------------------------
// Asteroids

struct VertexIn {
  float3 position : TEXCOORD0;
  float4 orbit : TEXCOORD1;    // radius, start angle, height, size
  float4 axisSpin : TEXCOORD2; // spin axis, spin speed
  float4 shape : TEXCOORD3;    // orbit speed, noise seed, stretch y, stretch z
  float4 albedo : TEXCOORD4;   // rgb, metallic
};

struct VertexOut {
  float4 position : SV_Position;
  float3 world : TEXCOORD0;
  float3 normal : TEXCOORD1;
  float3 local : TEXCOORD2;
  float3 albedo : TEXCOORD3;
  float metallic : TEXCOORD4;
  float crater : TEXCOORD5;
  float seed : TEXCOORD6;
};

struct Surface {
  float radius;
  float crater;
};

// Radius of the rock along a unit direction: lumpy noise plus a few craters.
Surface rockSurface(float3 dir, float seed) {
  float lumps = fbm(dir * 1.5 + seed, 3) - 0.5;
  // Cellular craters: only some cells hold one, so the surface isn't pitted all over.
  float3 q = dir * 1.9 + seed * 0.37;
  float3 cell = floor(q);
  float x = 8.0;
  for (int z = -1; z <= 1; z++) {
    for (int y = -1; y <= 1; y++) {
      for (int w = -1; w <= 1; w++) {
        float3 c = cell + float3(w, y, z);
        float3 h = hash33(c);
        if (h.y < 0.55) {
          continue;
        }
        x = min(x, length(q - (c + h)) / (0.26 + h.x * 0.3));
      }
    }
  }
  float bowl = x < 1.0 ? (x * x - 1.0) * 0.085 : 0.0;
  float rimOffset = (x - 1.0) / 0.22;
  float rim = exp(-rimOffset * rimOffset) * 0.035;
  Surface surface;
  surface.radius = 1.0 + lumps * 0.72 + bowl + rim;
  surface.crater = saturate(1.0 - x);
  return surface;
}

VertexOut asteroid_vertex(VertexIn input) {
  float time = cameraTime.w;
  float seed = input.shape.y;
  float3 stretch = float3(1.0, input.shape.z, input.shape.w);

  // Rebuild the displaced surface around this vertex to get a matching normal.
  float3 dir = normalize(input.position);
  float3 helper = abs(dir.y) < 0.99 ? float3(0.0, 1.0, 0.0) : float3(1.0, 0.0, 0.0);
  float3 tangent = normalize(cross(dir, helper));
  float3 bitangent = cross(dir, tangent);
  const float eps = 0.012;
  float3 dirA = normalize(dir + tangent * eps);
  float3 dirB = normalize(dir + bitangent * eps);
  Surface center = rockSurface(dir, seed);
  float3 p0 = dir * center.radius * stretch;
  float3 pA = dirA * rockSurface(dirA, seed).radius * stretch;
  float3 pB = dirB * rockSurface(dirB, seed).radius * stretch;
  float3 localNormal = normalize(cross(pA - p0, pB - p0));
  if (dot(localNormal, dir) < 0.0) {
    localNormal = -localNormal;
  }

  float3 axis = normalize(input.axisSpin.xyz);
  float spin = time * input.axisSpin.w + seed;
  float3 spun = rotateAxis(p0 * input.orbit.w, axis, spin);

  float angle = input.orbit.y + time * input.shape.x;
  float3 orbitCenter = float3(cos(angle) * input.orbit.x, input.orbit.z, sin(angle) * input.orbit.x);
  float3 world = orbitCenter + spun;

  VertexOut output;
  output.position = mulScene(float4(world, 1.0));
  output.world = world;
  output.normal = rotateAxis(localNormal, axis, spin);
  output.local = p0;
  output.albedo = input.albedo.rgb;
  output.metallic = input.albedo.w;
  output.crater = center.crater;
  output.seed = seed;
  return output;
}

float4 asteroid_fragment(VertexOut input) : SV_Target {
  float3 grit = float3(
    valueNoise(input.local * 14.0 + input.seed),
    valueNoise(input.local * 14.0 + input.seed + 19.1),
    valueNoise(input.local * 14.0 + input.seed + 41.7)
  ) - 0.5;
  float3 n = normalize(input.normal + grit * 0.22);
  float3 l = sunDirection.xyz;
  float3 v = normalize(cameraTime.xyz - input.world);

  float mineral = fbm(input.local * 5.0 + input.seed * 2.4, 3);
  float3 albedo = input.albedo * lerp(0.7, 1.25, mineral);
  albedo *= lerp(1.0, 0.8, input.crater);

  float shadow = planetShadow(input.world);
  float3 sun = sunColor.rgb * shadow;
  float diffuse = max(dot(n, l), 0.0);
  float specular = pow(max(dot(n, normalize(l + v)), 0.0), 40.0) * lerp(0.04, 0.6, input.metallic) * step(0.0, dot(n, l));

  // Light reflected off the planet's day side.
  float3 toPlanet = normalize(planet.xyz - input.world);
  float planetLit = saturate(dot(-toPlanet, l) * 0.5 + 0.5);
  float3 planetShine = float3(0.55, 0.42, 0.30) * max(dot(n, toPlanet), 0.0) * planetLit * 0.5;

  // Dusty rims light up when the rock is between the camera and the sun.
  float backlight = pow(saturate(dot(-v, l)), 3.0);
  float rim = pow(1.0 - saturate(dot(n, v)), 3.0) * (0.2 + backlight * 1.4);

  float3 ambient = float3(0.05, 0.05, 0.085);
  float3 color = albedo * (ambient + sun * diffuse + planetShine)
    + sun * specular
    + sun * rim * 0.45;
  return float4(toneMap(color, sunColor.w), 1.0);
}

// ---------------------------------------------------------------------------
// Backdrop: stars, nebula, sun and the ringed planet, drawn as one full-screen
// triangle that writes real depth where the planet is.

struct BackdropIn {
  float2 position : TEXCOORD0;
};

struct BackdropOut {
  float4 position : SV_Position;
  float2 ndc : TEXCOORD0;
};

struct BackdropFragment {
  float4 color : SV_Target0;
  float depth : SV_Depth;
};

BackdropOut backdrop_vertex(BackdropIn input) {
  BackdropOut output;
  output.position = float4(input.position, 0.0, 1.0);
  output.ndc = input.position;
  return output;
}

float3 starField(float3 dir, float scale, float threshold) {
  float3 q = dir * scale;
  float3 cell = floor(q);
  float3 h = hash33(cell);
  if (h.x < threshold) {
    return float3(0.0, 0.0, 0.0);
  }
  float3 star = cell + 0.25 + h * 0.5;
  float d = length(q - star);
  float brightness = pow((h.x - threshold) / (1.0 - threshold), 2.0);
  float3 tint = lerp(float3(0.7, 0.8, 1.0), float3(1.0, 0.85, 0.7), h.y);
  return tint * brightness * smoothstep(0.12, 0.0, d) * 3.0;
}

float3 nebula(float3 dir) {
  // A soft band of gas across the sky, broken up by noise.
  float3 bandNormal = normalize(float3(0.25, 1.0, -0.35));
  float bandOffset = dot(dir, bandNormal) / 0.38;
  float band = exp(-bandOffset * bandOffset);
  float3 warp = float3(fbm(dir * 2.0, 4), fbm(dir * 2.0 + 7.3, 4), fbm(dir * 2.0 + 13.1, 4));
  float gas = fbm(dir * 3.2 + warp * 1.8, 5);
  float dust = smoothstep(0.45, 0.75, fbm(dir * 5.0 + warp * 2.4 + 3.0, 4));
  float3 violet = float3(0.30, 0.10, 0.42);
  float3 teal = float3(0.04, 0.28, 0.36);
  float3 color = lerp(violet, teal, smoothstep(0.35, 0.7, warp.x)) * pow(gas, 2.2) * 1.6;
  color += float3(0.02, 0.025, 0.05);
  return color * band * (1.0 - dust * 0.8);
}

float3 planetColor(float3 n, float3 l, float3 v, float time) {
  // Latitude bands, stirred by noise that drifts with time.
  float3 swirl = float3(fbm(n * 4.0 + float3(time * 0.01, 0.0, 0.0), 4), 0.0, 0.0);
  float latitude = n.y * 7.0 + swirl.x * 1.6 + fbm(n * float3(2.0, 18.0, 2.0), 3) * 0.6;
  float bands = sin(latitude) * 0.5 + 0.5;
  float3 cream = float3(0.86, 0.74, 0.56);
  float3 rust = float3(0.62, 0.36, 0.22);
  float3 dark = float3(0.30, 0.20, 0.16);
  float3 albedo = lerp(rust, cream, bands);
  albedo = lerp(albedo, dark, smoothstep(0.6, 0.9, fbm(n * 9.0 + swirl * 3.0, 3)) * 0.5);

  float nl = dot(n, l);
  float diffuse = saturate(nl * 0.9 + 0.1);
  float terminator = smoothstep(-0.15, 0.2, nl);
  float fresnel = pow(1.0 - saturate(dot(n, v)), 3.0);
  float3 atmosphere = float3(0.45, 0.62, 1.0) * fresnel * terminator * 0.9;
  return albedo * diffuse * terminator + atmosphere;
}

BackdropFragment backdrop_fragment(BackdropOut input) {
  float4 farPoint = mulInverse(float4(input.ndc, 1.0, 1.0));
  float3 origin = cameraTime.xyz;
  float3 dir = normalize(farPoint.xyz / farPoint.w - origin);
  float3 l = sunDirection.xyz;
  float3 sunLight = sunColor.rgb;
  float time = cameraTime.w;

  BackdropFragment output;
  output.depth = 0.99999;

  // Ray against the planet sphere.
  float3 oc = origin - planet.xyz;
  float radius = planet.w;
  float b = dot(oc, dir);
  float c = dot(oc, oc) - radius * radius;
  float discriminant = b * b - c;
  float closest = sqrt(max(dot(oc, oc) - b * b, 0.0));

  float3 color;
  if (discriminant > 0.0 && -b - sqrt(discriminant) > 0.0) {
    float t = -b - sqrt(discriminant);
    float3 hit = origin + dir * t;
    float3 n = normalize(hit - planet.xyz);
    color = planetColor(n, l, -dir, time) * sunLight;
    float4 clipPosition = mulScene(float4(hit, 1.0));
    output.depth = clipPosition.z / clipPosition.w;
  } else {
    color = nebula(dir) + starField(dir, 240.0, 0.965) + starField(dir, 90.0, 0.985) * 1.5;
    float s = max(dot(dir, l), 0.0);
    color += sunLight * (pow(s, 3000.0) * 40.0 + pow(s, 180.0) * 1.2 + pow(s, 12.0) * 0.12);
    // Thin atmosphere halo around the planet's limb, brightest toward the sun.
    if (b < 0.0) {
      float halo = exp(-(closest - radius) / (radius * 0.035));
      float facing = saturate(dot(normalize(oc + dir * -b), l) * 0.8 + 0.3);
      color += float3(0.35, 0.55, 1.0) * halo * facing * 0.8;
    }
  }

  output.color = float4(toneMap(color, sunColor.w), 1.0);
  return output;
}
