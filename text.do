import { readText } from "std/fs"
import { dirname, join } from "std/path"

import { SimpleMesh, SimpleMeshSpec } from "./mesh"
import { SimpleModel } from "./model"
import { Color, Point, Point3, Texture, loadTextureForSurface } from "./render"
import { GameSurface } from "./surface"
import { Transform } from "./transform"

export enum TextAlign {
  Left,
  Center,
  Right,
}

export class BitmapGlyph {
  readonly id: int
  readonly x: int
  readonly y: int
  readonly width: int
  readonly height: int
  readonly xOffset: int
  readonly yOffset: int
  readonly xAdvance: int
  readonly page: int = 0
  readonly channel: int = 0
}

export class BitmapKerning {
  readonly first: int
  readonly second: int
  readonly amount: int
}

export interface BitmapFontMetrics {
  readonly lineHeight: int
  readonly base: int
  readonly scaleWidth: int
  readonly scaleHeight: int
  glyph(codepoint: int): BitmapGlyph | null
  kerning(first: int, second: int): int
}

export class BitmapFontData {
  readonly lineHeight: int
  readonly base: int
  readonly scaleWidth: int
  readonly scaleHeight: int
  readonly textureFile: string
  glyphs: Map<int, BitmapGlyph>
  kernings: Map<string, int>

  glyph(codepoint: int): BitmapGlyph | null {
    return case glyphs.get(codepoint) {
      s: Success -> s.value,
      f: Failure -> null,
    }
  }

  kerning(first: int, second: int): int {
    return case kernings.get(kerningKey(first, second)) {
      s: Success -> s.value,
      f: Failure -> 0,
    }
  }
}

export class BitmapFont {
  readonly lineHeight: int
  readonly base: int
  readonly scaleWidth: int
  readonly scaleHeight: int
  readonly texture: Texture
  glyphs: Map<int, BitmapGlyph>
  kernings: Map<string, int>

  glyph(codepoint: int): BitmapGlyph | null {
    return case glyphs.get(codepoint) {
      s: Success -> s.value,
      f: Failure -> null,
    }
  }

  kerning(first: int, second: int): int {
    return case kernings.get(kerningKey(first, second)) {
      s: Success -> s.value,
      f: Failure -> 0,
    }
  }
}

export class TextLayoutOptions {
  color: Color = Color { r: 1.0, g: 1.0, b: 1.0, a: 1.0 }
  position: Point = Point { x: 0.0, y: 0.0 }
  z: double = 0.0
  maxWidth: double = 0.0
  align: TextAlign = TextAlign.Left
  letterSpacing: double = 0.0
  lineSpacing: double = 0.0
  fallbackCodepoint: int = 63
}

export class TextBounds {
  readonly width: double
  readonly height: double
  readonly lineCount: int
}

class FontParseState {
  foundCommon: bool = false
  lineHeight: int = 0
  base: int = 0
  scaleWidth: int = 0
  scaleHeight: int = 0
  pages: int = 1
  textureFile: string | null = null
  glyphs: Map<int, BitmapGlyph> = {}
  kernings: Map<string, int> = {}
}

class TextGlyphPlacement {
  glyph: BitmapGlyph
  x: double
  y: double
}

class TextLine {
  placements: TextGlyphPlacement[] = []
  width: double = 0.0
}

class TextLineBuilder {
  placements: TextGlyphPlacement[] = []
  penX: double = 0.0
  prevCodepoint: int = -1
  hasAdvance: bool = false
}

class TextLayout {
  lines: TextLine[] = []
  width: double = 0.0
  height: double = 0.0
}

function kerningKey(first: int, second: int): string {
  return string(first) + ":" + string(second)
}

function parseError(source: string, lineNumber: int, message: string): string {
  if lineNumber <= 0 {
    return `${source}: ${message}`
  }
  return `${source}:${lineNumber}: ${message}`
}

function stripComment(line: string): string {
  marker := line.indexOf("#")
  if marker >= 0 {
    return line.substring(0, marker).trim()
  }
  return line.trim()
}

function splitFontTokens(text: string): string[] {
  tokens: string[] := []
  let current = ""
  let inQuote = false
  normalized := text.replaceAll("\t", " ")

  for index of 0..<normalized.length {
    ch := normalized.charAt(index)
    if ch == '"' {
      inQuote = !inQuote
      current += ch
      continue
    }

    if ch == ' ' && !inQuote {
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

function unquote(value: string): string {
  if value.length >= 2 && value.charAt(0) == '"' && value.charAt(value.length - 1) == '"' {
    return value.substring(1, value.length - 1)
  }
  return value
}

function parseAttributes(tokens: string[], source: string, lineNumber: int): Result<Map<string, string>, string> {
  attributes: Map<string, string> := {}

  for index of 1..<tokens.length {
    token := tokens[index]
    equals := token.indexOf("=")
    if equals <= 0 {
      return Failure {
        error: parseError(source, lineNumber, `expected key=value attribute, got "${token}"`)
      }
    }

    key := token.substring(0, equals)
    value := token.substring(equals + 1, token.length)
    attributes.set(key, unquote(value))
  }

  return Success { value: attributes }
}

function requiredInt(
  attributes: Map<string, string>,
  key: string,
  source: string,
  lineNumber: int,
): Result<int, string> {
  value := attributes.get(key) else {
    return Failure {
      error: parseError(source, lineNumber, `missing ${key} attribute`)
    }
  }

  return case int.parse(value) {
    s: Success -> Success { value: s.value },
    f: Failure -> Failure {
      error: parseError(source, lineNumber, `invalid ${key} value "${value}"`)
    },
  }
}

function optionalInt(
  attributes: Map<string, string>,
  key: string,
  fallback: int,
  source: string,
  lineNumber: int,
): Result<int, string> {
  value := attributes.get(key) else {
    return Success { value: fallback }
  }

  return case int.parse(value) {
    s: Success -> Success { value: s.value },
    f: Failure -> Failure {
      error: parseError(source, lineNumber, `invalid ${key} value "${value}"`)
    },
  }
}

function parseCommon(attributes: Map<string, string>, state: FontParseState, source: string, lineNumber: int): Result<void, string> {
  try lineHeight := requiredInt(attributes, "lineHeight", source, lineNumber)
  try base := requiredInt(attributes, "base", source, lineNumber)
  try scaleWidth := requiredInt(attributes, "scaleW", source, lineNumber)
  try scaleHeight := requiredInt(attributes, "scaleH", source, lineNumber)
  try pages := optionalInt(attributes, "pages", 1, source, lineNumber)

  if pages != 1 {
    return Failure {
      error: parseError(source, lineNumber, "bitmap fonts with multiple pages are not supported")
    }
  }

  state.foundCommon = true
  state.lineHeight = lineHeight
  state.base = base
  state.scaleWidth = scaleWidth
  state.scaleHeight = scaleHeight
  state.pages = pages
  return Success()
}

function parseGlyph(attributes: Map<string, string>, state: FontParseState, source: string, lineNumber: int): Result<void, string> {
  try id := requiredInt(attributes, "id", source, lineNumber)
  try x := requiredInt(attributes, "x", source, lineNumber)
  try y := requiredInt(attributes, "y", source, lineNumber)
  try width := requiredInt(attributes, "width", source, lineNumber)
  try height := requiredInt(attributes, "height", source, lineNumber)
  try xOffset := requiredInt(attributes, "xoffset", source, lineNumber)
  try yOffset := requiredInt(attributes, "yoffset", source, lineNumber)
  try xAdvance := requiredInt(attributes, "xadvance", source, lineNumber)
  try page := optionalInt(attributes, "page", 0, source, lineNumber)
  try channel := optionalInt(attributes, "chnl", 0, source, lineNumber)

  if page != 0 {
    return Failure {
      error: parseError(source, lineNumber, "bitmap fonts with multiple pages are not supported")
    }
  }

  state.glyphs.set(id, BitmapGlyph {
    id,
    x,
    y,
    width,
    height,
    xOffset,
    yOffset,
    xAdvance,
    page,
    channel,
  })
  return Success()
}

function parsePage(attributes: Map<string, string>, state: FontParseState, source: string, lineNumber: int): Result<void, string> {
  try id := requiredInt(attributes, "id", source, lineNumber)
  if id != 0 {
    return Failure {
      error: parseError(source, lineNumber, "bitmap font page id must be 0")
    }
  }

  file := attributes.get("file") else {
    return Failure {
      error: parseError(source, lineNumber, "missing file attribute")
    }
  }
  if file == "" {
    return Failure {
      error: parseError(source, lineNumber, "bitmap font page file cannot be empty")
    }
  }
  if state.textureFile != null {
    return Failure {
      error: parseError(source, lineNumber, "bitmap fonts with multiple pages are not supported")
    }
  }

  state.textureFile = file
  return Success()
}

function parseKerning(attributes: Map<string, string>, state: FontParseState, source: string, lineNumber: int): Result<void, string> {
  try first := requiredInt(attributes, "first", source, lineNumber)
  try second := requiredInt(attributes, "second", source, lineNumber)
  try amount := requiredInt(attributes, "amount", source, lineNumber)

  state.kernings.set(kerningKey(first, second), amount)
  return Success()
}

export function parseBitmapFontData(text: string, source: string = "<font>"): Result<BitmapFontData, string> {
  state := FontParseState {}
  normalizedText := text.replaceAll("\r\n", "\n").replaceAll("\r", "\n")
  lines := normalizedText.split("\n")

  for lineIndex of 0..<lines.length {
    lineNumber := lineIndex + 1
    line := stripComment(lines[lineIndex])
    if line == "" {
      continue
    }

    tokens := splitFontTokens(line)
    if tokens.length == 0 {
      continue
    }

    kind := tokens[0]
    try attributes := parseAttributes(tokens, source, lineNumber)

    if kind == "common" {
      parseCommon(attributes, state, source, lineNumber) else error {
        return Failure(error)
      }
      continue
    }

    if kind == "char" {
      parseGlyph(attributes, state, source, lineNumber) else error {
        return Failure(error)
      }
      continue
    }

    if kind == "kerning" {
      parseKerning(attributes, state, source, lineNumber) else error {
        return Failure(error)
      }
      continue
    }

    if kind == "page" {
      parsePage(attributes, state, source, lineNumber) else error {
        return Failure(error)
      }
      continue
    }

    if kind == "info" || kind == "chars" || kind == "kernings" {
      continue
    }
  }

  if !state.foundCommon {
    return Failure {
      error: parseError(source, 0, "missing common font metrics")
    }
  }

  if state.glyphs.keys().length == 0 {
    return Failure {
      error: parseError(source, 0, "missing glyph data")
    }
  }

  textureFile := state.textureFile else {
    return Failure {
      error: parseError(source, 0, "missing bitmap font page")
    }
  }

  return Success {
    value: BitmapFontData {
      lineHeight: state.lineHeight,
      base: state.base,
      scaleWidth: state.scaleWidth,
      scaleHeight: state.scaleHeight,
      textureFile,
      glyphs: state.glyphs,
      kernings: state.kernings,
    }
  }
}

export function loadBitmapFontForSurface(surface: GameSurface, path: string): Result<BitmapFont, string> {
  text := readText(path) else error {
    return Failure {
      error: `${path}: failed to read bitmap font: ${error}`
    }
  }

  data := parseBitmapFontData(text, path) else error {
    return Failure(error)
  }
  texturePath := join([dirname(path), data.textureFile])
  texture := loadTextureForSurface(surface, texturePath) else error {
    return Failure {
      error: `${path}: failed to load bitmap font texture ${texturePath}: ${error}`
    }
  }

  return Success {
    value: BitmapFont {
      lineHeight: data.lineHeight,
      base: data.base,
      scaleWidth: data.scaleWidth,
      scaleHeight: data.scaleHeight,
      texture,
      glyphs: data.glyphs,
      kernings: data.kernings,
    }
  }
}

function requireGlyph(font: BitmapFontMetrics, codepoint: int, options: TextLayoutOptions): BitmapGlyph {
  glyph := font.glyph(codepoint)
  if glyph != null {
    return glyph!
  }

  fallback := font.glyph(options.fallbackCodepoint)
  if fallback != null {
    return fallback!
  }

  panic("BitmapFont has no glyph for codepoint ${codepoint} and no fallback glyph ${options.fallbackCodepoint}")
}

function glyphAdvance(font: BitmapFontMetrics, previous: int, codepoint: int, glyph: BitmapGlyph, options: TextLayoutOptions): double {
  kerning := if previous >= 0 then font.kerning(previous, codepoint) else 0
  return double(kerning + glyph.xAdvance) + options.letterSpacing
}

function decodeUtf8(text: string): int[] {
  codepoints: int[] := []
  let index = 0

  while index < text.length {
    first := int(text.charAt(index))
    if first <= 127 {
      codepoints.push(first)
      index += 1
      continue
    }

    if first >= 194 && first <= 223 && index + 1 < text.length {
      second := int(text.charAt(index + 1))
      if second >= 128 && second <= 191 {
        codepoints.push((first - 192) * 64 + second - 128)
        index += 2
        continue
      }
    }

    if first >= 224 && first <= 239 && index + 2 < text.length {
      second := int(text.charAt(index + 1))
      third := int(text.charAt(index + 2))
      validSecond := second >= 128 && second <= 191 &&
        (first != 224 || second >= 160) &&
        (first != 237 || second <= 159)
      if validSecond && third >= 128 && third <= 191 {
        codepoints.push((first - 224) * 4096 + (second - 128) * 64 + third - 128)
        index += 3
        continue
      }
    }

    if first >= 240 && first <= 244 && index + 3 < text.length {
      second := int(text.charAt(index + 1))
      third := int(text.charAt(index + 2))
      fourth := int(text.charAt(index + 3))
      validSecond := second >= 128 && second <= 191 &&
        (first != 240 || second >= 144) &&
        (first != 244 || second <= 143)
      if validSecond && third >= 128 && third <= 191 && fourth >= 128 && fourth <= 191 {
        codepoints.push(
          (first - 240) * 262144 + (second - 128) * 4096 +
          (third - 128) * 64 + fourth - 128,
        )
        index += 4
        continue
      }
    }

    codepoints.push(65533)
    index += 1
  }

  return codepoints
}

function measureSegment(font: BitmapFontMetrics, codepoints: int[], startPenX: double, previous: int, options: TextLayoutOptions): double {
  let penX = startPenX
  let prev = previous

  for codepoint of codepoints {
    glyph := requireGlyph(font, codepoint, options)
    penX += glyphAdvance(font, prev, codepoint, glyph, options)
    prev = codepoint
  }

  return penX
}

function addCodepoint(builder: TextLineBuilder, font: BitmapFontMetrics, codepoint: int, options: TextLayoutOptions): void {
  glyph := requireGlyph(font, codepoint, options)
  kerning := if builder.prevCodepoint >= 0 then font.kerning(builder.prevCodepoint, codepoint) else 0
  glyphX := builder.penX + double(kerning + glyph.xOffset)
  glyphY := double(glyph.yOffset)

  if glyph.width > 0 && glyph.height > 0 && codepoint != 32 {
    builder.placements.push(TextGlyphPlacement {
      glyph,
      x: glyphX,
      y: glyphY,
    })
  }

  builder.penX += double(kerning + glyph.xAdvance) + options.letterSpacing
  builder.prevCodepoint = codepoint
  builder.hasAdvance = true
}

function finishLine(lines: TextLine[], builder: TextLineBuilder): void {
  lines.push(TextLine {
    placements: builder.placements,
    width: builder.penX,
  })
  builder.placements = []
  builder.penX = 0.0
  builder.prevCodepoint = -1
  builder.hasAdvance = false
}

function addWordBreaking(lines: TextLine[], builder: TextLineBuilder, font: BitmapFontMetrics, word: int[], options: TextLayoutOptions): void {
  for codepoint of word {
    glyph := requireGlyph(font, codepoint, options)
    nextPen := builder.penX + glyphAdvance(font, builder.prevCodepoint, codepoint, glyph, options)

    if options.maxWidth > 0.0 && nextPen > options.maxWidth && builder.hasAdvance {
      finishLine(lines, builder)
    }

    addCodepoint(builder, font, codepoint, options)
  }
}

function addSpaces(builder: TextLineBuilder, font: BitmapFontMetrics, count: int, options: TextLayoutOptions): void {
  for spaceIndex of 0..<count {
    addCodepoint(builder, font, 32, options)
  }
}

function isSpace(codepoint: int): bool {
  return codepoint == 32 || codepoint == 9
}

function layoutParagraph(lines: TextLine[], font: BitmapFontMetrics, text: string, options: TextLayoutOptions): void {
  builder := TextLineBuilder {}
  let word: int[] = []
  let pendingSpaces = 0
  codepoints := decodeUtf8(text)

  for codepoint of codepoints {
    if isSpace(codepoint) {
      if word.length > 0 {
        addWordWithWrap(lines, builder, font, word, pendingSpaces, options)
        word = []
        pendingSpaces = 0
      }
      pendingSpaces += 1
      continue
    }

    word.push(codepoint)
  }

  if word.length > 0 {
    addWordWithWrap(lines, builder, font, word, pendingSpaces, options)
  }

  finishLine(lines, builder)
}

function addWordWithWrap(
  lines: TextLine[],
  builder: TextLineBuilder,
  font: BitmapFontMetrics,
  word: int[],
  pendingSpaces: int,
  options: TextLayoutOptions,
): void {
  candidate: int[] := []
  if builder.hasAdvance {
    for spaceIndex of 0..<pendingSpaces {
      candidate.push(32)
    }
  }
  for codepoint of word {
    candidate.push(codepoint)
  }
  candidateWidth := measureSegment(font, candidate, builder.penX, builder.prevCodepoint, options)

  if options.maxWidth > 0.0 && builder.hasAdvance && candidateWidth > options.maxWidth {
    finishLine(lines, builder)
    addWordBreaking(lines, builder, font, word, options)
    return
  }

  if builder.hasAdvance {
    addSpaces(builder, font, pendingSpaces, options)
  }
  addWordBreaking(lines, builder, font, word, options)
}

function layoutText(font: BitmapFontMetrics, text: string, options: TextLayoutOptions): TextLayout {
  lines: TextLine[] := []
  normalizedText := text.replaceAll("\r\n", "\n").replaceAll("\r", "\n")
  paragraphs := normalizedText.split("\n")

  for index of 0..<paragraphs.length {
    layoutParagraph(lines, font, paragraphs[index], options)
  }

  let maxWidth = 0.0
  for line of lines {
    if line.width > maxWidth {
      maxWidth = line.width
    }
  }

  lineCount := lines.length
  height := if lineCount == 0 then 0.0 else
    double(font.lineHeight) * double(lineCount) + options.lineSpacing * double(lineCount - 1)

  return TextLayout {
    lines,
    width: maxWidth,
    height,
  }
}

function lineOffset(line: TextLine, options: TextLayoutOptions): double {
  if options.align == TextAlign.Center {
    return (options.maxWidth - line.width) * 0.5
  }

  if options.align == TextAlign.Right {
    return options.maxWidth - line.width
  }

  return 0.0
}

export function measureText(font: BitmapFontMetrics, text: string, options: TextLayoutOptions = TextLayoutOptions {}): TextBounds {
  layout := layoutText(font, text, options)
  return TextBounds {
    width: layout.width,
    height: layout.height,
    lineCount: layout.lines.length,
  }
}

export function createTextMeshSpec(font: BitmapFontMetrics, text: string, options: TextLayoutOptions = TextLayoutOptions {}): SimpleMeshSpec {
  layout := layoutText(font, text, options)
  positions: Point3[] := []
  indices: int[] := []
  colors: Color[] := []
  uvs: Point[] := []
  normals: Point3[] := []
  lineStep := double(font.lineHeight) + options.lineSpacing

  for lineIndex of 0..<layout.lines.length {
    line := layout.lines[lineIndex]
    offsetX := if options.maxWidth > 0.0 then lineOffset(line, options) else 0.0
    baselineY := double(lineIndex) * lineStep

    for placement of line.placements {
      glyph := placement.glyph
      x0 := options.position.x + offsetX + placement.x
      y0 := options.position.y + baselineY + placement.y
      x1 := x0 + double(glyph.width)
      y1 := y0 + double(glyph.height)
      u0 := double(glyph.x) / double(font.scaleWidth)
      v0 := double(glyph.y) / double(font.scaleHeight)
      u1 := double(glyph.x + glyph.width) / double(font.scaleWidth)
      v1 := double(glyph.y + glyph.height) / double(font.scaleHeight)
      baseIndex := positions.length

      positions.push(Point3(x0, y0, options.z))
      positions.push(Point3(x1, y0, options.z))
      positions.push(Point3(x1, y1, options.z))
      positions.push(Point3(x0, y1, options.z))

      colors.push(options.color)
      colors.push(options.color)
      colors.push(options.color)
      colors.push(options.color)

      uvs.push(Point(u0, v0))
      uvs.push(Point(u1, v0))
      uvs.push(Point(u1, v1))
      uvs.push(Point(u0, v1))

      normals.push(Point3(0.0, 0.0, 1.0))
      normals.push(Point3(0.0, 0.0, 1.0))
      normals.push(Point3(0.0, 0.0, 1.0))
      normals.push(Point3(0.0, 0.0, 1.0))

      indices.push(baseIndex)
      indices.push(baseIndex + 1)
      indices.push(baseIndex + 2)
      indices.push(baseIndex)
      indices.push(baseIndex + 2)
      indices.push(baseIndex + 3)
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

export function createTextMesh(
  surface: GameSurface,
  font: BitmapFontMetrics,
  text: string,
  options: TextLayoutOptions = TextLayoutOptions {},
): SimpleMesh {
  spec := createTextMeshSpec(font, text, options)
  if spec.vertexCount() == 0 {
    panic("Cannot create a SimpleMesh for text with no drawable glyphs")
  }
  return SimpleMesh(surface, spec)
}

export function createTextModel(
  surface: GameSurface,
  font: BitmapFont,
  text: string,
  options: TextLayoutOptions = TextLayoutOptions {},
): SimpleModel {
  return SimpleModel(createTextMesh(surface, font, text, options), font.texture)
}
