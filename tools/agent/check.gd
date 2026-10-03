extends SceneTree
## Loads every script, scene, resource, and shader so parse errors and broken references
## surface in one headless pass. Run it through `tools/dev check`, which turns the
## engine's error output into file:line messages.

const EXTENSIONS: Array[String] = ["gd", "tscn", "tres", "gdshader"]

func _initialize() -> void:
	var failed: Array[String] = []
	var paths := _collect("res://")
	for path: String in paths:
		var resource := ResourceLoader.load(path)
		if resource == null or (resource is GDScript and not resource.can_instantiate()):
			failed.append(path)
	for path: String in failed:
		print("CHECK_FAILED ", path)
	print("CHECK_DONE %d files, %d failed" % [paths.size(), failed.size()])
	quit(0 if failed.is_empty() else 1)

func _collect(directory: String) -> Array[String]:
	var found: Array[String] = []
	var access := DirAccess.open(directory)
	if access == null or access.file_exists(".gdignore"):
		return found
	for child: String in access.get_directories():
		if not child.begins_with("."):
			found.append_array(_collect(directory.path_join(child)))
	for file: String in access.get_files():
		if file.get_extension() in EXTENSIONS:
			found.append(directory.path_join(file))
	return found
