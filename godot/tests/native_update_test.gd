extends SceneTree
const Policy = preload("res://scripts/update_policy.gd")
const Updater = preload("res://scripts/update_manager.gd")
var failures: Array = []
var assertions = 0

func expect(condition: bool, message: String):
	assertions += 1
	if not condition: failures.append(message)

func _init():
	var source = Policy.manifest_url("dev")
	var valid = {"schema":1,"app_id":Policy.APP_ID,"platform":Policy.PLATFORM,"install_layout":1,"channel":"dev","version":"0.7.1-dev.1","commit":"a".repeat(40),"sha256":"b".repeat(64),"exe_sha256":"c".repeat(64),"size":2048,"installer_url":Policy.REPOSITORY+"native-dev-v0.7.1-dev.1/SecurityLabSetup.exe"}
	expect(Policy.manifest_valid(valid,"dev",source,false),"valid manifest")
	for channel in Policy.CHANNELS:
		var build = {"schema":1,"app_id":Policy.APP_ID,"platform":Policy.PLATFORM,"install_layout":1,"channel":channel,"version":"0.7.1" if channel=="stable" else "0.7.1-"+channel+".1","commit":"a".repeat(40),"updates_default":channel=="stable","manifest_url":Policy.manifest_url(channel)}
		expect(Policy.build_valid(build),channel+" baked identity")
		expect(Policy.preference_path(channel)=="user://update-settings-"+channel+".json",channel+" isolated preference")
		expect(Policy.enabled_for(build,[],null,true)==(channel=="stable"),channel+" default")
		expect(not Policy.enabled_for(build,["--force-update-check","--disable-updates"],null,true),"disable wins")
		expect(Policy.enabled_for(build,["--force-update-check"],null,true),"forced check")
		expect(not Policy.enabled_for(build,["--force-update-check"],null,false),"Windows only")
		expect(not Policy.enabled_for(build,[],{"enabled":false},true),"persisted opt out")
		expect(Policy.trusted_manifest(Policy.manifest_url(channel),channel,false),"own channel endpoint")
		for other in Policy.CHANNELS:
			if other==channel: continue
			expect(not Policy.trusted_manifest(Policy.manifest_url(other),channel,false),"other channel URL")
			var cross = valid.duplicate(); cross.channel = other
			expect(not Policy.manifest_valid(cross,channel,Policy.manifest_url(channel),false),"cross channel manifest")
	for url in ["https://evil.example/update.json",source+"?x=1",source+"#x",source.replace("github.com","github.com.evil"),source.replace("https:","http:"),"https://user@github.com/nu4ddi4/security-lab-game/releases/download/native-channel-dev/update.json",source.replace("native-channel-dev","native-channel-%2e%2e"),"http://localhost.evil:123/dev/update.json","http://127.1:123/dev/update.json","http://localhost@evil:123/dev/update.json","http://localhost:0/dev/update.json","http://localhost:65536/dev/update.json"]:
		expect(not Policy.trusted_manifest(url,"dev",false),"reject remote manifest "+url)
	for host in ["localhost","127.0.0.1"]:
		var url = "http://"+host+":12345/dev/update.json"
		expect(Policy.trusted_manifest(url,"dev",true),"explicit loopback port")
		expect(not Policy.trusted_manifest(url,"dev",false),"loopback default off")
		var local = valid.duplicate(); local.installer_url="http://"+host+":12345/dev/SecurityLabSetup.exe"
		expect(Policy.manifest_valid(local,"dev",url,true),"loopback installer")
		local.installer_url=local.installer_url.replace(":12345",":12346")
		expect(not Policy.manifest_valid(local,"dev",url,true),"different loopback port")
	for pair in [["0.7.1","0.7.0",true],["0.7.1","0.7.1",false],["0.7.0","0.7.1",false],["0.7.1-dev.10","0.7.1-dev.9",true],["0.7.1-beta.1","0.7.1-dev.1",false],["0.7.1","0.7.1-beta.9",true],["0.7.1-dev.1","0.7.1",false]]:
		expect(Policy.newer(pair[0],pair[1])==pair[2],"version comparison")
	for version in ["01.2.3-dev.1","0.7.x-dev.1","0.7.1-dev.01","0.7.1-dev.1;calc","65536.0.0-dev.1","0.7.1-dev..1"]:
		expect(not Policy.valid_version(version,"dev"),"invalid version")
	for entry in [["app_id","other"],["platform","linux"],["install_layout",2],["schema",2],["sha256","z".repeat(64)],["exe_sha256","a"],["commit",123],["size",true],["size",2048.5],["size",0],["size",536870913],["version","0.7.1-beta.1"],["installer_url","https://evil.example/SecurityLabSetup.exe"]]:
		var malformed = valid.duplicate(); malformed[entry[0]]=entry[1]
		expect(not Policy.manifest_valid(malformed,"dev",source,false),"malformed "+entry[0])
	for url in ["https://evil.example/a.exe","http://release-assets.githubusercontent.com/a.exe","https://release-assets.githubusercontent.com.evil/a.exe","https://user@release-assets.githubusercontent.com/a.exe","https://release-assets.githubusercontent.com/a.exe#b"]:
		expect(not Policy.trusted_redirect(url,source,false),"redirect origin")
	expect(Policy.trusted_redirect("https://release-assets.githubusercontent.com/a/b?sig=c&x=1",source,false),"GitHub asset redirect")
	var updater = Updater.new()
	expect(updater.state=="disabled" and not updater.enabled and not updater.consent_granted,"idle source cannot update")
	updater.free()
	print("NATIVE_UPDATE_TEST ",JSON.stringify({"passed":failures.is_empty(),"assertions":assertions,"failures":failures}))
	quit(0 if failures.is_empty() else 1)
