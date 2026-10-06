"""Build Interior 07 from preserved Interior 06 in a background Blender.
Usage: blender -b MASTER06 --python scripts/experience_upgrade.py -- OUTPUT07
Runtime live screens are bound by device-visuals.js; no functional nodes change.
"""
import bpy,json,hashlib,math,sys
import numpy as np
from pathlib import Path
from mathutils import Vector
out=Path(sys.argv[sys.argv.index('--')+1]).resolve();out.mkdir(parents=True,exist_ok=True)
scene=bpy.data.scenes['Security_Lab'];bpy.context.window.scene=scene
assert not scene.get('experience_07'),'Use preserved Interior 06'
def snapshot():
 return {o.name:{'matrix':[list(r) for r in o.matrix_world],'props':repr(dict(o.items())),'geometry':hashlib.sha256(b''.join(np.array(v.co,dtype=np.float32).tobytes() for v in o.data.vertices)).hexdigest() if o.type=='MESH' else None} for o in scene.objects if o.name.startswith(('INTERACT_','DOOR_','COLLIDER_','SPAWN_'))}
before=snapshot();col=bpy.data.collections.new('Experience_07_Office');bpy.data.collections['Security_Lab_Export'].children.link(col)
created=[]
def shader(m):return next(n for n in m.node_tree.nodes if n.type=='BSDF_PRINCIPLED')
def mat(name,color,rough=.7,metal=0):
 m=bpy.data.materials.new(name);m.use_nodes=True;s=shader(m);s.inputs['Base Color'].default_value=(*color,1);s.inputs['Roughness'].default_value=rough;s.inputs['Metallic'].default_value=metal;return m
def image(name,arr,data=False):
 h,w=arr.shape[:2];rgba=np.ones((h,w,4),dtype=np.float32);rgba[:,:,:3]=arr if arr.ndim==3 else arr[:,:,None]
 im=bpy.data.images.new(name,width=w,height=h,alpha=False);im.colorspace_settings.name='Non-Color' if data else 'sRGB';im.pixels.foreach_set(rgba.ravel());im.filepath_raw=str(out/(name+'.png'));im.file_format='PNG';im.save();im.pack();return im
def link_texture(m,im,slot):
 n=m.node_tree.nodes.new('ShaderNodeTexImage');n.image=im;s=shader(m)
 for l in list(s.inputs[slot].links):m.node_tree.links.remove(l)
 m.node_tree.links.new(n.outputs['Color'],s.inputs[slot])
# Controlled reflectance and micro-roughness, using original maps and contact AO.
rng=np.random.default_rng(707);N=1024;y,x=np.mgrid[:N,:N]
wood=np.clip(.53+.035*np.sin(x*.11)+.018*np.sin(x*.9)+rng.normal(0,.009,(N,N)),0,1)
fabric=np.clip(.88+.018*np.sin(x*math.pi)+.018*np.sin(y*math.pi)+rng.normal(0,.008,(N,N)),0,1)
metal=np.clip(.62+.018*np.sin(y*.74)+rng.normal(0,.012,(N,N)),0,1)
rough={k:image('EX07_'+k+'_Roughness_1K',v,True) for k,v in [('Laminate',wood),('Fabric',fabric),('Coated_Metal',metal)]}
clothnormal=image('EX07_Fabric_Normal_1K',np.stack([.5+.035*np.sin(x*math.pi/2),.5+.035*np.sin(y*math.pi/2),np.ones_like(x)],axis=-1),True)
for name,roughness,metallic in [('LAB_Dark',.76,.01),('CORP_Office_Warm_White',.66,.10),('CORP_Powder_Coated_Aluminium',.72,.18),('RL_Brushed_Stainless',.36,.85),('RL_Ceiling_T_Grid',.62,.38),('RL_Rubber_Seal',.86,0)]:
 m=bpy.data.materials[name];s=shader(m);s.inputs['Roughness'].default_value=roughness;s.inputs['Metallic'].default_value=metallic
link_texture(bpy.data.materials['RL_Maple_Desk_Veneer'],rough['Laminate'],'Roughness')
link_texture(bpy.data.materials['CORP_Woven_Partition_Fabric_2K'],rough['Fabric'],'Roughness')
link_texture(bpy.data.materials['CORP_Powder_Coated_Aluminium'],rough['Coated_Metal'],'Roughness')
# Keep the scanned grain, but give the laminate a warmer, less bleached average.
m=bpy.data.materials['RL_Maple_Desk_Veneer']
for n in m.node_tree.nodes:
 if n.type=='TEX_IMAGE' and n.image and ('Oak' in n.image.name or 'BaseColor' in n.image.name or 'Diffuse' in n.image.name):
  a=np.empty(len(n.image.pixels),dtype=np.float32);n.image.pixels.foreach_get(a);a=a.reshape(n.image.size[1],n.image.size[0],4)
  a[:,:,:3]=np.clip(a[:,:,:3]*np.array([.92,.85,.77]),0,1);n.image=image('EX07_Laminate_Grain_Master',a[:,:,:3]);break
# Dense, subdued carpet tiles; keep the original floor's independent ContactAO UV.
m=bpy.data.materials['CORP_Office_Carpet_2K'];N=2048;y,x=np.mgrid[:N,:N];turn=((x//1024+y//1024)%2)==0
weave=np.sin(np.where(turn,x,y)*math.tau/3)*.004+rng.normal(0,.004,(N,N));tones=np.array([[0,-.003],[.002,-.002]])[(y//1024),(x//1024)]
link_texture(m,image('EX07_Carpet_Tile_2K',np.clip(np.array([.145,.164,.174])[None,None,:]+(weave+tones)[:,:,None],0,1)),'Base Color');shader(m).inputs['Roughness'].default_value=.96
shader(bpy.data.materials['IP06_Server_Antistatic']).inputs['Roughness'].default_value=.84
shader(bpy.data.materials['LAB_Light']).inputs['Emission Strength'].default_value=.85
# Chairs vary by team through shared materials, preserving their geometry and colliders.
chair=bpy.data.materials['Executive'];chairvariants=[]
for i,c in enumerate([(.040,.062,.072),(.068,.074,.069),(.070,.052,.042)]):
 m=chair.copy();m.name='EX07_Chair_Fabric_'+str(i);s=shader(m);s.inputs['Base Color'].default_value=(*c,1);s.inputs['Roughness'].default_value=.93;s.inputs['Sheen Weight'].default_value=.12;link_texture(m,rough['Fabric'],'Roughness');n=m.node_tree.nodes.new('ShaderNodeTexImage');n.image=clothnormal;normal=m.node_tree.nodes.new('ShaderNodeNormalMap');normal.inputs['Strength'].default_value=.16;m.node_tree.links.new(n.outputs['Color'],normal.inputs['Color']);m.node_tree.links.new(normal.outputs['Normal'],s.inputs['Normal']);chairvariants.append(m)
for o in scene.objects:
 if o.type=='MESH' and 'Chair' in o.name and not o.name.startswith('COLLIDER_'):
  variant=0 if 'Staff' in o.name else 1 if 'TRAIN' in o.name else 2
  for i,m in enumerate(o.data.materials):
   if m==chair:o.material_slots[i].link='OBJECT';o.material_slots[i].material=chairvariants[variant]
# Compact shared props, all on existing desks: no new navigation obstacles.
leaf=mat('EX07_Plant_Foliage',(.075,.16,.105),.87);ceramic=mat('EX07_Satin_Ceramic',(.24,.28,.27),.55);paper=mat('EX07_Uncoated_Paper',(.65,.61,.52),.9);ink=mat('EX07_Dark_Ink',(.018,.027,.032),.83);steel=bpy.data.materials['CORP_Powder_Coated_Aluminium']
class Builder:
 def __init__(self):self.v=[];self.f=[];self.mi=[];self.m=[]
 def slot(self,m):
  if m not in self.m:self.m.append(m)
  return self.m.index(m)
 def box(self,c,s,m):
  x,y,z=c;a,b,d=[v/2 for v in s];k=len(self.v);self.v += [(x-a,y-b,z-d),(x+a,y-b,z-d),(x+a,y+b,z-d),(x-a,y+b,z-d),(x-a,y-b,z+d),(x+a,y-b,z+d),(x+a,y+b,z+d),(x-a,y+b,z+d)]
  f=[(0,3,2,1),(4,5,6,7),(0,1,5,4),(1,2,6,5),(2,3,7,6),(3,0,4,7)];self.f += [tuple(k+i for i in p) for p in f];self.mi += [self.slot(m)]*6
 def cylinder(self,c,r,h,m,n=16):
  x,y,z=c;k=len(self.v);self.v += [(x+r*math.cos(i*math.tau/n),y+r*math.sin(i*math.tau/n),z+d*h/2) for d in [-1,1] for i in range(n)];self.f += [tuple(k+i for i in reversed(range(n))),tuple(k+n+i for i in range(n))]+[(k+i,k+(i+1)%n,k+n+(i+1)%n,k+n+i) for i in range(n)];self.mi += [self.slot(m)]*(n+2)
 def create(self,name,parent=None):
  me=bpy.data.meshes.new(name+'_Mesh');me.from_pydata(self.v,[],self.f);me.update()
  for m in self.m:me.materials.append(m)
  for p,i in zip(me.polygons,self.mi):p.material_index=i
  uv=me.uv_layers.new(name='UVMap')
  for p in me.polygons:
   axes=[i for i in range(3) if i!=max(range(3),key=lambda i:abs(p.normal[i]))]
   for li in p.loop_indices:co=me.vertices[me.loops[li].vertex_index].co;uv.data[li].uv=(co[axes[0]],co[axes[1]])
  o=bpy.data.objects.new(name,me);col.objects.link(o);o.parent=parent;created.append(name);return o
plant=Builder();plant.cylinder((0,0,.041),.048,.082,ceramic)
for i in range(7):
 a=i*math.tau/7;k=len(plant.v);p=np.array([.033*math.cos(a),.033*math.sin(a),.17+i%3*.019]);plant.v += [tuple(p+np.array([-.035,0,-.055])),tuple(p+np.array([.035,0,-.035])),tuple(p+np.array([.018,0,.025])),tuple(p+np.array([-.016,0,.048]))];plant.f.append((k,k+1,k+2,k+3));plant.mi.append(plant.slot(leaf))
po=plant.create('EX07_Desk_Plant_Template');po.hide_render=True
roots=[bpy.data.objects.get('CORP_Staff_Seat_'+str(i)) for i in range(13,26)]+[bpy.data.objects.get('TRAIN_Workstation_%02d'%i) for i in range(4,13)]
for i,r in enumerate(roots):
 if not r:continue
 if i%4==0:
  o=bpy.data.objects.new('EX07_Desk_Plant_%02d'%i,po.data);col.objects.link(o);o.parent=r;o.location=(.53,.22,.824);created.append(o.name)
 if i%4==1:
  b=Builder();b.cylinder((0,0,.095),.035,.19,ceramic);b.cylinder((0,0,.197),.024,.017,steel);o=b.create('EX07_Desk_Insulated_Bottle_%02d'%i,r);o.location=(-.53,-.23,.824)
 if i%4==2:
  b=Builder();b.box((0,0,.006),(.17,.078,.012),steel)
  for j in range(3):b.box((-.03+j*.026,0,.014),(.006,.060,.006),ink)
  o=b.create('EX07_Desk_Pen_Tray_%02d'%i,r);o.location=(.29,-.26,.824)
# The template itself is removed, instances keep its shared mesh.
bpy.data.objects.remove(po,do_unlink=True);created.remove('EX07_Desk_Plant_Template')
# A console laptop at the original firewall bench, below its existing bounding box.
r=bpy.data.objects['INTERACT_Router'];b=Builder();b.box((.82,-.15,.841),(.39,.26,.025),steel);b.box((.82,-.17,.857),(.29,.15,.004),ink);b.box((.82,-.28,1.017),(.39,.025,.246),ink);b.create('EX07_Network_Console_Laptop',r)
screenmat=bpy.data.materials['CORP_Display_firewall'];b=Builder();b.v=[(.637,-.294,.905),(1.003,-.294,.905),(1.003,-.294,1.130),(.637,-.294,1.130)];b.f=[(0,1,2,3)];b.mi=[b.slot(screenmat)];o=b.create('EX07_Network_Console_Screen',r)
for li,uv in zip(o.data.polygons[0].loop_indices,[(0,0),(1,0),(1,1),(0,1)]):o.data.uv_layers.active.data[li].uv=uv
# A subtle task-use trace at SOC, inside the existing desk footprint.
soc=bpy.data.objects['INTERACT_AdminPC'];b=Builder();b.box((-.5,-.18,.845),(.22,.15,.005),paper)
for i in range(5):b.box((-.51,-.225+i*.018,.848),(.14,.002,.0008),ink)
b.create('EX07_SOC_Incident_Worksheet',soc)
scene['experience_07']='Corporate operations: live equipment visuals, quieter lighting, laminate/fabric/steel finishes, shared desk accessories'
assert snapshot()==before,'Protected nodes changed'
bpy.ops.wm.save_as_mainfile(filepath=str(out/'Security_Lab_Interior_07.blend'),compress=True)
(out/'authoring-07.json').write_text(json.dumps({'protectedNodes':len(before),'protectedUnchanged':True,'created':created,'roughnessMaps':'3 shared 1K','floor':'2K carpet, existing contact AO preserved'},indent=2),encoding='utf-8')
print('EXPERIENCE_07',len(created),'objects; protected unchanged')
