extends SceneTree

const Serializer = preload("res://scripts/diagnostics_serializer.gd")
class TestDiagnostics:
	extends "res://scripts/diagnostics.gd"
	# Linux CI exercises the native ZIP implementation without a Windows shell.
	func supported() -> bool: return true

class FakeUpdater:
	extends RefCounted
	var state = "ready"
	var enabled = true
	var info = {"version":"0.7.1","channel":"stable","commit":"1234567890123456789012345678901234567890","secret":"do-not-copy"}

class FakeGame:
	extends Node
	var updater = FakeUpdater.new()

var failures: Array = []
var assertions = 0
var directory = "user://qa/diagnostics-tests-%d" % Time.get_ticks_usec()

func check(value: bool, message: String):
	assertions += 1
	if not value: failures.append(message); push_error(message)

func write(path: String, content: String):
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file = FileAccess.open(path,FileAccess.WRITE)
	check(file != null,"Fixture opens")
	if file != null: file.store_string(content); file.close()

func _initialize():
	var serializer = Serializer.new()
	serializer.profile = "C:/Users/Alice"
	serializer.private_terms.assign(["Alice","WORKSTATION-PRIVATE","CORPDOMAIN"])
	for raw in ["C:\\Users\\Alice\\AppData\\Roaming\\test.log","c:/users/ALICE/AppData/test.log","D:/Users/홍길동/AppData/test.log","/home/alice/private/file","/Users/Bob/private/file"]:
		var clean = serializer.text(raw)
		check(clean.contains("%USERPROFILE%"),"Profile path anonymized")
		for identity in ["Alice","ALICE","홍길동","Bob"]: check(not clean.contains(identity),"Path identity excluded")
	for raw in ["192.168.1.11","127.0.0.1","2001:db8::1234","::1","fe80::1234%8","AA:BB:CC:DD:EE:FF","aa-bb-cc-dd-ee-ff","person@example.com","password=pa55word","Authorization: Bearer supersecret","token=abc123","https://example.com/?secret=123","\\\\PrivateServer\\users\\Alice","C:/PrivateProject/NamedClient","Alice WORKSTATION-PRIVATE CORPDOMAIN"]:
		var clean = serializer.text(raw)
		check(clean != raw and not clean.contains("pa55word") and not clean.contains("supersecret") and not clean.contains("abc123"),"Sensitive string removed")
	check(serializer.text("NVIDIA RTX 4070 / AMD Ryzen 7 7700") == "NVIDIA RTX 4070 / AMD Ryzen 7 7700","Useful hardware names retained")
	var encoded = serializer.json({"username":"Alice","environment":{"PASS":"hidden"},"api_key":"secretvalue","display":{"gpu":"RTX 4070","location":"C:/Users/Alice/AppData"},"finite":INF})
	var parsed = JSON.parse_string(encoded)
	check(parsed is Dictionary and parsed.finite == null and not parsed.has("username") and not parsed.has("api_key"),"JSON serializes without private fields or nonfinite numbers")
	check(not encoded.contains("Alice") and not encoded.contains("secretvalue") and not encoded.contains("hidden"),"Nested redaction and key filtering")
	var build = serializer.build({"version":"0.7.1-beta.1","channel":"beta","commit":"d9c573dae2099c4caf0138f5183654509a76a949","token":"secret","path":"private"})
	check(build.size() == 4 and build.version == "0.7.1-beta.1" and build.channel == "beta","Build uses strict projection")
	check(serializer.build({"version":"Alice/secret","channel":"private","commit":"path"}).commit == "unknown","Malformed build identity rejected")
	check(serializer.version("1.2.3-private-password") == "unknown","Arbitrary version suffix cannot carry free text")
	check(serializer.settings({"quality":2,"sensitivity":.002,"token":"secret","resolution":"C:/Users/Alice"}).size() == 2,"Only typed known settings included")
	var logs = "ERROR: password=private-token C:/Users/Alice\nSCRIPT ERROR: Person@example.com\nWARNING: 192.168.1.1\nNATIVE_READY {\"renderer\":\"forward_plus\",\"load_ms\":500,\"token\":\"supersecret\",\"devices\":5}\nhandle_crash Alice"
	var summary = serializer.log_summary(logs)
	check(summary.error_lines == 2 and summary.warning_lines == 1 and summary.crash_marker,"Log severity and crash marker retained")
	check(summary.events.size() == 1 and summary.events[0].devices == 5,"Allowlisted native log event retained")
	var projected = JSON.stringify(summary)
	for forbidden in ["Alice","Person","192.168","supersecret","private-token","password","token"]: check(not projected.contains(forbidden),"Raw log text never included")
	var safe_site = serializer.log_summary("SCRIPT ERROR: Invalid access password=secret\n at: run (res://scripts/settings.gd:100)\nERROR: C:/Users/Alice/private.gd:10")
	check(safe_site.errors[0] == {"kind":"invalid_access","source":"res://scripts/settings.gd","line":100},"Error category and allowlisted source retained")
	check(not JSON.stringify(safe_site).contains("secret") and not JSON.stringify(safe_site).contains("private.gd"),"Error details and unknown paths discarded")
	var diagnostics = TestDiagnostics.new()
	root.add_child(diagnostics)
	diagnostics.data_directory = directory
	diagnostics.save_directory = directory.path_join("saves")
	diagnostics.log_directory = directory.path_join("logs")
	diagnostics.update_directory = directory.path_join("updates")
	diagnostics.begin_session()
	check(diagnostics.session_writable and not diagnostics.previous_session.available,"First session marker created")
	check(diagnostics.recent_logs()[0].status == "missing" and not diagnostics.updater_summary().available,"Absent optional log and updater handled")
	check(diagnostics.save_validation()["progress.json"].status == "missing","Absent save remains absent")
	check(diagnostics.create_package().ok,"Missing optional files still permit ZIP generation")
	var resumed = TestDiagnostics.new()
	root.add_child(resumed)
	resumed.data_directory = directory
	resumed.begin_session()
	check(resumed.previous_session.suspected_abnormal_exit,"Unclean previous session reported without claiming crash")
	resumed.write_session(true)
	resumed.begin_session()
	check(not resumed.previous_session.suspected_abnormal_exit,"Clean previous exit retained")
	var probe = LabMissions.new()
	var store = LabSave.new()
	var raw_save = JSON.stringify({"format":"security-lab-native","version":1,"game":store.encode(probe)})
	write(diagnostics.save_directory.path_join("progress.json"),raw_save)
	var validation = diagnostics.save_validation()
	check(validation["progress.json"].status == "valid" and validation["progress.backup.json"].status == "missing","Valid save and absent optional backup")
	check(FileAccess.get_file_as_string(diagnostics.save_directory.path_join("progress.json")) == raw_save,"Validation never rewrites save")
	write(diagnostics.save_directory.path_join("progress.json"),"not JSON Alice secret")
	check(diagnostics.save_validation()["progress.json"].status == "invalid","Invalid save reported without raw/error text")
	write(diagnostics.save_directory.path_join("progress.json"),"X".repeat(131073))
	check(diagnostics.save_validation()["progress.json"].status == "oversize","Oversized save bounded")
	write(diagnostics.log_directory.path_join("godot.log"),logs)
	write(diagnostics.log_directory.path_join("arbitrary-user.log"),"do-not-copy-this")
	check(diagnostics.recent_logs().size() == 1 and diagnostics.recent_logs()[0].summary.events.size() == 1,"Only known engine log names read")
	write(diagnostics.log_directory.path_join("godot.log"),"X".repeat(100000)+"\n"+logs)
	check(diagnostics.recent_logs()[0].tail_truncated,"Large log uses bounded tail")
	check(not diagnostics.safe_path("//server/private"),"UNC paths rejected")
	var updater_dir = diagnostics.update_directory.path_join("12345678-1234-1234-1234-123456789012")
	write(updater_dir.path_join("result.json"),JSON.stringify({"state":"rolled_back","version":"0.7.1","token":"secret","backup":"C:/Users/Alice","error":"password=private"}))
	var updater = diagnostics.updater_summary()
	check(updater.available and updater.recent_result.state == "rolled_back","Optional updater result detected")
	for forbidden in ["secret","Alice","backup","password","error"]: check(not JSON.stringify(updater).contains(forbidden),"Updater sensitive fields excluded")
	var fake = FakeGame.new()
	diagnostics.game = fake
	check(diagnostics.updater_summary().state == "ready" and diagnostics.updater_summary().enabled,"Optional runtime updater reflected without calling updater")
	diagnostics.game = null
	fake.free()
	var snapshot = diagnostics.snapshot()
	check(snapshot.schema == 1 and snapshot.runtime.available == false and snapshot.privacy.save_content_included == false,"Snapshot generated with optional runtime absent")
	check(snapshot.build.has("commit") and snapshot.godot.contains("4.7.2"),"Build and Godot identity present")
	var package = diagnostics.create_package()
	check(package.ok and package.file.ends_with(".zip"),"Real native ZIP generated")
	var reader = ZIPReader.new()
	check(reader.open(package.get("file","")) == OK,"ZIP can be reopened")
	var expected = ["README.txt","diagnostics.json","build_info.json","save_validation.json","logs/recent.json","updater.json","session.json"]
	check(reader.get_files().size() == expected.size()+1 and "logs/" in reader.get_files(),"ZIP contains fixed support files and the logs directory")
	for name in expected:
		check(name in reader.get_files(),"ZIP contains "+name)
		var text = reader.read_file(name).get_string_from_utf8()
		if name.ends_with(".json"): check(JSON.parse_string(text) != null,"ZIP JSON parseable")
		for forbidden in ["Alice","supersecret","private-token","do-not-copy-this","password=","X".repeat(80),"\"clues\"","\"answer\""]: check(not text.contains(forbidden),"Private content absent in "+name)
	reader.close()
	check(diagnostics.create_package().file != package.file,"Same-second filenames do not overwrite")
	var invalid = diagnostics.create_package(directory.path_join("missing-folder"))
	check(not invalid.ok and invalid.message.contains("실패") or not invalid.ok and invalid.message.contains("폴더"),"Invalid destination has clear error")
	write(directory.path_join("not-a-directory"),"fixture")
	check(not diagnostics.create_package(directory.path_join("not-a-directory")).ok,"File destination rejected")
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--diagnostics-denied="):
			check(not diagnostics.create_package(argument.trim_prefix("--diagnostics-denied=")).ok,"Unwritable destination returns error")
		if argument.begins_with("--diagnostics-link="):
			var link = argument.trim_prefix("--diagnostics-link=")
			check(not diagnostics.safe_path(link) and not diagnostics.safe_path(link.path_join("private.json")),"Link and linked ancestors rejected before reading")
			check(diagnostics.read_json(link.path_join("private.json")).status == "unsafe_path","Linked optional file not read")
			check(not diagnostics.create_package(link).ok,"Linked output destination rejected")
	probe.free()
	diagnostics.queue_free(); resumed.queue_free()
	print("NATIVE_DIAGNOSTICS ",JSON.stringify({"passed":failures.is_empty(),"assertions":assertions,"failures":failures}))
	quit(0 if failures.is_empty() else 1)
