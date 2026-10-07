extends Control

var profile = "case"
var snapshot: Dictionary = {}
var font = FontVariation.new()

func _ready():
	font.base_font = preload("res://assets/fonts/NotoSansKR.ttf")
	font.variation_opentype = {2003265652:450.0}
	queue_redraw()

func _draw():
	draw_rect(Rect2(Vector2.ZERO,size),Color(.018,.035,.05))
	draw_rect(Rect2(0,0,size.x,72),Color(.045,.105,.135))
	draw_string(font,Vector2(28,46),"SECURITY OPERATIONS  /  " + profile.to_upper(),HORIZONTAL_ALIGNMENT_LEFT,-1,26,Color(.67,.85,.87))
	var rows = ["LOCAL SIMULATION", snapshot.get("title","Evidence and incident response"), "HTTPS 443  ·  " + ("HEALTHY" if snapshot.get("ports",{}).get("443",true) else "UNAVAILABLE"), "MGMT 8080  ·  " + ("EXPOSED / REVIEW" if snapshot.get("ports",{}).get("8080",true) else "FILTERED / BLOCKED")]
	if profile == "timeline": rows = ["INCIDENT TIMELINE", "01  Evidence inspection", "02  Policy change" if snapshot.get("changed",false) else "02  Awaiting defense", "03  Field recheck confirmed" if snapshot.get("rechecked",false) else "03  Awaiting physical recheck", "04  Verified" if snapshot.get("verified",false) else "04  Verification pending"]
	if profile in ["operations","analysis","forensics","response"]: rows = ["LOCAL SAMPLE  /  " + profile.to_upper(), "Work queue / Documentation", "Evidence review  |  Case notes", "Internal training dataset", "No external traffic"]
	if snapshot.get("mission") == "integrity" and profile in ["case","logs","queue"]:
		rows = ["FILE INTEGRITY", "APPROVED OFFLINE BASELINE"]
		if snapshot.hashes.is_empty(): rows.append("PENDING SCAN" if snapshot.restored else "Awaiting hash comparison")
		for row in snapshot.hashes: rows.append(row.name + "  /  " + ("MATCHED" if row.matches else "MISMATCH"))
	if snapshot.get("mission") == "login" and profile in ["case","logs","queue"]: rows = ["LOGIN POLICY", "Minimum length: " + str(snapshot.login.minLength), "Repeated failures: " + ("LIMITED" if snapshot.login.limitAttempts else "UNLIMITED"), "Common values: " + ("BLOCKED" if snapshot.login.blockCommon else "ALLOWED"), "Normal dummy login: " + ("HEALTHY" if snapshot.login.normal else "UNAVAILABLE")]
	for i in range(rows.size()):
		var color = Color(.77,.83,.86)
		if "EXPOSED" in rows[i] or "MISMATCH" in rows[i] or "UNLIMITED" in rows[i] or "UNAVAILABLE" in rows[i]: color = Color(.83,.63,.38)
		if "HEALTHY" in rows[i] or "MATCHED" in rows[i] or "BLOCKED" in rows[i]: color = Color(.49,.75,.66)
		draw_string(font,Vector2(32,124+i*64),rows[i],HORIZONTAL_ALIGNMENT_LEFT,-1,27,color)
	for i in range(15):
		draw_rect(Rect2(34+i*59,470,38,28+sin(i*1.9)*13),Color(.12,.32,.38))
	draw_string(font,Vector2(32,548),"INTERNAL LAB  ·  Evidence → Defense → Recheck",HORIZONTAL_ALIGNMENT_LEFT,-1,18,Color(.38,.53,.60))
