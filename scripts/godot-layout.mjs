// Native decoration corrections, derived from the preserved web authoring mesh.
// Functional nodes and their indexed geometry are deliberately never edited.
import assert from 'node:assert/strict';
import {Matrix4,Vector3,Quaternion,Box3} from '../vendor/three/build/three.module.js';

export function refineNativeLayout(doc,binary){
 const nodes=doc.nodes,parents=new Map(),worldCache=new Map(),changedAccessors=new Set(),patchCache=new Set(),originalPositions=new Map();
 nodes.forEach((n,i)=>(n.children??[]).forEach(c=>parents.set(c,i)));
 const report={revision:1,keyboards:[],props:[],chairs:[],compoundProps:[],labels:[],suppressedDuplicateLabels:[]};
 const floats=i=>{const a=doc.accessors[i],v=doc.bufferViews[a.bufferView];assert.equal(a.componentType,5126);const count={VEC2:2,VEC3:3,VEC4:4}[a.type];return new Float32Array(binary.buffer,binary.byteOffset+(v.byteOffset??0)+(a.byteOffset??0),a.count*count);};
 const indices=i=>{const a=doc.accessors[i],v=doc.bufferViews[a.bufferView],Type={5125:Uint32Array,5123:Uint16Array,5121:Uint8Array}[a.componentType];return new Type(binary.buffer,binary.byteOffset+(v.byteOffset??0)+(a.byteOffset??0),a.count);};
 const original=i=>{if(!originalPositions.has(i))originalPositions.set(i,floats(i).slice());return originalPositions.get(i);};
 function partBounds(i,region){
  const box=new Box3(),selection=region.clone().expandByScalar(.005);
  for(const p of doc.meshes[nodes[i].mesh].primitives){
   if(/Cable/.test(doc.materials[p.material].name))continue;
   const pos=original(p.attributes.POSITION);
   for(const ix of indices(p.indices)){const point=new Vector3(pos[ix*3],pos[ix*3+1],pos[ix*3+2]);if(selection.containsPoint(point))box.expandByPoint(point);}
  }
  assert.ok(!box.isEmpty(),nodes[i].name+' prop bounds');return box;
 }
 function local(i){const n=nodes[i];return n.matrix?new Matrix4().fromArray(n.matrix):new Matrix4().compose(new Vector3().fromArray(n.translation??[0,0,0]),new Quaternion().fromArray(n.rotation??[0,0,0,1]),new Vector3().fromArray(n.scale??[1,1,1]));}
 function world(i){if(!worldCache.has(i))worldCache.set(i,parents.has(i)?world(parents.get(i)).clone().multiply(local(i)):local(i));return worldCache.get(i).clone();}
 function bounds(i,relative=null,wood=false){
  const b=new Box3(),n=nodes[i];
  for(const p of doc.meshes[n.mesh]?.primitives??[]){
   if(wood&&!/Maple_Desk_Veneer/.test(doc.materials[p.material].name))continue;
   const v=floats(p.attributes.POSITION);
   for(const ix of indices(p.indices))b.expandByPoint(new Vector3(v[ix*3],v[ix*3+1],v[ix*3+2]));
  }
  return b.applyMatrix4(relative===null?world(i):world(relative).invert().multiply(world(i)));
 }
 function move(i,delta,relative){
  assert.ok(!/^(INTERACT_|DOOR_|COLLIDER_|SPAWN_)/.test(nodes[i].name));
  const vector=delta.clone().transformDirection(world(relative)).multiplyScalar(delta.length());
  const parent=parents.get(i),parentVector=parent===undefined?vector:vector.clone().transformDirection(world(parent).invert()).multiplyScalar(vector.length());
  const transform=local(i);transform.setPosition(new Vector3().setFromMatrixPosition(transform).add(parentVector));
  if(nodes[i].matrix)nodes[i].matrix=transform.toArray();else nodes[i].translation=new Vector3().setFromMatrixPosition(transform).toArray();
  worldCache.clear();return vector;
 }
 function patch(i,region,delta,rotation=false,skipCable=false){
  const mesh=doc.meshes[nodes[i].mesh],sets=new Map();
  for(const p of mesh.primitives){
   if(skipCable&&/Cable/.test(doc.materials[p.material].name))continue;
   // Rotate the keycaps/legends, not just the top half of the keyboard case.
   if(rotation&&!/Powder|Ink/.test(doc.materials[p.material].name))continue;
   const key=[p.attributes.POSITION,p.attributes.NORMAL,p.attributes.TANGENT].join('/');
   if(!sets.has(key))sets.set(key,{p,set:new Set()});for(const ix of indices(p.indices))sets.get(key).set.add(ix);
  }
  let count=0;
  for(const {p,set}of sets.values()){
   // AO UVs can differ between stations sharing the same position accessor.
   // Track each edited vertex/normal independently so sharing never flips it twice.
   // Quantized tabletops vary by micrometres even when their prop geometry is
   // shared. Treat sub-0.1 mm support differences as the same mesh operation.
   const operation=JSON.stringify([region.min.toArray(),region.max.toArray(),delta.toArray().map(v=>Math.round(v*1e4)/1e4),rotation]);
   const pos=floats(p.attributes.POSITION),sourcePos=original(p.attributes.POSITION),normal=p.attributes.NORMAL===undefined?null:floats(p.attributes.NORMAL),tangent=p.attributes.TANGENT===undefined?null:floats(p.attributes.TANGENT);
   const center=region.getCenter(new Vector3());
   // Source meshopt quantization and bevels can extend a few millimetres beyond
   // nominal prop dimensions. Include those vertices to avoid stretched faces.
   const selection=region.clone().expandByScalar(.005);
   for(const primitive of mesh.primitives.filter(q=>q.attributes.POSITION===p.attributes.POSITION)){
    if(skipCable&&/Cable/.test(doc.materials[primitive.material].name))continue;
    if(rotation&&!/Powder|Ink/.test(doc.materials[primitive.material].name))continue;
    const ids=indices(primitive.indices);
    for(let j=0;j<ids.length;j+=3){
     if([ids[j],ids[j+1],ids[j+2]].every(ix=>patchCache.has('p/'+p.attributes.POSITION+'/'+ix+'/'+operation)))continue;
     const inside=[ids[j],ids[j+1],ids[j+2]].filter(ix=>selection.containsPoint(new Vector3(sourcePos[ix*3],sourcePos[ix*3+1],sourcePos[ix*3+2]))).length;
     assert.ok(inside===0||inside===3,nodes[i].name+' partial prop triangle '+JSON.stringify([ids[j],ids[j+1],ids[j+2]].map(ix=>[pos[ix*3],pos[ix*3+1],pos[ix*3+2]])));
    }
   }
   for(const ix of set){
    const v=new Vector3(sourcePos[ix*3],sourcePos[ix*3+1],sourcePos[ix*3+2]);if(!selection.containsPoint(v))continue;
    const positionKey='p/'+p.attributes.POSITION+'/'+ix+'/'+operation;
    if(!patchCache.has(positionKey)){
     if(rotation){v.x=center.x*2-v.x;v.z=center.z*2-v.z;}
     v.add(delta);pos[ix*3]=v.x;pos[ix*3+1]=v.y;pos[ix*3+2]=v.z;patchCache.add(positionKey);count++;
    }
    if(rotation&&normal){const k='n/'+p.attributes.NORMAL+'/'+ix+'/'+operation;if(!patchCache.has(k)){normal[ix*3]*=-1;normal[ix*3+2]*=-1;patchCache.add(k);}}
    if(rotation&&tangent){const k='t/'+p.attributes.TANGENT+'/'+ix+'/'+operation;if(!patchCache.has(k)){tangent[ix*4]*=-1;tangent[ix*4+2]*=-1;patchCache.add(k);}}
   }
   changedAccessors.add(p.attributes.POSITION);
  }
  return count;
 }
 const archive=nodes.findIndex(n=>n.name==='ENV_Desk_Archive');
 const roots=nodes.map((n,i)=>({n,i})).filter(({n})=>/^CORP_Staff_Seat_|^TRAIN_Workstation_|^ENV_Desk_0[234]$|^INTERACT_AdminPC$/.test(n.name));
 for(const {n,i:root}of roots){
  const children=n.children??[],num=Number(n.name.match(/\d+$/)?.[0]??1);
  let desk=children.find(c=>/^(CORP_Staff_Desk_|TRAIN_Desk_|Desk_)/.test(nodes[c].name));
  if(desk===undefined&&/^CORP_Staff_Seat_2[2-5]$/.test(n.name))desk=archive;
  assert.notEqual(desk,undefined,n.name+' tabletop');const table=bounds(desk,root,true);assert.ok(!table.isEmpty());
  const top=table.max.y,margin=.025;
  for(const c of children.filter(c=>/^CORP_Desk_Nameplate_/.test(nodes[c].name))){
   const b=bounds(c,root);move(c,new Vector3(0,top-.040-b.min.y,table.max.z+.0015-b.min.z),root);report.labels.push(nodes[c].name);
  }
  for(const c of children.filter(c=>/^TRAIN_SeatLabel_/.test(nodes[c].name))){delete nodes[c].mesh;nodes[c].extras={...nodes[c].extras,nativeSuppressedDuplicateLabel:true};report.suppressedDuplicateLabels.push(nodes[c].name);}
  if(n.name==='INTERACT_AdminPC')for(const c of children.filter(c=>/^CORP_SOC_Desk_(Plaque|Title)$/.test(nodes[c].name))){move(c,new Vector3(0,.080,-.004),root);report.labels.push(nodes[c].name);}
  const computer=children.find(c=>/^(Workstation_|TRAIN_Computer_|CORP_Staff_Computer_|CORP_Forensics_Computer_)/.test(nodes[c].name));
  if(computer!==undefined){
   const forensic=/Forensics/.test(nodes[computer].name),cx=forensic?0:-.22,cz=forensic?.17:.22;
   const region=new Box3(new Vector3(cx-.214,.833,cz-.073),new Vector3(cx+.214,.848,cz+.073));
   patch(computer,region,new Vector3(),true);
   const dy=top+.002-.8125;
   if(Math.abs(dy)>.0005){move(computer,new Vector3(0,dy,0),root);if(forensic)for(const c of children.filter(c=>/^CORP_Forensics_Display_/.test(nodes[c].name)))move(c,new Vector3(0,dy,0),root);}
   report.keyboards.push({name:nodes[computer].name,root:n.name,center:[cx,cz],spacebarSide:'operator',top});
  }
  const laptop=children.find(c=>/^IP05_Laptop_Screen_/.test(nodes[c].name));
  for(const c of children){
   const name=nodes[c].name;
   if(!/^(CORP_(Document|Pen|PenCup|StickyNotes|Desk_Phone)_|EX07_Desk_|IP05_Open_Notebook_|TRAIN_Props_Variant_|ADMIN_Incident_Document$)/.test(name))continue;
   const before=bounds(c,root),center=before.getCenter(new Vector3()),size=before.getSize(new Vector3());
   const desired=center.clone();
   if(/Pen_Tray/.test(name)){desired.x=.50;desired.z=.34;}
   if(/StickyNotes/.test(name)&&laptop!==undefined){desired.x=.28;desired.z=.35;}
   if(/Desk_Phone/.test(name)&&laptop!==undefined){desired.x=-.85;desired.z=table.min.z+margin+size.z/2;}
   desired.x=Math.max(table.min.x+margin+size.x/2,Math.min(table.max.x-margin-size.x/2,desired.x));
   desired.z=Math.max(table.min.z+margin+size.z/2,Math.min(table.max.z-margin-size.z/2,desired.z));
   const delta=new Vector3(desired.x-center.x,top+.002-before.min.y,desired.z-center.z);
   move(c,delta,root);const after=bounds(c,root);
   assert.ok(Math.abs(after.min.y-top-.002)<.0001,name+' support');
   assert.ok(after.min.x>=table.min.x+margin-.0001&&after.max.x<=table.max.x-margin+.0001&&after.min.z>=table.min.z+margin-.0001&&after.max.z<=table.max.z-margin+.0001,name+' footprint');
   report.props.push({name,root:n.name,before:[before.min.toArray(),before.max.toArray()],after:[after.min.toArray(),after.max.toArray()],table:[table.min.toArray(),table.max.toArray()]});
  }
  const personal=children.find(c=>/^CORP_Personal_Details_/.test(nodes[c].name));
  if(personal!==undefined){
   const personalNum=Number(nodes[personal].name.match(/\d+$/)[0]),base=personalNum>=22&&personalNum<=25?.850:.811;
   if(personalNum%3!==0){
    const mug=personalNum%3===1;
    const region=new Box3(new Vector3(.20,base-.02,-.30),new Vector3(1.10,base+.20,.30));
    const part=partBounds(personal,region),center=part.getCenter(new Vector3()),size=part.getSize(new Vector3());
    const hasPlant=children.some(c=>/^EX07_Desk_Plant_/.test(nodes[c].name));
    const x=Math.min(mug?.84:.83,table.max.x-margin-size.x/2),z=Math.max(hasPlant?0:(mug?-.22:-.20),table.min.z+margin+size.z/2);
    patch(personal,region,new Vector3(x-center.x,top+.002-part.min.y,z-center.z),false,true);
    report.compoundProps.push({name:nodes[personal].name,part:mug?'mug':'headset',center:[x,z],support:top});
   }
  }
  const accessory=children.find(c=>/^IP05_Seat_\d+_Managed_Accessories/.test(nodes[c].name));
  if(accessory!==undefined){
   const variant=Number(nodes[accessory].name.match(/Seat_(\d+)/)[1])%4;
   if(variant!==2){
    const region=new Box3(new Vector3(.35,.80,0),new Vector3(1.20,1.10,.27));
    const part=partBounds(accessory,region),center=part.getCenter(new Vector3()),size=part.getSize(new Vector3());
    const x=Math.max(table.min.x+margin+size.x/2,Math.min(table.max.x-margin-size.x/2,center.x));
    const z=Math.max(table.min.z+margin+size.z/2,Math.min(table.max.z-margin-size.z/2,variant===1?.30:center.z));
    const delta=new Vector3(x-center.x,top+.002-part.min.y,z-center.z);
    patch(accessory,region,delta,false,true);if(laptop!==undefined)move(laptop,delta,root);
    report.compoundProps.push({name:nodes[accessory].name,part:['phone','hub','','laptop'][variant],center:[x,z],support:top});
   }
  }
  let chair=children.find(c=>/^(CORP_Staff_Chair_|TRAIN_Chair_)/.test(nodes[c].name));
  let collider=children.find(c=>/^COLLIDER_.*Chair/.test(nodes[c].name));
  if(/^ENV_Desk_|^INTERACT_AdminPC/.test(n.name)){chair=nodes.findIndex(o=>o.name==='ENV_Chair_'+String(num).padStart(2,'0'));collider=nodes.findIndex(o=>o.name==='COLLIDER_Chair_'+(num-1));}
  assert.ok(chair!==undefined&&chair>=0&&collider!==undefined&&collider>=0,n.name+' chair');
  const before=bounds(chair,root),gap=before.min.z-table.max.z,delta=new Vector3(0,0,.09-gap);
  const shift=move(chair,delta,root);report.chairs.push({name:nodes[chair].name,collider:nodes[collider].name,root:n.name,beforeGap:gap,afterGap:.09,shift_world:shift.toArray()});
 }
 for(const index of changedAccessors){const a=doc.accessors[index],v=floats(index),b=new Box3();for(let i=0;i<v.length;i+=3)b.expandByPoint(new Vector3(v[i],v[i+1],v[i+2]));a.min=b.min.toArray();a.max=b.max.toArray();}
 assert.equal(report.keyboards.length,26);assert.equal(report.chairs.length,26);
 doc.asset.extras.nativeDressingRevision=report.revision;
 return report;
}
