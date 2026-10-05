import {Box3,Group,Mesh,MeshBasicMaterial,PlaneGeometry,CanvasTexture,SRGBColorSpace} from '../vendor/three/build/three.module.js';
// Four small informational placards. No new GLB geometry, lights, or passes.
// Installed after batching/culling and registered against the original anchors.
export function createWorldStatus(model) {
  const group=new Group();group.name='Runtime_Device_Status';model.add(group);
  const geometry=new PlaneGeometry(.58,.29),panels=[];
  const heights={INTERACT_ServerRack:1.6,INTERACT_AdminPC:1.8,INTERACT_Router:1.45,INTERACT_FileCabinet:1.75};
  model.updateMatrixWorld(true);
  for(const [id,height]of Object.entries(heights)) {
    const object=model.getObjectByName(id);if(!object)continue;
    const displayObject=id==='INTERACT_ServerRack'?model.getObjectByName('ServerRack_01')??object:object;
    const bounds=new Box3().setFromObject(displayObject),canvas=document.createElement('canvas');canvas.width=512;canvas.height=256;
    const texture=new CanvasTexture(canvas);texture.colorSpace=SRGBColorSpace;
    const material=new MeshBasicMaterial({map:texture,toneMapped:false});
    const mesh=new Mesh(geometry,material);mesh.name='STATUS_'+id;
    mesh.position.set((bounds.min.x+bounds.max.x)/2,height,bounds.max.z+.045);group.add(mesh);
    panels.push({id,canvas,texture,material,mesh,anchor:object,key:null});
  }
  return {
    count:panels.length,
    targets:panels.map(({mesh,anchor})=>({mesh,anchor})),
    update(states={}) {
      let changed=false;
      for(const panel of panels) {
        const status=states[panel.id]??{label:panel.id,text:'장비 준비 중',tone:'neutral'},key=JSON.stringify(status);
        if(panel.key===key)continue;panel.key=key;changed=true;
        const c=panel.canvas.getContext('2d'),color={normal:'#78bda4',warning:'#d5a37b',pending:'#e0c376',neutral:'#b4c2c7'}[status.tone];
        c.fillStyle='#18272e';c.fillRect(0,0,512,256);c.fillStyle=color;c.fillRect(0,0,7,256);
        c.font='bold 30px "Malgun Gothic", sans-serif';c.fillStyle='#edf1ed';c.fillText(status.label,24,50,465);
        c.font='24px "Malgun Gothic", sans-serif';c.fillStyle=color;
        status.text.split('\n').slice(0,3).forEach((line,i)=>c.fillText(line,24,103+i*37,465));
        c.font='18px sans-serif';c.fillStyle='#93a5ac';c.fillText('LOCAL SIMULATION · E 조사 / F 도구',24,237);
        panel.texture.needsUpdate=true;
      }
      return changed;
    },
    dispose(){group.removeFromParent();geometry.dispose();for(const p of panels){p.material.dispose();p.texture.dispose();}},
  };
}
