#!/bin/sh
printf '\033c\033]0;%s\a' MotorCursor
base_path="$(dirname "$(realpath "$0")")"
"$base_path/MotorCursor.x86_64" "$@"
