// Offline lossless decompression of the shipped v0.7.0 base mesh. Godot runs no
// web decoder, browser LOD selector, batching system or JavaScript at runtime.
import fs from 'node:fs';
import crypto from 'node:crypto';
import {MeshoptDecoder} from 'three/examples/jsm/libs/meshopt_decoder.module.js';
await MeshoptDecoder.ready;
const source='assets/models/security_lab.glb',destination='godot/assets/models/Interior_07_Godot.glb';
const input=fs.readFileSync(source),length=input.readUInt32LE(12);
const doc=JSON.parse(input.subarray(20,20+length)),binary=input.subarray(28+length);
const parts=[];let offset=0;
for(const view of doc.bufferViews){
 const extension=view.extensions?.EXT_meshopt_compression;
 let data;
 if(extension){data=new Uint8Array(extension.count*extension.byteStride);MeshoptDecoder.decodeGltfBuffer(data,extension.count,extension.byteStride,binary.subarray(extension.byteOffset,extension.byteOffset+extension.byteLength),extension.mode,extension.filter);}
 else data=binary.subarray(view.byteOffset||0,(view.byteOffset||0)+view.byteLength);
 if(offset%4){const pad=4-offset%4;parts.push(Buffer.alloc(pad));offset+=pad;}
 view.buffer=0;view.byteOffset=offset;view.byteLength=data.byteLength;
 if(view.extensions){delete view.extensions.EXT_meshopt_compression;if(!Object.keys(view.extensions).length)delete view.extensions;}
 parts.push(Buffer.from(data));offset+=data.byteLength;
}
for(const mesh of doc.meshes)for(const primitive of mesh.primitives)if(primitive.extras)delete primitive.extras.runtimeLOD;
for(const field of ['extensionsUsed','extensionsRequired'])doc[field]=doc[field]?.filter(e=>e!=='EXT_meshopt_compression');
doc.buffers=[{byteLength:offset}];
const protectedNodes=Object.fromEntries(doc.nodes.filter(n=>/^(INTERACT_|DOOR_|COLLIDER_|SPAWN_)/.test(n.name)).map(n=>[n.name,Object.fromEntries(['matrix','translation','rotation','scale','extras'].filter(k=>k in n).map(k=>[k,n[k]]))]));
doc.asset.extras={nativeBaseSourceSHA256:crypto.createHash('sha256').update(input).digest('hex'),baseErrorMetres:.0012,protectedNodes:Object.keys(protectedNodes).length,nativeLOD:'Godot importer'};
const json=Buffer.from(JSON.stringify(doc));const jsonPad=Buffer.concat([json,Buffer.alloc((-json.length)&3,32)]),bin=Buffer.concat(parts),binPad=Buffer.concat([bin,Buffer.alloc((-bin.length)&3)]);
const header=Buffer.alloc(20);header.writeUInt32LE(0x46546c67);header.writeUInt32LE(2,4);header.writeUInt32LE(28+jsonPad.length+binPad.length,8);header.writeUInt32LE(jsonPad.length,12);header.writeUInt32LE(0x4e4f534a,16);
const binHeader=Buffer.alloc(8);binHeader.writeUInt32LE(binPad.length);binHeader.writeUInt32LE(0x004e4942,4);
fs.mkdirSync('godot/assets/models',{recursive:true});fs.writeFileSync(destination,Buffer.concat([header,jsonPad,binHeader,binPad]));
fs.writeFileSync('godot/resources/functional.json',JSON.stringify(protectedNodes,null,2)+'\n');
console.log(JSON.stringify({bytes:fs.statSync(destination).size,sourceSHA256:doc.asset.extras.nativeBaseSourceSHA256,protectedNodes:Object.keys(protectedNodes).length}));
