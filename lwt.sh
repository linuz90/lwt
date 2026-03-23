# shellcheck shell=bash
# Light Worktrees (lwt) — opinionated git worktree management
#
# https://github.com/linuz90/lwt
#
# Usage: source this file from your shell profile
#   source /path/to/lwt.sh
#
# lwt.sh is the public entrypoint and sources helpers from lib/.
#
# Commands:
#   lwt add [name] [-s] [-d] [-e] [-yolo] [--editor-cmd "cmd"]
#           [--claude ["prompt"]] [--codex ["prompt"]] [--gemini ["prompt"]]
#           [--agents list ["prompt"]] [--claude-codex|--codex-gemini|... ["prompt"]]
#           [--split "cmd"] [--tab "cmd"]
#   lwt checkout [query] [-e] [--editor-cmd "cmd"]
#   lwt switch [query] [-e] [--editor-cmd "cmd"]
#   lwt list
#   lwt merge [target-branch] [--keep-worktree] [--keep-branch] [--no-push]
#   lwt remove [query] [-y|--yes] [-f|--force] [--delete-remote]
#   lwt clean [-n]
#   lwt rename <new-name>
#   lwt config [show|get|set|add|unset] [--global|--local]
#   lwt hook [list|path|run] [event]
#   lwt doctor
#   lwt help [command|automation]

if [[ -n "${ZSH_VERSION:-}" ]]; then
  typeset -g LWT_ROOT="${${(%):-%N}:A:h}"
else
  LWT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
fi

for _lwt_module in core git config status worktree editor project terminal agent hooks help commands; do
  _lwt_lib="$LWT_ROOT/lib/${_lwt_module}.sh"
  if [[ ! -f "$_lwt_lib" ]]; then
    echo "lwt: missing required file: $_lwt_lib" >&2
    return 1 2>/dev/null || exit 1
  fi

  # shellcheck disable=SC1090
  source "$_lwt_lib"
done

unset _lwt_lib _lwt_module

lwt() {
  lwt::dispatch "$@"
}
