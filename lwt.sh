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
#   lwt add [name] [-e] [--editor-cmd "cmd"]
#           [--agents claude,codex[,gemini] [prompt]]
#           [--claude|--codex|--gemini [prompt]]
#           [--claude-codex|--codex-claude|--codex-gemini|... [prompt]]
#           [--split "cmd"] [--tab "cmd"] [--split-dev] [--tab-dev]
#           [--split-claude|--split-codex|--split-gemini [prompt]]
#           [--tab-claude|--tab-codex|--tab-gemini [prompt]]
#   lwt checkout [query] [-e] [--editor-cmd "cmd"]
#   lwt switch [query] [-e] [--editor-cmd "cmd"]
#   lwt list
#   lwt remove [query]
#   lwt clean [-n]
#   lwt rename <new-name>
#   lwt doctor
#   lwt help [command]

if [[ -n "${ZSH_VERSION:-}" ]]; then
  typeset -g LWT_ROOT="${${(%):-%N}:A:h}"
else
  LWT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
fi

for _lwt_module in core git status worktree editor project terminal agent help commands; do
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
