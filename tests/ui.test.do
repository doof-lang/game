import { Assert } from "std/assert"
import { readText } from "std/fs"
import { approxEqual } from "std/math"

import {
  BitmapFont,
  Point,
  Point3,
  Rect,
  ScreenPointer,
  Transform,
  UiElementKind,
  UiButtonStyle,
  UiLayer,
  UiStyle,
  Vec3,
  initGameApp,
  rectContains,
} from "../index"
import { createTestUiLayer } from "../ui"

function testFont(): BitmapFont {
  app := initGameApp{ title: "Doof Game UI Tests" }
  rootFont := app.loadBitmapFont("game/samples/ui/fonts/DejaVuSans.fnt")
  return case rootFont {
    s: Success -> s.value,
    f: Failure -> try! app.loadBitmapFont("samples/ui/fonts/DejaVuSans.fnt"),
  }
}

function testFixturePath(name: string): string {
  rootPath := "game/tests/fixtures/${name}"
  return case readText(rootPath) {
    s: Success -> rootPath,
    f: Failure -> "tests/fixtures/${name}",
  }
}

function testLayer(): UiLayer {
  return createTestUiLayer()
}

function testStyle(): UiStyle => UiStyle { font: testFont() }

function testButtonStyle(): UiButtonStyle => UiButtonStyle { font: testFont() }

function assertApprox(actual: double, expected: double): void {
  Assert.isTrue(approxEqual(actual, expected), "expected ${actual} to approximately equal ${expected}")
}

export function testRectContainsIncludesEdgesAndRejectsOutside(): void {
  rect := Rect(10.0, 20.0, 30.0, 40.0)

  Assert.isTrue(rectContains(rect, Point(10.0, 20.0)))
  Assert.isTrue(rectContains(rect, Point(40.0, 60.0)))
  Assert.isTrue(rectContains(rect, Point(25.0, 45.0)))
  Assert.isFalse(rectContains(rect, Point(9.9, 20.0)))
  Assert.isFalse(rectContains(rect, Point(10.0, 60.1)))
}

export function testGameAppLoadsReferencedBitmapFontTexture(): void {
  font := testFont()
  Assert.equal(font.texture.pixelWidth(), 256)
  Assert.equal(font.texture.pixelHeight(), 256)
}

export function testGameAppBitmapFontTextureErrorIncludesFontAndAtlasPaths(): void {
  app := initGameApp{ title: "Doof Game Font Loader Error Test" }
  path := testFixturePath("missing-texture.fnt")
  result := app.loadBitmapFont(path)
  case result {
    s: Success -> Assert.fail("expected missing bitmap font texture to fail")
    f: Failure -> {
      Assert.isTrue(f.error.indexOf("missing-texture.fnt") >= 0)
      Assert.isTrue(f.error.indexOf("missing-atlas.png") >= 0)
    }
  }
}

export function testHitTestMapsIdentityTranslationAndScaleToUiSpace(): void {
  identity := testLayer()
  identity.addButton("Play", Rect(10.0, 20.0, 100.0, 40.0), testButtonStyle(), (): void => {})
  identityHit := identity.hitTest(Point(25.0, 30.0)) else {
    Assert.fail("expected identity hit")
    return
  }

  translated := testLayer()
  translated
    .setTransform(Transform.identity().withPosition(Point3(50.0, 25.0, 0.0)))
    .addButton("Play", Rect(10.0, 20.0, 100.0, 40.0), testButtonStyle(), (): void => {})
  translatedHit := translated.hitTest(Point(65.0, 50.0)) else {
    Assert.fail("expected translated hit")
    return
  }

  scaled := testLayer()
  scaled
    .setTransform(Transform.identity().withScale(Vec3.xyz(2.0, 3.0, 1.0)))
    .addButton("Play", Rect(10.0, 20.0, 100.0, 40.0), testButtonStyle(), (): void => {})
  scaledHit := scaled.hitTest(Point(30.0, 75.0)) else {
    Assert.fail("expected scaled hit")
    return
  }

  Assert.equal(identityHit.id, 1)
  assertApprox(identityHit.point.x, 25.0)
  assertApprox(identityHit.point.y, 30.0)
  assertApprox(translatedHit.point.x, 15.0)
  assertApprox(translatedHit.point.y, 25.0)
  assertApprox(scaledHit.point.x, 15.0)
  assertApprox(scaledHit.point.y, 25.0)
  Assert.equal(scaled.hitTest(Point(5.0, 5.0)), null)
}

export function testHitTestUsesLastAddedTopmostElement(): void {
  layer := testLayer()
  layer.addButton("Back", Rect(0.0, 0.0, 100.0, 100.0), testButtonStyle(), (): void => {})
  top := layer.addLabel("Top", Rect(0.0, 0.0, 100.0, 100.0), testStyle())

  hit := layer.hitTest(Point(50.0, 50.0)) else {
    Assert.fail("expected hit")
    return
  }

  Assert.equal(hit.id, top.id())
  Assert.equal(hit.kind, UiElementKind.Label)
}

export function testButtonHoverPressAndClickOnReleaseInside(): void {
  layer := testLayer()
  let clicks = 0
  button := layer.addButton("Play", Rect(10.0, 20.0, 100.0, 40.0), testButtonStyle(), (): void => {
    clicks += 1
  })

  layer.handlePointerMove(Point(20.0, 30.0))
  Assert.isTrue(button.isHovered())
  Assert.isFalse(button.isPressed())

  layer.handlePointerDown(Point(20.0, 30.0))
  Assert.isTrue(button.isPressed())

  layer.handlePointerUp(Point(20.0, 30.0))
  Assert.equal(clicks, 1)
  Assert.isTrue(button.isHovered())
  Assert.isFalse(button.isPressed())
}

export function testButtonDoesNotClickWhenReleasedOutside(): void {
  layer := testLayer()
  let clicks = 0
  button := layer.addButton("Play", Rect(10.0, 20.0, 100.0, 40.0), testButtonStyle(), (): void => {
    clicks += 1
  })

  layer.handlePointerDown(Point(20.0, 30.0))
  layer.handlePointerMove(Point(200.0, 200.0))
  layer.handlePointerUp(Point(200.0, 200.0))

  Assert.equal(clicks, 0)
  Assert.isFalse(button.isHovered())
  Assert.isFalse(button.isPressed())
}

export function testDisabledButtonDoesNotHoverPressOrClick(): void {
  layer := testLayer()
  let clicks = 0
  button := layer.addButton("Play", Rect(10.0, 20.0, 100.0, 40.0), testButtonStyle(),  (): void => {
    clicks += 1
  })
  button.setEnabled(false)

  layer.handlePointerMove(Point(20.0, 30.0))
  layer.handlePointerDown(Point(20.0, 30.0))
  layer.handlePointerUp(Point(20.0, 30.0))
  layer.handlePointerTap(Point(20.0, 30.0))

  Assert.equal(clicks, 0)
  Assert.isFalse(button.isHovered())
  Assert.isFalse(button.isPressed())
}

export function testRegisteredPointerDrivesButtonHoverPressAndClick(): void {
  layer := testLayer()
  pointer := ScreenPointer {}
  layer.registerPointer(pointer)
  let clicks = 0
  button := layer.addButton("Play", Rect(10.0, 20.0, 100.0, 40.0), testButtonStyle(), (): void => {
    clicks += 1
  })

  pointer.moveTo(Point(20.0, 30.0))
  Assert.isTrue(button.isHovered())

  pointer.pressAt(Point(20.0, 30.0))
  Assert.isTrue(button.isPressed())

  pointer.releaseAt(Point(20.0, 30.0))
  Assert.equal(clicks, 1)
  Assert.isTrue(button.isHovered())
  Assert.isFalse(button.isPressed())
}

export function testRegisteredPointerDoesNotClickWhenReleasedOutside(): void {
  layer := testLayer()
  pointer := ScreenPointer {}
  layer.registerPointer(pointer)
  let clicks = 0
  button := layer.addButton("Play", Rect(10.0, 20.0, 100.0, 40.0), testButtonStyle(), (): void => {
    clicks += 1
  })

  pointer.pressAt(Point(20.0, 30.0))
  pointer.moveTo(Point(200.0, 200.0))
  pointer.releaseAt(Point(200.0, 200.0))

  Assert.equal(clicks, 0)
  Assert.isFalse(button.isHovered())
  Assert.isFalse(button.isPressed())
}
