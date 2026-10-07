class_name InvestigationUpdates
extends Node

signal changed
const API = "https://api.github.com/repos/nu4ddi4/security-lab-game/releases?per_page=100"
const DOWNLOAD = "https://github.com/nu4ddi4/security-lab-game/releases/download/"
var installed = {}
var platform = OS.get_name()
var status = ""
var download_url = ""
var busy = false
var request: HTTPRequest

static func version_parts(value: String) -> Array:
	var pattern = RegEx.new()
	pattern.compile("^(0|[1-9][0-9]*)\\.(0|[1-9][0-9]*)\\.(0|[1-9][0-9]*)$")
	if pattern.search(value) == null: return []
	return Array(value.split(".")).map(func(part): return int(part))

static func newer(a: String, b: String) -> bool:
	var left = version_parts(a)
	var right = version_parts(b)
	if left.is_empty() or right.is_empty(): return false
	for index in range(3):
		if left[index] != right[index]: return left[index] > right[index]
	return false

static func select_release(releases: Array, metadata: Dictionary, target: String) -> Dictionary:
	var best = {}
	var prefix = metadata.get("tag_prefix","SecurityLab-proto-")
	for release in releases:
		if not release is Dictionary or release.get("draft",true) != false: continue
		if release.get("prerelease") != metadata.get("prerelease"): continue
		var tag = release.get("tag_name","")
		if not tag is String or not tag.begins_with(prefix): continue
		var version = tag.trim_prefix(prefix)
		if not newer(version,metadata.get("version","")): continue
		if not best.is_empty() and not newer(version,best.version): continue
		best = {"version":version,"url":""}
		var extension = {"Android":".apk","Windows":".exe"}.get(target,"")
		if extension == "": continue
		var filename = tag+extension
		var expected_url = DOWNLOAD+tag.uri_encode()+"/"+filename.uri_encode()
		var assets = release.get("assets",[])
		if not assets is Array: continue
		for asset in assets:
			if asset is Dictionary and asset.get("name") == filename and asset.get("state") == "uploaded" and typeof(asset.get("size",0)) in [TYPE_INT,TYPE_FLOAT] and asset.get("size",0) > 0 and asset.get("browser_download_url") == expected_url:
				best.url = expected_url
	return best

func _ready():
	var metadata = JSON.parse_string(FileAccess.get_file_as_string("res://prototype/version.json"))
	if metadata is Dictionary: installed = metadata
	status = "현재 %s · %s 채널" % [installed.get("version","개발"),"사전 릴리즈" if installed.get("prerelease",true) else "안정"]
	request = HTTPRequest.new()
	request.timeout = 12
	request.body_size_limit = 1024*1024
	request.max_redirects = 0
	add_child(request)
	request.request_completed.connect(_completed)

func check():
	if busy: return
	busy = true
	download_url = ""
	status = "업데이트 확인 중…"
	changed.emit()
	var result = request.request(API,PackedStringArray(["Accept: application/vnd.github+json","User-Agent: SecurityLab-update-check"]))
	if result != OK: _failed()

func _failed():
	busy = false
	status = "업데이트를 확인하지 못했습니다. 연결 후 다시 확인하세요."
	changed.emit()

func _completed(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray):
	if result != HTTPRequest.RESULT_SUCCESS or code != 200: _failed(); return
	var releases = JSON.parse_string(body.get_string_from_utf8())
	if not releases is Array: _failed(); return
	busy = false
	var candidate = select_release(releases,installed,platform)
	if candidate.is_empty(): status = "현재 채널의 최신 버전입니다."
	elif candidate.url == "": status = "새 버전 %s · 이 플랫폼의 배포 파일이 아직 없습니다." % candidate.version
	else:
		download_url = candidate.url
		status = "새 버전 %s · 다운로드 후 %s" % [candidate.version,"기존 앱 위에 설치하세요. 저장은 유지됩니다." if platform == "Android" else "게임을 닫고 새 실행 파일로 실행하세요. 저장은 유지됩니다."]
	changed.emit()

func open_download():
	if not download_url.begins_with(DOWNLOAD): return
	if OS.shell_open(download_url) != OK:
		status = "다운로드 페이지를 열지 못했습니다. GitHub 릴리즈에서 파일을 받아 주세요."
		changed.emit()
