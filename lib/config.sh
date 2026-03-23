lwt::config::supported_keys() {
  cat <<'EOF'
editor
agent-mode
dev-cmd
terminal
merge-target
copy-on-create
hook.post-create
hook.post-switch
hook.pre-remove
hook.post-remove
hook.pre-rename
hook.post-rename
hook.pre-merge
hook.post-merge
EOF
}

lwt::config::public_keys() {
  cat <<'EOF'
editor
agent-mode
dev-cmd
terminal
merge-target
copy-on-create
EOF
}

lwt::config::each_key() {
  lwt::config::supported_keys
}

lwt::config::normalize_key() {
  local key="${1:-}"

  case "$key" in
    editor|agent-mode|dev-cmd|terminal|merge-target|copy-on-create)
      printf '%s\n' "$key"
      ;;
    hook.post-create|hook.post-switch|hook.pre-remove|hook.post-remove|hook.pre-rename|hook.post-rename|hook.pre-merge|hook.post-merge)
      printf '%s\n' "$key"
      ;;
    *)
      return 1
      ;;
  esac
}

lwt::config::is_multi_value() {
  local key

  key=$(lwt::config::normalize_key "$1") || return 1

  case "$key" in
    copy-on-create)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

lwt::config::default_scope() {
  local key

  key=$(lwt::config::normalize_key "$1") || return 1

  case "$key" in
    editor|agent-mode|terminal)
      printf 'global\n'
      ;;
    *)
      printf 'local\n'
      ;;
  esac
}

lwt::config::git_key() {
  local key

  key=$(lwt::config::normalize_key "$1") || return 1

  case "$key" in
    editor)
      printf 'lwt.editor\n'
      ;;
    agent-mode)
      printf 'lwt.agent-mode\n'
      ;;
    dev-cmd)
      printf 'lwt.dev-cmd\n'
      ;;
    terminal)
      printf 'lwt.terminal\n'
      ;;
    merge-target)
      printf 'lwt.merge-target\n'
      ;;
    copy-on-create)
      printf 'lwt.copy-on-create\n'
      ;;
    hook.*)
      printf 'lwt.%s\n' "$key"
      ;;
    *)
      return 1
      ;;
  esac
}

lwt::config::default_value() {
  local key

  key=$(lwt::config::normalize_key "$1") || return 1

  case "$key" in
    editor)
      printf '%s\n' "${LWT_EDITOR:-${VISUAL:-${EDITOR:-}}}"
      ;;
    agent-mode)
      printf 'interactive\n'
      ;;
    dev-cmd)
      printf 'auto\n'
      ;;
    terminal)
      printf 'auto\n'
      ;;
    merge-target)
      printf '%s\n' "${LWT_DEFAULT_BRANCH:-default-branch}"
      ;;
    copy-on-create)
      printf '%s\n' "(unset)"
      ;;
    hook.*)
      printf '%s\n' "(unset)"
      ;;
    *)
      return 1
      ;;
  esac
}

lwt::config::get_raw() {
  local scope="${2:-}"
  local git_key

  git_key=$(lwt::config::git_key "$1") || return 1

  case "$scope" in
    global)
      if lwt::config::is_multi_value "$1"; then
        git config --global --get-all "$git_key" 2>/dev/null
      else
        git config --global --get "$git_key" 2>/dev/null
      fi
      ;;
    local)
      if lwt::config::is_multi_value "$1"; then
        git config --local --get-all "$git_key" 2>/dev/null
      else
        git config --local --get "$git_key" 2>/dev/null
      fi
      ;;
    *)
      if lwt::config::is_multi_value "$1"; then
        git config --get-all "$git_key" 2>/dev/null
      else
        git config --get "$git_key" 2>/dev/null
      fi
      ;;
  esac
}

lwt::config::get_effective() {
  local key raw

  key=$(lwt::config::normalize_key "$1") || return 1
  raw=$(lwt::config::get_raw "$key")
  if [[ -n "$raw" ]]; then
    printf '%s\n' "$raw"
  else
    lwt::config::default_value "$key"
  fi
}

lwt::config::source_for() {
  local key

  key=$(lwt::config::normalize_key "$1") || return 1

  if [[ -n "$(lwt::config::get_raw "$key" "local")" ]]; then
    printf 'local\n'
    return 0
  fi

  if [[ -n "$(lwt::config::get_raw "$key" "global")" ]]; then
    printf 'global\n'
    return 0
  fi

  printf 'default\n'
}

lwt::config::description() {
  local key

  key=$(lwt::config::normalize_key "$1") || return 1

  case "$key" in
    editor)
      printf 'Editor command used by --editor and editor-aware flows\n'
      ;;
    agent-mode)
      printf 'Default agent approval mode for Claude, Codex, and Gemini\n'
      ;;
    dev-cmd)
      printf 'Project dev command used by lwt add --dev\n'
      ;;
    terminal)
      printf 'Preferred terminal driver for splits and tabs\n'
      ;;
    merge-target)
      printf 'Default target branch for merge flows\n'
      ;;
    copy-on-create)
      printf 'Repeatable repo-relative path copied into new worktrees; directories copy recursively\n'
      ;;
    hook.*)
      printf 'Shell command run for %s\n' "${key#hook.}"
      ;;
    *)
      return 1
      ;;
  esac
}

lwt::config::require_local_scope() {
  git rev-parse --is-inside-work-tree >/dev/null 2>&1 && return 0

  lwt::ui::error "Local config requires a Git repository."
  lwt::ui::hint "Run inside a repo or use --global."
  return 1
}

lwt::config::set() {
  local scope="$1"
  local key="$2"
  local value="$3"
  local git_key

  [[ -n "$scope" && -n "$key" ]] || return 1
  git_key=$(lwt::config::git_key "$key") || return 1

  if [[ "$scope" == "local" ]]; then
    lwt::config::require_local_scope || return 1
  fi

  case "$scope" in
    global)
      if lwt::config::is_multi_value "$key"; then
        git config --global --replace-all "$git_key" "$value"
      else
        git config --global "$git_key" "$value"
      fi
      ;;
    local)
      if lwt::config::is_multi_value "$key"; then
        git config --replace-all "$git_key" "$value"
      else
        git config "$git_key" "$value"
      fi
      ;;
    *)
      return 1
      ;;
  esac
}

lwt::config::add() {
  local scope="$1"
  local key="$2"
  local value="$3"
  local git_key

  [[ -n "$scope" && -n "$key" ]] || return 1
  git_key=$(lwt::config::git_key "$key") || return 1
  lwt::config::is_multi_value "$key" || return 1

  if [[ "$scope" == "local" ]]; then
    lwt::config::require_local_scope || return 1
  fi

  case "$scope" in
    global)
      git config --global --add "$git_key" "$value"
      ;;
    local)
      git config --add "$git_key" "$value"
      ;;
    *)
      return 1
      ;;
  esac
}

lwt::config::unset() {
  local scope="$1"
  local key="$2"
  local git_key

  [[ -n "$scope" && -n "$key" ]] || return 1
  git_key=$(lwt::config::git_key "$key") || return 1

  if [[ "$scope" == "local" ]]; then
    lwt::config::require_local_scope || return 1
  fi

  case "$scope" in
    global)
      git config --global --unset-all "$git_key" 2>/dev/null
      ;;
    local)
      git config --unset-all "$git_key" 2>/dev/null
      ;;
    *)
      return 1
      ;;
  esac
}
