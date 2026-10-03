# Flex layout sample

This sample uses `std/layout` to drive a retained `std/game` UI. It demonstrates:

- a responsive root row with a fixed sidebar and growing content panel;
- nested row and column containers;
- a wrapping card grid with 300-unit bases and growth applied per line;
- intrinsic text measurement;
- a measured badge anchored as an absolute overlay;
- flex growth, fixed sizes, padding, and gaps;
- a vertically scrolling activity grid;
- immediate descendant placement after scrolling;
- adapting `LayoutPlacement` callbacks to existing game UI controls.

Run it from the standard-library workspace:

```sh
doof run game/samples/layout
```

Resize the window to see cards move between rows. Card bases and the 12-unit
gap choose each line, then `grow: 1.0` makes its cards share the remaining
width. The content node keeps `shrink: 0.0` so wrapped rows contribute their
full height to scrolling. Narrow or shorten the window until the grid exceeds
the viewport, then hover over it and use a mouse wheel or trackpad to scroll.
The Previous and Next buttons and the up/down arrow keys scroll by one row.

When developing the standard library, set `DOOF_STDLIB_ROOT` to its workspace
so imports use the current source. For a renderer-free example with printed
geometry and tests, run `doof run layout/samples/wrapping`.

The sample uses continuous rendering and consumes the frame-relative scroll delta immediately before drawing. Layout placement therefore updates in the same frame instead of waiting for a requested-render round trip.

The current `UiLayer` does not expose arbitrary per-element scissor rectangles, so partially clipped card panels use `visibleBounds()` and their text is hidden until fully visible. The layout engine still retains the complete unclipped and clipped geometry.
