extends Node3D

var cue: AudioStreamPlayer

func setup(game: Node):
	var ventilation = AudioStreamPlayer.new()
	ventilation.stream = loop_stream("ventilation")
	ventilation.bus = "SFX"
	ventilation.volume_db = -32
	add_child(ventilation)
	ventilation.play()
	for position in [Vector3(-8,1,-6),Vector3(-5.5,1,-8)]:
		var fan = AudioStreamPlayer3D.new()
		fan.position = position
		fan.stream = loop_stream("server-fan")
		fan.bus = "SFX"
		fan.volume_db = -24
		fan.unit_size = 2
		fan.max_distance = 9
		add_child(fan)
		fan.play()
	cue = AudioStreamPlayer.new()
	cue.stream = load("res://assets/audio/interaction.wav")
	cue.bus = "SFX"
	cue.volume_db = -22
	add_child(cue)
	game.missions.observation.connect(func(_result): cue.play())
	for id in game.world.doors:
		var door = game.world.doors[id]
		var sound = AudioStreamPlayer3D.new()
		sound.stream = load("res://assets/audio/door-latch.wav")
		sound.bus = "SFX"
		sound.volume_db = -20
		sound.max_distance = 6
		door.add_child(sound)
		door.moved.connect(sound.play)

func loop_stream(name: String) -> AudioStreamWAV:
	var stream = load("res://assets/audio/"+name+".wav").duplicate()
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_begin = 0
	stream.loop_end = stream.data.size()/2
	return stream
