const encoder = new TextEncoder();
// Browser host for the std/game Wasm backend. DOM and WebGL resources are kept
// private here and exposed to native_game_wasm.cpp/native_mesh_wasm.cpp only as
// opaque integer handles and small rendering operations.
const decoder = new TextDecoder();

async function preloadTextureAssets(document, textureUrls) {
  const entries = textureUrls instanceof Map ? Array.from(textureUrls) : Object.entries(textureUrls);
  return new Map(await Promise.all(entries.map(async ([path, url]) => {
    const response = await fetch(new URL(url, document.baseURI));
    if (!response.ok) throw new Error(`Could not load texture '${path}': ${response.status} ${response.statusText}`);
    const blob = await response.blob();
    if (typeof globalThis.createImageBitmap === "function") {
      return [path, await globalThis.createImageBitmap(blob)];
    }
    const image = document.createElement("img");
    const objectUrl = URL.createObjectURL(blob);
    try { image.src = objectUrl; await image.decode(); }
    finally { URL.revokeObjectURL(objectUrl); }
    return [path, image];
  })));
}

function createGameBridge(document, onError, textureAssets) {
  let instance;
  let nextWindow = 1;
  let nextResource = 1;
  const windows = new Map();
  const resources = new Map();

  const memory = () => instance.exports.memory.buffer;
  const readString = (pointer) => {
    const bytes = new Uint8Array(memory());
    let end = pointer;
    while (bytes[end] !== 0) end += 1;
    return decoder.decode(bytes.subarray(pointer, end));
  };
  const doubles = (pointer, count) => Array.from(new Float64Array(memory(), pointer, count));
  const matrix4 = (pointer) => {
    const m = doubles(pointer, 16);
    return new Float32Array([m[0],m[4],m[8],m[12],m[1],m[5],m[9],m[13],m[2],m[6],m[10],m[14],m[3],m[7],m[11],m[15]]);
  };
  const matrix3 = (pointer) => {
    const m = doubles(pointer, 9);
    return new Float32Array([m[0],m[3],m[6],m[1],m[4],m[7],m[2],m[5],m[8]]);
  };
  const gameWindow = (id) => {
    const value = windows.get(id);
    if (!value) throw new Error(`Unknown Doof game window ${id}`);
    return value;
  };
  const resource = (id, kind) => {
    const value = resources.get(id);
    if (!value || value.kind !== kind) throw new Error(`Unknown Doof game ${kind} ${id}`);
    return value;
  };
  const saveResource = (kind, value) => {
    const id = nextResource++;
    resources.set(id, { kind, ...value });
    return id;
  };
  const uploadTexture = (id, source, width, height) => {
    const { gl } = gameWindow(id);
    const texture = gl.createTexture();
    gl.bindTexture(gl.TEXTURE_2D, texture);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.REPEAT);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);
    gl.pixelStorei(gl.UNPACK_ALIGNMENT, 1);
    if (source instanceof Uint8Array) {
      gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA, width, height, 0, gl.RGBA, gl.UNSIGNED_BYTE, source);
    } else {
      gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA, gl.RGBA, gl.UNSIGNED_BYTE, source);
    }
    return saveResource("texture", { window: id, value: texture, width, height });
  };
  const compile = (gl, kind, source) => {
    const shader = gl.createShader(kind);
    gl.shaderSource(shader, source);
    gl.compileShader(shader);
    if (gl.getShaderParameter(shader, gl.COMPILE_STATUS)) return shader;
    const message = gl.getShaderInfoLog(shader) || "shader compilation failed";
    gl.deleteShader(shader);
    throw new Error(message);
  };
  const program = (gl, vertexSource, fragmentSource) => {
    const value = gl.createProgram();
    const vertex = compile(gl, gl.VERTEX_SHADER, vertexSource);
    const fragment = compile(gl, gl.FRAGMENT_SHADER, fragmentSource);
    gl.attachShader(value, vertex);
    gl.attachShader(value, fragment);
    gl.linkProgram(value);
    gl.deleteShader(vertex);
    gl.deleteShader(fragment);
    if (gl.getProgramParameter(value, gl.LINK_STATUS)) return value;
    throw new Error(gl.getProgramInfoLog(value) || "shader link failed");
  };
  const resize = (entry) => {
    const scale = entry.window.devicePixelRatio || 1;
    const width = Math.max(1, Math.round(entry.canvas.clientWidth * scale));
    const height = Math.max(1, Math.round(entry.canvas.clientHeight * scale));
    const changed = entry.canvas.width !== width || entry.canvas.height !== height;
    if (changed) { entry.canvas.width = width; entry.canvas.height = height; }
    return changed;
  };
  const keyCode = (code) => {
    if (/^Key[A-Z]$/.test(code)) return code.charCodeAt(3) - 64;
    if (/^Digit[0-9]$/.test(code)) return 27 + Number(code[5]);
    return ({ArrowLeft:37,ArrowRight:38,ArrowUp:39,ArrowDown:40,Escape:41,Enter:42,Space:43,
      Backspace:44,Tab:45,ShiftLeft:46,ShiftRight:46,ControlLeft:47,ControlRight:47,
      AltLeft:48,AltRight:48,MetaLeft:49,MetaRight:49,
      F1:50,F2:51,F3:52,F4:53,F5:54,F6:55,F7:56,F8:57,F9:58,F10:59,F11:60,F12:61})[code] || 0;
  };
  const mouseButton = (button) => button === 0 ? 0 : button === 2 ? 1 : button === 1 ? 2 : 3;

  const imports = {
    window_create(titlePointer, width, height, windowed) {
      const title = readString(titlePointer);
      document.title = title;
      let root = document.querySelector(".app");
      if (!root) { root = document.createElement("div"); root.className = "app"; document.body.appendChild(root); }
      let canvas = document.getElementById("doof-game-canvas");
      if (!canvas) { canvas = document.createElement("canvas"); canvas.id = "doof-game-canvas"; canvas.className = "sky"; canvas.tabIndex = 0; canvas.setAttribute("aria-label", title); root.prepend(canvas); }
      canvas.style.display = "block";
      canvas.style.width = windowed ? `${width}px` : "100%";
      canvas.style.height = windowed ? `${height}px` : "100%";
      const gl = canvas.getContext("webgl", { alpha: false, antialias: true, depth: true });
      if (!gl) return 0;
      const id = nextWindow++;
      windows.set(id, { id, canvas, gl, window: document.defaultView ?? globalThis, running: false, frame: 0, cleanup: [] });
      resize(windows.get(id));
      return id;
    },
    window_width(id) { return gameWindow(id).canvas.width; },
    window_height(id) { return gameWindow(id).canvas.height; },
    window_scale(id) { return gameWindow(id).window.devicePixelRatio || 1; },
    window_start(id, frameDispatcher, eventDispatcher) {
      const entry = gameWindow(id);
      const table = instance.exports.__indirect_function_table;
      const frame = table.get(frameDispatcher);
      const emit = table.get(eventDispatcher);
      const event = (kind, key=0, button=0, x=0, y=0, dx=0, dy=0, sx=0, sy=0) => emit(kind,key,button,x,y,dx,dy,sx,sy,entry.canvas.width,entry.canvas.height);
      const listen = (target, type, handler, options) => { target.addEventListener(type, handler, options); entry.cleanup.push(() => target.removeEventListener(type, handler, options)); };
      listen(entry.window, "keydown", value => { const key=keyCode(value.code); if(key){event(2,key);if(key===43)value.preventDefault();} });
      listen(entry.window, "keyup", value => { const key=keyCode(value.code); if(key)event(3,key); });
      listen(entry.canvas, "pointerdown", value => { entry.canvas.focus();entry.canvas.setPointerCapture?.(value.pointerId);event(4,0,mouseButton(value.button),value.offsetX,value.offsetY); });
      listen(entry.window, "pointerup", value => event(5,0,mouseButton(value.button),value.offsetX||0,value.offsetY||0));
      listen(entry.canvas, "pointermove", value => event(6,0,0,value.offsetX,value.offsetY,value.movementX,value.movementY));
      listen(entry.canvas, "wheel", value => { event(7,0,0,value.offsetX,value.offsetY,0,0,value.deltaX,value.deltaY);value.preventDefault(); }, { passive:false });
      listen(entry.window, "resize", () => { if(resize(entry))event(1); });
      entry.running = true;
      const tick = (timestamp) => { if(!entry.running)return;if(resize(entry))event(1);try{frame(timestamp);}catch(error){entry.running=false;onError(error);}if(entry.running)entry.frame=entry.window.requestAnimationFrame(tick); };
      entry.frame = entry.window.requestAnimationFrame(tick);
    },
    window_stop(id) { const entry=gameWindow(id);entry.running=false;if(entry.frame)entry.window.cancelAnimationFrame(entry.frame);for(const cleanup of entry.cleanup)cleanup();entry.cleanup=[]; },
    begin_pass(id, clearKind, red, green, blue, alpha, depth, depthMode, blendMode, winding, cull) {
      const { gl, canvas } = gameWindow(id);
      gl.viewport(0,0,canvas.width,canvas.height);gl.clearColor(red,green,blue,alpha);gl.clearDepth(depth);
      let mask=0;if(clearKind===1||clearKind===3)mask|=gl.COLOR_BUFFER_BIT;if(clearKind===2||clearKind===3)mask|=gl.DEPTH_BUFFER_BIT;if(mask)gl.clear(mask);
      if(depthMode===0)gl.disable(gl.DEPTH_TEST);else{gl.enable(gl.DEPTH_TEST);gl.depthFunc(gl.LEQUAL);gl.depthMask(depthMode===2);}
      if(blendMode===1){gl.enable(gl.BLEND);gl.blendFunc(gl.SRC_ALPHA,gl.ONE_MINUS_SRC_ALPHA);}else gl.disable(gl.BLEND);
      gl.frontFace(winding===0?gl.CW:gl.CCW);if(cull===0)gl.disable(gl.CULL_FACE);else{gl.enable(gl.CULL_FACE);gl.cullFace(cull===1?gl.FRONT:gl.BACK);}
    },
    frame_commit() {},
    texture_load(id, pathPointer) {
      const path = readString(pathPointer);
      const source = textureAssets.get(path);
      if (!source) return 0;
      return uploadTexture(id, source, source.width, source.height);
    },
    texture_width(texture) { return resource(texture, "texture").width; },
    texture_height(texture) { return resource(texture, "texture").height; },
    texture_rgba(id, pointer, count, width, height) {
      return uploadTexture(id, new Uint8Array(memory(), pointer, count), width, height);
    },
    texture_delete(id, texture) { const item=resource(texture,"texture");gameWindow(id).gl.deleteTexture(item.value);resources.delete(texture); },
    mesh_create(id, verticesPointer, vertexValueCount, indicesPointer, indexCount) {
      const { gl }=gameWindow(id);const vertexData=new Float32Array(doubles(verticesPointer,vertexValueCount));const indexData=new Uint16Array(memory(),indicesPointer,indexCount).slice();const vertex=gl.createBuffer(),index=gl.createBuffer();gl.bindBuffer(gl.ARRAY_BUFFER,vertex);gl.bufferData(gl.ARRAY_BUFFER,vertexData,gl.STATIC_DRAW);gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER,index);gl.bufferData(gl.ELEMENT_ARRAY_BUFFER,indexData,gl.STATIC_DRAW);return saveResource("mesh",{window:id,vertex,index,indexCount});
    },
    dust_create(id, pointer, count) { const {gl}=gameWindow(id);const buffer=gl.createBuffer();gl.bindBuffer(gl.ARRAY_BUFFER,buffer);gl.bufferData(gl.ARRAY_BUFFER,new Float32Array(doubles(pointer,count)),gl.STATIC_DRAW);return saveResource("dust",{window:id,buffer,count:count/4}); },
    resource_delete(id, kind, resourceId) { const {gl}=gameWindow(id);const item=resource(resourceId,kind===0?"mesh":"dust");if(item.vertex)gl.deleteBuffer(item.vertex);if(item.index)gl.deleteBuffer(item.index);if(item.buffer)gl.deleteBuffer(item.buffer);resources.delete(resourceId); },
    draw_mesh(id, meshId, textureId, textured, blendMode, viewPointer, modelPointer, normalPointer, ambient, directional, lightX, lightY, lightZ, red, green, blue, alpha) {
      const entry=gameWindow(id),gl=entry.gl,mesh=resource(meshId,"mesh");if(!entry.meshProgram)entry.meshProgram=program(gl,
        "attribute vec3 position;attribute vec4 color;attribute vec2 uv;attribute vec3 normal;uniform mat4 viewProjection;uniform mat4 model;uniform mat3 normalMatrix;varying vec4 vertexColor;varying vec2 textureUv;varying vec3 worldNormal;void main(){gl_Position=viewProjection*model*vec4(position,1.0);vertexColor=color;textureUv=uv;worldNormal=normalize(normalMatrix*normal);}",
        "precision mediump float;varying vec4 vertexColor;varying vec2 textureUv;varying vec3 worldNormal;uniform sampler2D colorTexture;uniform float textured;uniform vec4 tint;uniform float ambientLight;uniform float directionalLight;uniform vec3 lightDirection;void main(){vec4 base=mix(vertexColor,texture2D(colorTexture,textureUv)*vertexColor,textured);float diffuse=max(dot(normalize(worldNormal),normalize(lightDirection)),0.0);gl_FragColor=vec4(base.rgb*tint.rgb*(ambientLight+directionalLight*diffuse),base.a*tint.a);}");
      const p=entry.meshProgram;gl.useProgram(p);gl.bindBuffer(gl.ARRAY_BUFFER,mesh.vertex);gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER,mesh.index);for(const [name,size,offset] of [["position",3,0],["color",4,12],["uv",2,28],["normal",3,36]]){const location=gl.getAttribLocation(p,name);gl.enableVertexAttribArray(location);gl.vertexAttribPointer(location,size,gl.FLOAT,false,48,offset);}gl.uniformMatrix4fv(gl.getUniformLocation(p,"viewProjection"),false,matrix4(viewPointer));gl.uniformMatrix4fv(gl.getUniformLocation(p,"model"),false,matrix4(modelPointer));gl.uniformMatrix3fv(gl.getUniformLocation(p,"normalMatrix"),false,matrix3(normalPointer));gl.uniform1f(gl.getUniformLocation(p,"textured"),textured?1:0);gl.uniform4f(gl.getUniformLocation(p,"tint"),red,green,blue,alpha);gl.uniform1f(gl.getUniformLocation(p,"ambientLight"),ambient);gl.uniform1f(gl.getUniformLocation(p,"directionalLight"),directional);gl.uniform3f(gl.getUniformLocation(p,"lightDirection"),lightX,lightY,lightZ);if(textured){gl.activeTexture(gl.TEXTURE0);gl.bindTexture(gl.TEXTURE_2D,resource(textureId,"texture").value);gl.uniform1i(gl.getUniformLocation(p,"colorTexture"),0);}gl.drawElements(gl.TRIANGLES,mesh.indexCount,gl.UNSIGNED_SHORT,0);
    },
    draw_sky(id, textureId, width, height, fovY, exposure, rotationPointer) {
      const entry=gameWindow(id),gl=entry.gl;if(!entry.skyProgram){entry.skyProgram=program(gl,"attribute vec2 position;varying vec2 screenUv;void main(){screenUv=position;gl_Position=vec4(position,1.0,1.0);}","precision mediump float;varying vec2 screenUv;uniform sampler2D panorama;uniform mat3 cameraRotation;uniform float aspect;uniform float tanHalfFov;uniform float exposure;const float PI=3.14159265359;void main(){vec3 direction=normalize(cameraRotation*vec3(screenUv.x*aspect*tanHalfFov,screenUv.y*tanHalfFov,-1.0));float u=atan(direction.x,-direction.z)/(2.0*PI)+0.5;float v=asin(clamp(direction.y,-1.0,1.0))/PI+0.5;vec4 color=texture2D(panorama,vec2(u,v));gl_FragColor=vec4(color.rgb*exposure,color.a);}");entry.skyBuffer=gl.createBuffer();gl.bindBuffer(gl.ARRAY_BUFFER,entry.skyBuffer);gl.bufferData(gl.ARRAY_BUFFER,new Float32Array([-1,-1,3,-1,-1,3]),gl.STATIC_DRAW);}const p=entry.skyProgram;gl.disable(gl.DEPTH_TEST);gl.depthMask(false);gl.disable(gl.CULL_FACE);gl.useProgram(p);gl.bindBuffer(gl.ARRAY_BUFFER,entry.skyBuffer);const position=gl.getAttribLocation(p,"position");gl.enableVertexAttribArray(position);gl.vertexAttribPointer(position,2,gl.FLOAT,false,0,0);gl.activeTexture(gl.TEXTURE0);gl.bindTexture(gl.TEXTURE_2D,resource(textureId,"texture").value);gl.uniform1i(gl.getUniformLocation(p,"panorama"),0);gl.uniformMatrix3fv(gl.getUniformLocation(p,"cameraRotation"),false,matrix3(rotationPointer));gl.uniform1f(gl.getUniformLocation(p,"aspect"),height>0?width/height:1);gl.uniform1f(gl.getUniformLocation(p,"tanHalfFov"),Math.tan(fovY*0.5));gl.uniform1f(gl.getUniformLocation(p,"exposure"),exposure);gl.drawArrays(gl.TRIANGLES,0,3);gl.enable(gl.DEPTH_TEST);gl.depthMask(true);
    },
    draw_dust(id, dustId, particleCount, pixelHeight, cameraX, cameraY, cameraZ, fieldSize, particleSize, fadeStart, fadeEnd, opacity, red, green, blue, matrixPointer) {
      const entry=gameWindow(id),gl=entry.gl,dust=resource(dustId,"dust");if(!entry.dustProgram)entry.dustProgram=program(gl,"attribute vec3 position;attribute float brightness;uniform mat4 cameraMatrix;uniform vec3 cameraPosition;uniform float fieldSize;uniform float particleSize;uniform float pixelScale;uniform float fadeStart;uniform float fadeEnd;uniform float opacity;varying float particleAlpha;float wrapAxis(float value,float camera){float relative=value-camera;return(fract(relative/fieldSize+0.5)-0.5)*fieldSize+camera;}void main(){vec3 world=vec3(wrapAxis(position.x,cameraPosition.x),wrapAxis(position.y,cameraPosition.y),wrapAxis(position.z,cameraPosition.z));float distanceToCamera=length(world-cameraPosition);float fadeSpan=max(fadeEnd-fadeStart,0.001);particleAlpha=opacity*brightness*clamp((fadeEnd-distanceToCamera)/fadeSpan,0.0,1.0);gl_Position=cameraMatrix*vec4(world,1.0);gl_PointSize=max(particleSize*pixelScale*brightness,1.0);}","precision mediump float;uniform vec3 dustColor;varying float particleAlpha;void main(){vec2 delta=gl_PointCoord-vec2(0.5);float core=1.0-smoothstep(0.12,0.5,length(delta));gl_FragColor=vec4(dustColor,particleAlpha*core);}");const p=entry.dustProgram;gl.enable(gl.BLEND);gl.blendFunc(gl.SRC_ALPHA,gl.ONE_MINUS_SRC_ALPHA);gl.enable(gl.DEPTH_TEST);gl.depthFunc(gl.LEQUAL);gl.depthMask(false);gl.useProgram(p);gl.bindBuffer(gl.ARRAY_BUFFER,dust.buffer);for(const [name,size,offset] of [["position",3,0],["brightness",1,12]]){const location=gl.getAttribLocation(p,name);gl.enableVertexAttribArray(location);gl.vertexAttribPointer(location,size,gl.FLOAT,false,16,offset);}gl.uniformMatrix4fv(gl.getUniformLocation(p,"cameraMatrix"),false,matrix4(matrixPointer));gl.uniform3f(gl.getUniformLocation(p,"cameraPosition"),cameraX,cameraY,cameraZ);gl.uniform1f(gl.getUniformLocation(p,"fieldSize"),fieldSize);gl.uniform1f(gl.getUniformLocation(p,"particleSize"),particleSize);gl.uniform1f(gl.getUniformLocation(p,"pixelScale"),pixelHeight/720);gl.uniform1f(gl.getUniformLocation(p,"fadeStart"),fadeStart);gl.uniform1f(gl.getUniformLocation(p,"fadeEnd"),fadeEnd);gl.uniform1f(gl.getUniformLocation(p,"opacity"),opacity);gl.uniform3f(gl.getUniformLocation(p,"dustColor"),red,green,blue);gl.drawArrays(gl.POINTS,0,particleCount);gl.depthMask(true);
    },
  };

  return { imports, attach(value) { instance = value; }, memory() { return instance?.exports.memory.buffer; } };
}

async function instantiate(source, imports) {
  if (source instanceof WebAssembly.Module) return { instance: await WebAssembly.instantiate(source, imports) };
  if (source instanceof ArrayBuffer || ArrayBuffer.isView(source)) return WebAssembly.instantiate(source, imports);
  const response = source instanceof Response ? source : await fetch(source);
  if (!response.ok) throw new Error(`Could not load WASM: ${response.status} ${response.statusText}`);
  try { return await WebAssembly.instantiateStreaming(response.clone(), imports); }
  catch { return WebAssembly.instantiate(await response.arrayBuffer(), imports); }
}

export async function loadDoofGame(source, options = {}) {
  const onError = options.onError ?? (error => console.error(error));
  const document = options.document ?? globalThis.document;
  const textureAssets = await preloadTextureAssets(document, options.textures ?? {});
  const bridge = createGameBridge(document, onError, textureAssets);
  const supplied = options.imports ?? {};
  const imports = {
    ...supplied,
    doof_game: { ...(supplied.doof_game ?? {}), ...bridge.imports },
    wasi_snapshot_preview1: {
      fd_close() { return 0; },
      environ_sizes_get(count, size) {
        const view = new DataView(bridge.memory() ?? new ArrayBuffer(8));
        if (view.byteLength >= size + 4) { view.setUint32(count, 0, true); view.setUint32(size, 0, true); }
        return 0;
      },
      environ_get() { return 0; },
      clock_time_get(clock, precision, output) {
        const now = clock === 0 ? Date.now() : performance.now();
        new DataView(bridge.memory()).setBigUint64(output, BigInt(Math.floor(now * 1e6)), true);
        return 0;
      },
      ...(supplied.wasi_snapshot_preview1 ?? {}),
    },
  };
  const result = await instantiate(source, imports);
  const instance = result.instance ?? result;
  bridge.attach(instance);
  const exports = instance.exports;
  const readCString = pointer => { const bytes=new Uint8Array(exports.memory.buffer);let end=pointer;while(bytes[end]!==0)end+=1;return decoder.decode(bytes.subarray(pointer,end)); };
  const readEnvelope = pointer => { if(!pointer)throw new Error("Doof WASM returned a null response pointer");try{const envelope=JSON.parse(readCString(pointer));if(!envelope.ok)throw new Error(typeof envelope.error==="string"?envelope.error:JSON.stringify(envelope.error));return envelope.value;}finally{exports.doof_free(pointer);} };
  if (typeof exports._initialize === "function") exports._initialize();
  readEnvelope(exports.doof_initialize());
  return { instance, call(name, params={}) { const callable=exports[`doof_export_${name}`];if(typeof callable!=="function")throw new Error(`Doof WASM does not export '${name}'`);const bytes=encoder.encode(JSON.stringify(params));const pointer=exports.malloc(bytes.length+1);new Uint8Array(exports.memory.buffer).set(bytes,pointer);new Uint8Array(exports.memory.buffer)[pointer+bytes.length]=0;try{return readEnvelope(callable(pointer));}finally{exports.free(pointer);} } };
}
