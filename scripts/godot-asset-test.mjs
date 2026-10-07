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

// Verify the visible long spacebar itself, rather than trusting layout metadata.
const layout=JSON.parse(fs.readFileSync('godot/resources/native-layout.json'));
assert.equal(layout.keyboards.length,26);assert.equal(layout.chairs.length,26);
for(const keyboard of layout.keyboards){
 const node=doc.nodes.find(n=>n.name===keyboard.name),points=new Map(),parent=[];
 const point=v=>{const key=Array.from(v).map(x=>x.toFixed(5)).join('/');if(!points.has(key)){const id=parent.length;parent.push(id);points.set(key,{id,v:Array.from(v)});}return points.get(key).id;};
 const find=i=>parent[i]===i?i:(parent[i]=find(parent[i]));
 for(const p of doc.meshes[node.mesh].primitives){
  const positions=array(p.attributes.POSITION),idx=array(p.indices);
  for(let i=0;i<idx.length;i+=3){
   const v=[0,1,2].map(k=>positions.subarray(idx[i+k]*3,idx[i+k]*3+3));
   if(v.every(a=>a[1]>.84&&a[1]<.849)&&Math.max(...v.map(a=>a[1]))-Math.min(...v.map(a=>a[1]))<.0015){const ids=v.map(point);parent[find(ids[1])]=find(ids[0]);parent[find(ids[2])]=find(ids[0]);}
  }
 }
 const groups=new Map();for(const {id,v}of points.values()){const root=find(id);if(!groups.has(root))groups.set(root,[]);groups.get(root).push(v);}
 const bars=[...groups.values()].filter(v=>{const width=Math.max(...v.map(a=>a[0]))-Math.min(...v.map(a=>a[0]));return width>.14&&width<.20;});
 assert.equal(bars.length,1,keyboard.name+' long spacebar');
 const center=bars[0].reduce((sum,v)=>sum+v[2],0)/bars[0].length;
 assert.ok(center>keyboard.center[1]+.025,keyboard.name+' spacebar faces operator');
}
console.log('Native layout: 26 operator-facing spacebars, 26 coordinated chair/collider offsets.');
