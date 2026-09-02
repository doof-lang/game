import { loadDoofGame } from "../std/game/doof-game.js?v=runtime-uniforms-1";

const status = document.getElementById("status");
const loadText = async path => {
  const response = await fetch(path);
  if (!response.ok) throw new Error(`Could not load ${path}: ${response.status} ${response.statusText}`);
  return response.text();
};

try {
  const [backdropVertexSource, backdropFragmentSource, prismVertexSource, prismFragmentSource] = await Promise.all([
    loadText("../shaders/backdrop.vert.glsl?v=prism-field-5"),
    loadText("../shaders/backdrop.frag.glsl?v=prism-field-5"),
    loadText("../shaders/prism.vert.glsl?v=prism-field-5"),
    loadText("../shaders/prism.frag.glsl?v=prism-field-5"),
  ]);
  const app = await loadDoofGame("../std-game-custom-shader-web-sample.wasm");
  app.call("start", {
    backdropVertexSource: backdropVertexSource,
    backdropFragmentSource: backdropFragmentSource,
    prismVertexSource: prismVertexSource,
    prismFragmentSource: prismFragmentSource,
  });
  document.documentElement.classList.add("is-ready");
  if (status) status.textContent = "384 instances · live uniforms · WebGL 2";

  const scene = document.querySelector(".app");
  window.addEventListener("pointermove", event => {
    if (!scene) return;
    const x = (event.clientX / window.innerWidth - 0.5) * -12;
    const y = (event.clientY / window.innerHeight - 0.5) * -9;
    scene.style.setProperty("--shift-x", `${x.toFixed(2)}px`);
    scene.style.setProperty("--shift-y", `${y.toFixed(2)}px`);
  }, { passive: true });
} catch (error) {
  console.error(error);
  document.documentElement.classList.add("has-error");
  if (status) status.textContent = `Could not start: ${error instanceof Error ? error.message : error}`;
}
