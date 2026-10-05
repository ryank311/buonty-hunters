#!/bin/sh
# This directory is one immutable build, reached through the current-build symlink.
set -eu
cd -- "$(dirname -- "$0")"
state="${XDG_STATE_HOME:-$HOME/.local/state}/socom"
mkdir -p "$state"
if [ -f "$state/play.log" ]; then
	mv -f "$state/play.log" "$state/play.previous.log"
fi
exec ./socom.x86_64 --log-file "$state/play.log" "$@"
