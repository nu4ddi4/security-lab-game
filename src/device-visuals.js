import {CanvasTexture,MeshStandardMaterial,SRGBColorSpace,BufferAttribute} from '../vendor/three/build/three.module.js';
// Existing screen surfaces and LED slots only. Read-only simulated telemetry;
// E/F, raycasts, mission/save mutations and protected geometry remain unchanged.
const colors={neutral:'#98adba',warning:'#d3aa70',error:'#bb7970',normal:'#73ad96'};
const rootOf=o=>{for(let p=o;p;p=p.parent)if(p.name.startsWith('INTERACT_'))return p.name;return null;};
function severity(d){
 if(d.mission==='services')return !d.ports[443]?'error':d.ports[8080]?'warning':'normal';
 if(d.mission==='login')return d.login.adequate&&d.login.normal?'normal':'warning';
 if(d.mission==='integrity')return !d.hashes.length?'warning':d.hashes.some(r=>!r.matches)?'error':'normal';
 return 'neutral';
}
function readings(d){
 if(d.mission==='services')return [['443 / DOCUMENT SERVICE',d.ports[443]?'OPEN · HEALTHY':'FILTERED · UNAVAILABLE',d.ports[443]?'normal':'error'],['8080 / LEGACY MANAGEMENT',d.ports[8080]?'OPEN · EXPOSED':'FILTERED · ACCESS BLOCKED',d.ports[8080]?'warning':'normal']];
 if(d.mission==='login')return [['NORMAL DUMMY LOGIN',d.login.normal?'SUCCESS':'DENIED',d.login.normal?'normal':'error'],['REPEATED FAILURES',d.login.limited?'LIMITED AFTER 3 FAILURES':'UNLIMITED ATTEMPTS',d.login.limited?'normal':'warning'],['CANDIDATE POLICY',d.login.commonAllowed+' / 5 COMMON VALUES ACCEPTED · '+d.login.minLength+' CHARS',d.login.adequate?'normal':'warning']];
 if(d.mission==='integrity')return d.hashes.length?d.hashes.map(r=>[r.name,r.matches?'APPROVED HASH MATCHED':'HASH MISMATCH',r.matches?'normal':'error']):[['FILE COMPARISON',d.restored?'RESTORE APPLIED · NEW HASH SCAN DUE':'AWAITING APPROVED BASELINE / HASH SCAN','warning']];
 return [['AUTHORIZED SCOPE','club-server / BUILT-IN DATA','neutral'],['WORKFLOW','OBSERVE · DEFEND · CHECK','neutral']];
}
function phase(d){return d.verified?'CASE VERIFIED':d.changed&&!d.rechecked?'CONFIGURATION CHANGED · FIELD CHECK DUE':d.rechecked?'FIELD RECHECK RECORDED':'INCIDENT UNDER REVIEW';}
function label(c,t,x,y,size=20,color='#c8d5dc',bold=false,max=Infinity){c.font=`${bold?'600 ':''}${size}px "Segoe UI",sans-serif`;c.fillStyle=color;c.fillText(t,x,y,max);}
function line(c,x,y,w,color='#293943'){c.fillStyle=color;c.fillRect(x,y,w,1);}
function chart(c,x,y,w,h,color,seed=0){
 c.strokeStyle='#283740';c.lineWidth=1;for(let i=0;i<4;i++){c.beginPath();c.moveTo(x,y+i*h/3);c.lineTo(x+w,y+i*h/3);c.stroke();}
 c.strokeStyle=color;c.lineWidth=2.5;c.beginPath();for(let i=0;i<38;i++){const a=Math.sin(i*1.19+seed)*.14+Math.sin(i*.33+seed)*.2;const yy=y+h*(.55+a);if(i)c.lineTo(x+i*w/37,yy);else c.moveTo(x,yy);}c.stroke();
}
function frame(c,w,h,title,subtitle,color){
 c.fillStyle='#101b23';c.fillRect(0,0,w,h);c.fillStyle='#1d2d37';c.fillRect(0,0,w,48);label(c,'NORTH / '+title,20,31,18,'#deebe9',true,w-40);label(c,subtitle,20,75,13,'#96aab7',false,w-40);line(c,20,87,w-40,color);
}
function drawCase(c,w,h,d,kind){
 const color=colors[severity(d)];frame(c,w,h,kind==='soc'?'SECURITY OPERATIONS':'INCIDENT / '+kind.toUpperCase(),'CASE '+String(d.active).padStart(2,'0')+'  ·  LOCAL SIMULATION',color);
 if(kind==='soc'){
  label(c,d.title,28,133,30,'#e6efeb',true,w-56);label(c,phase(d),28,162,16,color,true,w-56);
  if(kind==='health'){
  label(c,'DOCUMENT SERVICE',20,119,16,'#a9c1cb');label(c,'443  '+(d.ports[443]?'HEALTHY':'UNAVAILABLE'),20,150,26,colors[d.ports[443]?'normal':'error'],true);
  label(c,'LEGACY MANAGEMENT',20,193,16,'#a9c1cb');label(c,'8080  '+(d.ports[8080]?'EXPOSED':'BLOCKED'),20,224,26,colors[d.ports[8080]?'warning':'normal'],true);return;
 }
 if(kind==='queue'){
  label(c,severity(d)==='normal'?'NO UNRESOLVED FINDINGS':'CURRENT FINDINGS',20,121,22,color,true,w-40);
  readings(d).filter(r=>r[2]!=='normal').forEach((r,i)=>{label(c,'0'+(i+1)+'  '+r[0],20,160+i*47,16,'#b8c9d0',false,w-40);label(c,r[1],20,183+i*47,16,colors[r[2]],false,w-40);});return;
 }
 if(kind==='timeline'){
  ['OBSERVATION / '+(d.inspected?'RECORDED':'ASSIGNED'),'CHANGE / '+(d.changed?'APPLIED':'PENDING'),'FIELD CHECK / '+(d.rechecked?'RECORDED':'DUE'),'VERIFICATION / '+(d.verified?'PASSED':'PENDING')].forEach((t,i)=>label(c,t,23,121+i*41,19,i===3&&d.verified?colors.normal:'#a7bbc4',false,w-46));return;
 }
 if(kind==='logs'){
  const rows=d.mission==='login'?['NORMAL USER  '+(d.login.normal?'SUCCESS':'DENIED'),...Array.from({length:5},(_,i)=>'FAILURE '+(i+1)+'  '+(d.login.limited&&i>=3?'RATE LIMITED':'FAILED'))]:['OBSERVATION / '+(d.inspected?'RECORDED':'NOT YET RECORDED'),'CONFIGURATION / '+(d.changed?'MODIFIED':'BASELINE'),'FIELD RECHECK / '+(d.rechecked?'RECORDED':'PENDING'),'FINAL VERIFY / '+(d.verified?'PASSED':'PENDING')];rows.forEach((t,i)=>label(c,t,22,114+i*25,16,'#afc2cb',false,w-44));return;
 }
 const rows=readings(d);rows.forEach((r,i)=>{const y=205+i*74;c.fillStyle='#182932';c.fillRect(24,y-25,w*.60,66);label(c,r[0],38,y,17,'#9fb5c0',false,w*.56);label(c,r[1],38,y+26,22,colors[r[2]],true,w*.56);});
  const x=w*.67;label(c,'RESPONSE DESK',x,206,17,'#ccddd6',true);['OBSERVATION','POLICY / RECOVERY','FIELD RECHECK','FINAL VERIFICATION'].forEach((t,i)=>{label(c,(i===0&&d.inspected||i===1&&d.changed||i===2&&d.rechecked||i===3&&d.verified?'● ':'○ ')+t,x,243+i*42,15,i===3&&d.verified?colors.normal:'#a7bac2',false,w*.3);});
  chart(c,x,425,w*.27,78,color,d.active);label(c,'SIMULATED SAMPLE',x,524,12,'#7f98a6');
  label(c,'E  FIELD INVESTIGATION   /   F  DETAIL TOOLS',28,h-22,14,'#92a9b6');return;
 }
 const rows=readings(d);rows.forEach((r,i)=>{const y=113+i*52;label(c,r[0],20,y,14,'#a8bbc6',false,w-40);label(c,r[1],20,y+23,18,colors[r[2]],true,w-40);});label(c,phase(d),20,h-16,12,color,false,w-40);
}
function drawNetwork(c,w,h,d){
 const bad=!d.ports[443],attention=d.ports[8080],color=colors[bad?'error':attention?'warning':'normal'];frame(c,w,h,'NETWORK ENGINEERING','FIREWALL / LOCAL SERVICE TOPOLOGY',color);
 c.strokeStyle='#63818b';c.lineWidth=3;c.beginPath();c.moveTo(95,138);c.lineTo(400,138);c.stroke();
 ['CLIENT','FIREWALL','SERVER'].forEach((t,i)=>{c.fillStyle='#253b45';c.fillRect(40+i*170,108,105,55);label(c,t,52+i*170,140,14,'#cadbdc',true,91);});
 label(c,'443  '+(d.ports[443]?'OPEN / DOCUMENTS AVAILABLE':'FILTERED / DOCUMENTS UNAVAILABLE'),20,205,18,colors[bad?'error':'normal'],true,w-40);
 label(c,'8080  '+(d.ports[8080]?'OPEN / MANAGEMENT EXPOSED':'FILTERED / MANAGEMENT BLOCKED'),20,237,18,colors[attention?'warning':'normal'],true,w-40);label(c,'LOCAL SIMULATION · CONFIGURATION STATE',20,h-15,12,'#92a9b6');
}
function drawOffice(c,w,h,profile){
 const kind=profile.split('-')[0],alt=profile.endsWith('1'),titles={response:'INCIDENT RESPONSE',analysis:'THREAT ANALYSIS',forensics:'DIGITAL FORENSICS',operations:'OPERATIONS SUPPORT'};frame(c,w,h,titles[kind],alt?'WORK NOTES / CURRENT SHIFT':'TEAM WORKSPACE / LOCAL SAMPLE',colors.neutral);
 if(alt){label(c,'SHIFT HANDOVER',23,120,24,'#dce4df',true);['Approved scope reviewed','Evidence source retained','Change request in review','Normal service check required'].forEach((t,i)=>{label(c,'□ '+t,26,157+i*30,17,'#b2c2c8',false,w-48);});}
 else if(kind==='analysis'){chart(c,26,113,w-52,90,'#789caf',3);label(c,'LOG STREAM / SAMPLE',26,236,16,'#b9cdd6');label(c,'09:12  auth event · normal',26,265,15,'#9eb5be');}
 else if(kind==='forensics'){['APPROVED ORIGINALS','notice.txt','budget.csv','members.txt'].forEach((t,i)=>{label(c,t,27,122+i*38,i?18:22,i?'#a9bcc6':'#d5e2db',i===0);line(c,25,133+i*38,w-50);});}
 else if(kind==='response'){['09:10  Observation assigned','09:14  Evidence reviewed','09:18  Change request draft','09:22  Field check scheduled'].forEach((t,i)=>label(c,t,24,120+i*39,18,'#aebfc8',false,w-48));}
 else{label(c,'AUTHORIZED OPERATIONS',24,123,22,'#d5e2dc',true);chart(c,25,155,w-50,73,'#779f97',1);label(c,'DOCUMENTATION / SERVICE DESK',25,267,15,'#a1b6bf');}
}
function drawPrint(c,w,h,profile){
 if(profile==='board'){
  c.fillStyle='#d8d5c8';c.fillRect(0,0,w,h);const headings=['ON CALL','CHANGE','RESPONSE'],rows=[['DESK A','SOC RESPONSE','DESK B','THREAT ANALYSIS','NETWORK','CHANGE OWNER'],['REQ. 021','PORT POLICY','REQ. 022','LOGIN CONTROL','APPROVAL','SCOPE CHECK'],['OBSERVE','KEEP EVIDENCE','INTERPRET','APPLY CHANGE','RECHECK','NORMAL USERS']];
  headings.forEach((t,i)=>{const x=12+i*w/3;label(c,t,x,45,24,'#294e52',true,w/3-22);rows[i].forEach((t,j)=>label(c,t,x,112+j*48,19,'#31464b',j%2===0,w/3-22));});label(c,'LOCAL TRAINING / SHIFT PLAN',12,h-24,13,'#5a6c6c');return;
 }
 c.fillStyle='#d8d5c8';c.fillRect(0,0,w,h);c.fillStyle='#294e52';c.fillRect(0,0,w,90);label(c,'NORTH / SECURITY OPERATIONS',26,38,20,'#e3ece7',true,w-52);
 const titles={policy:'AUTHORIZED OPERATIONS',response:'INCIDENT RESPONSE',schedule:'TEAM / SHIFT HANDOVER'};label(c,titles[profile],26,69,24,'#e1ede5',true,w-52);
 const rows={policy:['01  Approved scope only','02  Preserve original evidence','03  Record every change','04  Protect normal users','05  Verify the outcome'],response:['01  Identify the affected service','02  Collect and compare evidence','03  Review the cause','04  Apply a controlled change','05  Recheck the live equipment'],schedule:['08:30  SOC / Operations briefing','10:00  Network change review','12:00  Evidence and archive check','15:00  Response desk handover','17:00  Service continuity review']}[profile];rows.forEach((t,i)=>{label(c,t,28,145+i*62,22,'#31464b',true,w-56);line(c,28,165+i*62,w-56,'#a3afa7');});label(c,'LOCAL TRAINING / SAMPLE PROCEDURE',28,h-28,14,'#5a6c6c',false,w-56);
}
export function createDeviceVisuals(model,{canvasFactory=()=>document.createElement('canvas')}={}){
 const bindings=[],materials=new Map(),geometries=new Map(),indicators=[],ledMaterials=new Map();let last=null,disposed=false;
 function screenMaterial(profile){if(materials.has(profile))return materials.get(profile);const canvas=canvasFactory();canvas.width=profile==='soc'?1024:profile==='print-board'?768:512;canvas.height=profile==='soc'?576:profile.startsWith('print-')?512:288;const texture=new CanvasTexture(canvas);texture.flipY=false;texture.colorSpace=SRGBColorSpace;const material=new MeshStandardMaterial({map:texture,emissiveMap:texture,emissive:0xffffff,emissiveIntensity:.42,roughness:.58,metalness:0});material.name='LIVE_SCREEN_'+profile;if(profile.startsWith('print-')){material.emissiveIntensity=0;material.roughness=.94;}const p={profile,canvas,texture,material};materials.set(profile,p);if(profile.includes('-')){if(profile.startsWith('print-'))drawPrint(canvas.getContext('2d'),canvas.width,canvas.height,profile.slice(6));else drawOffice(canvas.getContext('2d'),canvas.width,canvas.height,profile);texture.needsUpdate=true;}return p;}
 function normalizedGeometry(geometry){if(geometries.has(geometry))return geometries.get(geometry);const copy=geometry.clone(),uv=geometry.attributes.uv;if(uv){let minX=Infinity,minY=Infinity,maxX=-Infinity,maxY=-Infinity;for(let i=0;i<uv.count;i++){minX=Math.min(minX,uv.getX(i));maxX=Math.max(maxX,uv.getX(i));minY=Math.min(minY,uv.getY(i));maxY=Math.max(maxY,uv.getY(i));}const a=new Float32Array(uv.count*2);for(let i=0;i<uv.count;i++){a[i*2]=(uv.getX(i)-minX)/(maxX-minX||1);a[i*2+1]=(uv.getY(i)-minY)/(maxY-minY||1);}copy.setAttribute('uv',new BufferAttribute(a,2));}geometries.set(geometry,copy);return copy;}
 model.traverse(o=>{
  if(!o.isMesh||o.name.startsWith('COLLIDER_')||o.name.startsWith('DOOR_'))return;
  const base=Array.isArray(o.material)?o.material:[o.material],root=rootOf(o);
  if(o.name.startsWith('IP05_Board_Title_')||o.parent?.name==='IP05_Change_Control_And_Response_Board'&&base.length===1&&(base[0].name==='LAB_Dark'||base[0].name==='CORP_Office_Warm_White'||base[0].name.startsWith('IP05_Binder_'))){bindings.push({object:o,material:o.material,visible:o.visible});o.visible=false;return;}
  let owner=o;while(owner&&!/^(ServerRack_\d+|Router_Switch_Firewall|NETWORK_Switch_Firewall_PatchPanel)$/.test(owner.name))owner=owner.parent;
  if(base.length===1&&(base[0]?.name.startsWith('CORP_Display_')||/^CORP_Poster_(Policy|Response|Schedule)$/.test(base[0]?.name)||base[0]?.name==='IP05_Document_Paper'&&o.parent?.name==='IP05_Change_Control_And_Response_Board')){
   let profile;
   if(base[0].name==='IP05_Document_Paper')profile='print-board';
   else if(base[0].name.startsWith('CORP_Poster_'))profile='print-'+base[0].name.slice(12).toLowerCase();
   else if(o.name==='CORP_SOC_Status_Display')profile='soc';
   else if(root==='INTERACT_AdminPC')profile=o.name.includes('Upper_Display_2')?'health':o.name.includes('Upper_Display_1')?'queue':o.name==='CORP_Display_ADMIN_Monitor_03'?'logs':o.name.includes('TRAIN_Monitor_Extra')?'timeline':'case';
   else if(o.name==='EX07_Network_Console_Screen')profile='network';
   else if(owner&&owner.name.startsWith('ServerRack_'))return;
   else {let parent=o;while(parent&&!/Staff_Seat|TRAIN_Workstation|Workstation_/.test(parent.name))parent=parent.parent;const n=Number(parent?.name.match(/\d+$/)?.[0]??o.name.match(/\d+/)?.[0]??0);const team=parent?.name.includes('Staff')?(n>=22?'forensics':n>=18?'analysis':'response'):'operations';const secondary=Number(o.name.match(/Screen_(\d+)/)?.[1]??(o.name.includes('SecondMonitor')||o.name.includes('Laptop')?1:0));profile=team+'-'+((n+secondary)%2);}
   const p=screenMaterial(profile);bindings.push({object:o,material:o.material,geometry:o.geometry,profile});o.material=p.material;o.geometry=normalizedGeometry(o.geometry);if(profile==='print-board'){const a=o.geometry.attributes.position,uv=o.geometry.attributes.uv;let loY=Infinity,hiY=-Infinity,loZ=Infinity,hiZ=-Infinity;for(let i=0;i<a.count;i++){loY=Math.min(loY,a.getY(i));hiY=Math.max(hiY,a.getY(i));loZ=Math.min(loZ,a.getZ(i));hiZ=Math.max(hiZ,a.getZ(i));}for(let i=0;i<a.count;i++)uv.setXY(i,(a.getZ(i)-loZ)/(hiZ-loZ),1-(a.getY(i)-loY)/(hiY-loY));}o.castShadow=false;
  }
  if(owner&&base.some(m=>/^(LAB_LED|CORP_Amber_Status_LED)$/.test(m.name))){
   const replacements=base.map(m=>{
    if(!/^(LAB_LED|CORP_Amber_Status_LED)$/.test(m.name))return m;const role=m.name==='LAB_LED'?'service':'management',key=role+'|'+m.uuid;
    if(!ledMaterials.has(key)){const copy=m.clone();copy.name='LIVE_INDICATOR_'+role;ledMaterials.set(key,{material:copy,role});}return ledMaterials.get(key).material;
   });bindings.push({object:o,material:o.material});o.material=Array.isArray(o.material)?replacements:replacements[0];indicators.push(o);
  }
 });
 return {
  screens:bindings.filter(b=>b.geometry&&!b.profile.startsWith('print-')).length,printedPanels:bindings.filter(b=>b.profile?.startsWith('print-')).length,indicators:indicators.length,textures:materials.size,
  update(data){if(disposed||!data)return false;const key=JSON.stringify(data);if(key===last)return false;last=key;for(const p of materials.values()){if(p.profile.includes('-'))continue;const c=p.canvas.getContext('2d');if(p.profile==='network')drawNetwork(c,p.canvas.width,p.canvas.height,data);else drawCase(c,p.canvas.width,p.canvas.height,data,p.profile);p.texture.needsUpdate=true;}
   for(const p of ledMaterials.values()){const tone=p.role==='service'?(data.ports[443]?'normal':'error'):(data.ports[8080]?'warning':'normal');p.material.color.set(colors[tone]);p.material.emissive.set(colors[tone]);p.material.emissiveIntensity=.5;p.material.roughness=.46;}return true;},
  dispose(){if(disposed)return;disposed=true;for(const b of bindings){b.object.material=b.material;if(b.visible!==undefined)b.object.visible=b.visible;if(b.geometry)b.object.geometry=b.geometry;}for(const p of materials.values()){p.material.dispose();p.texture.dispose();}for(const p of ledMaterials.values())p.material.dispose();for(const g of geometries.values())g.dispose();},
 };
}
