import assert from "node:assert/strict";
import test from "node:test";

import { __testing } from "../doof-game.js";

class FakeWebGL2 {
  constructor() {
    this.calls = [];
    this.nextAttribute = 0;
    this.ARRAY_BUFFER = 34962;
    this.ELEMENT_ARRAY_BUFFER = 34963;
    this.STATIC_DRAW = 35044;
    this.DYNAMIC_DRAW = 35048;
    this.FLOAT = 5126;
    this.UNSIGNED_INT = 5125;
    this.TRIANGLES = 4;
    this.VERTEX_SHADER = 35633;
    this.FRAGMENT_SHADER = 35632;
    this.COMPILE_STATUS = 35713;
    this.LINK_STATUS = 35714;
  }
  record(name, ...args) { this.calls.push([name, ...args]); }
  createBuffer() { const value = {}; this.record("createBuffer", value); return value; }
  deleteBuffer(value) { this.record("deleteBuffer", value); }
  bindBuffer(...args) { this.record("bindBuffer", ...args); }
  bufferData(...args) { this.record("bufferData", ...args); }
  bufferSubData(target, offset, values) { this.record("bufferSubData", target, offset, Array.from(values)); }
  createShader(kind) { return { kind }; }
  shaderSource(shader, source) { shader.source = source; this.record("shaderSource", shader, source); }
  compileShader() {}
  getShaderParameter() { return true; }
  getShaderInfoLog() { return ""; }
  deleteShader() {}
  createProgram() { return {}; }
  attachShader() {}
  linkProgram() {}
  getProgramParameter() { return true; }
  getProgramInfoLog() { return ""; }
  useProgram(...args) { this.record("useProgram", ...args); }
  getAttribLocation(program, name) {
    if (!program.attributes) program.attributes = new Map();
    if (!program.attributes.has(name)) program.attributes.set(name, this.nextAttribute++);
    return program.attributes.get(name);
  }
  enableVertexAttribArray(...args) { this.record("enableVertexAttribArray", ...args); }
  disableVertexAttribArray(...args) { this.record("disableVertexAttribArray", ...args); }
  vertexAttribPointer(...args) { this.record("vertexAttribPointer", ...args); }
  vertexAttribDivisor(...args) { this.record("vertexAttribDivisor", ...args); }
  getUniformLocation(program, name) { return { program, name }; }
  uniformMatrix4fv(...args) { this.record("uniformMatrix4fv", ...args); }
  uniform1f(...args) { this.record("uniform1f", ...args); }
  uniform2f(...args) { this.record("uniform2f", ...args); }
  uniform3f(...args) { this.record("uniform3f", ...args); }
  drawElementsInstanced(...args) { this.record("drawElementsInstanced", ...args); }
}

function harness() {
  const gl = new FakeWebGL2();
  const canvas = {
    style: {}, clientWidth: 640, clientHeight: 360, width: 0, height: 0,
    setAttribute() {}, addEventListener() {}, removeEventListener() {},
    getContext(kind) { canvas.contextKind = kind; return kind === "webgl2" ? gl : null; },
  };
  const root = { appendChild() {}, prepend() {} };
  const window = { devicePixelRatio: 1, requestAnimationFrame() { return 1; } };
  const document = {
    title: "", defaultView: window,
    querySelector() { return root; },
    getElementById() { return null; },
    createElement(kind) { assert.equal(kind, "canvas"); return canvas; },
  };
  const bridge = __testing.createGameBridge(document, error => { throw error; }, new Map());
  const memory = new ArrayBuffer(65536);
  bridge.attach({ exports: { memory: { buffer: memory } } });
  const bytes = new Uint8Array(memory);
  const write = (offset, value) => {
    bytes.set(new TextEncoder().encode(value), offset);
    bytes[offset + value.length] = 0;
    return offset;
  };
  return { bridge, canvas, gl, memory, write };
}

test("uploads and draws a WebGL 2 simple-model batch", () => {
  const { bridge, canvas, gl, memory, write } = harness();
  const imports = bridge.imports;
  const window = imports.window_create(write(64, "Batch test"), 640, 360, 1);
  assert.equal(canvas.contextKind, "webgl2");

  const vertexPointer = 1024;
  new Float64Array(memory, vertexPointer, 36).fill(1);
  const indexPointer = 2048;
  new Uint32Array(memory, indexPointer, 3).set([0, 1, 2]);
  const mesh = imports.mesh_create(window, vertexPointer, 36, indexPointer, 3);
  const batch = imports.batch_create(window, 2);

  const instancePointer = 4096;
  const instance = new Float32Array(memory, instancePointer, 44);
  instance.fill(0);
  instance[0] = instance[5] = instance[10] = instance[15] = 1;
  instance[28] = instance[29] = instance[30] = instance[31] = 1;
  instance[38] = instance[39] = 1;
  imports.batch_set_instance(window, batch, 1, instancePointer, 44);

  const viewPointer = 8192;
  const view = new Float64Array(memory, viewPointer, 16);
  view[0] = view[5] = view[10] = view[15] = 1;
  imports.draw_batch(window, mesh, batch, 0, 0, 0, 2, viewPointer, 0.35, 0.65, 0, 0, 1, 0, 0, 4);

  assert.ok(gl.calls.some(([name, target, size, usage]) =>
    name === "bufferData" && target === gl.ARRAY_BUFFER && size === 352 && usage === gl.DYNAMIC_DRAW));
  assert.ok(gl.calls.some(([name, target, offset, values]) =>
    name === "bufferSubData" && target === gl.ARRAY_BUFFER && offset === 176 && values.length === 44));
  assert.equal(gl.calls.filter(([name, , divisor]) => name === "vertexAttribDivisor" && divisor === 1).length, 11);
  assert.ok(gl.calls.some(([name, mode, count, type, offset, instances]) =>
    name === "drawElementsInstanced" && mode === gl.TRIANGLES && count === 3
      && type === gl.UNSIGNED_INT && offset === 0 && instances === 2));
  const shaderSources = gl.calls.filter(([name]) => name === "shaderSource");
  assert.equal(shaderSources.length, 2);
  assert.ok(shaderSources.every(([, , source]) => source.startsWith("#version 300 es")));

  imports.resource_delete(window, 2, batch);
  assert.ok(gl.calls.some(([name]) => name === "deleteBuffer"));
});
