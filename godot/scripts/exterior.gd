extends Node3D

func _ready():
	name = "NativeExteriorCity"
	var surface = SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var segments = 96
	var rows = 32
	for j in range(rows):
		for i in range(segments):
			for pair in [Vector2i(i,j),Vector2i(i,j+1),Vector2i(i+1,j),Vector2i(i+1,j),Vector2i(i,j+1),Vector2i(i+1,j+1)]:
				var angle = -PI + float(pair.x)/segments*TAU
				var latitude = -PI/2 + float(pair.y)/rows*PI
				var y = sin(latitude)*960
				var r = cos(latitude)*960
				surface.set_uv(Vector2(.5-angle/deg_to_rad(220),(y+1194)/1900))
				surface.add_vertex(Vector3(-cos(angle)*r,y,sin(angle)*r))
	var dome = MeshInstance3D.new()
	dome.mesh = surface.commit()
	var material = ShaderMaterial.new()
	material.shader = Shader.new()
	material.shader.code = "shader_type spatial; render_mode unshaded, cull_disabled, fog_disabled; uniform sampler2D panorama:source_color,filter_linear; void fragment(){ vec2 p=clamp(UV,vec2(.001),vec2(.999)); vec3 photo=texture(panorama,vec2(p.x,1.0-p.y)).rgb; float edge=smoothstep(.035,.12,UV.x)*(1.0-smoothstep(.88,.965,UV.x)); vec3 haze=mix(vec3(.09,.12,.18),vec3(.44,.29,.29),smoothstep(.4,.7,UV.y)); haze=mix(haze,vec3(.16,.22,.31),smoothstep(.7,1.0,UV.y)); edge*=1.0-smoothstep(.95,1.10,UV.y); ALBEDO=mix(haze,photo*.9,edge); }"
	material.set_shader_parameter("panorama",load("res://assets/textures/city-sunset.png"))
	dome.material_override = material
	dome.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(dome)
	var random = RandomNumberGenerator.new()
	random.seed = 831
	var instances = MultiMeshInstance3D.new()
	var multimesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_custom_data = true
	var box = BoxMesh.new()
	box.size = Vector3.ONE
	var facade = ShaderMaterial.new()
	facade.shader = Shader.new()
	facade.shader.code = "shader_type spatial; render_mode unshaded; varying vec3 local_pos; varying vec3 n; varying vec4 seed; void vertex(){local_pos=VERTEX; n=NORMAL;seed=INSTANCE_CUSTOM;} float hash(vec2 p){return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453);} void fragment(){vec2 grid=vec2(abs(n.x)>.5?local_pos.z:local_pos.x,local_pos.y)*vec2(seed.b*7.0,seed.g*16.0); vec2 c=fract(grid); float pane=step(.17,c.x)*step(c.x,.79)*step(.18,c.y)*step(c.y,.77)*(1.0-step(.6,abs(n.y)));float light=step(.62,hash(floor(grid)+seed.r*999.0));ALBEDO=mix(vec3(.16,.20,.25),vec3(.29,.27,.24),seed.r)*(.65+.25*max(n.x,0.0));ALBEDO=mix(ALBEDO,vec3(.025,.045,.065),pane*.8);ALBEDO+=pane*light*vec3(.35,.18,.065);}"
	box.material = facade
	multimesh.mesh = box
	multimesh.instance_count = 130
	for i in range(130):
		var band = 0 if i < 24 else 1 if i < 66 else 2
		var near = [42,196,380][band]
		var far = [108,360,720][band]
		var height = random.randf_range(22,80)
		var size = Vector3(random.randf_range(9,24),height,random.randf_range(9,24))
		var position = Vector3(-random.randf_range(near,far),-64+height/2.0,random.randf_range(-650,650))
		multimesh.set_instance_transform(i,Transform3D(Basis.IDENTITY.scaled(size),position))
		multimesh.set_instance_custom_data(i,Color(random.randf(),height/48.0,size.z/16.0,1))
	instances.multimesh = multimesh
	instances.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(instances)
	for spec in [[Vector3(-390,-64.1,0),Vector3(1500,.2,1800),Color(.10,.12,.14)], [Vector3(-147,-63.9,0),Vector3(78,.2,1680),Color(.11,.20,.25)]]:
		add_box(spec[0],spec[1],spec[2])
	for z in [64,-235,360]:
		add_box(Vector3(-147,-59.5,z),Vector3(127,1.1,8),Color(.22,.23,.25))
		for x in [-172,-122]: add_box(Vector3(x,-62,z),Vector3(1.8,4,6),Color(.19,.20,.22))
		for i in range(29):
			for side in [-1,1]: add_box(Vector3(-210+i*4.5,-58.55,z+side*3.7),Vector3(.20,.26,.20),Color(1,.56,.22))

func add_box(position: Vector3, size: Vector3, color: Color):
	var node = MeshInstance3D.new()
	var mesh = BoxMesh.new()
	mesh.size = size
	var material = StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	mesh.material = material
	node.mesh = mesh
	node.position = position
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(node)
