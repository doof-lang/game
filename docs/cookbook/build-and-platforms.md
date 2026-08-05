# Build And Platforms

`std/game` supports Windows, macOS, and Doof's `ios-app` target. Windows apps
use a Win32/D3D11 host, macOS apps use the native Metal-backed host, and iOS
apps attach the Metal surface to the generated UIKit shell.

## Run A Windows Sample

From an MSVC developer shell:

```powershell
$env:DOOF_STDLIB_ROOT = (Resolve-Path .).Path
doof run game/samples/minimal
```

## Run A macOS Sample

```bash
doof run game/samples/minimal
```

Build without launching:

```bash
doof build game/samples/minimal
```

Run the full module test suite:

```bash
doof test game
```

## Build For The iOS Simulator

```bash
doof build --target ios-app --ios-destination simulator game/samples/jigsaw
```

Install and launch on a booted simulator:

```bash
doof run --target ios-app --ios-destination simulator game/samples/jigsaw
```

## Build For An iOS Device

Use the same target with `--ios-destination device` and the standard Doof iOS
signing options or environment variables for the signing identity and
provisioning profile.

```bash
doof build --target ios-app --ios-destination device game/samples/jigsaw
```

## Platform Notes

- Windows supports a Win32 window, D3D11 clear passes and built-in
  colored/textured meshes, keyboard and mouse input, resizing, requested
  rendering, WIC textures, and WAV/generated sound. Metal shader source, model
  batches, sky maps, space dust, and native gestures are not available.
- macOS supports keyboard, mouse, controller input, windowed apps, full-screen
  apps, sound, Metal rendering, and native gestures.
- iOS supports the Metal-backed surface and single-touch input through the
  existing pointer and mouse button APIs.
- Hardware keyboard events are not exposed on iOS yet.
- Prefer logical surface coordinates from `surface.width()` and
  `surface.height()` for layout. Use pixel dimensions only for native or
  low-level rendering interop.
