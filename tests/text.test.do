import { Assert } from "std/assert"
import { approxEqual } from "std/math"

import {
  Color,
  Point,
  TextAlign,
  BitmapFont,
  TextLayoutOptions,
  createTextMeshSpec,
  measureText,
  parseBitmapFont,
} from "../index"

const FONT_TEXT =
  "info face=\"Tiny Font\" size=16 bold=0 italic=0 charset=\"\" unicode=1 stretchH=100 smooth=1 aa=1 padding=0,0,0,0 spacing=1,1\n" +
  "common lineHeight=10 base=8 scaleW=64 scaleH=32 pages=1 packed=0\n" +
  "page id=0 file=\"tiny font.png\"\n" +
  "chars count=5\n" +
  "char id=32 x=0 y=0 width=0 height=0 xoffset=0 yoffset=0 xadvance=3 page=0 chnl=15\n" +
  "char id=63 x=48 y=0 width=4 height=7 xoffset=0 yoffset=1 xadvance=5 page=0 chnl=15\n" +
  "char id=65 x=0 y=0 width=5 height=7 xoffset=1 yoffset=2 xadvance=6 page=0 chnl=15\n" +
  "char id=66 x=8 y=0 width=4 height=7 xoffset=0 yoffset=2 xadvance=5 page=0 chnl=15\n" +
  "char id=67 x=16 y=0 width=5 height=7 xoffset=0 yoffset=2 xadvance=6 page=0 chnl=15\n" +
  "kernings count=1\n" +
  "kerning first=65 second=66 amount=-1\n"

function requireFont(): BitmapFont {
  parsed := parseBitmapFont(FONT_TEXT, "tiny.fnt")
  return try! parsed
}

function assertApprox(actual: double, expected: double): void {
  Assert.isTrue(approxEqual(actual, expected), "expected ${actual} to approximately equal ${expected}")
}

export function testParseBitmapFontReadsMetricsGlyphsAndKerning(): void {
  font := requireFont()
  glyphA := font.glyph(65) else {
    Assert.fail("expected A glyph")
    return
  }

  Assert.equal(font.lineHeight, 10)
  Assert.equal(font.base, 8)
  Assert.equal(font.scaleWidth, 64)
  Assert.equal(font.scaleHeight, 32)
  Assert.equal(glyphA.xOffset, 1)
  Assert.equal(glyphA.xAdvance, 6)
  Assert.equal(font.kerning(65, 66), -1)
  Assert.equal(font.kerning(66, 65), 0)
}

export function testParseBitmapFontRejectsMalformedInput(): void {
  missingCommon := parseBitmapFont("char id=65 x=0 y=0 width=1 height=1 xoffset=0 yoffset=0 xadvance=1\n")
  badNumber := parseBitmapFont(
    "common lineHeight=nope base=8 scaleW=64 scaleH=32 pages=1\n" +
    "char id=65 x=0 y=0 width=1 height=1 xoffset=0 yoffset=0 xadvance=1\n",
  )
  multiPage := parseBitmapFont(
    "common lineHeight=10 base=8 scaleW=64 scaleH=32 pages=2\n" +
    "char id=65 x=0 y=0 width=1 height=1 xoffset=0 yoffset=0 xadvance=1 page=0\n",
  )

  Assert.isTrue(missingCommon.isFailure())
  Assert.isTrue(badNumber.isFailure())
  Assert.isTrue(multiPage.isFailure())
}

export function testMeasureTextHandlesKerningLinesAndWrap(): void {
  font := requireFont()

  kerned := measureText(font, "AB")
  multiline := measureText(font, "A\nBC")
  wrapped := measureText(font, "A BC", TextLayoutOptions { maxWidth: 8.0 })

  assertApprox(kerned.width, 10.0)
  assertApprox(kerned.height, 10.0)
  Assert.equal(kerned.lineCount, 1)
  assertApprox(multiline.width, 11.0)
  assertApprox(multiline.height, 20.0)
  Assert.equal(multiline.lineCount, 2)
  assertApprox(wrapped.width, 6.0)
  assertApprox(wrapped.height, 30.0)
  Assert.equal(wrapped.lineCount, 3)
}

export function testCreateTextMeshSpecBuildsGlyphQuadsAndUvs(): void {
  font := requireFont()
  spec := createTextMeshSpec(
    font,
    "AB",
    TextLayoutOptions {
      position: Point(10.0, 20.0),
      z: 2.0,
      color: Color(0.25, 0.5, 0.75, 0.9),
    },
  )

  Assert.equal(spec.vertexCount(), 8)
  Assert.equal(spec.indexCount(), 12)
  assertApprox(spec.positions[0].x, 11.0)
  assertApprox(spec.positions[0].y, 22.0)
  assertApprox(spec.positions[0].z, 2.0)
  assertApprox(spec.positions[4].x, 15.0)
  assertApprox(spec.positions[4].y, 22.0)
  assertApprox(spec.uvs[0].x, 0.0)
  assertApprox(spec.uvs[0].y, 0.0)
  assertApprox(spec.uvs[2].x, 5.0 / 64.0)
  assertApprox(spec.uvs[2].y, 7.0 / 32.0)
  Assert.equal(spec.colors[0].r, 0.25)
  Assert.equal(spec.colors[0].a, 0.9)
  Assert.equal(spec.indices[0], 0)
  Assert.equal(spec.indices[5], 3)
}

export function testCreateTextMeshSpecAlignsWithinMaxWidth(): void {
  font := requireFont()
  centered := createTextMeshSpec(
    font,
    "A",
    TextLayoutOptions {
      maxWidth: 20.0,
      align: TextAlign.Center,
    },
  )
  right := createTextMeshSpec(
    font,
    "A",
    TextLayoutOptions {
      maxWidth: 20.0,
      align: TextAlign.Right,
    },
  )

  assertApprox(centered.positions[0].x, 8.0)
  assertApprox(right.positions[0].x, 15.0)
}
