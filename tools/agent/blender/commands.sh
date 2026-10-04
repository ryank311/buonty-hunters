# Blender commands for tools/dev (sourced by it): the agents' Blender instances and the
# .blend -> .glb asset pipeline. Uses $root, $out, and new_run from tools/dev.

blender_dir="$root/tools/agent/blender"
blender_state="$out/blender"
export PATH="$PATH:$HOME/.local/bin:/usr/local/bin:/opt/homebrew/bin"

blender_usage() {
	cat <<'EOF'
Usage: tools/dev blender <command>

  status                List the agents' Blender instances: port, open file, unsaved changes.
  start                 Start your Blender instance. The MCP server does this on its own
                        at the first tool call; use it to open Blender ahead of time.
  stop [--discard]      Quit your Blender instance. Refuses when it holds unsaved changes
                        unless --discard is given.
  export [name...]      Export art/blender/<name>.blend to art/models/<name>.glb with the
                        project's settings and report size, triangles, and problems.
                        No names exports every source file.
  preview <name>...     Render a four-view sheet of art/blender/<name>.blend beside a
                        1.8 m figure, without opening a window.
  smoke                 Drive the Blender MCP server end to end on a test instance.

Each agent has its own instance: Claude Code on port 9886, Codex on 9887. Add
--port=<n> to address a specific one.
EOF
}

find_blender() {
	local candidate
	if [[ -n "${BLENDER_BIN:-}" ]]; then
		[[ -x "$BLENDER_BIN" ]] && { echo "$BLENDER_BIN"; return 0; }
		echo "BLENDER_BIN is set but not executable: $BLENDER_BIN" >&2
		return 1
	fi
	candidate="$(command -v blender 2>/dev/null || true)"
	[[ -n "$candidate" ]] && { echo "$candidate"; return 0; }
	for candidate in "/Applications/Blender.app/Contents/MacOS/Blender" "$HOME/Applications/Blender.app/Contents/MacOS/Blender"; do
		[[ -x "$candidate" ]] && { echo "$candidate"; return 0; }
	done
	echo "Blender not found. Install it, or set BLENDER_BIN to the executable." >&2
	return 1
}

# One instance per kind of agent, so two agents never share a scene.
blender_port() {
	if [[ -n "${SOCOM_BLENDER_PORT:-}" ]]; then
		echo "$SOCOM_BLENDER_PORT"
	elif [[ -n "${CODEX_THREAD_ID:-}${CODEX_SESSION_ID:-}" ]]; then
		echo 9887
	else
		echo 9886
	fi
}

blender_listening() {
	(exec 3<>"/dev/tcp/127.0.0.1/$1") 2>/dev/null
}

blender_field() {
	sed -n "s/.*\"$2\": \"\{0,1\}\([^,\"}]*\)\"\{0,1\}[,}].*/\1/p" "$blender_state/$1.json" 2>/dev/null
}

# The add-on is copied from the pinned MCP package into .agent/, never into the user's
# own Blender configuration, so it always matches the server version.
blender_addon() {
	local version marker="$blender_state/addon/version"
	version="$(cat "$blender_dir/mcp-version")"
	if [[ -f "$blender_state/addon/blender_mcp.py" && "$(cat "$marker" 2>/dev/null)" == "$version" ]]; then
		return 0
	fi
	mkdir -p "$blender_state/addon"
	if ! BLENDERMCP_ADDONS_DIR="$blender_state/addon" DISABLE_TELEMETRY=true \
		uvx --python 3.11 "mcp-for-blender@$version" install-addon >"$blender_state/addon/install.log" 2>&1; then
		echo "Could not fetch the Blender add-on (is uv installed?). Log: ${blender_state#"$root"/}/addon/install.log"
		return 1
	fi
	echo "$version" >"$marker"
}

blender_start() {
	local port="$1" blender
	if blender_listening "$port"; then
		echo "Blender is already running on port $port (pid $(blender_field "$port" pid))."
		return 0
	fi
	blender="$(find_blender)" || return 1
	blender_addon || return 1
	rm -f "$blender_state/$port.json"
	# Factory settings keep the user's own Blender preferences out of it, and
	# --no-window-focus opens the window behind whatever they are working in.
	# Job control gives Blender its own process group, so it outlives the agent session
	# that started it and the user can still look at the result.
	(
		set -m
		cd "$root" || exit 1
		nohup "$blender" --factory-startup --no-window-focus --window-geometry 60 60 1280 800 \
			--python "$blender_dir/startup.py" -- --port "$port" \
			--addon "$blender_state/addon/blender_mcp.py" --state "$blender_state/$port.json" \
			>"$blender_state/$port.log" 2>&1 </dev/null &
	)
	for _ in $(seq 1 120); do
		if blender_listening "$port"; then
			echo "Blender started on port $port. Its window opens behind your other windows."
			return 0
		fi
		sleep 0.5
	done
	echo "Blender did not start listening on port $port within 60 s. Log: ${blender_state#"$root"/}/$port.log"
	return 1
}

blender_stop() {
	local port="$1" discard="$2" pid
	pid="$(blender_field "$port" pid)"
	if [[ -z "$pid" ]] || ! kill -0 "$pid" 2>/dev/null; then
		echo "No Blender instance on port $port."
		rm -f "$blender_state/$port.json"
		return 0
	fi
	if [[ "$(blender_field "$port" unsaved_changes)" == "true" && "$discard" != "1" ]]; then
		echo "Blender on port $port has unsaved changes (file: $(blender_field "$port" file)). Save first, or run: tools/dev blender stop --discard"
		return 1
	fi
	kill "$pid" 2>/dev/null
	for _ in $(seq 1 20); do
		kill -0 "$pid" 2>/dev/null || break
		sleep 0.25
	done
	rm -f "$blender_state/$port.json"
	echo "Blender on port $port stopped."
}

blender_status() {
	local file port pid any=0
	for file in "$blender_state"/*.json; do
		[[ -f "$file" ]] || continue
		port="$(basename "$file" .json)"
		pid="$(blender_field "$port" pid)"
		if ! kill -0 "$pid" 2>/dev/null; then
			rm -f "$file"
			continue
		fi
		any=1
		local owner="other"
		[[ "$port" == "9886" ]] && owner="Claude Code"
		[[ "$port" == "9887" ]] && owner="Codex"
		local open
		open="$(blender_field "$port" file)"
		echo "port $port ($owner)  pid $pid  file ${open:-<unsaved new file>}  unsaved changes: $(blender_field "$port" unsaved_changes)  objects: $(blender_field "$port" objects)"
	done
	(( any )) || echo "No agent Blender instance is running. The MCP server starts one at the first tool call."
}

# Runs a pipeline script in a windowless Blender and prints its report lines.
blender_batch() {
	local script="$1" source="$2" log="$3" blender
	shift 3
	blender="$(find_blender)" || return 1
	"$blender" --background --factory-startup "$source" --python "$blender_dir/$script" -- "$@" >"$log" 2>&1
	local status=$?
	if [[ $status -ge 128 ]]; then
		# Blender occasionally crashes on start-up inside an agent's sandbox; once more.
		"$blender" --background --factory-startup "$source" --python "$blender_dir/$script" -- "$@" >"$log" 2>&1
		status=$?
	fi
	grep -E '^(EXPORT|PREVIEW|NOTE|PROBLEM) ' "$log"
	if [[ $status -ne 0 ]] && ! grep -q '^PROBLEM ' "$log"; then
		grep -E 'Error|Traceback' "$log" | head -5
	fi
	return $status
}

blender_names() {
	local name
	if [[ $# -gt 0 ]]; then
		for name in "$@"; do
			name="${name##*/}"
			echo "${name%.blend}"
		done
	else
		(cd "$root/art/blender" 2>/dev/null && ls *.blend 2>/dev/null | sed 's/\.blend$//')
	fi
}

blender_export() {
	local run name failures=0 count=0
	run="$(new_run logs)"
	mkdir -p "$root/art/models"
	for name in $(blender_names "$@"); do
		count=$((count + 1))
		if [[ ! -f "$root/art/blender/$name.blend" ]]; then
			echo "PROBLEM no source file art/blender/$name.blend"
			failures=$((failures + 1))
			continue
		fi
		blender_batch export.py "$root/art/blender/$name.blend" "$run/export-$name.log" --out "$root/art/models/$name.glb" \
			|| failures=$((failures + 1))
	done
	if [[ $count -eq 0 ]]; then
		echo "EXPORT: nothing to export (no .blend files in art/blender/)"
		return 1
	fi
	if [[ $failures -gt 0 ]]; then
		echo "EXPORT: FAIL ($failures of $count). Logs: ${run#"$root"/}"
		return 1
	fi
	rm -rf "$run"
	echo "EXPORT: ok ($count). Run tools/dev import so Godot picks the models up."
}

blender_preview() {
	local run shots name failures=0
	if [[ $# -eq 0 ]]; then
		echo "Usage: tools/dev blender preview <name>..."
		return 2
	fi
	run="$(new_run logs)"
	shots="$(new_run shots)"
	for name in $(blender_names "$@"); do
		if [[ ! -f "$root/art/blender/$name.blend" ]]; then
			echo "PROBLEM no source file art/blender/$name.blend"
			failures=$((failures + 1))
			continue
		fi
		blender_batch preview.py "$root/art/blender/$name.blend" "$run/preview-$name.log" --out "$shots/$name-preview.png" \
			|| failures=$((failures + 1))
	done
	if [[ $failures -gt 0 ]]; then
		echo "PREVIEW: FAIL. Logs: ${run#"$root"/}"
		return 1
	fi
	rm -rf "$run"
}

cmd_blender() {
	local action="${1:-help}" port discard=0 arg rest=()
	[[ $# -gt 0 ]] && shift
	port="$(blender_port)"
	for arg in "$@"; do
		case "$arg" in
			--port=*) port="${arg#--port=}" ;;
			--discard) discard=1 ;;
			*) rest+=("$arg") ;;
		esac
	done
	mkdir -p "$blender_state"
	[[ -f "$out/.gdignore" ]] || : > "$out/.gdignore"
	case "$action" in
		start) blender_start "$port" ;;
		stop) blender_stop "$port" "$discard" ;;
		status) blender_status ;;
		export) blender_export ${rest[@]+"${rest[@]}"} ;;
		preview) blender_preview ${rest[@]+"${rest[@]}"} ;;
		smoke) node "$blender_dir/smoke.mjs" ${rest[@]+"${rest[@]}"} ;;
		help|-h|--help) blender_usage ;;
		*) echo "Unknown blender command: $action"; blender_usage; return 2 ;;
	esac
}
