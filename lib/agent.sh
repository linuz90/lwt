lwt::agent::supported_list() {
  printf 'claude\ncodex\ngemini\n'
}

lwt::agent::is_supported() {
  case "$1" in
    claude|codex|gemini)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

lwt::agent::normalize_spec() {
  local spec="$1"
  local expanded="${spec//,/ }"
  local token=""
  local agent=""
  local -A requested=()
  local -a tokens=()

  expanded="${expanded//-/ }"
  [[ -n "$expanded" ]] || return 1
  tokens=(${=expanded})

  for token in "${tokens[@]}"; do
    if ! lwt::agent::is_supported "$token"; then
      return 1
    fi

    requested[$token]=1
  done

  [[ ${#requested[@]} -gt 0 ]] || return 1

  while IFS= read -r agent; do
    [[ -n "${requested[$agent]:-}" ]] && printf '%s\n' "$agent"
  done < <(lwt::agent::supported_list)

  return 0
}

lwt::agent::installed_list() {
  local agent=""

  while IFS= read -r agent; do
    lwt::deps::has "$agent" && printf '%s\n' "$agent"
  done < <(lwt::agent::supported_list)
}

lwt::agent::command_string() {
  local agent="$1"
  local prompt="$2"
  local yolo="$3"
  local cmd=""

  [[ -z "$agent" ]] && return 1

  if ! lwt::deps::has "$agent"; then
    return 1
  fi

  case "$agent" in
    claude)
      cmd="claude"
      [[ "$yolo" == "true" ]] && cmd="$cmd --dangerously-skip-permissions"
      ;;
    codex)
      cmd="codex"
      [[ "$yolo" == "true" ]] && cmd="$cmd --yolo"
      ;;
    gemini)
      cmd="gemini"
      [[ "$yolo" == "true" ]] && cmd="$cmd --yolo"
      ;;
    *)
      return 1
      ;;
  esac

  if [[ -n "$prompt" ]]; then
    printf '%s %s\n' "$cmd" "$(lwt::shell::quote "$prompt")"
  else
    printf '%s\n' "$cmd"
  fi
}

# Keep conflict-assistance prompts centralized so merge/restack surfaces the
# same conservative instructions regardless of which command hit the conflict.
lwt::agent::restack_prompt() {
  local worktree="$1"
  local branch="$2"
  local target_ref="$3"

  [[ -n "$worktree" && -n "$branch" && -n "$target_ref" ]] || return 1

  printf '%s' \
    "In $worktree on branch $branch, sync this branch onto $target_ref with lwt restack --onto $target_ref. Resolve conflicts conservatively, preserve the branch behavior, run the most relevant validation, and push $branch if it already has a remote and the restack finishes cleanly. Stop and explain if $target_ref does not look like the right base."
}

lwt::agent::continue_rebase_prompt() {
  local worktree="$1"
  local branch="$2"
  local target_ref="$3"

  [[ -n "$worktree" && -n "$branch" && -n "$target_ref" ]] || return 1

  printf '%s' \
    "In $worktree on branch $branch, a rebase onto $target_ref is already in progress and has conflicts. Resolve them conservatively, preserve the branch behavior, run the most relevant validation, and continue the rebase. Abort only if $target_ref is clearly the wrong base or the conflicts show the branch should be rebased differently. Push $branch if it already has a remote and the rebase finishes cleanly."
}

lwt::agent::pick_installed() {
  local agent=""
  local choice=""
  local -a installed=()

  # Keep the chosen agent in shared shell state because the interactive picker
  # must run in the current shell; returning it through $(...) breaks the read.
  LWT_LAST_SELECTED_AGENT=""

  while IFS= read -r agent; do
    [[ -n "$agent" ]] && installed+=("$agent")
  done < <(lwt::agent::installed_list)

  (( ${#installed[@]} > 0 )) || return 1

  if (( ${#installed[@]} == 1 )); then
    LWT_LAST_SELECTED_AGENT="${installed[1]}"
    return 0
  fi

  echo "Available agents:" >&2
  local idx=1
  for agent in "${installed[@]}"; do
    printf '  %s. %s\n' "$idx" "$agent" >&2
    ((idx++))
  done

  while true; do
    printf 'Launch which agent? [1-%s] ' "${#installed[@]}" >&2
    if ! IFS= read -r choice; then
      echo >&2
      return 1
    fi
    echo >&2

    [[ -z "$choice" ]] && return 1
    if [[ "$choice" == <-> ]] && (( choice >= 1 && choice <= ${#installed[@]} )); then
      LWT_LAST_SELECTED_AGENT="${installed[$choice]}"
      return 0
    fi

    lwt::ui::warn "Pick a number between 1 and ${#installed[@]}, or press Enter to cancel."
  done
}

lwt::agent::launch_in_worktree() {
  local worktree="$1"
  local agent="$2"
  local prompt="$3"
  local yolo="${4:-false}"

  [[ -n "$worktree" && -n "$agent" ]] || return 1

  (
    cd "$worktree" || return 1
    lwt::agent::launch "$agent" "$prompt" "$yolo"
  )
}

lwt::agent::offer_conflict_help() {
  local worktree="$1"
  local prompt="$2"
  local installed_agents=""
  local selected_agent=""

  [[ -n "$worktree" && -n "$prompt" ]] || return 0

  installed_agents=$(lwt::agent::installed_list)
  if [[ -z "$installed_agents" ]]; then
    lwt::ui::hint "Agent prompt: $prompt"
    return 0
  fi

  if [[ ! -t 0 ]]; then
    lwt::ui::hint "Agent prompt: $prompt"
    return 0
  fi

  lwt::ui::hint "Worktree: $worktree"
  if ! lwt::ui::confirm "Launch an agent in this worktree to fix it now? [y/N]" false; then
    return 0
  fi

  lwt::agent::pick_installed || return 0
  selected_agent="$LWT_LAST_SELECTED_AGENT"
  [[ -n "$selected_agent" ]] || return 0
  lwt::agent::launch_in_worktree "$worktree" "$selected_agent" "$prompt"
}

lwt::agent::launch() {
  local agent="$1"
  local prompt="$2"
  local yolo="$3"
  [[ -z "$agent" ]] && return 0

  if ! lwt::deps::has "$agent"; then
    lwt::ui::warn "$agent is not installed; skipping AI launch."
    return 0
  fi

  # Resolve yolo mode: flag > config > default (interactive)
  if [[ "$yolo" != "true" ]]; then
    local configured
    configured=$(lwt::config::get_effective "agent-mode" 2>/dev/null)
    [[ "$configured" == "yolo" ]] && yolo=true
  fi

  lwt::ui::step "Launching $agent..."
  case "$agent" in
    claude)
      if [[ "$yolo" == "true" ]]; then
        if [[ -n "$prompt" ]]; then
          claude --dangerously-skip-permissions "$prompt"
        else
          claude --dangerously-skip-permissions
        fi
      else
        if [[ -n "$prompt" ]]; then
          claude "$prompt"
        else
          claude
        fi
      fi
      ;;
    codex)
      if [[ "$yolo" == "true" ]]; then
        if [[ -n "$prompt" ]]; then
          codex --yolo "$prompt"
        else
          codex --yolo
        fi
      else
        if [[ -n "$prompt" ]]; then
          codex "$prompt"
        else
          codex
        fi
      fi
      ;;
    gemini)
      if [[ "$yolo" == "true" ]]; then
        if [[ -n "$prompt" ]]; then
          gemini --yolo "$prompt"
        else
          gemini --yolo
        fi
      else
        if [[ -n "$prompt" ]]; then
          gemini "$prompt"
        else
          gemini
        fi
      fi
      ;;
  esac
}
