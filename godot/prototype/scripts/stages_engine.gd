class_name TerminalStagesEngine
extends InvestigationEngine

const COUNT = 6
const PHASES = ["playing","clear","exploded","complete"]

func create_state() -> Dictionary:
	var s = super.create_state()
	s["stage"] = {"version":1,"index":1,"unlocked":1,"phase":"playing","cleared":[],"mistakes":0,"blasts":0,"attempt":1}
	return s

func definition(s: Dictionary) -> Dictionary:
	return content.stages[int(s.stage.index)-1]

func parse(command: String, _device: String, _state: Dictionary) -> Dictionary:
	return {"type":"stage.command","payload":{"command":command}}

func step(original: Dictionary, action: Dictionary) -> Dictionary:
	var s = original.duplicate(true)
	var p = action.get("payload",{})
	if not p is Dictionary: return _result(original,"INVALID_ACTION")
	var a = s.stage
	match action.get("type",""):
		"stage.retry":
			if a.phase != "exploded": return _result(original,"STAGE_BUSY","retry: no crashed computer")
			a.phase = "playing"
			a.attempt += 1
			return changed(s,"STAGE_RETRY","BOOT OK")
		"stage.next":
			if a.phase != "clear": return _result(original,"STAGE_BUSY","stage: finish current task first")
			if a.index == COUNT:
				a.phase = "complete"
				return changed(s,"STAGES_COMPLETE","CLOCK_OUT=APPROVED")
			a.index += 1
			a.phase = "playing"
			a.attempt = 1
			return changed(s,"STAGE_STARTED","BOOT OK")
		"stage.select":
			var selected = p.get("index")
			if not InvestigationSaveCodec.whole(selected,1,int(a.unlocked)): return _result(original,"INVALID_ACTION")
			a.index = int(selected)
			a.phase = "playing"
			a.attempt = 1
			return changed(s,"STAGE_STARTED","BOOT OK")
		"stage.command":
			if a.phase != "playing": return _result(original,"STAGE_BUSY","terminal: session closed")
			var raw = p.get("command","")
			if not raw is String or raw.length() > 200: return mistake(s,"command: invalid input")
			var command = " ".join(raw.strip_edges().split(" ",false)).to_lower()
			if command.is_empty(): return _result(original,"STAGE_EMPTY","")
			var stage = definition(s)
			if command == "help": return _result(original,"STAGE_OUTPUT",stage.help+"\nclear  history  exit")
			if command == "ls": return _result(original,"STAGE_OUTPUT","\n".join(stage.files.keys()))
			if command == "pwd": return _result(original,"STAGE_OUTPUT","/office/pc-%02d" % a.index)
			if stage.solutions.has(command):
				if a.index not in a.cleared:
					a.cleared.append(int(a.index))
					a.unlocked = mini(COUNT,int(a.index)+1)
				a.phase = "clear"
				return changed(s,"STAGE_CLEAR",stage.solutions[command])
			if stage.outputs.has(command): return _result(original,"STAGE_OUTPUT",stage.outputs[command])
			if command.begins_with("cat ") and stage.files.has(command.substr(4)):
				return _result(original,"STAGE_OUTPUT",stage.files[command.substr(4)])
			return mistake(s,"%s: command or target not found" % command)
	return _result(original,"INVALID_ACTION")

func changed(s: Dictionary, code: String, output: String) -> Dictionary:
	s.revision += 1
	return _result(s,code,output)

func mistake(s: Dictionary, output: String) -> Dictionary:
	s.stage.mistakes += 1
	if s.stage.index < 3: return changed(s,"STAGE_PRACTICE",output)
	s.stage.phase = "exploded"
	s.stage.blasts += 1
	return changed(s,"STAGE_EXPLODED",output+"\nKERNEL PANIC\nWARRANTY=VOID")

static func valid_progress(a) -> bool:
	if not a is Dictionary or a.keys().size() != 8 or a.get("version") != 1: return false
	if not InvestigationSaveCodec.whole(a.get("index"),1,COUNT) or not InvestigationSaveCodec.whole(a.get("unlocked"),1,COUNT) or a.index > a.unlocked: return false
	if a.get("phase") not in PHASES: return false
	for key in ["mistakes","blasts"]:
		if not InvestigationSaveCodec.whole(a.get(key),0,1000000): return false
	if a.blasts > a.mistakes or not InvestigationSaveCodec.whole(a.get("attempt"),1,1000000): return false
	if not a.get("cleared") is Array or a.cleared.size() > COUNT: return false
	for i in range(a.cleared.size()):
		if a.cleared[i] != i+1: return false
	if a.unlocked != mini(COUNT,a.cleared.size()+1): return false
	if a.phase == "exploded" and (a.index < 3 or a.blasts == 0): return false
	if a.phase == "clear" and a.index not in a.cleared: return false
	if a.phase == "complete" and (a.index != COUNT or a.cleared.size() != COUNT): return false
	return true
