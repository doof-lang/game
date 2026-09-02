#version 300 es

precision highp float;

in vec3 prismBarycentric;
flat in float prismId;
flat in float prismDepth;
out vec4 fragmentColor;

uniform float doofTime;

void main() {
  float edgeDistance = min(min(prismBarycentric.x, prismBarycentric.y), prismBarycentric.z);
  float edge = 1.0 - smoothstep(0.012, 0.085, edgeDistance);
  float razor = 1.0 - smoothstep(0.0, 0.018, edgeDistance);
  float interior = smoothstep(0.0, 0.22, edgeDistance);
  float shimmer = 0.5 + 0.5 * sin(doofTime * 2.0 + prismId * 0.61);
  float hue = prismId * 0.173 + doofTime * 0.18;
  vec3 spectral = 0.56 + 0.44 * cos(hue + vec3(0.1, 2.15, 4.3));
  float facet = dot(prismBarycentric, vec3(0.18, 0.72, 0.42));
  vec3 glass = mix(spectral * 0.18, spectral * (0.45 + facet * 0.55), interior);
  vec3 color = glass + spectral * edge * (0.9 + shimmer * 0.42) + vec3(0.55, 0.72, 1.0) * razor * 0.38;
  float depthFade = smoothstep(0.0, 0.12, prismDepth);
  float alpha = (0.035 + interior * 0.12 + edge * 0.4 + razor * 0.25) * depthFade;
  fragmentColor = vec4(color, alpha);
}
