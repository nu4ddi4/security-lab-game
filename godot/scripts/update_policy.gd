class_name NativeUpdatePolicy
extends RefCounted

const APP_ID = "security-lab-native"
const PLATFORM = "windows-x86_64"
const REPOSITORY = "https://github.com/nu4ddi4/security-lab-game/releases/download/"
const CHANNELS = ["stable", "beta", "dev"]
const MAX_INSTALLER_BYTES = 536870912
const MAX_CONTENT_BYTES = 268435456

static func manifest_url(channel: String, app_id: String = APP_ID) -> String:
	return REPOSITORY+("beta-channel-" if app_id=="security-lab-beta" else "native-channel-")+channel+"/update.json" if channel in CHANNELS and app_id in [APP_ID,"security-lab-beta"] else ""

# Dev builds only follow dev. Stable and beta builds always watch stable, so a
# promoted release reaches beta testers, and add beta when the preview is on.
static func channels_to_check(own: String, preview: bool) -> Array:
	if own not in CHANNELS: return []
	if own == "dev": return ["dev"]
	return ["stable","beta"] if preview else ["stable"]

static func preference_path(channel: String, app_id: String = APP_ID) -> String:
	return "user://"+("beta-update-settings-" if app_id=="security-lab-beta" else "update-settings-")+channel+".json" if channel in CHANNELS else ""

static func enabled_for(build: Dictionary, arguments: PackedStringArray, preference, windows: bool) -> bool:
	if not windows or "--disable-updates" in arguments: return false
	if "--force-update-check" in arguments: return true
	return preference.enabled if preference is Dictionary and preference.get("enabled") is bool else build.get("updates_default",false)

static func version_parts(value: String) -> Array:
	if value.length()>96: return []
	var match = RegEx.create_from_string("^(0|[1-9][0-9]{0,4})\\.(0|[1-9][0-9]{0,4})\\.(0|[1-9][0-9]{0,4})(?:-([0-9A-Za-z]+(?:[.-][0-9A-Za-z]+)*))?$").search(value)
	if match == null: return []
	var numbers = [int(match.get_string(1)),int(match.get_string(2)),int(match.get_string(3))]
	for number in numbers:
		if number>65535: return []
	var pre = match.get_string(4)
	for part in pre.split("."):
		if part.is_valid_int() and part.length()>1 and part.begins_with("0"): return []
	return numbers+[pre]

static func valid_version(value: String, channel: String) -> bool:
	var parts = version_parts(value)
	if parts.is_empty() or channel not in CHANNELS: return false
	return parts[3]=="" if channel=="stable" else parts[3].begins_with(channel+".")

static func newer(remote: String, current: String) -> bool:
	var a = version_parts(remote); var b = version_parts(current)
	if a.is_empty() or b.is_empty(): return false
	for i in range(3):
		if a[i]!=b[i]: return a[i]>b[i]
	if a[3]==b[3]: return false
	if a[3]=="": return true
	if b[3]=="": return false
	var ap = a[3].split("."); var bp = b[3].split(".")
	for i in range(min(ap.size(),bp.size())):
		if ap[i]==bp[i]: continue
		if ap[i].is_valid_int() and bp[i].is_valid_int(): return int(ap[i])>int(bp[i])
		if ap[i].is_valid_int()!=bp[i].is_valid_int(): return not ap[i].is_valid_int()
		return ap[i]>bp[i]
	return ap.size()>bp.size()

static func clean_url(url: String) -> bool:
	return url.length()<8192 and RegEx.create_from_string("[\\x00-\\x20\\x7f\\\\#]").search(url)==null

static func local_origin(url: String) -> String:
	if not clean_url(url): return ""
	var match = RegEx.create_from_string("^http://(127\\.0\\.0\\.1|localhost)(?::([0-9]{1,5}))?/").search(url)
	if match == null: return ""
	var port = match.get_string(2)
	if port!="" and (int(port)<1 or int(port)>65535): return ""
	return match.get_string(0).trim_suffix("/")

static func trusted_manifest(url: String, channel: String, local_test: bool, app_id: String = APP_ID) -> bool:
	if channel not in CHANNELS or not clean_url(url): return false
	if url==manifest_url(channel,app_id): return true
	var origin = local_origin(url) if local_test else ""
	return origin!="" and url==origin+"/"+channel+"/update.json"

static func trusted_installer(url: String, version: String, channel: String, source: String, local_test: bool, app_id: String = APP_ID) -> bool:
	if not clean_url(url): return false
	var tag = "SecurityLab-"+version if app_id=="security-lab-beta" else "native-"+channel+"-v"+version
	if url==REPOSITORY+tag+"/SecurityLabSetup.exe": return true
	# Existing beta.1 installations still recognize their immutable legacy payload.
	if app_id=="security-lab-beta" and channel=="beta" and version.ends_with("-beta.1") and url==REPOSITORY+"SecurityLab-beta-"+version.split("-")[0]+"/SecurityLabSetup.exe": return true
	var origin = local_origin(source) if local_test else ""
	return origin!="" and url==origin+"/"+channel+"/SecurityLabSetup.exe"

# The game-data pack of a release. It replaces files inside the installed executable,
# so it is only valid for executables carrying the same compat key.
static func trusted_content(url: String, version: String, channel: String, source: String, local_test: bool, app_id: String = APP_ID) -> bool:
	if not clean_url(url): return false
	var tag = "SecurityLab-"+version if app_id=="security-lab-beta" else "native-"+channel+"-v"+version
	if url==REPOSITORY+tag+"/SecurityLabContent.pck": return true
	var origin = local_origin(source) if local_test else ""
	return origin!="" and url==origin+"/"+channel+"/SecurityLabContent.pck"

static func content_valid(info: Dictionary, channel: String, source: String, local_test: bool, app_id: String = APP_ID) -> bool:
	if not manifest_valid(info,channel,source,local_test,app_id): return false
	if not hex(info.get("compat"),64) or not hex(info.get("content_sha256"),64): return false
	var size = info.get("content_size")
	if not (size is int or size is float) or not is_finite(float(size)) or size!=int(size) or size<1024 or size>MAX_CONTENT_BYTES: return false
	return info.get("content_url") is String and trusted_content(info.content_url,info.version,channel,source,local_test,app_id)

static func trusted_redirect(url: String, source: String, local_test: bool) -> bool:
	if not clean_url(url): return false
	if local_test and local_origin(source)!="": return local_origin(url)==local_origin(source)
	return RegEx.create_from_string("^https://(?:release-assets|objects)\\.githubusercontent\\.com/[A-Za-z0-9_./%?=&+~:-]+$").search(url)!=null

static func hex(value, length: int) -> bool:
	return value is String and RegEx.create_from_string("^[0-9a-f]{%d}$"%length).search(value)!=null

static func build_valid(info: Dictionary) -> bool:
	return info.get("schema")==1 and info.get("app_id") in [APP_ID,"security-lab-beta"] and info.get("platform")==PLATFORM and info.get("channel") in CHANNELS and info.get("version") is String and valid_version(info.version,info.channel) and hex(info.get("commit"),40) and info.get("install_layout")==1 and info.get("updates_default") is bool and (info.app_id=="security-lab-beta" or info.updates_default==(info.channel=="stable")) and info.get("manifest_url")==manifest_url(info.channel,info.app_id)

static func manifest_valid(info: Dictionary, channel: String, source: String, local_test: bool, app_id: String = APP_ID) -> bool:
	if info.get("schema")!=1 or info.get("app_id")!=app_id or info.get("platform")!=PLATFORM or info.get("channel")!=channel or info.get("install_layout")!=1: return false
	if not info.get("version") is String or not valid_version(info.version,channel): return false
	if not hex(info.get("commit"),40) or not hex(info.get("sha256"),64) or not hex(info.get("exe_sha256"),64): return false
	var size = info.get("size")
	if not (size is int or size is float) or not is_finite(float(size)) or size!=int(size) or size<1024 or size>MAX_INSTALLER_BYTES: return false
	return info.get("installer_url") is String and trusted_installer(info.installer_url,info.version,channel,source,local_test,app_id)
