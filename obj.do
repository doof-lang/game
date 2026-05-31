import { readText } from "std/fs"
import { sqrt } from "std/math"

import { SimpleMeshSpec } from "./mesh"
import { Color, Point, Point3 } from "./render"

const EPSILON = 0.000001

class ObjTexCoord {
  u: double = 0.0
  v: double = 0.0
}

class ObjVertexRef {
  positionIndex: int = 0
  uvIndex: int = -1
  normalIndex: int = -1
}

class ObjFace {
  vertices: ObjVertexRef[] = []
}

class ObjData {
  positions: Point3[] = []
  uvs: ObjTexCoord[] = []
  normals: Point3[] = []
  faces: ObjFace[] = []
}

export class ObjError {
  stage: string = ""
  line: int = 0
  message: string = ""
}

function objError(stage: string, line: int, message: string): ObjError {
  return ObjError {
    stage,
    line,
    message,
  }
}

function stripComment(line: string): string {
  marker := line.indexOf("#")
  if marker >= 0 {
    return line.substring(0, marker).trim()
  }
  return line.trim()
}

function splitWhitespace(text: string): string[] {
  tokens: string[] := []
  let current = ""
  normalized := text.replaceAll("\t", " ")

  for index of 0..<normalized.length {
    ch := normalized.charAt(index)
    if ch == ' ' {
      if current != "" {
        tokens.push(current)
        current = ""
      }
      continue
    }

    current += ch
  }

  if current != "" {
    tokens.push(current)
  }

  return tokens
}

function parseDoubleToken(token: string, lineNumber: int, source: string, label: string): Result<double, ObjError> {
  return case double.parse(token) {
    s: Success -> Success { value: s.value },
    f: Failure -> Failure {
      error: objError("parse", lineNumber, `${source}:${lineNumber}: invalid ${label} value "${token}"`)
    },
  }
}

function parseIntToken(token: string, lineNumber: int, source: string, label: string): Result<int, ObjError> {
  return case int.parse(token) {
    s: Success -> Success { value: s.value },
    f: Failure -> Failure {
      error: objError("parse", lineNumber, `${source}:${lineNumber}: invalid ${label} value "${token}"`)
    },
  }
}

function parsePosition(tokens: string[], lineNumber: int, source: string): Result<Point3, ObjError> {
  if tokens.length < 4 {
    return Failure {
      error: objError("parse", lineNumber, `${source}:${lineNumber}: expected three coordinates after v`)
    }
  }

  try x := parseDoubleToken(tokens[1], lineNumber, source, "x")
  try y := parseDoubleToken(tokens[2], lineNumber, source, "y")
  try z := parseDoubleToken(tokens[3], lineNumber, source, "z")

  return Success {
    value: Point3(x, y, z)
  }
}

function parseTexCoord(tokens: string[], lineNumber: int, source: string): Result<ObjTexCoord, ObjError> {
  if tokens.length < 3 {
    return Failure {
      error: objError("parse", lineNumber, `${source}:${lineNumber}: expected two coordinates after vt`)
    }
  }

  try u := parseDoubleToken(tokens[1], lineNumber, source, "u")
  try v := parseDoubleToken(tokens[2], lineNumber, source, "v")

  return Success {
    value: ObjTexCoord { u, v }
  }
}

function parseNormal(tokens: string[], lineNumber: int, source: string): Result<Point3, ObjError> {
  if tokens.length < 4 {
    return Failure {
      error: objError("parse", lineNumber, `${source}:${lineNumber}: expected three coordinates after vn`)
    }
  }

  try x := parseDoubleToken(tokens[1], lineNumber, source, "normal x")
  try y := parseDoubleToken(tokens[2], lineNumber, source, "normal y")
  try z := parseDoubleToken(tokens[3], lineNumber, source, "normal z")

  return Success {
    value: normalizePoint3(Point3(x, y, z))
  }
}

function resolveIndex(
  rawIndex: int,
  count: int,
  lineNumber: int,
  source: string,
  label: string,
): Result<int, ObjError> {
  if rawIndex == 0 {
    return Failure {
      error: objError("parse", lineNumber, `${source}:${lineNumber}: OBJ ${label} indices are 1-based; 0 is invalid`)
    }
  }

  resolvedIndex := if rawIndex > 0 then rawIndex - 1 else count + rawIndex
  if resolvedIndex < 0 || resolvedIndex >= count {
    return Failure {
      error: objError("parse", lineNumber, `${source}:${lineNumber}: ${label} index ${rawIndex} is out of range for ${count} records`)
    }
  }

  return Success {
    value: resolvedIndex
  }
}

function resolveOptionalIndex(
  token: string,
  count: int,
  lineNumber: int,
  source: string,
  label: string,
): Result<int, ObjError> {
  if token.trim() == "" {
    return Success {
      value: -1
    }
  }

  try rawIndex := parseIntToken(token, lineNumber, source, label + " index")
  return resolveIndex(rawIndex, count, lineNumber, source, label)
}

function parseVertexRef(
  token: string,
  positionCount: int,
  uvCount: int,
  normalCount: int,
  lineNumber: int,
  source: string,
): Result<ObjVertexRef, ObjError> {
  parts := token.split("/")
  if parts.length == 0 || parts[0].trim() == "" {
    return Failure {
      error: objError("parse", lineNumber, `${source}:${lineNumber}: invalid face element "${token}"`)
    }
  }

  try rawPositionIndex := parseIntToken(parts[0], lineNumber, source, "position index")
  try positionIndex := resolveIndex(rawPositionIndex, positionCount, lineNumber, source, "position")
  let uvIndex = -1
  let normalIndex = -1

  if parts.length >= 2 {
    uvResult := resolveOptionalIndex(parts[1], uvCount, lineNumber, source, "texture")
    case uvResult {
      s: Success -> {
        uvIndex = s.value
      }
      f: Failure -> return Failure { error: f.error }
    }
  }

  if parts.length >= 3 {
    normalResult := resolveOptionalIndex(parts[2], normalCount, lineNumber, source, "normal")
    case normalResult {
      s: Success -> {
        normalIndex = s.value
      }
      f: Failure -> return Failure { error: f.error }
    }
  }

  return Success {
    value: ObjVertexRef {
      positionIndex,
      uvIndex,
      normalIndex,
    }
  }
}

function parseFace(
  tokens: string[],
  positionCount: int,
  uvCount: int,
  normalCount: int,
  lineNumber: int,
  source: string,
): Result<ObjFace, ObjError> {
  if tokens.length < 4 {
    return Failure {
      error: objError("parse", lineNumber, `${source}:${lineNumber}: faces need at least three vertices`)
    }
  }

  vertices: ObjVertexRef[] := []
  for tokenIndex of 1..<tokens.length {
    try vertex := parseVertexRef(tokens[tokenIndex], positionCount, uvCount, normalCount, lineNumber, source)
    vertices.push(vertex)
  }

  return Success {
    value: ObjFace { vertices }
  }
}

function parseObjData(text: string, source: string): Result<ObjData, ObjError> {
  positions: Point3[] := []
  uvs: ObjTexCoord[] := []
  normals: Point3[] := []
  faces: ObjFace[] := []
  normalizedText := text.replaceAll("\r\n", "\n").replaceAll("\r", "\n")
  lines := normalizedText.split("\n")

  for lineIndex of 0..<lines.length {
    lineNumber := lineIndex + 1
    line := stripComment(lines[lineIndex])
    if line == "" {
      continue
    }

    tokens := splitWhitespace(line)
    if tokens.length == 0 {
      continue
    }

    kind := tokens[0]
    if kind == "v" {
      try position := parsePosition(tokens, lineNumber, source)
      positions.push(position)
      continue
    }

    if kind == "vt" {
      try uv := parseTexCoord(tokens, lineNumber, source)
      uvs.push(uv)
      continue
    }

    if kind == "vn" {
      try normal := parseNormal(tokens, lineNumber, source)
      normals.push(normal)
      continue
    }

    if kind == "f" {
      try face := parseFace(tokens, positions.length, uvs.length, normals.length, lineNumber, source)
      faces.push(face)
      continue
    }

    if kind == "vp" || kind == "o" || kind == "g" || kind == "s" ||
       kind == "mtllib" || kind == "usemtl" {
      continue
    }
  }

  if positions.length == 0 {
    return Failure {
      error: objError("parse", 0, `${source}: no vertex records were found`)
    }
  }

  if faces.length == 0 {
    return Failure {
      error: objError("parse", 0, `${source}: no face records were found`)
    }
  }

  return Success {
    value: ObjData {
      positions,
      uvs,
      normals,
      faces,
    }
  }
}

function point3Minus(a: Point3, b: Point3): Point3 {
  return Point3(a.x - b.x, a.y - b.y, a.z - b.z)
}

function cross(a: Point3, b: Point3): Point3 {
  return Point3(
    a.y * b.z - a.z * b.y,
    a.z * b.x - a.x * b.z,
    a.x * b.y - a.y * b.x,
  )
}

function normalizePoint3(value: Point3): Point3 {
  length := sqrt(value.x * value.x + value.y * value.y + value.z * value.z)
  if length <= EPSILON {
    return Point3(0.0, 0.0, 1.0)
  }

  return Point3(value.x / length, value.y / length, value.z / length)
}

function triangleNormal(a: Point3, b: Point3, c: Point3): Point3 {
  return normalizePoint3(cross(point3Minus(b, a), point3Minus(c, a)))
}

function appendVertex(
  specPositions: Point3[],
  specIndices: int[],
  specColors: Color[],
  specUvs: Point[],
  specNormals: Point3[],
  data: ObjData,
  vertex: ObjVertexRef,
  fallbackNormal: Point3,
  color: Color,
): void {
  position := data.positions[vertex.positionIndex]
  uv := if vertex.uvIndex >= 0 then data.uvs[vertex.uvIndex] else ObjTexCoord {}
  normal := if vertex.normalIndex >= 0 then data.normals[vertex.normalIndex] else fallbackNormal

  specPositions.push(position)
  specColors.push(color)
  specUvs.push(Point(uv.u, uv.v))
  specNormals.push(normal)
  specIndices.push(specPositions.length - 1)
}

function buildSimpleMeshSpec(data: ObjData, color: Color): SimpleMeshSpec {
  positions: Point3[] := []
  indices: int[] := []
  colors: Color[] := []
  uvs: Point[] := []
  normals: Point3[] := []

  for face of data.faces {
    first := face.vertices[0]

    for triangleIndex of 1..<face.vertices.length - 1 {
      second := face.vertices[triangleIndex]
      third := face.vertices[triangleIndex + 1]
      a := data.positions[first.positionIndex]
      b := data.positions[second.positionIndex]
      c := data.positions[third.positionIndex]
      normal := triangleNormal(a, b, c)

      appendVertex(positions, indices, colors, uvs, normals, data, first, normal, color)
      appendVertex(positions, indices, colors, uvs, normals, data, second, normal, color)
      appendVertex(positions, indices, colors, uvs, normals, data, third, normal, color)
    }
  }

  return SimpleMeshSpec {
    positions,
    indices,
    colors,
    uvs,
    normals,
  }
}

export function parseObjMeshSpec(
  text: string,
  source: string = "input",
  color: Color = Color { r: 1.0, g: 1.0, b: 1.0, a: 1.0 },
): Result<SimpleMeshSpec, ObjError> {
  try data := parseObjData(text, source)
  return Success {
    value: buildSimpleMeshSpec(data, color)
  }
}

export function loadObjMeshSpec(
  path: string,
  color: Color = Color { r: 1.0, g: 1.0, b: 1.0, a: 1.0 },
): Result<SimpleMeshSpec, ObjError> {
  textResult := readText(path)
  return case textResult {
    s: Success -> parseObjMeshSpec(s.value, path, color),
    f: Failure -> Failure {
      error: objError("read", 0, `${path}: failed to read OBJ file: ${f.error}`)
    },
  }
}
