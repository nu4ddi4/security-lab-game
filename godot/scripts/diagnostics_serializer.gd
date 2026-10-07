class_name LabDiagnosticsSerializer
extends RefCounted

# No identifiers are retained in the report. These values exist only to redact
# hardware strings and any future diagnostic fields before serialization.
var private_terms: Array[String] = []
var profile = ""

func _init():
	profile = OS.get_environment("USERPROFILE").replace("\\","/").trim_suffix("/")
	for key in ["USERNAME","USERDOMAIN","COMPUTERNAME"]:
		var value = OS.get_environment(key)
		if value.length() >= 2: private_terms.append(value)

func replace_pattern(text: String, pattern: String, replacement: String) -> String:
	var regex = RegEx.new()
	if regex.compile(pattern) != OK: return "[redacted]"
	return regex.sub(text,replacement,true)

func text(value: String) -> String:
	var result = display_path(value.left(2048))
	result = replace_pattern(result,"(?i)Bearer\\s+[^\\s]+","[credential redacted]")
	result = replace_pattern(result,"(?i)(?:authorization|password|passwd|token|secret|api[_-]?key|cookie)\\s*[:=]\\s*[^\\r\\n;]+","[credential redacted]")
	result = replace_pattern(result,"(?i)[a-z0-9._%+-]+@[a-z0-9.-]+\\.[a-z]{2,}","[email redacted]")
	result = replace_pattern(result,"(?<![0-9])(?:[0-9]{1,3}\\.){3}[0-9]{1,3}(?![0-9])","[IP redacted]")
	result = replace_pattern(result,"(?i)(?:[0-9a-f]{2}[:-]){5}[0-9a-f]{2}","[MAC redacted]")
	result = replace_pattern(result,"(?i)(?<![a-z0-9])(?:[0-9a-f]{0,4}:){2,}[0-9a-f:.%]*(?![a-z0-9])","[IP redacted]")
	result = replace_pattern(result,"(?i)(?:https?://|//)[^\\s\"<>]+","[network location redacted]")
	# Paths outside the profile are also omitted rather than leaking folder names.
	result = replace_pattern(result,"(?i)(?<![a-z0-9])[a-z]:/[^\"\\r\\n<>]*","[path redacted]")
	for term in private_terms:
		result = replace_pattern(result,"(?i)(?<![\\p{L}\\p{N}_])"+escape_regex(term)+"(?![\\p{L}\\p{N}_])","[identity redacted]")
	return result

func display_path(value: String) -> String:
	# UI-only destination label. Preserve the actual suffix and non-profile
	# drive locations so users can find the file. Never placed in the ZIP.
	var result = value.replace("\\","/")
	if not profile.is_empty(): result = replace_pattern(result,"(?i)"+escape_regex(profile),"%USERPROFILE%")
	result = replace_pattern(result,"(?i)[a-z]:/users/[^/\\s\"<>]+","%USERPROFILE%")
	return replace_pattern(result,"(?i)/(?:home|Users)/[^/\\s\"<>]+","%USERPROFILE%")

func escape_regex(value: String) -> String:
	var result = ""
	for character in value:
		if character in "\\.^$|?*+()[]{}": result += "\\"
		result += character
	return result

func clean(value, depth = 0):
	if depth > 12: return "[depth limit]"
	if value is String: return text(value)
	if value is Dictionary:
		var result = {}
		for key in value:
			# Defensive second layer; collectors themselves use fixed allowlists.
			if String(key).to_lower() in ["username","user","account","hostname","ip","mac","environment","password","token","secret","authorization","save_raw","path","command_line","api_key","apikey","cookie","credentials","raw_save"]: continue
			result[text(String(key))] = clean(value[key],depth+1)
		return result
	if value is Array:
		var result = []
		for item in value.slice(0,256): result.append(clean(item,depth+1))
		return result
	if value is bool or value == null or value is int: return value
	if value is float: return value if is_finite(value) else null
	return "[unsupported value]"

func json(value) -> String:
	return JSON.stringify(clean(value),"\t")

func version(value) -> String:
	var candidate = str(value).left(80)
	var regex = RegEx.new()
	regex.compile("^[0-9]{1,8}\\.[0-9]{1,8}\\.[0-9]{1,8}(?:-(?:native|alpha|beta|dev|rc)\\.[0-9]{1,8})?$")
	return candidate if regex.search(candidate) != null else "unknown"

func build(raw) -> Dictionary:
	if not raw is Dictionary: raw = {}
	var commit = str(raw.get("commit","unknown"))
	var regex = RegEx.new()
	regex.compile("^[0-9a-f]{40}$")
	return {"app_id":enum_value(raw.get("app_id"),["security-lab-native","security-lab-beta"],"security-lab-native"),"version":version(raw.get("version","unknown")),"commit":commit if regex.search(commit) != null else "unknown","channel":enum_value(raw.get("channel"),["stable","beta","dev"],"unknown")}

func enum_value(value, allowed: Array, fallback = "unknown") -> String:
	return value if value is String and value in allowed else fallback

func settings(raw: Dictionary) -> Dictionary:
	var result = {}
	for key in ["resolution","fullscreen","vsync","quality","master","sfx","sensitivity","fov"]:
		var value = raw.get(key)
		if value is bool or value is int or value is float and is_finite(value): result[key] = value
	return result

func log_summary(raw: String) -> Dictionary:
	# Free-form log text is not copied: an error can contain secrets even after
	# regex redaction. Only fixed event codes, numeric counters and enums survive.
	var result = {"lines_scanned":0,"error_lines":0,"warning_lines":0,"crash_marker":false,"events":[],"errors":[],"free_text_included":false}
	var site = RegEx.new()
	site.compile("\\(res://((?:scripts/(?:diagnostics|diagnostics_serializer|game|settings|save_manager|missions|ui|player|world|audio|equipment|screen|device|door|exterior|update_manager|update_policy)|prototype/scripts/(?:diagnostics|game|ui|input_controls|installer_updates|updates|engine|store|save_codec|target)))\\.gd:([0-9]{1,7})\\)")
	for line in raw.split("\n"):
		result.lines_scanned += 1
		if line.begins_with("ERROR:") or line.begins_with("SCRIPT ERROR:"): result.error_lines += 1
		if line.begins_with("WARNING:"): result.warning_lines += 1
		if line.begins_with("ERROR:") or line.begins_with("SCRIPT ERROR:") or line.begins_with("WARNING:"):
			var kind = "script_error" if line.begins_with("SCRIPT ERROR:") else "warning" if line.begins_with("WARNING:") else "engine_error"
			if line.contains("Parse Error"): kind = "parse_error"
			elif line.contains("Invalid access") or line.contains("Invalid assignment"): kind = "invalid_access"
			elif line.contains("null instance"): kind = "null_instance"
			result.errors.append({"kind":kind})
			if result.errors.size() > 16: result.errors.pop_front()
		var match_site = site.search(line)
		if match_site != null and not result.errors.is_empty():
			var last = result.errors[-1]
			if not last.has("source"):
				last.source = "res://"+match_site.get_string(1)+".gd"
				last.line = int(match_site.get_string(2))
		if line.contains("handle_crash") or line.contains("Program crashed") or line.contains("Fatal error"): result.crash_marker = true
		var prefix = "PROTOTYPE_READY " if line.begins_with("PROTOTYPE_READY ") else "NATIVE_READY "
		if not line.begins_with(prefix): continue
		var ready = JSON.parse_string(line.trim_prefix(prefix))
		if not ready is Dictionary: continue
		var event = {"event":"investigation_ready" if prefix=="PROTOTYPE_READY " else "native_ready","renderer":enum_value(ready.get("renderer"),["forward_plus","mobile","gl_compatibility"])}
		for key in ["load_ms","functional","colliders","doors","devices","screens","leds","npcs"]:
			if ready.get(key) is int or ready.get(key) is float and is_finite(ready[key]): event[key] = clampf(float(ready[key]),0,10000000)
		result.events.append(event)
	result.events = result.events.slice(-16)
	return result
