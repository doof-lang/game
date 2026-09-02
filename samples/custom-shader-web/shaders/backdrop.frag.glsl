#version 300 es

precision highp float;

in vec2 screenPosition;
out vec4 fragmentColor;

uniform float doofTime;
uniform vec2 doofPointer;

float hash(vec2 point) {
  return fract(sin(dot(point, vec2(127.1, 311.7))) * 43758.5453123);
}

void main() {
  vec2 uv = screenPosition * 0.5 + 0.5;
  vec2 fieldCenter = vec2(0.69, 0.5) + (doofPointer - 0.5) * vec2(0.055, 0.045);
  vec2 fieldDelta = (uv - fieldCenter) * vec2(1.0, 1.28);
  float fieldRadius = length(fieldDelta);
  float vignette = smoothstep(1.02, 0.16, length((uv - 0.5) * vec2(1.12, 0.88)));
  float core = exp(-fieldRadius * 3.6);
  float halo = exp(-abs(fieldRadius - 0.255) * 18.0);
  float outerHalo = exp(-abs(fieldRadius - 0.43) * 28.0);
  float spectral = 0.5 + 0.5 * sin(atan(fieldDelta.y, fieldDelta.x) * 3.0 + fieldRadius * 21.0 - doofTime * 0.8);
  vec2 gridUv = vec2(uv.x * 52.0, uv.y * 30.0);
  vec2 gridDistance = abs(fract(gridUv) - 0.5);
  float grid = 1.0 - smoothstep(0.46, 0.5, max(gridDistance.x, gridDistance.y));
  vec2 starUv = fract(gridUv * 1.7 + vec2(doofTime * 0.015, 0.0)) - 0.5;
  float star = step(0.988, hash(floor(gridUv * 1.7)))
    * hash(floor(gridUv * 3.1))
    * (1.0 - smoothstep(0.025, 0.085, length(starUv)));

  vec3 base = mix(vec3(0.004, 0.006, 0.022), vec3(0.018, 0.035, 0.082), uv.y);
  base += vec3(0.018, 0.038, 0.095) * vignette;
  base += mix(vec3(0.12, 0.025, 0.19), vec3(0.0, 0.22, 0.26), spectral) * core * 0.54;
  base += mix(vec3(0.17, 0.04, 0.24), vec3(0.01, 0.27, 0.34), spectral) * halo * 0.18;
  base += vec3(0.13, 0.19, 0.35) * outerHalo * 0.055;
  base += vec3(0.11, 0.17, 0.29) * grid * 0.045 * vignette;
  base += vec3(0.52, 0.72, 1.0) * star * 0.72 * vignette;
  base *= mix(0.36, 1.0, vignette);
  fragmentColor = vec4(base, 1.0);
}
