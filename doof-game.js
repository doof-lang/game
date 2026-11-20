const encoder = new TextEncoder();
// Browser host for the std/game Wasm backend. DOM and WebGL 2 resources are kept
// private here and exposed to native_game_wasm.cpp/native_mesh_wasm.cpp only as
// opaque integer handles and small rendering operations.
const decoder = new TextDecoder();
const BATCH_INSTANCE_FLOATS = 44;
const BATCH_INSTANCE_STRIDE = BATCH_INSTANCE_FLOATS * 4;
const batchVertexSource = `#version 300 es
in vec3 position;in vec4 color;in vec2 uv;in vec3 normal;
in vec4 instanceRow0;in vec4 instanceRow1;in vec4 instanceRow2;in vec4 instanceRow3;
in vec4 instanceNormal0;in vec4 instanceNormal1;in vec4 instanceNormal2;
in vec4 instanceTint;in vec4 instanceEffects;in vec4 instanceUv;in vec4 instanceMaterial;
uniform mat4 viewProjection;
out vec4 vertexColor;out vec2 textureUv;out vec3 worldNormal;out vec3 worldPosition;out vec4 effects;out vec4 material;
void main(){vec4 local=vec4(position,1.0);vec4 world=vec4(dot(instanceRow0,local),dot(instanceRow1,local),dot(instanceRow2,local),dot(instanceRow3,local));gl_Position=viewProjection*world;vertexColor=color*instanceTint;textureUv=uv*instanceUv.zw+instanceUv.xy;worldNormal=vec3(dot(instanceNormal0.xyz,normal),dot(instanceNormal1.xyz,normal),dot(instanceNormal2.xyz,normal));worldPosition=world.xyz;effects=instanceEffects;material=instanceMaterial;}`;
// Packed parameter blocks shared with native_mesh_wasm.cpp.
// Lighting: ambient, directional, light xyz, eye xyz, light rgb, ambient rgb.
// Material: tint rgba, whiteBlend, uv offset xy, uv scale xy, specular,
// shininess, fresnel, fresnelPower, alphaCutoff.
const LIGHTING_PARAMS = 14;
const MATERIAL_PARAMS = 14;
const meshVertexSource = `#version 300 es
in vec3 position;in vec4 color;in vec2 uv;in vec3 normal;
uniform mat4 viewProjection;uniform mat4 model;uniform mat3 normalMatrix;
uniform vec4 tint;uniform vec4 materialEffects;uniform vec4 uvTransform;uniform vec4 materialParams;
out vec4 vertexColor;out vec2 textureUv;out vec3 worldNormal;out vec3 worldPosition;out vec4 effects;out vec4 material;
void main(){vec4 world=model*vec4(position,1.0);gl_Position=viewProjection*world;vertexColor=color*tint;textureUv=uv*uvTransform.zw+uvTransform.xy;worldNormal=normalMatrix*normal;worldPosition=world.xyz;effects=materialEffects;material=materialParams;}`;
// Shared by single meshes and model batches so both match the Metal and
// D3D11 lighting: effects = (whiteBlend, specular, shininess, fresnel),
// material = (fresnelPower, alphaCutoff, -, -).
const litFragmentSource = `#version 300 es
precision highp float;
in vec4 vertexColor;in vec2 textureUv;in vec3 worldNormal;in vec3 worldPosition;in vec4 effects;in vec4 material;
uniform sampler2D colorTexture;uniform float textured;uniform vec3 lightDirection;uniform vec2 lightLevels;uniform vec3 eyePosition;uniform vec3 lightColor;uniform vec3 ambientColor;
out vec4 fragmentColor;
void main(){vec4 base=vertexColor;if(textured>0.5)base*=texture(colorTexture,textureUv);if(base.a<material.y)discard;base.rgb=mix(base.rgb,vec3(1.0),clamp(effects.x,0.0,1.0));vec3 n=worldNormal/max(length(worldNormal),0.0001);vec3 light=length(lightDirection)<0.0001?normalize(vec3(0.35,0.60,0.72)):normalize(lightDirection);float directional=max(lightLevels.y,0.0);float diffuse=max(dot(n,light),0.0);vec3 amount=ambientColor*max(lightLevels.x,0.0)+lightColor*(directional*diffuse);vec3 viewDirection=normalize(eyePosition-worldPosition);vec3 halfDirection=normalize(light+viewDirection);float specular=diffuse>0.0?directional*max(effects.y,0.0)*pow(max(dot(n,halfDirection),0.0),max(effects.z,0.0001)):0.0;float fresnel=max(effects.w,0.0)*pow(1.0-clamp(dot(n,viewDirection),0.0,1.0),max(material.x,0.0001));fragmentColor=vec4(base.rgb*amount+lightColor*specular+vec3(fresnel),base.a);}`;

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
  const ints = (pointer, count) => Array.from(new Int32Array(memory(), pointer, count));
  const strings = (pointer, count) => Array.from(new Uint32Array(memory(), pointer, count), readString);
  const shaderGlBuffer = (gl, item, target) => {
    const key = target === gl.ELEMENT_ARRAY_BUFFER ? "elementBuffer" : "arrayBuffer";
    if (!item[key]) {
      const buffer = gl.createBuffer();
      if (!buffer) throw new Error("Failed to create WebGL 2 shader buffer");
      gl.bindBuffer(target, buffer);
      gl.bufferData(target, item.bytes, gl.STATIC_DRAW);
      item[key] = buffer;
    }
    return item[key];
  };
  const matrix4 = (pointer) => {
    const m = doubles(pointer, 16);
    return new Float32Array([m[0],m[4],m[8],m[12],m[1],m[5],m[9],m[13],m[2],m[6],m[10],m[14],m[3],m[7],m[11],m[15]]);
  };
  const matrix3 = (pointer) => {
    const m = doubles(pointer, 9);
    return new Float32Array([m[0],m[3],m[6],m[1],m[4],m[7],m[2],m[5],m[8]]);
  };
  const setLighting = (gl, p, pointer) => {
    const l = doubles(pointer, LIGHTING_PARAMS);
    gl.uniform2f(gl.getUniformLocation(p, "lightLevels"), l[0], l[1]);
    gl.uniform3f(gl.getUniformLocation(p, "lightDirection"), l[2], l[3], l[4]);
    gl.uniform3f(gl.getUniformLocation(p, "eyePosition"), l[5], l[6], l[7]);
    gl.uniform3f(gl.getUniformLocation(p, "lightColor"), l[8], l[9], l[10]);
    gl.uniform3f(gl.getUniformLocation(p, "ambientColor"), l[11], l[12], l[13]);
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
      F1:50,F2:51,F3:52,F4:53,F5:54,F6:55,F7:56,F8:57,F9:58,F10:59,F11:60,F12:61,
      Numpad0:62,Numpad1:63,Numpad2:64,Numpad3:65,Numpad4:66,Numpad5:67,Numpad6:68,Numpad7:69,Numpad8:70,Numpad9:71,NumpadDecimal:72,NumpadEnter:73,NumpadAdd:74,NumpadSubtract:75,NumpadMultiply:76,NumpadDivide:77,NumpadEqual:78,NumpadClear:79})[code] || 0;
  };
  const mouseButton = (button) => button === 0 ? 0 : button === 2 ? 1 : button === 1 ? 2 : 3;
  // Browsers report wheel deltas with the opposite sign to macOS and Windows and in pixels,
  // lines or pages. std/game reports them like the desktop: positive moves content down,
  // about one unit per wheel notch.
  const wheelNotches = (value) => value.deltaMode === 1 ? 1 / 3 : value.deltaMode === 2 ? 3 : 1 / 100;

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
      const gl = canvas.getContext("webgl2", { alpha: false, antialias: true, depth: true });
      if (!gl) return 0;
      const id = nextWindow++;
      windows.set(id, {
        id, canvas, gl, window: document.defaultView ?? globalThis,
        running: false, frame: 0, timeSeconds: 0, pointerX: 0.5, pointerY: 0.5, cleanup: [],
      });
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
      const updatePointer = value => {
        entry.pointerX = entry.canvas.clientWidth > 0 ? value.offsetX / entry.canvas.clientWidth : 0.5;
        entry.pointerY = entry.canvas.clientHeight > 0 ? 1 - value.offsetY / entry.canvas.clientHeight : 0.5;
      };
      listen(entry.canvas, "pointerdown", value => { updatePointer(value);entry.canvas.focus();entry.canvas.setPointerCapture?.(value.pointerId);event(4,0,mouseButton(value.button),value.offsetX,value.offsetY); });
      listen(entry.window, "pointerup", value => event(5,0,mouseButton(value.button),value.offsetX||0,value.offsetY||0));
      listen(entry.canvas, "pointermove", value => { updatePointer(value);event(6,0,0,value.offsetX,value.offsetY,value.movementX,value.movementY); });
      listen(entry.canvas, "wheel", value => { const notches=wheelNotches(value);event(7,0,0,value.offsetX,value.offsetY,0,0,-value.deltaX*notches,-value.deltaY*notches);value.preventDefault(); }, { passive:false });
      listen(entry.window, "resize", () => { if(resize(entry))event(1); });
      entry.running = true;
      const tick = (timestamp) => { if(!entry.running)return;entry.timeSeconds=timestamp*0.001;if(resize(entry))event(1);try{frame(timestamp);}catch(error){entry.running=false;onError(error);}if(entry.running)entry.frame=entry.window.requestAnimationFrame(tick); };
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
      const { gl }=gameWindow(id);const vertexData=new Float32Array(doubles(verticesPointer,vertexValueCount));const indexData=new Uint32Array(memory(),indicesPointer,indexCount).slice();const vertex=gl.createBuffer(),index=gl.createBuffer();gl.bindBuffer(gl.ARRAY_BUFFER,vertex);gl.bufferData(gl.ARRAY_BUFFER,vertexData,gl.STATIC_DRAW);gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER,index);gl.bufferData(gl.ELEMENT_ARRAY_BUFFER,indexData,gl.STATIC_DRAW);return saveResource("mesh",{window:id,vertex,index,indexCount});
    },
    batch_create(id, capacity) { const {gl}=gameWindow(id);if(capacity<=0)return 0;const buffer=gl.createBuffer();if(!buffer)return 0;gl.bindBuffer(gl.ARRAY_BUFFER,buffer);gl.bufferData(gl.ARRAY_BUFFER,capacity*BATCH_INSTANCE_STRIDE,gl.DYNAMIC_DRAW);return saveResource("batch",{window:id,buffer,capacity}); },
    batch_set_instance(id, batchId, slot, pointer, count) { const {gl}=gameWindow(id),batch=resource(batchId,"batch");if(slot<0||slot>=batch.capacity||count!==BATCH_INSTANCE_FLOATS)throw new Error("Invalid Doof game model batch instance upload");const values=new Float32Array(memory(),pointer,count).slice();gl.bindBuffer(gl.ARRAY_BUFFER,batch.buffer);gl.bufferSubData(gl.ARRAY_BUFFER,slot*BATCH_INSTANCE_STRIDE,values); },
    dust_create(id, pointer, count) { const {gl}=gameWindow(id);const buffer=gl.createBuffer();gl.bindBuffer(gl.ARRAY_BUFFER,buffer);gl.bufferData(gl.ARRAY_BUFFER,new Float32Array(doubles(pointer,count)),gl.STATIC_DRAW);return saveResource("dust",{window:id,buffer,count:count/4}); },
    shader_buffer_create(id, pointer, count) {
      gameWindow(id);if(count<=0)return 0;
      // GL buffers are created lazily per binding target: WebGL 2 forbids
      // binding one buffer object as both an index buffer and anything else.
      return saveResource("shaderBuffer",{window:id,bytes:new Uint8Array(memory(),pointer,count).slice(),byteLength:count,arrayBuffer:null,elementBuffer:null});
    },
    shader_buffer_update(id, bufferId, pointer, count, offset) {
      const {gl}=gameWindow(id),item=resource(bufferId,"shaderBuffer");
      if(count<=0||offset<0||offset+count>item.byteLength)return 0;
      const data=new Uint8Array(memory(),pointer,count);item.bytes.set(data,offset);
      if(item.arrayBuffer){gl.bindBuffer(gl.ARRAY_BUFFER,item.arrayBuffer);gl.bufferSubData(gl.ARRAY_BUFFER,offset,data);}
      if(item.elementBuffer){gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER,item.elementBuffer);gl.bufferSubData(gl.ELEMENT_ARRAY_BUFFER,offset,data);}
      return 1;
    },
    shader_pipeline_create(id, vertexSourcePointer, fragmentSourcePointer, attributeIndicesPointer, attributeBuffersPointer, attributeOffsetsPointer, attributeFormatsPointer, attributeCount, layoutBuffersPointer, layoutStridesPointer, layoutStepFunctionsPointer, layoutStepRatesPointer, layoutCount, uniformNamesPointer, uniformCount, textureNamesPointer, textureCount) {
      const {gl}=gameWindow(id);
      let value=null;
      try {
        value=program(gl,readString(vertexSourcePointer),readString(fragmentSourcePointer));
        // Uniform slot ordinals double as UBO binding points and texture slot
        // ordinals as texture units, so draws can bind by ordinal.
        const uniforms=strings(uniformNamesPointer,uniformCount).map((name,binding)=>{
          const blockIndex=gl.getUniformBlockIndex(value,name);
          if(blockIndex===gl.INVALID_INDEX)throw new Error(`WebGL 2 shader has no uniform block named '${name}'`);
          gl.uniformBlockBinding(value,blockIndex,binding);
          return {name,size:gl.getActiveUniformBlockParameter(value,blockIndex,gl.UNIFORM_BLOCK_DATA_SIZE),stream:null};
        });
        gl.useProgram(value);
        const textures=strings(textureNamesPointer,textureCount).map((name,unit)=>{
          const location=gl.getUniformLocation(value,name);
          if(location!==null)gl.uniform1i(location,unit);
          return {name};
        });
        return saveResource("shaderPipeline",{window:id,value,uniforms,textures,
          runtimeUniforms:{
            time:gl.getUniformLocation(value,"doofTime"),
            viewport:gl.getUniformLocation(value,"doofViewport"),
            pointer:gl.getUniformLocation(value,"doofPointer"),
          },
          attributeIndices:ints(attributeIndicesPointer,attributeCount),attributeBuffers:ints(attributeBuffersPointer,attributeCount),attributeOffsets:ints(attributeOffsetsPointer,attributeCount),attributeFormats:ints(attributeFormatsPointer,attributeCount),
          layoutBuffers:ints(layoutBuffersPointer,layoutCount),layoutStrides:ints(layoutStridesPointer,layoutCount),layoutStepFunctions:ints(layoutStepFunctionsPointer,layoutCount),layoutStepRates:ints(layoutStepRatesPointer,layoutCount)});
      } catch(error) { if(value)gl.deleteProgram(value);onError(error);return 0; }
    },
    shader_draw(id, pipelineId, vertexBufferIndicesPointer, vertexBufferHandlesPointer, vertexBufferOffsetsPointer, vertexBufferCount, uniformSlotsPointer, uniformHandlesPointer, uniformOffsetsPointer, uniformLengthsPointer, uniformCount, uniformBytesPointer, uniformBytesLength, textureSlotsPointer, textureHandlesPointer, textureCount, indexBufferId, indexCount, vertexCount, instanceCount) {
      const entry=gameWindow(id),{gl,canvas}=entry,enabled=[];
      try {
        const pipeline=resource(pipelineId,"shaderPipeline");
        const bindingIndices=ints(vertexBufferIndicesPointer,vertexBufferCount),bindingHandles=ints(vertexBufferHandlesPointer,vertexBufferCount),bindingOffsets=ints(vertexBufferOffsetsPointer,vertexBufferCount);
        const bindings=new Map();for(let i=0;i<vertexBufferCount;i+=1)bindings.set(bindingIndices[i],{buffer:resource(bindingHandles[i],"shaderBuffer"),offset:bindingOffsets[i]});
        const layouts=new Map();for(let i=0;i<pipeline.layoutBuffers.length;i+=1)layouts.set(pipeline.layoutBuffers[i],{stride:pipeline.layoutStrides[i],stepFunction:pipeline.layoutStepFunctions[i],stepRate:pipeline.layoutStepRates[i]});
        gl.useProgram(pipeline.value);
        if(pipeline.runtimeUniforms.time!==null)gl.uniform1f(pipeline.runtimeUniforms.time,entry.timeSeconds);
        if(pipeline.runtimeUniforms.viewport!==null)gl.uniform2f(pipeline.runtimeUniforms.viewport,canvas.width,canvas.height);
        if(pipeline.runtimeUniforms.pointer!==null)gl.uniform2f(pipeline.runtimeUniforms.pointer,entry.pointerX,entry.pointerY);

        const uniformSlots=ints(uniformSlotsPointer,uniformCount),uniformHandles=ints(uniformHandlesPointer,uniformCount),uniformOffsets=ints(uniformOffsetsPointer,uniformCount),uniformLengths=ints(uniformLengthsPointer,uniformCount);
        for(let i=0;i<uniformCount;i+=1){
          const binding=uniformSlots[i],slot=pipeline.uniforms[binding];
          if(!slot)throw new Error(`Unknown WebGL 2 shader uniform slot ${binding}`);
          if(uniformLengths[i]<slot.size&&uniformHandles[i])throw new Error(`WebGL 2 uniform block '${slot.name}' needs ${slot.size} bytes but its buffer range has ${uniformLengths[i]}`);
          if(uniformHandles[i]){
            const buffer=shaderGlBuffer(gl,resource(uniformHandles[i],"shaderBuffer"),gl.UNIFORM_BUFFER);
            gl.bindBufferRange(gl.UNIFORM_BUFFER,binding,buffer,uniformOffsets[i],uniformLengths[i]);
            continue;
          }
          if(uniformOffsets[i]<0||uniformOffsets[i]+uniformLengths[i]>uniformBytesLength)throw new Error("WebGL 2 shader uniform bytes are out of range");
          const data=new Uint8Array(memory(),uniformBytesPointer+uniformOffsets[i],uniformLengths[i]);
          // Pad short blocks to the size the linker reported so the draw is valid.
          let upload=data;if(data.length<slot.size){upload=new Uint8Array(slot.size);upload.set(data);}
          if(!slot.stream)slot.stream=gl.createBuffer();
          gl.bindBuffer(gl.UNIFORM_BUFFER,slot.stream);gl.bufferData(gl.UNIFORM_BUFFER,upload,gl.DYNAMIC_DRAW);
          gl.bindBufferBase(gl.UNIFORM_BUFFER,binding,slot.stream);
        }

        const textureSlots=ints(textureSlotsPointer,textureCount),textureHandles=ints(textureHandlesPointer,textureCount);
        for(let i=0;i<textureCount;i+=1){
          if(!pipeline.textures[textureSlots[i]])throw new Error(`Unknown WebGL 2 shader texture slot ${textureSlots[i]}`);
          gl.activeTexture(gl.TEXTURE0+textureSlots[i]);gl.bindTexture(gl.TEXTURE_2D,resource(textureHandles[i],"texture").value);
        }
        if(textureCount>0)gl.activeTexture(gl.TEXTURE0);

        for(let i=0;i<pipeline.attributeIndices.length;i+=1){const location=pipeline.attributeIndices[i],binding=bindings.get(pipeline.attributeBuffers[i]),layout=layouts.get(pipeline.attributeBuffers[i]);if(!binding||!layout)throw new Error(`Missing WebGL 2 shader buffer ${pipeline.attributeBuffers[i]}`);gl.bindBuffer(gl.ARRAY_BUFFER,shaderGlBuffer(gl,binding.buffer,gl.ARRAY_BUFFER));gl.enableVertexAttribArray(location);enabled.push(location);const offset=binding.offset+pipeline.attributeOffsets[i],format=pipeline.attributeFormats[i];if(format===5)gl.vertexAttribIPointer(location,1,gl.UNSIGNED_INT,layout.stride,offset);else{const sizes=[0,1,2,3,4,1,4],types=[0,gl.FLOAT,gl.FLOAT,gl.FLOAT,gl.FLOAT,gl.UNSIGNED_INT,gl.UNSIGNED_BYTE];gl.vertexAttribPointer(location,sizes[format],types[format],format===6,layout.stride,offset);}gl.vertexAttribDivisor(location,layout.stepFunction===2?layout.stepRate:0);}
        if(indexBufferId){gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER,shaderGlBuffer(gl,resource(indexBufferId,"shaderBuffer"),gl.ELEMENT_ARRAY_BUFFER));if(instanceCount>1)gl.drawElementsInstanced(gl.TRIANGLES,indexCount,gl.UNSIGNED_INT,0,instanceCount);else gl.drawElements(gl.TRIANGLES,indexCount,gl.UNSIGNED_INT,0);}else if(instanceCount>1)gl.drawArraysInstanced(gl.TRIANGLES,0,vertexCount,instanceCount);else gl.drawArrays(gl.TRIANGLES,0,vertexCount);
        return 1;
      } catch(error) { onError(error);return 0; }
      finally { for(const location of enabled){gl.vertexAttribDivisor(location,0);gl.disableVertexAttribArray(location);} }
    },
    resource_delete(id, kind, resourceId) { const {gl}=gameWindow(id),names=["mesh","dust","batch","shaderBuffer","shaderPipeline"],item=resource(resourceId,names[kind]);if(item.vertex)gl.deleteBuffer(item.vertex);if(item.index)gl.deleteBuffer(item.index);if(item.buffer)gl.deleteBuffer(item.buffer);if(item.arrayBuffer)gl.deleteBuffer(item.arrayBuffer);if(item.elementBuffer)gl.deleteBuffer(item.elementBuffer);if(item.value&&kind===4){gl.deleteProgram(item.value);for(const uniform of item.uniforms)if(uniform.stream)gl.deleteBuffer(uniform.stream);}resources.delete(resourceId); },
    draw_mesh(id, meshId, textureId, textured, blendMode, viewPointer, modelPointer, normalPointer, lightingPointer, materialPointer) {
      const entry=gameWindow(id),gl=entry.gl,mesh=resource(meshId,"mesh");if(!entry.meshProgram)entry.meshProgram=program(gl,meshVertexSource,litFragmentSource);
      const p=entry.meshProgram,m=doubles(materialPointer,MATERIAL_PARAMS);gl.useProgram(p);gl.bindBuffer(gl.ARRAY_BUFFER,mesh.vertex);gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER,mesh.index);for(const [name,size,offset] of [["position",3,0],["color",4,12],["uv",2,28],["normal",3,36]]){const location=gl.getAttribLocation(p,name);if(location<0)continue;gl.enableVertexAttribArray(location);gl.vertexAttribPointer(location,size,gl.FLOAT,false,48,offset);}gl.uniformMatrix4fv(gl.getUniformLocation(p,"viewProjection"),false,matrix4(viewPointer));gl.uniformMatrix4fv(gl.getUniformLocation(p,"model"),false,matrix4(modelPointer));gl.uniformMatrix3fv(gl.getUniformLocation(p,"normalMatrix"),false,matrix3(normalPointer));gl.uniform1f(gl.getUniformLocation(p,"textured"),textured?1:0);gl.uniform4f(gl.getUniformLocation(p,"tint"),m[0],m[1],m[2],m[3]);gl.uniform4f(gl.getUniformLocation(p,"materialEffects"),m[4],m[9],m[10],m[11]);gl.uniform4f(gl.getUniformLocation(p,"uvTransform"),m[5],m[6],m[7],m[8]);gl.uniform4f(gl.getUniformLocation(p,"materialParams"),m[12],m[13],0,0);setLighting(gl,p,lightingPointer);if(textured){gl.activeTexture(gl.TEXTURE0);gl.bindTexture(gl.TEXTURE_2D,resource(textureId,"texture").value);gl.uniform1i(gl.getUniformLocation(p,"colorTexture"),0);}gl.drawElements(gl.TRIANGLES,mesh.indexCount,gl.UNSIGNED_INT,0);
    },
    draw_batch(id, meshId, batchId, textureId, textured, blendMode, instanceCount, viewPointer, lightingPointer) {
      const entry=gameWindow(id),gl=entry.gl,mesh=resource(meshId,"mesh"),batch=resource(batchId,"batch");if(instanceCount<=0||instanceCount>batch.capacity)return;if(!entry.batchProgram)entry.batchProgram=program(gl,batchVertexSource,litFragmentSource);const p=entry.batchProgram;gl.useProgram(p);gl.bindBuffer(gl.ARRAY_BUFFER,mesh.vertex);gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER,mesh.index);for(const [name,size,offset] of [["position",3,0],["color",4,12],["uv",2,28],["normal",3,36]]){const location=gl.getAttribLocation(p,name);if(location<0)continue;gl.enableVertexAttribArray(location);gl.vertexAttribPointer(location,size,gl.FLOAT,false,48,offset);gl.vertexAttribDivisor(location,0);}gl.bindBuffer(gl.ARRAY_BUFFER,batch.buffer);const instanceAttributes=[["instanceRow0",0],["instanceRow1",4],["instanceRow2",8],["instanceRow3",12],["instanceNormal0",16],["instanceNormal1",20],["instanceNormal2",24],["instanceTint",28],["instanceEffects",32],["instanceUv",36],["instanceMaterial",40]];const enabled=[];for(const [name,floatOffset] of instanceAttributes){const location=gl.getAttribLocation(p,name);if(location<0)continue;enabled.push(location);gl.enableVertexAttribArray(location);gl.vertexAttribPointer(location,4,gl.FLOAT,false,BATCH_INSTANCE_STRIDE,floatOffset*4);gl.vertexAttribDivisor(location,1);}gl.uniformMatrix4fv(gl.getUniformLocation(p,"viewProjection"),false,matrix4(viewPointer));gl.uniform1f(gl.getUniformLocation(p,"textured"),textured?1:0);setLighting(gl,p,lightingPointer);if(textured){gl.activeTexture(gl.TEXTURE0);gl.bindTexture(gl.TEXTURE_2D,resource(textureId,"texture").value);gl.uniform1i(gl.getUniformLocation(p,"colorTexture"),0);}gl.drawElementsInstanced(gl.TRIANGLES,mesh.indexCount,gl.UNSIGNED_INT,0,instanceCount);for(const location of enabled){gl.vertexAttribDivisor(location,0);gl.disableVertexAttribArray(location);}
    },
    draw_sky(id, textureId, width, height, fovY, exposure, rotationPointer) {
      const entry=gameWindow(id),gl=entry.gl;if(!entry.skyProgram){entry.skyProgram=program(gl,"#version 300 es\nin vec2 position;out vec2 screenUv;void main(){screenUv=position;gl_Position=vec4(position,1.0,1.0);}","#version 300 es\nprecision mediump float;in vec2 screenUv;uniform sampler2D panorama;uniform mat3 cameraRotation;uniform float aspect;uniform float tanHalfFov;uniform float exposure;out vec4 fragmentColor;const float PI=3.14159265359;void main(){vec3 direction=normalize(cameraRotation*vec3(screenUv.x*aspect*tanHalfFov,screenUv.y*tanHalfFov,-1.0));float u=atan(direction.x,-direction.z)/(2.0*PI)+0.5;float v=asin(clamp(direction.y,-1.0,1.0))/PI+0.5;vec4 color=texture(panorama,vec2(u,v));fragmentColor=vec4(color.rgb*exposure,color.a);}");entry.skyBuffer=gl.createBuffer();gl.bindBuffer(gl.ARRAY_BUFFER,entry.skyBuffer);gl.bufferData(gl.ARRAY_BUFFER,new Float32Array([-1,-1,3,-1,-1,3]),gl.STATIC_DRAW);}const p=entry.skyProgram;gl.disable(gl.DEPTH_TEST);gl.depthMask(false);gl.disable(gl.CULL_FACE);gl.useProgram(p);gl.bindBuffer(gl.ARRAY_BUFFER,entry.skyBuffer);const position=gl.getAttribLocation(p,"position");gl.enableVertexAttribArray(position);gl.vertexAttribPointer(position,2,gl.FLOAT,false,0,0);gl.activeTexture(gl.TEXTURE0);gl.bindTexture(gl.TEXTURE_2D,resource(textureId,"texture").value);gl.uniform1i(gl.getUniformLocation(p,"panorama"),0);gl.uniformMatrix3fv(gl.getUniformLocation(p,"cameraRotation"),false,matrix3(rotationPointer));gl.uniform1f(gl.getUniformLocation(p,"aspect"),height>0?width/height:1);gl.uniform1f(gl.getUniformLocation(p,"tanHalfFov"),Math.tan(fovY*0.5));gl.uniform1f(gl.getUniformLocation(p,"exposure"),exposure);gl.drawArrays(gl.TRIANGLES,0,3);gl.enable(gl.DEPTH_TEST);gl.depthMask(true);
    },
    draw_dust(id, dustId, particleCount, pixelHeight, cameraX, cameraY, cameraZ, fieldSize, particleSize, fadeStart, fadeEnd, opacity, red, green, blue, matrixPointer) {
      const entry=gameWindow(id),gl=entry.gl,dust=resource(dustId,"dust");if(!entry.dustProgram)entry.dustProgram=program(gl,"#version 300 es\nin vec3 position;in float brightness;uniform mat4 cameraMatrix;uniform vec3 cameraPosition;uniform float fieldSize;uniform float particleSize;uniform float pixelScale;uniform float fadeStart;uniform float fadeEnd;uniform float opacity;out float particleAlpha;float wrapAxis(float value,float camera){float relative=value-camera;return(fract(relative/fieldSize+0.5)-0.5)*fieldSize+camera;}void main(){vec3 world=vec3(wrapAxis(position.x,cameraPosition.x),wrapAxis(position.y,cameraPosition.y),wrapAxis(position.z,cameraPosition.z));float distanceToCamera=length(world-cameraPosition);float fadeSpan=max(fadeEnd-fadeStart,0.001);particleAlpha=opacity*brightness*clamp((fadeEnd-distanceToCamera)/fadeSpan,0.0,1.0);gl_Position=cameraMatrix*vec4(world,1.0);gl_PointSize=max(particleSize*pixelScale*brightness,1.0);}","#version 300 es\nprecision mediump float;uniform vec3 dustColor;in float particleAlpha;out vec4 fragmentColor;void main(){vec2 delta=gl_PointCoord-vec2(0.5);float core=1.0-smoothstep(0.12,0.5,length(delta));fragmentColor=vec4(dustColor,particleAlpha*core);}");const p=entry.dustProgram;gl.enable(gl.BLEND);gl.blendFunc(gl.SRC_ALPHA,gl.ONE_MINUS_SRC_ALPHA);gl.enable(gl.DEPTH_TEST);gl.depthFunc(gl.LEQUAL);gl.depthMask(false);gl.useProgram(p);gl.bindBuffer(gl.ARRAY_BUFFER,dust.buffer);for(const [name,size,offset] of [["position",3,0],["brightness",1,12]]){const location=gl.getAttribLocation(p,name);gl.enableVertexAttribArray(location);gl.vertexAttribPointer(location,size,gl.FLOAT,false,16,offset);}gl.uniformMatrix4fv(gl.getUniformLocation(p,"cameraMatrix"),false,matrix4(matrixPointer));gl.uniform3f(gl.getUniformLocation(p,"cameraPosition"),cameraX,cameraY,cameraZ);gl.uniform1f(gl.getUniformLocation(p,"fieldSize"),fieldSize);gl.uniform1f(gl.getUniformLocation(p,"particleSize"),particleSize);gl.uniform1f(gl.getUniformLocation(p,"pixelScale"),pixelHeight/720);gl.uniform1f(gl.getUniformLocation(p,"fadeStart"),fadeStart);gl.uniform1f(gl.getUniformLocation(p,"fadeEnd"),fadeEnd);gl.uniform1f(gl.getUniformLocation(p,"opacity"),opacity);gl.uniform3f(gl.getUniformLocation(p,"dustColor"),red,green,blue);gl.drawArrays(gl.POINTS,0,particleCount);gl.depthMask(true);
    },
  };

  return { imports, attach(value) { instance = value; }, memory() { return instance?.exports.memory.buffer; } };
}

export const __testing = { createGameBridge };

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
