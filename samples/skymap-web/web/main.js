import { loadDoofGame } from "../std/game/doof-game.js";

const status = document.getElementById("status");
try {
  const app = await loadDoofGame("../std-game-skymap-web-sample.wasm", {
    textures: {
      "images/panorama.jpg": "../images/panorama.jpg",
      "images/earth_daymap.jpg": "../images/earth_daymap.jpg",
    },
  });
  const markerResponse = await fetch("../models/marker.obj");
  if (!markerResponse.ok) throw new Error(`Could not load marker model: ${markerResponse.status} ${markerResponse.statusText}`);
  app.call("start", { markerObj: await markerResponse.text() });
} catch (error) {
  console.error(error);
  if (status) status.textContent = `Could not start: ${error instanceof Error ? error.message : error}`;
}
