# Flex layout sample

This sample uses `std/layout` to drive a retained `std/game` UI. It demonstrates:

- a responsive root row with a fixed sidebar and growing content panel;
- nested row and column containers;
- intrinsic text measurement;
- a measured badge anchored as an absolute overlay;
- flex growth, fixed sizes, padding, and gaps;
- a vertically scrolling activity list;
- immediate descendant placement after scrolling;
- adapting `LayoutPlacement` callbacks to existing game UI controls.

Run it from the standard-library workspace:

```sh
doof run game/samples/layout
```

Resize the window to see the flex tree reflow. Hover over the activity list and use a mouse wheel or trackpad to scroll. The Previous and Next buttons and the up/down arrow keys scroll by one card.

The sample uses continuous rendering and consumes the frame-relative scroll delta immediately before drawing. Layout placement therefore updates in the same frame instead of waiting for a requested-render round trip.

The current `UiLayer` does not expose arbitrary per-element scissor rectangles, so partially clipped card panels use `visibleBounds()` and their text is hidden until fully visible. The layout engine still retains the complete unclipped and clipped geometry.
