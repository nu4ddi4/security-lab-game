extends SceneTree

func _initialize():
	var file = FileAccess.open("res://LICENSES.txt",FileAccess.WRITE)
	file.store_string("Security Lab Native\n\nOriginal game code and generated assets: Security Lab contributors.\nAsset attribution: assets/credits.txt\nKorean font: assets/fonts/OFL.txt (Noto project, SIL OFL 1.1)\nProcedural audio: project-generated.\n\nGodot Engine\n" + Engine.get_license_text() + "\n\nThird-party components included with the engine:\n" + JSON.stringify(Engine.get_license_info(),"\t"))
	file.close()
	quit()
