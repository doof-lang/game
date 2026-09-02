#version 300 es

layout(location = 0) in vec2 position;
layout(location = 1) in vec3 barycentric;

out vec3 prismBarycentric;
flat out float prismId;
flat out float prismDepth;

uniform float doofTime;
uniform vec2 doofPointer;

const float PI = 3.14159265359;
const float TAU = 6.28318530718;

void main() {
  float id = float(gl_InstanceID);
  float ring = floor(id / 16.0);
  float spoke = mod(id, 16.0);
  float depth = fract(ring / 24.0 + doofTime * 0.055);
  float angle = spoke * (TAU / 16.0) + ring * 0.17 + doofTime * (0.12 + depth * 0.12);
  float radius = 0.018 + pow(depth, 1.24) * 0.79;
  float pulse = 0.92 + 0.08 * sin(doofTime * 2.3 + ring * 1.71);
  float scale = mix(0.014, 0.072, depth) * pulse;
  float rotation = angle - PI * 0.5 + sin(ring * 1.47 + doofTime * 0.7) * 0.31;
  mat2 rotate = mat2(cos(rotation), -sin(rotation), sin(rotation), cos(rotation));
  vec2 pointer = (doofPointer - 0.5) * vec2(0.10, 0.08);
  vec2 center = vec2(0.38 + cos(angle) * radius * 0.46, sin(angle) * radius * 0.77) + pointer;

  gl_Position = vec4(center + rotate * position * scale, 0.0, 1.0);
  prismBarycentric = barycentric;
  prismId = id + ring * 2.7;
  prismDepth = depth;
}
