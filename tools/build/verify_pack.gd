extends SceneTree
## Run against --main-pack from an isolated output directory, never source fallback.

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 1:
		push_error("Expected the absolute build-info.json path")
		quit(2)
		return
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(args[0]))
	var failures: Array[String] = []
	for path: String in manifest.runtime_json:
		if FileAccess.get_sha256(path) != manifest.runtime_json[path]:
			failures.append("Missing or mismatched JSON: " + path)
	for path: String in manifest.runtime_resources:
		if not ResourceLoader.exists(path):
			failures.append("Missing packed resource: " + path)
	for path: String in ["res://tools/dev", "res://tests/prototype_smoke.gd", "res://previous/recovery/reports/assets.json"]:
		if FileAccess.file_exists(path):
			failures.append("Development file leaked into export: " + path)
	for failure: String in failures:
		push_error(failure)
	print("PACK_AUDIT: %d JSON files, %d resources, %d failures" % [manifest.runtime_json.size(), manifest.runtime_resources.size(), failures.size()])
	quit(0 if failures.is_empty() else 1)
