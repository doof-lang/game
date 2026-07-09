# std/game Cookbook

This cookbook is the task-oriented companion to the broader
[API reference](../API.md). Each page focuses on one workflow and points to a
sample that shows the same idea in a complete program.

## Start Here

- [Create an app window and run the loop](app-loop.md)
- [Draw simple 2D and 3D geometry](rendering.md)
- [Handle keyboard, mouse, touch, and controllers](input.md)
- [Build retained UI panels and buttons](ui.md)
- [Render bitmap text](text.md)
- [Play generated and file-backed sounds](sound.md)
- [Load textures, OBJ, glTF, and GLB assets](assets-and-models.md)
- [Build and run samples for macOS and iOS](build-and-platforms.md)

## Choosing A Render Mode

Use `GameRenderMode.Continuous` for animated games, simulations, camera motion,
particle effects, and anything that changes every display tick.

Use `GameRenderMode.Requested` for tools, menus, board games, and UI-heavy apps.
After each state change, call `app.requestRender()` to schedule the next draw.

## Running Examples

Run the module tests with:

```bash
doof test game
```

Run a sample from this repository with:

```bash
doof run game/samples/minimal
```

Build a sample without launching it with:

```bash
doof build game/samples/minimal
```
