import fs from 'node:fs';
import crypto from 'node:crypto';
import assert from 'node:assert/strict';
const bytes=fs.readFileSync('godot/assets/models/Interior_07_Godot.glb'),length=bytes.readUInt32LE(12);
const doc=JSON.parse(bytes.subarray(20,20+length)),binary=bytes.subarray(28+length);
const baseline=JSON.parse(fs.readFileSync('assets/models/security_lab_runtime_functional.json'));
const nodes=doc.nodes.filter(n=>/^(DOOR_|COLLIDER_|INTERACT_|SPAWN_)/.test(n.name)).map(({mesh,children,...n})=>n);
assert.deepEqual(nodes,baseline.nodes);
assert.ok(!doc.extensionsRequired?.includes('EXT_meshopt_compression'));
function array(index){const a=doc.accessors[index],v=doc.bufferViews[a.bufferView],Type={5126:Float32Array,5125:Uint32Array,5123:Uint16Array}[a.componentType];return new Type(binary.buffer,binary.byteOffset+(v.byteOffset||0)+(a.byteOffset||0),a.count*(a.type==='VEC3'?3:1));}
for(const [name,expected] of Object.entries(baseline.geometry)){
 const node=doc.nodes.find(n=>n.name===name),hash=crypto.createHash('sha256');
 for(const p of doc.meshes[node.mesh].primitives){const positions=array(p.attributes.POSITION),indices=array(p.indices),values=new Float32Array(indices.length*3);for(let i=0;i<indices.length;i++)values.set(positions.subarray(indices[i]*3,indices[i]*3+3),i*3);hash.update(new Uint8Array(values.buffer));}
 assert.equal(hash.digest('hex'),expected,name);
}
console.log(`Native source: ${nodes.length} unchanged functional interfaces; ${Object.keys(baseline.geometry).length} exact indexed geometry hashes.`);
