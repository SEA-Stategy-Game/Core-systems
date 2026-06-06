#!/bin/sh
printf '\033c\033]0;%s\a' Core
base_path="$(dirname "$(realpath "$0")")"
"$base_path/gameroom.x86_64" "$@"
