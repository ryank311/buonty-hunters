extends Node
## Autoload that starts the live link: an MCP server inside the running game, through
## which an agent can inspect and change it while it is played (live_server.gd).
##
## Every Godot process on this project loads this script, so it stays tiny and decides
## here whether to do anything at all:
##   - never in an exported build or in the editor itself;
##   - never in a test run: anything headless, or started with `--script` (the regression
##     suites, `tools/dev check`, `tools/dev shot`), whatever the environment says. A
##     test instance must never be mistaken for the game;
##   - on in the real game: a window, run as a player runs it;
##   - off in a QA window, unless SOCOM_LIVE=1 asks for it: that is an agent's own hidden
##     sandbox (`tools/dev live sandbox`), which only its owner reaches, by port;
##   - SOCOM_LIVE=0 turns it off everywhere.
## The server is loaded only when it will run, so an error in it cannot stop the game or
## the test suites.

var server: Node

func _ready() -> void:
	if not wanted():
		return
	var script := load("res://scripts/live/live_server.gd") as GDScript
	if script == null or not script.can_instantiate():
		push_warning("Live link: scripts/live/live_server.gd did not load; the game runs without it.")
		return
	server = script.new()
	server.name = "Server"
	add_child(server)

static func wanted() -> bool:
	if not OS.has_feature("editor") or Engine.is_editor_hint():
		return false
	var engine := OS.get_cmdline_args()
	if DisplayServer.get_name() == "headless" or "--script" in engine or "-s" in engine:
		return false
	var asked := OS.get_environment("SOCOM_LIVE")
	if asked == "0":
		return false
	var user := OS.get_cmdline_user_args()
	if "--qa" in user or "--capture" in user:
		return asked == "1"
	return true
