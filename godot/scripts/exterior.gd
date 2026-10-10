extends Node3D

# Web's deterministic city layout and facade response, rendered with native
# MultiMeshes. No per-window lights, reflections, new passes, or imported assets.
const GROUND = -64.0
var random_state = 831
var instance_count = 0

func rand() -> float:
	random_state = (random_state * 1664525 + 1013904223) & 0xffffffff
	return float(random_state) / 4294967296.0

func record(position: Vector3, size: Vector3, seed = 0.0, occupancy = .4) -> Dictionary:
	return {"position":position,"size":size,"seed":seed,"occupancy":occupancy}

func shader_material(code: String) -> ShaderMaterial:
	var result = ShaderMaterial.new()
	result.shader = Shader.new()
	result.shader.code = code
	return result

func boxes(label: String, records: Array, material: Material):
	if records.is_empty(): return
	var node = MultiMeshInstance3D.new()
	node.name = label
	var multimesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_custom_data = true
	var box = BoxMesh.new()
	box.size = Vector3.ONE
	box.material = material
	multimesh.mesh = box
	multimesh.instance_count = records.size()
	for i in range(records.size()):
		var r = records[i]
		multimesh.set_instance_transform(i,Transform3D(Basis.IDENTITY.scaled(r.size),r.position))
		multimesh.set_instance_custom_data(i,Color(r.seed,r.occupancy,0,1))
	node.multimesh = multimesh
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(node)
	instance_count += records.size()

func facade(color: Color, family: int) -> ShaderMaterial:
	var material = shader_material("""
shader_type spatial;
render_mode unshaded, fog_disabled;
uniform vec4 facade_color : source_color;
uniform int family;
varying vec3 city_local;
varying vec3 city_world;
varying vec3 city_normal;
varying vec4 variation;
// A sine hash loses precision for large cell ids and turns into blocky noise; this one stays stable.
float city_hash(vec2 p){vec3 q=fract(vec3(p.xyx)*0.1031);q+=dot(q,q.yzx+33.33);return fract((q.x+q.y)*q.z);}
void vertex(){
 vec3 size=vec3(length(MODEL_MATRIX[0].xyz),length(MODEL_MATRIX[1].xyz),length(MODEL_MATRIX[2].xyz));
 city_local=(VERTEX+0.5)*size;
 city_world=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;
 city_normal=NORMAL;
 variation=INSTANCE_CUSTOM;
}
void fragment(){
 vec3 n=normalize(city_normal);
 float wall=1.0-step(0.6,abs(n.y));
 float stable_seed=floor(variation.x+0.5);
 float along=abs(n.x)>0.5?city_local.z:city_local.x;
 float pitch=(family==0||family==4)?1.55:2.25;
 vec2 grid=vec2(along/pitch,city_local.y/3.0),cell=fract(grid),id=floor(grid);
 vec2 aa=max(fwidth(grid),vec2(0.001));
 vec2 mask=smoothstep(vec2(0.16,0.19)-aa,vec2(0.16,0.19)+aa,cell)*(1.0-smoothstep(vec2(0.79,0.77)-aa,vec2(0.79,0.77)+aa,cell));
 // Far away a window is smaller than a pixel: fade to its average look instead of shimmering.
 float detail=1.0-smoothstep(0.28,0.75,max(aa.x,aa.y));
 float window_wall=wall*(family<6?1.0:0.0);
 float pane=mix(0.365*window_wall,mask.x*mask.y*window_wall,detail);
 float floor_seed=city_hash(vec2(id.y,stable_seed));
 float occupancy=(variation.y+(0.5-floor_seed)*0.3)*step(0.12,floor_seed);
 float suite=city_hash(vec2(floor(id.x/3.0)+stable_seed,id.y));
 float light=step(1.0-occupancy,city_hash(id+stable_seed))*mix(0.22,1.0,step(0.18,suite));
 float brightness=mix(0.14,0.58,city_hash(id.yx+stable_seed*2.0));
 vec3 lamp=mix(vec3(1.0,0.58,0.25),vec3(0.80,0.84,0.86),step(0.80,city_hash(id+52.0+stable_seed)));
 lamp=mix(lamp,vec3(0.46,0.66,0.86),step(0.97,city_hash(id+73.0+stable_seed)));
 light=mix(clamp(occupancy,0.0,1.0)*0.62,light,detail);
 brightness=mix(0.36,brightness,detail);
 lamp=mix(vec3(0.93,0.62,0.36),lamp,detail);
 float sun=max(0.0,dot(n,vec3(-0.973,0.10,-0.208)));
 vec3 illumination=vec3(0.28,0.38,0.54)+sun*vec3(0.91,0.53,0.27);
 float floor_band=1.0-smoothstep(0.035,0.075,min(cell.y,1.0-cell.y));
 vec3 glazing=mix(vec3(0.032,0.067,0.11),vec3(0.26,0.16,0.12),sun*0.50);
 vec3 color=facade_color.rgb;
 if(family==0||family==4)color=mix(color,glazing,0.66*wall);
 color*=illumination*(1.0-floor_band*0.22*wall);
 color=mix(color,glazing*illumination,pane*0.88);
 color+=pane*light*brightness*lamp;
 float haze=smoothstep(110.0,650.0,length(city_world.xz))*0.34;
 ALBEDO=mix(color,vec3(0.23,0.19,0.23),haze);
}
""")
	material.set_shader_parameter("facade_color",color)
	material.set_shader_parameter("family",family)
	return material

func _ready():
	name = "NativeExteriorCity"
	panorama()
	var families = [[],[],[],[],[],[]]
	var roofs = []; var equipment = []; var antennae = []; var rims = []; var balconies = []; var fins = []; var lights = []
	for spec in [[24,42,108,0],[42,196,360,1],[64,380,720,2]]:
		var count = spec[0]; var band = spec[3]
		for i in range(count):
			var x = -spec[1]-rand()*(spec[2]-spec[1])
			var z = (i-count/2.0)*[15,19,22][band]+(rand()-.5)*12
			var depth = 9+rand()*11 if band==0 else 12+rand()*14
			var width = 9+rand()*9 if band==0 else 11+rand()*15
			var height = 22+rand()*32 if band==0 else 30+rand()*56 if band==1 else 18+rand()*58
			var family = int(rand()*6)
			var seed = rand()*999
			var occupancy = .25+rand()*.25 if family in [0,3] else .36+rand()*.25
			families[family].append(record(Vector3(x,GROUND+height/2,z),Vector3(depth,height,width),seed,occupancy))
			if band<2:
				var cap_height = 2+rand()*6; var cap_depth = depth*(.46+rand()*.3); var cap_width = width*(.42+rand()*.3)
				families[family].append(record(Vector3(x+(rand()-.5)*2,GROUND+height+cap_height/2,z),Vector3(cap_depth,cap_height,cap_width),seed,occupancy))
				roofs.append(record(Vector3(x,GROUND+height+.15,z),Vector3(depth+.35,.3,width+.35)))
				if rand()<.7: equipment.append(record(Vector3(x+depth*.19,GROUND+height+.7,z-width*.24),Vector3(1.9,.9,2.2)))
				if rand()<.32: antennae.append(record(Vector3(x,GROUND+height+cap_height+1.5,z),Vector3(.10,3,.10)))
				if family in [0,4]: rims.append(record(Vector3(x,GROUND+height-1.2,z),Vector3(depth+.08,.42,width+.08)))
				if band==0:
					if family in [1,5]:
						var floor_index = 2
						while floor_index*3<height-1:
							balconies.append(record(Vector3(x+depth/2+.42,GROUND+floor_index*3,z),Vector3(.86,.17,width*.80)))
							rims.append(record(Vector3(x+depth/2+.80,GROUND+floor_index*3+.42,z),Vector3(.10,.57,width*.80)))
							floor_index += 1
					if family in [0,3,4]:
						var bay = 1
						while bay*3<width-1:
							fins.append(record(Vector3(x+depth/2+.08,GROUND+height/2,z-width/2+bay*3),Vector3(.16,height,.12)))
							bay += 1
	var colors = [Color("283b50"),Color("827a6d"),Color("aaa18d"),Color("65727b"),Color("344a62"),Color("80716b")]
	for i in range(6): boxes("FacadeFamily_%d"%i,families[i],facade(colors[i],i))
	var roof_material = facade(Color("343b42"),6)
	var metal = facade(Color("78858b"),7)
	boxes("RoofCopings",roofs,roof_material); boxes("RooftopPlant",equipment,metal); boxes("Antennae",antennae,metal)
	boxes("MechanicalBands",rims,roof_material); boxes("ResidentialBalconies",balconies,roof_material); boxes("OfficeFins",fins,metal)
	ground_and_river()
	var banks = []; var bridges = []; var supports = []
	for x in [-105.5,-188.5]:
		banks.append(record(Vector3(x,GROUND+.35,0),Vector3(5,.7,1660)))
		for i in range(90): lights.append(record(Vector3(x,GROUND+.8,(i-45)*18),Vector3(.25,.22,.45)))
	for z in [64,-235,360]:
		bridges.append(record(Vector3(-147,GROUND+4.5,z),Vector3(127,1.1,8)))
		for x in [-172,-122]: supports.append(record(Vector3(x,GROUND+2,z),Vector3(1.8,4,6)))
		for i in range(29):
			for side in [-1,1]: lights.append(record(Vector3(-210+i*4.5,GROUND+5.45,z+side*3.7),Vector3(.20,.26,.20)))
	boxes("QuaysAndRiversideRoads",banks,roof_material); boxes("BridgeDecks",bridges,roof_material); boxes("BridgePiers",supports,roof_material)
	var lamp = StandardMaterial3D.new(); lamp.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED; lamp.albedo_color = Color("ffb56a")
	boxes("RoadLights",lights,lamp)
	window_envelope()

func panorama():
	var surface = SurfaceTool.new(); surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for j in range(48):
		for i in range(128):
			for pair in [Vector2i(i,j),Vector2i(i,j+1),Vector2i(i+1,j),Vector2i(i+1,j),Vector2i(i,j+1),Vector2i(i+1,j+1)]:
				var angle = -PI+float(pair.x)/128*TAU; var latitude = -PI/2+float(pair.y)/48*PI
				var y = sin(latitude)*960; var radius = cos(latitude)*960
				surface.set_uv(Vector2(.5-angle/deg_to_rad(220),(y+1194)/1900)); surface.add_vertex(Vector3(-cos(angle)*radius,y,sin(angle)*radius))
	var dome = MeshInstance3D.new(); dome.name = "DistantCurvedPanorama"; dome.mesh = surface.commit()
	var material = shader_material("shader_type spatial; render_mode unshaded,cull_disabled,fog_disabled; uniform sampler2D panorama:source_color,filter_linear_mipmap_anisotropic; void fragment(){vec2 p=clamp(UV,vec2(.001),vec2(.999));vec3 photo=texture(panorama,vec2(p.x,1.0-p.y)).rgb;float edge=smoothstep(.035,.12,UV.x)*(1.0-smoothstep(.88,.965,UV.x));vec3 haze=mix(vec3(.09,.12,.18),vec3(.44,.29,.29),smoothstep(.4,.7,UV.y));haze=mix(haze,vec3(.16,.22,.31),smoothstep(.7,1.0,UV.y));float luminance=dot(photo,vec3(.2126,.7152,.0722));photo=mix(vec3(luminance),photo,.94)*.9;edge*=1.0-smoothstep(.95,1.10,UV.y);ALBEDO=mix(haze,photo,edge);}")
	material.set_shader_parameter("panorama",load("res://assets/textures/city-sunset.png")); dome.material_override = material
	dome.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF; add_child(dome)

func plane(label: String, size: Vector2, position: Vector3, material: Material):
	var node = MeshInstance3D.new(); node.name = label
	var mesh = PlaneMesh.new(); mesh.size = size; mesh.material = material
	node.mesh = mesh; node.position = position; node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF; add_child(node)

func ground_and_river():
	var ground = shader_material("shader_type spatial;render_mode unshaded,fog_disabled;varying vec3 point;void vertex(){point=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;}float city_hash(vec2 p){return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453);}void fragment(){vec2 block=point.xz/vec2(51.0,62.0),cell=abs(fract(block)-.5),aa=fwidth(block);vec2 street=smoothstep(vec2(.43)-aa,vec2(.47)+aa,cell);float roads=max(street.x,street.y),park=step(.83,city_hash(floor(block)))*(1.0-roads);vec3 c=mix(vec3(.019,.023,.030),vec3(.023,.032,.043),roads);c=mix(c,vec3(.028,.048,.035),park*.7);ALBEDO=mix(c,vec3(.15,.12,.16),smoothstep(450.0,900.0,length(point.xz))*.55);}")
	plane("UrbanGround",Vector2(1580,1720),Vector3(-390,GROUND-.10,0),ground)
	var river = shader_material("shader_type spatial;render_mode unshaded,fog_disabled;varying vec3 point;void vertex(){point=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;}void fragment(){float stripe=exp(-pow((point.x+145.0)/19.0,2.0));float phase=point.z*.7+sin(point.x*.3);float ripple=.76+.24*sin(phase)*(1.0-smoothstep(.7,2.0,fwidth(phase)));vec3 c=vec3(.019,.032,.058)+vec3(.20,.08,.025)*stripe*ripple;ALBEDO=mix(c,vec3(.24,.19,.23),smoothstep(250.0,800.0,abs(point.z))*.35);}")
	plane("River",Vector2(78,1680),Vector3(-147,GROUND+.08,0),river)

func window_envelope():
	var concrete = StandardMaterial3D.new(); concrete.albedo_color = Color("858784"); concrete.roughness = .91
	var metal = StandardMaterial3D.new(); metal.albedo_color = Color("394753"); metal.roughness = .43; metal.metallic = .62
	var stone = StandardMaterial3D.new(); stone.albedo_color = Color("58676e"); stone.roughness = .57
	var seal = StandardMaterial3D.new(); seal.albedo_color = Color("151f25"); seal.roughness = .89
	var structure = [record(Vector3(-12.21,-.2,0),Vector3(.44,.4,20.45)),record(Vector3(-12.28,-32.3,-10.25),Vector3(.55,64.8,.55)),record(Vector3(-12.28,-32.3,10.25),Vector3(.55,64.8,.55))]
	var sills = []; var trims = []; var gaps = []; var mullions = []; var drains = []
	for i in range(10):
		var z = -9+i*2
		sills.append(record(Vector3(-12.075,1.185,z),Vector3(.70,.05,1.91)))
		trims.append(record(Vector3(-12.26,1.155,z),Vector3(.34,.035,1.91)))
		gaps.append(record(Vector3(-12.445,1.107,z),Vector3(.024,.03,1.92)))
		drains.append(record(Vector3(-12.29,1.137,z+.66),Vector3(.085,.013,.04)))
	for z in range(-10,11,2): mullions.append(record(Vector3(-12.15,1.9,z),Vector3(.15,1.51,.075)))
	trims.append(record(Vector3(-12.24,2.66,0),Vector3(.31,.075,20.5)))
	for floor_index in range(19):
		var y = -.38-floor_index*3.4
		structure.append(record(Vector3(-12.28,y,0),Vector3(.42,.25,20.45))); gaps.append(record(Vector3(-12.32,y-.8,0),Vector3(.04,.78,20.2)))
	boxes("OfficeSlabAndStructure",structure,concrete); boxes("InteriorSills",sills,stone); boxes("MetalTrims",trims,metal)
	boxes("Mullions",mullions,metal); boxes("ShadowGapsAndSpandrels",gaps,seal); boxes("SillDrains",drains,seal)
