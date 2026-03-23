lwt::cmd::list() {
  lwt::status::warn_gh_limitations
  lwt::worktree::display_rows | cut -f2-
}

lwt::cmd::config() {
  local action="show"
  local scope=""
  local key=""
  local value=""
  local show_all=false
  local -a positional=()

  while (( $# > 0 )); do
    case "$1" in
      -h|--help)
        lwt::ui::help_config
        return 0
        ;;
      --global)
        scope="global"
        ;;
      --local)
        scope="local"
        ;;
      --all)
        show_all=true
        ;;
      show|get|set|add|unset)
        action="$1"
        ;;
      *)
        if [[ "$1" != -* ]]; then
          positional+=("$1")
        else
          lwt::ui::error "Unknown option: $1"
          return 1
        fi
        ;;
    esac
    shift
  done

  if [[ "$action" == "show" && ${#positional[@]} -gt 0 ]]; then
    action="get"
  fi

  case "$action" in
    show)
      local item effective source description value_line
      local -a value_lines
      lwt::ui::header "lwt config"
      while IFS= read -r item; do
        effective=$(lwt::config::get_effective "$item" 2>/dev/null)
        source=$(lwt::config::source_for "$item" 2>/dev/null)
        description=$(lwt::config::description "$item" 2>/dev/null)

        [[ -z "$source" ]] && source="default"
        [[ -z "$effective" ]] && effective="(unset)"

        value_lines=()
        if lwt::config::is_multi_value "$item"; then
          while IFS= read -r value_line; do
            [[ -n "$value_line" ]] && value_lines+=("$value_line")
          done <<< "$effective"
        fi

        if (( ${#value_lines[@]} == 0 )); then
          printf '  %-18s %s%s%s  %s(%s)%s\n' \
            "$item" \
            "$_lwt_bold" "$effective" "$_lwt_reset" \
            "$_lwt_dim" "$source" "$_lwt_reset"
        else
          printf '  %-18s %s%s%s  %s(%s)%s\n' \
            "$item" \
            "$_lwt_bold" "${value_lines[1]}" "$_lwt_reset" \
            "$_lwt_dim" "$source" "$_lwt_reset"
          local extra_idx
          for (( extra_idx = 2; extra_idx <= ${#value_lines[@]}; extra_idx++ )); do
            printf '  %-18s %s%s%s\n' \
              "" \
              "$_lwt_bold" "${value_lines[$extra_idx]}" "$_lwt_reset"
          done
        fi
        [[ -n "$description" ]] && printf '  %s%s%s\n' "$_lwt_dim" "$description" "$_lwt_reset"
      done < <(
        if $show_all; then
          lwt::config::each_key
        else
          lwt::config::public_keys
        fi
      )
      if ! $show_all; then
        printf '  %sAdvanced hook settings are intentionally hidden here. Use `lwt hook` for scripted lifecycle automation.%s\n' "$_lwt_dim" "$_lwt_reset"
      fi
      ;;
    get)
      key="${positional[1]:-}"
      if [[ -z "$key" ]]; then
        lwt::ui::error "Config key is required."
        lwt::ui::hint "Usage: lwt config get <key>"
        return 1
      fi
      if [[ -n "$scope" ]]; then
        lwt::config::get_raw "$key" "$scope"
      else
        lwt::config::get_effective "$key"
      fi
      ;;
    set)
      key="${positional[1]:-}"
      value="${positional[2]:-}"
      if [[ -z "$key" || -z "$value" ]]; then
        lwt::ui::error "Config key and value are required."
        lwt::ui::hint "Usage: lwt config set <key> <value> [--global|--local]"
        return 1
      fi
      if [[ -z "$scope" ]]; then
        scope=$(lwt::config::default_scope "$key") || return 1
      fi
      lwt::config::set "$scope" "$key" "$value" || return 1
      lwt::ui::success "Set $key=$value ($scope)."
      ;;
    add)
      key="${positional[1]:-}"
      value="${positional[2]:-}"
      if [[ -z "$key" || -z "$value" ]]; then
        lwt::ui::error "Config key and value are required."
        lwt::ui::hint "Usage: lwt config add <key> <value> [--global|--local]"
        return 1
      fi
      if ! lwt::config::is_multi_value "$key"; then
        lwt::ui::error "Config key does not support repeated values: $key"
        lwt::ui::hint "Use lwt config set for single-value settings."
        return 1
      fi
      if [[ -z "$scope" ]]; then
        scope=$(lwt::config::default_scope "$key") || return 1
      fi
      if [[ -n "$(lwt::config::get_raw "$key" "$scope" 2>/dev/null | grep -Fx -- "$value")" ]]; then
        lwt::ui::success "$key already includes $value ($scope)."
        return 0
      fi
      lwt::config::add "$scope" "$key" "$value" || return 1
      lwt::ui::success "Added $key=$value ($scope)."
      ;;
    unset)
      key="${positional[1]:-}"
      if [[ -z "$key" ]]; then
        lwt::ui::error "Config key is required."
        lwt::ui::hint "Usage: lwt config unset <key> [--global|--local]"
        return 1
      fi
      if [[ -z "$scope" ]]; then
        scope=$(lwt::config::default_scope "$key") || return 1
      fi
      lwt::config::unset "$scope" "$key" || return 1
      lwt::ui::success "Unset $key ($scope)."
      ;;
  esac
}

lwt::cmd::switch() {
  local query=""
  local open_editor=false
  local editor_override=""

  while (( $# > 0 )); do
    case "$1" in
      -h|--help)
        lwt::ui::help_switch
        return 0
        ;;
      -e|--editor)
        open_editor=true
        ;;
      --editor-cmd)
        if [[ -z "$2" ]]; then
          lwt::ui::error "--editor-cmd expects a value."
          return 1
        fi
        editor_override="$2"
        shift
        ;;
      --editor-cmd=*)
        editor_override="${1#--editor-cmd=}"
        ;;
      --)
        shift
        query="$*"
        break
        ;;
      *)
        query="$query${query:+ }$1"
        ;;
    esac
    shift
  done

  if ! lwt::deps::has fzf; then
    lwt::ui::error "fzf is required for lwt switch. Install with: brew install fzf"
    return 1
  fi

  lwt::status::warn_gh_limitations

  local dir
  dir=$(lwt::worktree::display_rows | fzf --ansi --height 40% --reverse --select-1 \
    --query="$query" --delimiter='\t' --with-nth=2.. | awk -F'\t' '{print $1}')

  [[ -z "$dir" ]] && return 0

  cd "$dir" || return 1
  local repo_root branch
  repo_root=$(git rev-parse --show-toplevel 2>/dev/null)
  branch=$(git branch --show-current 2>/dev/null)
  lwt::hooks::run "post-switch" "$dir" "$repo_root" "$branch" \
    "LWT_MAIN_WORKTREE_PATH" "$(lwt::worktree::main_path)" || return 1

  if $open_editor; then
    lwt::editor::open "$dir" "$editor_override"
  fi
}

lwt::checkout::print_candidates() {
  local record wt_path branch title number
  local -A worktree_paths=()

  while IFS= read -r record; do
    wt_path="${record%%$'\t'*}"
    branch="${record#*$'\t'}"
    [[ -z "$branch" || "$branch" == "(detached)" ]] && continue
    worktree_paths["$branch"]="$wt_path"
  done < <(lwt::worktree::records)

  lwt::status::init_gh_mode
  [[ "$LWT_GH_MODE" != "ok" ]] && return 1

  while IFS=$'\t' read -r branch number title; do
    [[ -z "$branch" ]] && continue
    [[ -n "${worktree_paths[$branch]}" ]] && continue

    printf 'pr\t%s\t%sPR #%-5s%s  %s%s%s  %s\n' \
      "$branch" \
      "$_lwt_orange" "$number" "$_lwt_reset" \
      "$_lwt_bold" "$branch" "$_lwt_reset" \
      "$title"
  done < <(gh pr list --state open --limit 100 --json headRefName,number,title -q '.[] | "\(.headRefName)\t\(.number)\t\(.title)"' 2>/dev/null)
}

lwt::cmd::checkout() {
  local query=""
  local open_editor=false
  local editor_override=""
  local selection kind ref dir
  local created=false
  local -a candidates

  while (( $# > 0 )); do
    case "$1" in
      -h|--help)
        lwt::ui::help_checkout
        return 0
        ;;
      -e|--editor)
        open_editor=true
        ;;
      --editor-cmd)
        if [[ -z "$2" ]]; then
          lwt::ui::error "--editor-cmd expects a value."
          return 1
        fi
        editor_override="$2"
        shift
        ;;
      --editor-cmd=*)
        editor_override="${1#--editor-cmd=}"
        ;;
      --)
        shift
        query="$*"
        break
        ;;
      *)
        query="$query${query:+ }$1"
        ;;
    esac
    shift
  done

  if ! lwt::deps::has fzf; then
    lwt::ui::error "fzf is required for lwt checkout. Install with: brew install fzf"
    return 1
  fi

  lwt::status::init_gh_mode
  case "$LWT_GH_MODE" in
    missing)
      lwt::ui::error "gh is required for lwt checkout."
      lwt::ui::hint "Install gh: brew install gh"
      return 1
      ;;
    unauthenticated)
      lwt::ui::error "gh auth is required for lwt checkout."
      lwt::ui::hint "Run: gh auth login"
      return 1
      ;;
  esac

  while IFS= read -r selection; do
    candidates+=("$selection")
  done < <(lwt::checkout::print_candidates)

  if [[ ${#candidates[@]} -eq 0 ]]; then
    lwt::ui::hint "No open PRs without worktrees."
    lwt::ui::hint "Use lwt s to switch worktrees, or lwt a <branch> to create one explicitly."
    return 0
  fi

  selection=$(printf '%s\n' "${candidates[@]}" | fzf --ansi --height 50% --reverse \
    --prompt="Checkout PR: " --query="$query" --delimiter='\t' --with-nth=3..)

  [[ -z "$selection" ]] && return 0

  kind=$(printf '%s\n' "$selection" | awk -F'\t' '{print $1}')
  ref=$(printf '%s\n' "$selection" | awk -F'\t' '{print $2}')

  case "$kind" in
    pr)
      dir=$(lwt::worktree::path_for_branch "$ref" 2>/dev/null)
      if [[ -z "$dir" ]]; then
        lwt::worktree::create_branch "$ref" false false || return 1
        dir="$LWT_LAST_WORKTREE_PATH"
        [[ -z "$dir" ]] && return 1
        created=true
        lwt::ui::success "Created worktree ${ref}."
      fi
      ;;
    *)
      lwt::ui::error "Unknown selection type: $kind"
      return 1
      ;;
  esac

  cd "$dir" || return 1
  if $created; then
    lwt::hooks::run "post-create" "$dir" "$dir" "$ref" \
      "LWT_MAIN_WORKTREE_PATH" "$(lwt::worktree::main_path)" || return 1
  fi
  lwt::hooks::run "post-switch" "$dir" "$dir" "$ref" \
    "LWT_MAIN_WORKTREE_PATH" "$(lwt::worktree::main_path)" || return 1
  if $open_editor; then
    lwt::editor::open "$dir" "$editor_override"
  fi
}

lwt::cmd::add() {
  local branch=""
  local open_editor=false
  local run_setup=false
  local run_dev=false
  local yolo=false
  local editor_override=""
  local main_agent=""
  local main_agent_prompt=""
  local terminal_driver=""
  local fallback_command=""
  local session_command=""
  local -a agent_names=()
  local -a agent_prompts=()
  local -a runnable_agents=()
  local -a runnable_prompts=()
  local -a missing_agents=()
  local -a parallel_agents=()
  local -a parallel_prompts=()
  local -a session_modes=()
  local -a session_payloads=()

  while (( $# > 0 )); do
    case "$1" in
      -h|--help)
        lwt::ui::help_add
        return 0
        ;;
      -s|--setup)
        run_setup=true
        ;;
      -yolo)
        yolo=true
        ;;
      -e|--editor)
        open_editor=true
        ;;
      --editor-cmd)
        if [[ -z "$2" ]]; then
          lwt::ui::error "--editor-cmd expects a value."
          return 1
        fi
        editor_override="$2"
        shift
        ;;
      --editor-cmd=*)
        editor_override="${1#--editor-cmd=}"
        ;;
      --agents)
        if [[ -z "$2" ]]; then
          lwt::ui::error "--agents expects a comma-separated list."
          return 1
        fi
        local _as_expanded="${2//,/ }"
        _as_expanded="${_as_expanded//-/ }"
        local -a _as_tokens=(${=_as_expanded})
        shift
        local _as_prompt=""
        if [[ -n "${2:-}" && "$2" != -* ]]; then
          _as_prompt="$2"
          shift
        fi
        local _as_t
        for _as_t in "${_as_tokens[@]}"; do
          if ! lwt::agent::is_supported "$_as_t"; then
            lwt::ui::error "Unsupported agent: $_as_t"
            lwt::ui::hint "Supported agents: claude, codex, gemini"
            return 1
          fi
          agent_names+=("$_as_t")
          agent_prompts+=("$_as_prompt")
        done
        run_setup=true
        ;;
      --agents=*)
        local _ae_expanded="${${1#--agents=}//,/ }"
        _ae_expanded="${_ae_expanded//-/ }"
        local -a _ae_tokens=(${=_ae_expanded})
        local _ae_prompt=""
        if [[ -n "${2:-}" && "$2" != -* ]]; then
          _ae_prompt="$2"
          shift
        fi
        local _ae_t
        for _ae_t in "${_ae_tokens[@]}"; do
          if ! lwt::agent::is_supported "$_ae_t"; then
            lwt::ui::error "Unsupported agent: $_ae_t"
            lwt::ui::hint "Supported agents: claude, codex, gemini"
            return 1
          fi
          agent_names+=("$_ae_t")
          agent_prompts+=("$_ae_prompt")
        done
        run_setup=true
        ;;
      --claude)
        run_setup=true
        agent_names+=("claude")
        if [[ -n "${2:-}" && "$2" != -* ]]; then
          agent_prompts+=("$2")
          shift
        else
          agent_prompts+=("")
        fi
        ;;
      --codex)
        run_setup=true
        agent_names+=("codex")
        if [[ -n "${2:-}" && "$2" != -* ]]; then
          agent_prompts+=("$2")
          shift
        else
          agent_prompts+=("")
        fi
        ;;
      --gemini)
        run_setup=true
        agent_names+=("gemini")
        if [[ -n "${2:-}" && "$2" != -* ]]; then
          agent_prompts+=("$2")
          shift
        else
          agent_prompts+=("")
        fi
        ;;
      --split)
        if [[ -z "$2" ]]; then
          lwt::ui::error "--split expects a command."
          return 1
        fi
        session_modes+=("split")
        session_payloads+=("$2")
        shift
        ;;
      --split=*)
        session_modes+=("split")
        session_payloads+=("${1#--split=}")
        ;;
      --tab)
        if [[ -z "$2" ]]; then
          lwt::ui::error "--tab expects a command."
          return 1
        fi
        session_modes+=("tab")
        session_payloads+=("$2")
        shift
        ;;
      --tab=*)
        session_modes+=("tab")
        session_payloads+=("${1#--tab=}")
        ;;
      -d|--dev)
        run_setup=true
        run_dev=true
        ;;
      --split-dev|--tab-dev|--split-claude|--tab-claude|--split-codex|--tab-codex|--split-gemini|--tab-gemini)
        lwt::ui::error "Placement flags are no longer supported: $1"
        lwt::ui::hint "Use --claude/--codex/--gemini directly. First agent runs here; the rest open in splits."
        return 1
        ;;
      --)
        shift
        if [[ -z "$branch" && -n "${1:-}" ]]; then
          branch="$1"
          shift
        fi
        if (( $# > 0 )); then
          lwt::ui::error "Unexpected trailing arguments: $*"
          lwt::ui::hint "Prompts must follow their agent flag: --claude \"prompt\""
          return 1
        fi
        break
        ;;
      --*)
        # Try as agent combo (e.g. --claude-codex)
        local _co_expanded="${${1#--}//,/ }"
        _co_expanded="${_co_expanded//-/ }"
        local -a _co_tokens=(${=_co_expanded})
        local _co_valid=true
        local _co_t
        for _co_t in "${_co_tokens[@]}"; do
          if ! lwt::agent::is_supported "$_co_t"; then
            _co_valid=false
            break
          fi
        done
        if [[ "$_co_valid" != "true" || ${#_co_tokens[@]} -eq 0 ]]; then
          lwt::ui::error "Unknown option: $1"
          return 1
        fi
        local _co_prompt=""
        if [[ -n "${2:-}" && "$2" != -* ]]; then
          _co_prompt="$2"
          shift
        fi
        for _co_t in "${_co_tokens[@]}"; do
          agent_names+=("$_co_t")
          agent_prompts+=("$_co_prompt")
        done
        run_setup=true
        ;;
      -*)
        lwt::ui::error "Unknown option: $1"
        return 1
        ;;
      *)
        if [[ -z "$branch" ]]; then
          branch="$1"
        else
          lwt::ui::error "Unexpected argument: $1"
          lwt::ui::hint "Prompts must follow their agent flag: --claude \"prompt\""
          return 1
        fi
        ;;
    esac
    shift
  done

  if [[ -z "$branch" ]]; then
    branch=$(lwt::utils::random_branch_name)
  fi

  # Deduplicate agents, keeping first occurrence with its prompt
  local -a _deduped_names=()
  local -a _deduped_prompts=()
  local -A _seen_agents=()
  local _di
  for (( _di = 1; _di <= ${#agent_names[@]}; _di++ )); do
    if [[ -z "${_seen_agents[${agent_names[$_di]}]:-}" ]]; then
      _seen_agents[${agent_names[$_di]}]=1
      _deduped_names+=("${agent_names[$_di]}")
      _deduped_prompts+=("${agent_prompts[$_di]}")
    fi
  done
  agent_names=("${_deduped_names[@]}")
  agent_prompts=("${_deduped_prompts[@]}")

  # Split into runnable vs missing agents
  local _ri
  for (( _ri = 1; _ri <= ${#agent_names[@]}; _ri++ )); do
    if lwt::deps::has "${agent_names[$_ri]}"; then
      runnable_agents+=("${agent_names[$_ri]}")
      runnable_prompts+=("${agent_prompts[$_ri]}")
    else
      missing_agents+=("${agent_names[$_ri]}")
    fi
  done

  # --dev: promote to split when an agent occupies the main shell
  if $run_dev && (( ${#agent_names[@]} > 0 )); then
    session_modes+=("split")
    session_payloads+=("__lwt_dev__")
  fi

  lwt::worktree::create_branch "$branch" false true || return 1
  local target="$LWT_LAST_WORKTREE_PATH"
  [[ -z "$target" ]] && return 1

  cd "$target" || return 1

  if $run_setup || (( ${#agent_names[@]} > 0 )); then
    lwt::utils::install_dependencies
  fi

  lwt::hooks::run "post-create" "$target" "$target" "$branch" \
    "LWT_MAIN_WORKTREE_PATH" "$(lwt::worktree::main_path)" || {
      lwt::ui::hint "Worktree was created but post-create hooks failed."
      return 1
    }
  lwt::hooks::run "post-switch" "$target" "$target" "$branch" \
    "LWT_MAIN_WORKTREE_PATH" "$(lwt::worktree::main_path)" || {
      lwt::ui::hint "Worktree was created but post-switch hooks failed."
      return 1
    }

  lwt::ui::success "Created worktree ${branch}."

  if $open_editor; then
    lwt::editor::open "$target" "$editor_override"
  fi

  local resolved_yolo="$yolo"
  if [[ "$resolved_yolo" != "true" ]]; then
    local configured_agent_mode
    configured_agent_mode=$(lwt::config::get_effective "agent-mode" 2>/dev/null)
    [[ "$configured_agent_mode" == "yolo" ]] && resolved_yolo=true
  fi

  for agent_name in "${missing_agents[@]}"; do
    lwt::ui::warn "$agent_name is not installed; skipping AI launch."
  done

  # Determine main agent (first runnable) and parallel agents (rest)
  if (( ${#runnable_agents[@]} >= 1 )); then
    main_agent="${runnable_agents[1]}"
    main_agent_prompt="${runnable_prompts[1]}"

    if (( ${#runnable_agents[@]} > 1 )); then
      parallel_agents=("${runnable_agents[@]:1}")
      parallel_prompts=("${runnable_prompts[@]:1}")
    fi

    if (( ${#agent_names[@]} > ${#runnable_agents[@]} && ${#runnable_agents[@]} == 1 )); then
      lwt::ui::warn "Only ${main_agent} is available locally; launching it in the current shell."
    fi
  fi

  # Resolve terminal driver if splits/tabs are needed
  local needs_terminal=false
  (( ${#session_modes[@]} > 0 )) && needs_terminal=true
  (( ${#parallel_agents[@]} > 0 )) && needs_terminal=true

  if $needs_terminal; then
    terminal_driver=$(lwt::terminal::resolve_driver 2>/dev/null) || {
      lwt::ui::warn "Terminal automation requested, but no supported terminal driver was detected."
      lwt::ui::hint "Supported today: Ghostty and iTerm2 on macOS."
      lwt::ui::hint "Set one explicitly with: lwt config set terminal ghostty"
    }
  fi

  # Fallback for parallel agents without terminal automation
  if [[ -z "$terminal_driver" ]] && (( ${#parallel_agents[@]} > 0 )); then
    lwt::ui::warn "Parallel agent launch requested, but terminal automation is unavailable."
    lwt::ui::hint "Launching ${main_agent} in the current shell and printing commands for the rest."

    local _fi
    for (( _fi = 1; _fi <= ${#parallel_agents[@]}; _fi++ )); do
      fallback_command=$(lwt::agent::command_string "${parallel_agents[$_fi]}" "${parallel_prompts[$_fi]}" "$resolved_yolo") || continue
      lwt::ui::hint "Manual launch: cd $(lwt::shell::quote "$target") && $fallback_command"
    done
    parallel_agents=()
    parallel_prompts=()
  fi

  # Launch generic sessions (--split/--tab)
  local i mode payload
  for (( i = 1; i <= ${#session_modes[@]}; i++ )); do
    mode="${session_modes[$i]}"
    payload="${session_payloads[$i]}"

    # Resolve dev sentinel
    if [[ "$payload" == "__lwt_dev__" ]]; then
      if ! payload=$(lwt::project::dev_command); then
        lwt::ui::warn "Couldn't resolve a dev command for ${branch}; skipping ${mode}."
        lwt::ui::hint "Set one with: lwt config set dev-cmd \"pnpm --filter app dev\""
        continue
      fi
    fi

    if [[ -z "$terminal_driver" ]]; then
      continue
    fi

    lwt::ui::step "Opening ${mode}..."
    if ! lwt::terminal::launch "$terminal_driver" "$mode" "$target" "$payload"; then
      lwt::ui::warn "Failed to open ${mode}."
    fi
  done

  # Launch parallel agent splits
  local _pi
  for (( _pi = 1; _pi <= ${#parallel_agents[@]}; _pi++ )); do
    session_command=$(lwt::agent::command_string "${parallel_agents[$_pi]}" "${parallel_prompts[$_pi]}" "$resolved_yolo") || continue

    lwt::ui::step "Opening split for ${parallel_agents[$_pi]}..."
    if ! lwt::terminal::launch "$terminal_driver" "split" "$target" "$session_command"; then
      lwt::ui::warn "Failed to open split for ${parallel_agents[$_pi]}."
    fi
  done

  # Launch main agent in current shell
  lwt::agent::launch "$main_agent" "$main_agent_prompt" "$yolo"

  # --dev without agents: run dev command in the current shell
  if $run_dev && (( ${#agent_names[@]} == 0 )); then
    local dev_command
    if dev_command=$(lwt::project::dev_command); then
      lwt::ui::step "Running dev command..."
      eval "$dev_command"
    else
      lwt::ui::warn "Couldn't resolve a dev command for ${branch}."
      lwt::ui::hint "Set one with: lwt config set dev-cmd \"pnpm --filter app dev\""
    fi
  fi
}

lwt::merge::target_branch() {
  local explicit_target="${1:-}"
  local configured_target=""

  if [[ -n "$explicit_target" ]]; then
    printf '%s\n' "$explicit_target"
    return 0
  fi

  configured_target=$(lwt::config::get_effective merge-target 2>/dev/null)
  if [[ -z "$configured_target" || "$configured_target" == "default-branch" ]]; then
    printf '%s\n' "$LWT_DEFAULT_BRANCH"
  else
    printf '%s\n' "$configured_target"
  fi
}

lwt::merge::open_pr_metadata() {
  local branch="$1"

  [[ -n "$branch" ]] || return 1

  lwt::status::init_gh_mode
  [[ "$LWT_GH_MODE" == "ok" ]] || return 1

  gh pr list --head "$branch" --state open --json number,title,baseRefName,url \
    -q '.[0] // empty | "\(.number)\t\(.title)\t\(.baseRefName)\t\(.url)"' 2>/dev/null
}

lwt::merge::ensure_local_branch() {
  local repo_path="$1"
  local branch="$2"

  [[ -n "$repo_path" && -n "$branch" ]] || return 1

  if git -C "$repo_path" show-ref --verify --quiet "refs/heads/$branch" 2>/dev/null; then
    return 0
  fi

  if git -C "$repo_path" show-ref --verify --quiet "refs/remotes/origin/$branch" 2>/dev/null; then
    git -C "$repo_path" branch --track "$branch" "origin/$branch" >/dev/null 2>&1 || return 1
    return 0
  fi

  return 1
}

lwt::merge::commit_subject() {
  local worktree="$1"
  local branch="$2"
  local target_branch="$3"
  local subject=""
  local commit_count=0

  if [[ -n "$branch" ]]; then
    lwt::status::init_gh_mode
    if [[ "$LWT_GH_MODE" == "ok" ]]; then
      subject=$(gh pr list --head "$branch" --state open --json title -q '.[0].title // ""' 2>/dev/null)
      [[ -n "$subject" ]] && {
        printf '%s\n' "$subject"
        return 0
      }
    fi
  fi

  commit_count=$(git -C "$worktree" rev-list --count "${target_branch}..HEAD" 2>/dev/null)
  if [[ -n "$commit_count" && "$commit_count" == "1" ]]; then
    git -C "$worktree" log -1 --format=%s
    return 0
  fi

  subject="${branch//-/ }"
  subject="${subject//_/ }"
  [[ -z "$subject" ]] && subject="$branch"

  printf '%s\n' "$subject"
}

lwt::merge::commit_body() {
  local worktree="$1"
  local target_branch="$2"
  local commit_count=0

  commit_count=$(git -C "$worktree" rev-list --count "${target_branch}..HEAD" 2>/dev/null)
  if [[ -z "$commit_count" || "$commit_count" -le 1 ]] 2>/dev/null; then
    return 0
  fi

  git -C "$worktree" log --format='- %s' "${target_branch}..HEAD"
}

lwt::merge::close_pr_or_delete_remote() {
  local branch="$1"
  local target_branch="$2"
  local pr_number=""

  [[ -n "$branch" ]] || return 0

  lwt::status::init_gh_mode
  if [[ "$LWT_GH_MODE" == "ok" ]]; then
    pr_number=$(gh pr list --head "$branch" --state open --json number -q '.[0].number // ""' 2>/dev/null)
    if [[ -n "$pr_number" ]]; then
      gh pr comment "$pr_number" --body "Merged locally into \`$target_branch\` with \`lwt merge\`." >/dev/null 2>&1 || true
      gh pr close "$pr_number" >/dev/null 2>&1 || true
    fi
  fi

  if git ls-remote --heads origin "$branch" 2>/dev/null | grep -q .; then
    git push origin --delete "$branch" >/dev/null 2>&1 || true
  fi
}

lwt::merge::cleanup_local_source() {
  local worktree="$1"
  local branch="$2"
  local current_wt="$3"
  local main_wt="$4"
  local keep_worktree="$5"
  local keep_branch="$6"

  if [[ "$current_wt" == "$worktree" ]]; then
    cd "$main_wt" || return 1
  fi

  if [[ "$keep_worktree" != "true" ]]; then
    git worktree remove "$worktree" >/dev/null 2>&1 || git worktree remove --force "$worktree" >/dev/null 2>&1 || return 1
    git worktree prune --quiet 2>/dev/null || git worktree prune
  fi

  if [[ "$keep_branch" != "true" ]] && git show-ref --verify --quiet "refs/heads/$branch" 2>/dev/null; then
    git branch -D "$branch" >/dev/null 2>&1 || true
  fi
}

lwt::merge::sync_target_branch() {
  local main_wt="$1"
  local target_branch="$2"

  [[ -n "$main_wt" && -n "$target_branch" ]] || return 1

  local previous_main_branch main_changed
  previous_main_branch=$(git -C "$main_wt" branch --show-current 2>/dev/null)
  main_changed=$(git -C "$main_wt" status --porcelain 2>/dev/null | wc -l | tr -d ' ')

  if [[ -n "$previous_main_branch" && "$previous_main_branch" != "$target_branch" && "$main_changed" != "0" ]]; then
    lwt::ui::warn "Merged successfully, but your main worktree has uncommitted changes."
    lwt::ui::hint "Skipped fast-forwarding $target_branch locally."
    return 0
  fi

  if [[ "$previous_main_branch" != "$target_branch" ]]; then
    git -C "$main_wt" checkout "$target_branch" >/dev/null 2>&1 || {
      lwt::ui::warn "Merged successfully, but couldn't check out $target_branch in the main worktree."
      return 0
    }
  fi

  git -C "$main_wt" pull --ff-only >/dev/null 2>&1 || git -C "$main_wt" fetch --all --prune --quiet >/dev/null 2>&1 || true
}

lwt::merge::delete_remote_branch() {
  local branch="$1"

  [[ -n "$branch" ]] || return 0

  if git ls-remote --heads origin "$branch" 2>/dev/null | grep -q .; then
    git push origin --delete "$branch" >/dev/null 2>&1 || {
      if git ls-remote --heads origin "$branch" 2>/dev/null | grep -q .; then
        return 1
      fi
      return 0
    }
  fi

  return 0
}

lwt::merge::pr_is_merged() {
  local pr_number="$1"

  [[ -n "$pr_number" ]] || return 1

  lwt::status::init_gh_mode
  [[ "$LWT_GH_MODE" == "ok" ]] || return 1

  [[ "$(gh pr view "$pr_number" --json state,mergedAt -q 'if .state == "MERGED" or .mergedAt != null then "true" else "false" end' 2>/dev/null)" == "true" ]]
}

lwt::merge::run_gh_pr_merge() {
  local pr_number="$1"
  local use_admin="$2"
  local output_file=""
  local exit_code=0
  local -a gh_merge_cmd=(gh pr merge "$pr_number" --squash)

  [[ -n "$pr_number" ]] || return 1

  if [[ "$use_admin" == "true" ]]; then
    gh_merge_cmd+=(--admin)
  fi

  LWT_LAST_GH_MERGE_OUTPUT=""
  LWT_LAST_GH_MERGE_WARN_ONLY=false
  output_file=$(mktemp) || return 1
  "${gh_merge_cmd[@]}" >"$output_file" 2>&1 || exit_code=$?
  LWT_LAST_GH_MERGE_OUTPUT="$(cat "$output_file")"
  printf '%s\n' "$LWT_LAST_GH_MERGE_OUTPUT"
  rm -f "$output_file"

  if (( exit_code != 0 )) && lwt::merge::pr_is_merged "$pr_number"; then
    LWT_LAST_GH_MERGE_WARN_ONLY=true
    return 0
  fi

  return "$exit_code"
}

lwt::cmd::merge() {
  local target_branch=""
  local keep_worktree=false
  local keep_branch=false
  local no_push=false
  local use_admin=false

  while (( $# > 0 )); do
    case "$1" in
      -h|--help)
        lwt::ui::help_merge
        return 0
        ;;
      --keep-worktree)
        keep_worktree=true
        ;;
      --keep-branch)
        keep_branch=true
        ;;
      --no-push)
        no_push=true
        ;;
      --admin)
        use_admin=true
        ;;
      --)
        shift
        [[ -n "${1:-}" ]] && target_branch="$1"
        shift
        (( $# == 0 )) || {
          lwt::ui::error "Unexpected trailing arguments: $*"
          return 1
        }
        break
        ;;
      -*)
        lwt::ui::error "Unknown option: $1"
        return 1
        ;;
      *)
        if [[ -z "$target_branch" ]]; then
          target_branch="$1"
        else
          lwt::ui::error "Unexpected argument: $1"
          return 1
        fi
        ;;
    esac
    shift
  done

  local main_wt current_wt worktree=""
  main_wt=$(lwt::worktree::main_path) || return 1
  current_wt=$(git rev-parse --show-toplevel 2>/dev/null)

  if [[ "$current_wt" != "$main_wt" ]]; then
    worktree="$current_wt"
  else
    if ! lwt::deps::has fzf; then
      lwt::ui::error "Run lwt merge from inside a worktree, or install fzf to pick one."
      return 1
    fi

    worktree=$(lwt::worktree::display_rows | awk -F'\t' -v main="$main_wt" '$1 != main' | \
      fzf --ansi --height 40% --reverse --prompt="Merge worktree: " \
      --delimiter='\t' --with-nth=2.. | awk -F'\t' '{print $1}')
  fi

  [[ -z "$worktree" ]] && return 0

  local branch
  branch=$(git -C "$worktree" branch --show-current 2>/dev/null)
  [[ -n "$branch" && "$branch" != "(detached)" ]] || {
    lwt::ui::error "Cannot merge a detached HEAD worktree."
    return 1
  }
  if [[ "$branch" == "$LWT_DEFAULT_BRANCH" || "$branch" == "main" || "$branch" == "master" ]]; then
    lwt::ui::error "Refusing to merge the default branch into itself."
    return 1
  fi

  target_branch=$(lwt::merge::target_branch "$target_branch") || return 1
  if [[ "$target_branch" == "$branch" ]]; then
    lwt::ui::error "Source and target branches are the same: $branch"
    return 1
  fi

  lwt::git::fetch_if_stale
  lwt::merge::ensure_local_branch "$main_wt" "$target_branch" || {
    lwt::ui::error "Target branch not found locally or on origin: $target_branch"
    return 1
  }

  local worktree_changed=0
  local main_changed=0
  local ahead_count=0
  local remote_branch_exists=false
  local commit_subject=""
  local commit_body=""
  local previous_main_branch=""
  local open_pr_raw=""
  local open_pr_number=""
  local open_pr_title=""
  local open_pr_base=""
  local open_pr_url=""
  local merge_completed=false

  worktree_changed=$(git -C "$worktree" status --porcelain 2>/dev/null | wc -l | tr -d ' ')
  main_changed=$(git -C "$main_wt" status --porcelain 2>/dev/null | wc -l | tr -d ' ')
  ahead_count=$(git -C "$worktree" rev-list --count "${target_branch}..HEAD" 2>/dev/null)

  (( worktree_changed == 0 )) || {
    lwt::ui::error "Worktree has uncommitted changes. Commit or stash them before merging."
    return 1
  }
  (( ahead_count > 0 )) || {
    lwt::ui::error "Branch $branch has no commits ahead of $target_branch."
    return 1
  }

  if git ls-remote --heads origin "$branch" 2>/dev/null | grep -q .; then
    remote_branch_exists=true
  fi

  open_pr_raw=$(lwt::merge::open_pr_metadata "$branch" 2>/dev/null || true)
  if [[ -n "$open_pr_raw" ]]; then
    IFS=$'\t' read -r open_pr_number open_pr_title open_pr_base open_pr_url <<< "$open_pr_raw"

    if [[ -n "$target_branch" && "$target_branch" != "$open_pr_base" ]]; then
      lwt::ui::error "Open PR targets $open_pr_base, but lwt merge was asked to target $target_branch."
      lwt::ui::hint "Merge the PR as-is, or retarget the PR first."
      return 1
    fi

    target_branch="$open_pr_base"
  else
    (( main_changed == 0 )) || {
      lwt::ui::error "Main worktree has uncommitted changes. Keep it clean before merging."
      return 1
    }
  fi

  commit_subject=$(lwt::merge::commit_subject "$worktree" "$branch" "$target_branch")
  commit_body=$(lwt::merge::commit_body "$worktree" "$target_branch")

  lwt::ui::header "Merge worktree"
  echo "  Source: ${_lwt_bold}$branch${_lwt_reset} ${_lwt_dim}$worktree${_lwt_reset}"
  echo "  Target: ${_lwt_bold}$target_branch${_lwt_reset}"
  if [[ -n "$open_pr_number" ]]; then
    echo "  Mode:   ${_lwt_dim}GitHub PR squash merge + cleanup${_lwt_reset}"
    printf '  PR:     %s\e]8;;%s\e\\#%s\e]8;;\e\\%s %s\n' "$_lwt_dim" "$open_pr_url" "$open_pr_number" "$_lwt_reset" "$open_pr_title"
  else
    echo "  Mode:   ${_lwt_dim}local squash + rebase + cleanup${_lwt_reset}"
  fi
  echo "  Commits ahead: ${_lwt_bold}$ahead_count${_lwt_reset}"
  [[ -n "$commit_subject" ]] && echo "  Commit: ${_lwt_dim}$commit_subject${_lwt_reset}"
  $remote_branch_exists && echo "  Remote cleanup: ${_lwt_dim}origin/$branch will be deleted${_lwt_reset}"
  $keep_worktree && echo "  Keep worktree: ${_lwt_dim}yes${_lwt_reset}"
  $keep_branch && echo "  Keep branch: ${_lwt_dim}yes${_lwt_reset}"
  if [[ -n "$open_pr_number" ]]; then
    $use_admin && echo "  Admin merge: ${_lwt_dim}yes${_lwt_reset}"
    $no_push && echo "  ${_lwt_dim}Note: --no-push is ignored when merging through GitHub.${_lwt_reset}"
  else
    $no_push && echo "  Push target: ${_lwt_dim}no${_lwt_reset}"
  fi
  echo

  if ! read -rq "?Merge ${branch} into ${target_branch}? [y/N] "; then
    echo
    return 0
  fi
  echo

  lwt::hooks::run "pre-merge" "$worktree" "$worktree" "$branch" \
    "LWT_MAIN_WORKTREE_PATH" "$main_wt" \
    "LWT_TARGET_BRANCH" "$target_branch" || return 1

  if [[ -n "$open_pr_number" ]]; then
    lwt::merge::run_gh_pr_merge "$open_pr_number" "$use_admin"
    local gh_merge_status=$?

    if (( gh_merge_status != 0 )); then
      if [[ "$use_admin" != "true" && "$LWT_LAST_GH_MERGE_OUTPUT" == *"--admin"* ]]; then
        echo
        if read -rq "?Retry PR merge with administrator privileges (--admin)? [y/N] "; then
          echo
          lwt::merge::run_gh_pr_merge "$open_pr_number" "true" || {
            lwt::ui::error "GitHub PR merge failed."
            return 1
          }
        else
          echo
          lwt::ui::error "GitHub PR merge failed."
          lwt::ui::hint "Retry with: lwt merge --admin"
          return 1
        fi
      else
        lwt::ui::error "GitHub PR merge failed."
        if [[ "$use_admin" != "true" ]]; then
          lwt::ui::hint "If branch protection is blocking this and you have permission, retry with: lwt merge --admin"
        fi
        return 1
      fi
    fi

    merge_completed=true
    if [[ "$LWT_LAST_GH_MERGE_WARN_ONLY" == "true" ]]; then
      lwt::ui::warn "GitHub merged the PR, but gh hit a local worktree limitation afterward."
    fi
    if [[ "$keep_branch" != "true" ]] && ! lwt::merge::delete_remote_branch "$branch"; then
      lwt::ui::warn "PR merged. origin/$branch is still on the remote."
      lwt::ui::hint "GitHub may not have deleted it automatically, or it may be protected."
    fi
    lwt::merge::sync_target_branch "$main_wt" "$target_branch"
  else
    previous_main_branch=$(git -C "$main_wt" branch --show-current 2>/dev/null)

    if ! git -C "$worktree" rebase "$target_branch"; then
      lwt::ui::error "Rebase onto $target_branch failed."
      lwt::ui::hint "Resolve the rebase inside $worktree, then rerun lwt merge."
      return 1
    fi

    if [[ "$previous_main_branch" != "$target_branch" ]]; then
      git -C "$main_wt" checkout "$target_branch" >/dev/null 2>&1 || return 1
    fi

    if git -C "$main_wt" rev-parse --abbrev-ref '@{upstream}' >/dev/null 2>&1; then
      git -C "$main_wt" pull --ff-only >/dev/null 2>&1 || {
        lwt::ui::error "Failed to fast-forward $target_branch before merging."
        return 1
      }
    fi

    git -C "$main_wt" merge --squash "$branch" >/dev/null 2>&1 || {
      lwt::ui::error "Squash merge failed."
      return 1
    }

    if git -C "$main_wt" diff --cached --quiet; then
      lwt::ui::error "Squash merge produced no staged changes."
      return 1
    fi

    if [[ -n "$commit_body" ]]; then
      git -C "$main_wt" commit -m "$commit_subject" -m "$commit_body" >/dev/null 2>&1 || return 1
    else
      git -C "$main_wt" commit -m "$commit_subject" >/dev/null 2>&1 || return 1
    fi

    if ! $no_push && git -C "$main_wt" rev-parse --abbrev-ref '@{upstream}' >/dev/null 2>&1; then
      git -C "$main_wt" push >/dev/null 2>&1 || {
        lwt::ui::error "Merged locally, but failed to push $target_branch."
        return 1
      }
    fi

    if ! $keep_branch; then
      lwt::merge::close_pr_or_delete_remote "$branch" "$target_branch"
    fi

    merge_completed=true
  fi

  lwt::hooks::run "post-merge" "$main_wt" "$main_wt" "$target_branch" \
    "LWT_MAIN_WORKTREE_PATH" "$main_wt" \
    "LWT_SOURCE_BRANCH" "$branch" \
    "LWT_SOURCE_WORKTREE_PATH" "$worktree" \
    "LWT_TARGET_BRANCH" "$target_branch" || {
      if $merge_completed; then
        lwt::ui::warn "Merged successfully, but post-merge hooks failed."
      else
        return 1
      fi
    }

  lwt::merge::cleanup_local_source "$worktree" "$branch" "$current_wt" "$main_wt" "$keep_worktree" "$keep_branch" || {
    if $merge_completed; then
      lwt::ui::warn "Merged successfully, but local cleanup failed."
    else
      return 1
    fi
  }

  lwt::ui::success "Merged $branch into $target_branch."
}

lwt::cmd::hook() {
  local subcommand="${1:-list}"
  local repo_root=""
  local event=""

  if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    repo_root=$(git rev-parse --show-toplevel 2>/dev/null)
  fi

  case "$subcommand" in
    ""|list)
      local row event_name repo_file repo_dir local_cfg user_file user_dir global_cfg
      lwt::ui::header "lwt hooks"
      while IFS= read -r row; do
        event_name="${row%%$'\t'*}"
        repo_file=$(printf '%s\n' "$row" | awk -F'\t' '{print $2}' | cut -d: -f2)
        repo_dir=$(printf '%s\n' "$row" | awk -F'\t' '{print $3}' | cut -d: -f2)
        local_cfg=$(printf '%s\n' "$row" | awk -F'\t' '{print $4}' | cut -d: -f2)
        user_file=$(printf '%s\n' "$row" | awk -F'\t' '{print $5}' | cut -d: -f2)
        user_dir=$(printf '%s\n' "$row" | awk -F'\t' '{print $6}' | cut -d: -f2)
        global_cfg=$(printf '%s\n' "$row" | awk -F'\t' '{print $7}' | cut -d: -f2)
        printf '  %-12s repo[file:%s dir:%s cfg:%s] user[file:%s dir:%s cfg:%s]\n' \
          "$event_name" "$repo_file" "$repo_dir" "$local_cfg" "$user_file" "$user_dir" "$global_cfg"
      done < <(
        while IFS= read -r event; do
          lwt::hooks::describe_event "$event" "$repo_root"
        done < <(lwt::hooks::supported_events)
      )
      ;;
    path)
      event="${2:-}"
      if [[ -z "$event" ]]; then
        lwt::ui::error "Usage: lwt hook path <event>"
        return 1
      fi
      printf 'user: %s\n' "$(lwt::hooks::user_dir)/$event"
      if [[ -n "$repo_root" ]]; then
        printf 'repo: %s\n' "$(lwt::hooks::repo_dir "$repo_root")/$event"
      fi
      ;;
    run)
      event="${2:-}"
      if [[ -z "$event" ]]; then
        lwt::ui::error "Usage: lwt hook run <event>"
        return 1
      fi
      if [[ -z "$repo_root" ]]; then
        lwt::ui::error "Run lwt hook run inside a git repository."
        return 1
      fi
      lwt::hooks::run "$event" "$repo_root" "$repo_root" "$(git branch --show-current 2>/dev/null)"
      ;;
    -h|--help)
      lwt::ui::help_hook
      ;;
    *)
      lwt::ui::error "Unknown hook subcommand: $subcommand"
      return 1
      ;;
  esac
}

lwt::cmd::remove() {
  local query=""
  local assume_yes=false
  local force=false
  local delete_remote=false

  while (( $# > 0 )); do
    case "$1" in
      -h|--help)
        lwt::ui::help_remove
        return 0
        ;;
      -y|--yes)
        assume_yes=true
        ;;
      -f|--force)
        force=true
        ;;
      --delete-remote)
        delete_remote=true
        ;;
      --)
        shift
        query="$*"
        break
        ;;
      -*)
        lwt::ui::error "Unknown option: $1"
        return 1
        ;;
      *)
        query="$query${query:+ }$1"
        ;;
    esac
    shift
  done

  local main_wt current_wt worktree=""
  main_wt=$(lwt::worktree::main_path) || return 1
  current_wt=$(git rev-parse --show-toplevel 2>/dev/null)

  if [[ "$current_wt" != "$main_wt" ]]; then
    # if a query was passed while inside a worktree, the user may have meant `lwt rn`
    if [[ -n "$query" ]]; then
      lwt::ui::hint "Did you mean ${_lwt_bold}lwt rn $query${_lwt_reset}${_lwt_dim}? (rm ignores arguments inside a worktree)"
      echo
    fi
    worktree="$current_wt"
  else
    if [[ -n "$query" ]]; then
      worktree=$(lwt::worktree::resolve_query "$query" true)
      local resolve_exit=$?
      case "$resolve_exit" in
        0)
          ;;
        1)
          if [[ ! -t 0 ]]; then
            lwt::ui::error "No exact worktree matched: $query"
            lwt::ui::hint "Pass an exact branch name or worktree path, or run lwt rm interactively."
            return 1
          fi
          ;;
        2)
          lwt::ui::error "Query matched multiple worktrees: $query"
          lwt::ui::hint "Pass an exact branch name or worktree path."
          return 1
          ;;
        *)
          return "$resolve_exit"
          ;;
      esac
    fi

    if [[ -z "$worktree" ]]; then
      if ! lwt::deps::has fzf; then
        lwt::ui::error "fzf is required to pick a worktree. Install with: brew install fzf"
        return 1
      fi

      lwt::status::warn_gh_limitations

      worktree=$(lwt::worktree::display_rows | awk -F'\t' -v main="$main_wt" '$1 != main' | \
        fzf --ansi --height 40% --reverse --prompt="Remove worktree: " --query="$query" \
        --delimiter='\t' --with-nth=2.. | awk -F'\t' '{print $1}')
    fi
  fi

  [[ -z "$worktree" ]] && return 0

  local branch
  local commits=0
  local changed=0
  local unpushed=0
  local behind=0
  local merged=false

  branch=$(git -C "$worktree" branch --show-current 2>/dev/null)
  commits=$(git -C "$worktree" rev-list --count "${LWT_DEFAULT_BASE_REF}..HEAD" 2>/dev/null)
  changed=$(git -C "$worktree" status --porcelain 2>/dev/null | wc -l | tr -d ' ')

  if git -C "$worktree" rev-parse --abbrev-ref '@{upstream}' >/dev/null 2>&1; then
    unpushed=$(git -C "$worktree" rev-list --count '@{upstream}..HEAD' 2>/dev/null)
    behind=$(git -C "$worktree" rev-list --count 'HEAD..@{upstream}' 2>/dev/null)
  fi

  lwt::status::is_merged "$branch" && merged=true

  lwt::ui::header "Remove worktree"
  echo "  ${_lwt_dim}$worktree${_lwt_reset}"
  if $merged; then
    echo "  Branch: ${_lwt_bold}$branch${_lwt_reset} ${_lwt_green}✓ merged${_lwt_reset}"
  else
    echo "  Branch: ${_lwt_bold}$branch${_lwt_reset} ${_lwt_dim}($commits commit(s) ahead of $LWT_DEFAULT_BRANCH)${_lwt_reset}"
  fi
  ((changed > 0)) && echo "  ${_lwt_yellow}⚠ $changed uncommitted file(s)${_lwt_reset}"
  if ! $merged; then
    ((unpushed > 0)) && echo "  ${_lwt_yellow}⚠ $unpushed unpushed commit(s)${_lwt_reset}"
    ((behind > 0)) && echo "  ${_lwt_dim}↓ $behind commit(s) behind remote${_lwt_reset}"
  fi

  # detect PR (open → used for post-deletion cleanup; merged → informational link)
  local _rm_pr_num="" _rm_pr_link="" _rm_pr_state=""
  lwt::status::init_gh_mode
  if [[ "$LWT_GH_MODE" == "ok" && -n "$branch" ]]; then
    local _rm_pr_raw
    # check open first (actionable), then merged (informational)
    _rm_pr_raw=$(gh pr list --head "$branch" --state open --json number,url -q '.[0] // empty | "PR #\(.number)\t\(.url)"' 2>/dev/null)
    if [[ -n "$_rm_pr_raw" ]]; then
      _rm_pr_state="open"
    else
      _rm_pr_raw=$(gh pr list --head "$branch" --state merged --json number,url -q '.[0] // empty | "PR #\(.number)\t\(.url)"' 2>/dev/null)
      [[ -n "$_rm_pr_raw" ]] && _rm_pr_state="merged"
    fi
    if [[ -n "$_rm_pr_raw" ]]; then
      _rm_pr_num="${_rm_pr_raw%%$'\t'*}"
      _rm_pr_link="${_rm_pr_raw#*$'\t'}"
      if [[ "$_rm_pr_state" == "open" ]]; then
        printf '  %s\e]8;;%s\e\\%s\e]8;;\e\\ is open on this branch.%s\n' \
          "$_lwt_dim" "$_rm_pr_link" "$_rm_pr_num" "$_lwt_reset"
      else
        printf '  %s\e]8;;%s\e\\%s\e]8;;\e\\ was merged.%s\n' \
          "$_lwt_dim" "$_rm_pr_link" "$_rm_pr_num" "$_lwt_reset"
      fi
    fi
  fi

  local retry_target="${branch:-$query}"
  [[ -z "$retry_target" ]] && retry_target="<branch>"

  lwt::ui::confirm "${_lwt_red}Delete worktree permanently? [y/N]${_lwt_reset}" "$assume_yes" \
    "Retry with: lwt rm $(lwt::shell::quote "$retry_target") --yes"
  local confirm_exit=$?
  case "$confirm_exit" in
    0)
      ;;
    1)
      return 0
      ;;
    2)
      return 1
      ;;
    *)
      return "$confirm_exit"
      ;;
  esac

  cd "$main_wt" || return 1

  lwt::hooks::run "pre-remove" "$worktree" "$worktree" "$branch" \
    "LWT_MAIN_WORKTREE_PATH" "$main_wt" || return 1

  if ! git worktree remove "$worktree" 2>/dev/null; then
    if ((changed > 0)); then
      if [[ "$force" == "true" ]]; then
        :
      elif [[ "$assume_yes" == "true" ]]; then
        lwt::ui::error "Worktree has local changes; refusing to discard them without --force."
        lwt::ui::hint "Retry with: lwt rm $(lwt::shell::quote "$retry_target") --yes --force"
        return 1
      else
        lwt::ui::confirm "${_lwt_red}Worktree has local changes. Force remove and discard them? [y/N]${_lwt_reset}" false
        local force_remove_exit=$?
        case "$force_remove_exit" in
          0)
            ;;
          1)
            return 0
            ;;
          *)
            return 1
            ;;
        esac
      fi
    fi

    git worktree remove --force "$worktree" || return 1
  fi

  git worktree prune --quiet 2>/dev/null || git worktree prune

  if [[ -n "$branch" && "$branch" != "$LWT_DEFAULT_BRANCH" && "$branch" != "main" && "$branch" != "master" ]] \
    && git show-ref --verify --quiet "refs/heads/$branch"; then
    if git branch -d "$branch" >/dev/null 2>&1; then
      lwt::ui::step "Deleted local branch $branch"
    elif $merged; then
      git branch -D "$branch" >/dev/null 2>&1 && lwt::ui::step "Deleted local branch $branch"
    elif [[ "$force" == "true" ]]; then
      git branch -D "$branch" >/dev/null 2>&1 && lwt::ui::step "Deleted local branch $branch"
    else
      lwt::ui::warn "Branch $branch has unmerged work."
      if [[ "$assume_yes" == "true" ]]; then
        lwt::ui::hint "Kept branch $branch. Re-run with --force to delete unmerged local branches automatically."
      else
        lwt::ui::confirm "${_lwt_red}Force delete local branch? [y/N]${_lwt_reset}" false
        local force_branch_exit=$?
        case "$force_branch_exit" in
          0)
            git branch -D "$branch" >/dev/null 2>&1 && lwt::ui::step "Deleted local branch $branch"
            ;;
          1)
            lwt::ui::hint "Kept branch $branch."
            ;;
          *)
            return 1
            ;;
        esac
      fi
    fi
  fi

  # remote cleanup: offer to delete remote branch (and close open PR if any)
  if [[ -n "$branch" && "$branch" != "$LWT_DEFAULT_BRANCH" && "$branch" != "main" && "$branch" != "master" ]] \
    && git ls-remote --heads origin "$branch" 2>/dev/null | grep -q .; then
    echo
    if [[ "$_rm_pr_state" == "open" ]]; then
      # open PR exists — close it and delete remote branch together
      printf '  Remote branch %sorigin/%s%s still exists.\n' "$_lwt_bold" "$branch" "$_lwt_reset"
      printf '  %s\e]8;;%s\e\\%s\e]8;;\e\\%s is still open.\n' \
        "$_lwt_dim" "$_rm_pr_link" "$_rm_pr_num" "$_lwt_reset"
      if [[ "$delete_remote" == "true" ]]; then
        gh pr close "${_rm_pr_num#PR #}" --delete-branch >/dev/null 2>&1 \
          && lwt::ui::step "Closed $_rm_pr_num and deleted remote branch origin/$branch" \
          || lwt::ui::warn "Failed to close PR or delete remote branch."
      elif [[ "$assume_yes" == "true" ]]; then
        lwt::ui::hint "Kept open PR and remote branch. Re-run with --delete-remote to clean them up automatically."
      else
        lwt::ui::confirm "${_lwt_red}Close PR and delete remote branch? [y/N]${_lwt_reset}" false
        local remote_pr_exit=$?
        case "$remote_pr_exit" in
          0)
            gh pr close "${_rm_pr_num#PR #}" --delete-branch >/dev/null 2>&1 \
              && lwt::ui::step "Closed $_rm_pr_num and deleted remote branch origin/$branch" \
              || lwt::ui::warn "Failed to close PR or delete remote branch."
            ;;
          1)
            ;;
          *)
            return 1
            ;;
        esac
      fi
    else
      # no open PR — just offer remote branch deletion
      printf '  Remote branch %sorigin/%s%s still exists.\n' "$_lwt_bold" "$branch" "$_lwt_reset"
      if [[ "$delete_remote" == "true" ]]; then
        git push origin --delete "$branch" 2>/dev/null \
          && lwt::ui::step "Deleted remote branch origin/$branch"
      elif [[ "$assume_yes" == "true" ]]; then
        lwt::ui::hint "Kept remote branch origin/$branch. Re-run with --delete-remote to delete it automatically."
      else
        lwt::ui::confirm "${_lwt_red}Delete remote branch? [y/N]${_lwt_reset}" false
        local remote_delete_exit=$?
        case "$remote_delete_exit" in
          0)
            git push origin --delete "$branch" 2>/dev/null \
              && lwt::ui::step "Deleted remote branch origin/$branch"
            ;;
          1)
            ;;
          *)
            return 1
            ;;
        esac
      fi
    fi
  fi

  lwt::hooks::run "post-remove" "$main_wt" "$main_wt" "$branch" \
    "LWT_MAIN_WORKTREE_PATH" "$main_wt" \
    "LWT_REMOVED_WORKTREE_PATH" "$worktree" || return 1

  lwt::ui::success "Removed worktree ${branch:-$worktree}."
}

lwt::cmd::clean() {
  local dry_run=false

  while (( $# > 0 )); do
    case "$1" in
      -h|--help)
        lwt::ui::help_clean
        return 0
        ;;
      -n|--dry-run)
        dry_run=true
        ;;
      *)
        lwt::ui::error "Unknown option: $1"
        return 1
        ;;
    esac
    shift
  done

  lwt::status::warn_gh_limitations
  lwt::git::fetch_if_stale

  local main_wt
  main_wt=$(lwt::worktree::main_path) || return 1

  local -a merged_paths=()
  local -a merged_branches=()
  local record wt_path branch

  while IFS= read -r record; do
    wt_path="${record%%$'\t'*}"
    branch="${record#*$'\t'}"

    [[ "$wt_path" == "$main_wt" ]] && continue

    if lwt::status::is_merged "$branch"; then
      merged_paths+=("$wt_path")
      merged_branches+=("$branch")
    fi
  done < <(lwt::worktree::records)

  if [[ ${#merged_paths[@]} -eq 0 ]]; then
    lwt::ui::hint "No merged worktrees to clean up."
    return 0
  fi

  lwt::ui::header "Merged worktrees (${#merged_paths[@]})"
  local i
  for ((i = 1; i <= ${#merged_paths[@]}; i++)); do
    echo "  ${_lwt_green}✓${_lwt_reset} ${_lwt_bold}${merged_branches[$i]}${_lwt_reset} ${_lwt_dim}${merged_paths[$i]}${_lwt_reset}"
  done

  if $dry_run; then
    echo
    lwt::ui::hint "Dry run — nothing was removed."
    return 0
  fi

  echo
  if ! read -rq "?Remove all ${#merged_paths[@]} merged worktree(s)? [y/N] "; then
    echo
    return 0
  fi
  echo

  local current_wt
  current_wt=$(git rev-parse --show-toplevel 2>/dev/null)

  # move to main worktree if we're inside one that will be removed
  for ((i = 1; i <= ${#merged_paths[@]}; i++)); do
    if [[ "$current_wt" == "${merged_paths[$i]}" ]]; then
      cd "$main_wt" || return 1
      break
    fi
  done

  local removed=0
  for ((i = 1; i <= ${#merged_paths[@]}; i++)); do
    wt_path="${merged_paths[$i]}"
    branch="${merged_branches[$i]}"

    if ! lwt::hooks::run "pre-remove" "$wt_path" "$wt_path" "$branch" \
      "LWT_MAIN_WORKTREE_PATH" "$main_wt"; then
      lwt::ui::warn "Skipping $wt_path because pre-remove hooks failed."
      continue
    fi

    if git worktree remove "$wt_path" 2>/dev/null || git worktree remove --force "$wt_path" 2>/dev/null; then
      ((removed++))

      # clean up local branch
      if [[ -n "$branch" && "$branch" != "(detached)" ]] \
        && git show-ref --verify --quiet "refs/heads/$branch"; then
        git branch -D "$branch" >/dev/null 2>&1
      fi

      # clean up remote branch if it still exists
      if [[ -n "$branch" && "$branch" != "(detached)" ]] \
        && git ls-remote --heads origin "$branch" 2>/dev/null | grep -q .; then
        git push origin --delete "$branch" >/dev/null 2>&1
      fi

      if ! lwt::hooks::run "post-remove" "$main_wt" "$main_wt" "$branch" \
        "LWT_MAIN_WORKTREE_PATH" "$main_wt" \
        "LWT_REMOVED_WORKTREE_PATH" "$wt_path"; then
        lwt::ui::warn "post-remove hooks failed for $branch"
      fi
    else
      lwt::ui::warn "Failed to remove $wt_path"
    fi
  done

  git worktree prune --quiet 2>/dev/null || git worktree prune
  local s="s"; ((removed == 1)) && s=""
  lwt::ui::success "Cleaned $removed merged worktree$s."
}

lwt::cmd::rename() {
  local new_name=""

  while (( $# > 0 )); do
    case "$1" in
      -h|--help)
        lwt::ui::help_rename
        return 0
        ;;
      --)
        shift
        new_name="$1"
        break
        ;;
      -*)
        lwt::ui::error "Unknown option: $1"
        return 1
        ;;
      *)
        if [[ -z "$new_name" ]]; then
          new_name="$1"
        else
          lwt::ui::error "Unexpected argument: $1"
          return 1
        fi
        ;;
    esac
    shift
  done

  if [[ -z "$new_name" ]]; then
    lwt::ui::error "New name is required."
    lwt::ui::hint "Usage: lwt rename <new-name>"
    return 1
  fi

  # validate branch name
  if ! git check-ref-format --allow-onelevel "$new_name" 2>/dev/null; then
    lwt::ui::error "Invalid branch name: $new_name"
    return 1
  fi

  if git show-ref --verify --quiet "refs/heads/$new_name" 2>/dev/null; then
    lwt::ui::error "Branch $new_name already exists."
    return 1
  fi

  local main_wt current_wt worktree=""
  main_wt=$(lwt::worktree::main_path) || return 1
  current_wt=$(git rev-parse --show-toplevel 2>/dev/null)

  if [[ "$current_wt" != "$main_wt" ]]; then
    worktree="$current_wt"
  else
    if ! lwt::deps::has fzf; then
      lwt::ui::error "fzf is required to pick a worktree. Install with: brew install fzf"
      return 1
    fi

    worktree=$(lwt::worktree::display_rows | awk -F'\t' -v main="$main_wt" '$1 != main' | \
      fzf --ansi --height 40% --reverse --prompt="Rename worktree: " \
      --delimiter='\t' --with-nth=2.. | awk -F'\t' '{print $1}')
  fi

  [[ -z "$worktree" ]] && return 0

  local old_branch
  old_branch=$(git -C "$worktree" branch --show-current 2>/dev/null)

  if [[ -z "$old_branch" || "$old_branch" == "(detached)" ]]; then
    lwt::ui::error "Cannot rename a detached HEAD worktree."
    return 1
  fi

  if [[ "$old_branch" == "$LWT_DEFAULT_BRANCH" || "$old_branch" == "main" || "$old_branch" == "master" ]]; then
    lwt::ui::error "Cannot rename the default branch ($old_branch)."
    return 1
  fi

  local project base new_path
  project=$(basename "$main_wt")
  base="$main_wt/../.worktrees/$project"
  new_path="$base/$new_name"

  if [[ -e "$new_path" ]]; then
    lwt::ui::error "Target path already exists: $new_path"
    return 1
  fi

  local has_remote=false
  if git ls-remote --heads origin "$old_branch" 2>/dev/null | grep -q .; then
    has_remote=true
  fi

  # check for open PRs on this branch (relevant when renaming remote)
  local open_pr_count=0
  local has_gh=false
  if $has_remote; then
    lwt::status::init_gh_mode
    if [[ "$LWT_GH_MODE" == "ok" ]]; then
      has_gh=true
      open_pr_count=$(gh pr list --head "$old_branch" --state open --json number -q 'length' 2>/dev/null)
      [[ -z "$open_pr_count" ]] && open_pr_count=0
    fi
  fi

  # capture open PR details before any renaming (deletion auto-closes them)
  # GitHub has no API to change a PR's head branch, so we recreate PRs on the new branch
  local -a old_pr_nums=()
  local -A old_pr_urls=()
  if $has_gh && ((open_pr_count > 0)); then
    local n u
    while IFS=$'\t' read -r n u; do
      old_pr_nums+=("$n")
      old_pr_urls[$n]="$u"
    done < <(gh pr list --head "$old_branch" --state open --json number,url -q '.[] | "\(.number)\t\(.url)"' 2>/dev/null)
  fi

  lwt::ui::header "Rename worktree"
  echo "  ${_lwt_orange}${_lwt_bold}$old_branch${_lwt_reset} → ${_lwt_green}${_lwt_bold}$new_name${_lwt_reset}"
  echo "  ${_lwt_dim}$worktree${_lwt_reset}"
  if $has_remote; then
    echo "  Remote branch ${_lwt_bold}origin/$old_branch${_lwt_reset} will be renamed."
  fi
  echo
  lwt::ui::warn "Running AI agents will need to be restarted after renaming."
  if ((${#old_pr_nums[@]} > 0)); then
    local _n
    for _n in "${old_pr_nums[@]}"; do
      printf '  %s\e]8;;%s\e\\PR #%s\e]8;;\e\\ will be closed — you can recreate it on the new branch.%s\n' \
        "$_lwt_dim" "${old_pr_urls[$_n]}" "$_n" "$_lwt_reset"
    done
  fi

  echo
  if ! read -rq "?Rename? [y/N] "; then
    echo
    return 0
  fi
  echo

  lwt::hooks::run "pre-rename" "$worktree" "$worktree" "$old_branch" \
    "LWT_MAIN_WORKTREE_PATH" "$main_wt" \
    "LWT_OLD_BRANCH" "$old_branch" \
    "LWT_NEW_BRANCH" "$new_name" \
    "LWT_NEW_WORKTREE_PATH" "$new_path" || return 1

  # rename the branch
  git branch -m "$old_branch" "$new_name" || return 1

  # move the worktree directory
  git worktree move "$worktree" "$new_path" || {
    # rollback branch rename on failure
    git branch -m "$new_name" "$old_branch" 2>/dev/null
    lwt::ui::error "Failed to move worktree directory."
    return 1
  }

  # if we were cd'd into the old worktree, cd into the new one
  if [[ "$current_wt" == "$worktree" ]]; then
    cd "$new_path" || return 1
  fi

  # handle remote branch
  if $has_remote; then
    git -C "$new_path" push origin "$new_name" >/dev/null 2>&1 \
      && git push origin --delete "$old_branch" >/dev/null 2>&1 \
      && git -C "$new_path" branch --set-upstream-to="origin/$new_name" "$new_name" >/dev/null 2>&1 \
      && lwt::ui::step "Renamed remote branch origin/$old_branch -> origin/$new_name"

    # offer to recreate captured PRs on the new branch (closed PRs are still readable)
    # default yes, but user may decline to preserve comments/reviews on the old PR
    if ((${#old_pr_nums[@]} > 0)); then
      local _n
      for _n in "${old_pr_nums[@]}"; do
        # OSC 8 clickable link for the PR
        printf '  %s\e]8;;%s\e\\PR #%s\e]8;;\e\\%s was closed by the branch deletion.\n' \
          "$_lwt_dim" "${old_pr_urls[$_n]}" "$_n" "$_lwt_reset"
      done
      local _recreate_reply
      read -rk 1 "_recreate_reply?Recreate on new branch? [Y/n] "
      echo
      if [[ "$_recreate_reply" != [nN] ]]; then
        local _pr_num _pr_title _pr_body _pr_base _new_pr_url
        for _pr_num in "${old_pr_nums[@]}"; do
          _pr_title=$(gh pr view "$_pr_num" --json title -q '.title' 2>/dev/null)
          _pr_body=$(gh pr view "$_pr_num" --json body -q '.body' 2>/dev/null)
          _pr_base=$(gh pr view "$_pr_num" --json baseRefName -q '.baseRefName' 2>/dev/null)
          _new_pr_url=$(gh pr create \
            --head "$new_name" \
            --base "${_pr_base:-$LWT_DEFAULT_BRANCH}" \
            --title "$_pr_title" \
            --body "$_pr_body" 2>/dev/null)
          if [[ -n "$_new_pr_url" ]]; then
            gh pr comment "$_pr_num" --body "Branch renamed to \`$new_name\`. Continued in $_new_pr_url" >/dev/null 2>&1
            # extract new PR number from URL (last path segment)
            local _new_pr_num="${_new_pr_url##*/}"
            printf '%s› Recreated \e]8;;%s\e\\PR #%s\e]8;;\e\\%s\n' \
              "$_lwt_dim" "$_new_pr_url" "$_new_pr_num" "$_lwt_reset"
          else
            lwt::ui::warn "Failed to recreate PR #$_pr_num on new branch."
          fi
        done
      else
        lwt::ui::hint "Old PR(s) were closed when the branch was deleted. You can reopen manually."
      fi
    fi
  fi

  lwt::hooks::run "post-rename" "$new_path" "$new_path" "$new_name" \
    "LWT_MAIN_WORKTREE_PATH" "$main_wt" \
    "LWT_OLD_BRANCH" "$old_branch" \
    "LWT_NEW_BRANCH" "$new_name" \
    "LWT_OLD_WORKTREE_PATH" "$worktree" \
    "LWT_NEW_WORKTREE_PATH" "$new_path" || return 1

  lwt::ui::success "Renamed worktree $old_branch -> $new_name."
}

lwt::cmd::doctor() {
  lwt::ui::header "lwt doctor"

  local in_repo=false
  if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    in_repo=true
    lwt::git::resolve_default_branch
    echo "Repository: $(git rev-parse --show-toplevel)"
    echo "Default branch: $LWT_DEFAULT_BRANCH (${LWT_DEFAULT_BASE_REF})"
  else
    echo "Repository: ${_lwt_dim}not in a git repository${_lwt_reset}"
  fi

  echo
  lwt::ui::header "Required tools"

  if lwt::deps::has git; then
    echo "  ${_lwt_green}✓ git${_lwt_reset}"
  else
    echo "  ${_lwt_red}✗ git${_lwt_reset}"
    lwt::ui::hint "    Install: https://git-scm.com/downloads"
  fi

  if lwt::deps::has fzf; then
    echo "  ${_lwt_green}✓ fzf${_lwt_reset}"
  else
    echo "  ${_lwt_red}✗ fzf${_lwt_reset}"
    lwt::ui::hint "    Install: brew install fzf"
  fi

  echo
  lwt::ui::header "Optional tools"

  if lwt::deps::has gh; then
    if gh auth status -h github.com >/dev/null 2>&1; then
      echo "  ${_lwt_green}✓ gh (authenticated)${_lwt_reset}"
    else
      echo "  ${_lwt_yellow}⚠ gh (not authenticated)${_lwt_reset}"
      lwt::ui::hint "    Run: gh auth login"
    fi
  else
    echo "  ${_lwt_yellow}⚠ gh${_lwt_reset}"
    lwt::ui::hint "    Install: brew install gh"
    lwt::ui::hint "    Needed for squash-merge detection"
  fi

  local agent
  while IFS= read -r agent; do
    if lwt::deps::has "$agent"; then
      echo "  ${_lwt_green}✓ $agent${_lwt_reset}"
    else
      echo "  ${_lwt_dim}- $agent not found${_lwt_reset}"
    fi
  done < <(lwt::agent::supported_list)

  if [[ "$(uname -s)" == "Darwin" ]] && lwt::deps::has osascript; then
    echo "  ${_lwt_green}✓ osascript${_lwt_reset}"
  else
    echo "  ${_lwt_dim}- osascript not available${_lwt_reset}"
  fi

  echo
  lwt::ui::header "Settings"

  local resolved_editor
  resolved_editor=$(lwt::editor::resolve 2>/dev/null)
  if [[ -n "$resolved_editor" ]]; then
    echo "  ${_lwt_green}✓ editor${_lwt_reset} $resolved_editor"
  else
    echo "  ${_lwt_dim}- editor not set${_lwt_reset}"
    lwt::ui::hint "    Set with: lwt config set editor zed"
  fi

  local agent_mode
  agent_mode=$(lwt::config::get_effective "agent-mode" 2>/dev/null)
  echo "  ${_lwt_green}✓ agent-mode${_lwt_reset} ${agent_mode:-interactive}"

  local dev_cmd
  dev_cmd=$(lwt::config::get_raw "dev-cmd" 2>/dev/null)
  if [[ -n "$dev_cmd" ]]; then
    echo "  ${_lwt_green}✓ dev-cmd${_lwt_reset} $dev_cmd"
  else
    echo "  ${_lwt_dim}- dev-cmd auto-detect (default)${_lwt_reset}"
  fi

  local terminal_driver
  terminal_driver=$(lwt::terminal::resolve_driver 2>/dev/null)
  if [[ -n "$terminal_driver" ]]; then
    echo "  ${_lwt_green}✓ terminal${_lwt_reset} $terminal_driver"
  else
    echo "  ${_lwt_dim}- terminal automation unavailable or unsupported${_lwt_reset}"
  fi

  if $in_repo; then
    local merge_target
    merge_target=$(lwt::config::get_effective "merge-target" 2>/dev/null)
    echo "  ${_lwt_green}✓ merge-target${_lwt_reset} ${merge_target:-$LWT_DEFAULT_BRANCH}"
  fi

  echo
  lwt::ui::header "Hooks"

  local user_hook_dir user_hook_count
  user_hook_dir=$(lwt::hooks::user_dir)
  user_hook_count=$(lwt::hooks::count_for_root "$user_hook_dir")
  if [[ -d "$user_hook_dir" ]]; then
    echo "  ${_lwt_green}✓ user-hooks${_lwt_reset} $user_hook_dir (${user_hook_count})"
  else
    echo "  ${_lwt_dim}- user-hooks not set${_lwt_reset}"
    lwt::ui::hint "    Create: $user_hook_dir"
  fi

  if $in_repo; then
    local repo_hook_dir repo_hook_count
    repo_hook_dir="$(git rev-parse --show-toplevel)/.lwt/hooks"
    repo_hook_count=$(lwt::hooks::count_for_root "$repo_hook_dir")
    if [[ -d "$repo_hook_dir" ]]; then
      echo "  ${_lwt_green}✓ repo-hooks${_lwt_reset} $repo_hook_dir (${repo_hook_count})"
    else
      echo "  ${_lwt_dim}- repo-hooks not set${_lwt_reset}"
      lwt::ui::hint "    Create: $repo_hook_dir"
    fi
  fi
}

lwt::dispatch() {
  local cmd="${1:-help}"
  (( $# > 0 )) && shift

  LWT_GH_MODE=""
  LWT_GH_NOTICE_PRINTED=0

  case "$cmd" in
    add|a)
      lwt::git::ensure_repo || return 1
      lwt::git::resolve_default_branch
      lwt::cmd::add "$@"
      ;;
    checkout|co)
      lwt::git::ensure_repo || return 1
      lwt::git::resolve_default_branch
      lwt::cmd::checkout "$@"
      ;;
    switch|s)
      lwt::git::ensure_repo || return 1
      lwt::git::resolve_default_branch
      lwt::cmd::switch "$@"
      ;;
    list|ls)
      lwt::git::ensure_repo || return 1
      lwt::git::resolve_default_branch
      lwt::cmd::list "$@"
      ;;
    merge)
      lwt::git::ensure_repo || return 1
      lwt::git::resolve_default_branch
      lwt::cmd::merge "$@"
      ;;
    remove|rm)
      lwt::git::ensure_repo || return 1
      lwt::git::resolve_default_branch
      lwt::cmd::remove "$@"
      ;;
    clean)
      lwt::git::ensure_repo || return 1
      lwt::git::resolve_default_branch
      lwt::cmd::clean "$@"
      ;;
    rename|rn)
      lwt::git::ensure_repo || return 1
      lwt::git::resolve_default_branch
      lwt::cmd::rename "$@"
      ;;
    config|cfg)
      lwt::cmd::config "$@"
      ;;
    hook)
      lwt::git::ensure_repo || return 1
      lwt::git::resolve_default_branch
      lwt::cmd::hook "$@"
      ;;
    doctor)
      lwt::cmd::doctor "$@"
      ;;
    help|-h|--help)
      case "$1" in
        automation|agent|agents|noninteractive)
          lwt::ui::help_automation
          ;;
        add|a)
          lwt::ui::help_add
          ;;
        checkout|co)
          lwt::ui::help_checkout
          ;;
        switch|s)
          lwt::ui::help_switch
          ;;
        list|ls)
          lwt::ui::help_list
          ;;
        merge)
          lwt::ui::help_merge
          ;;
        remove|rm)
          lwt::ui::help_remove
          ;;
        clean)
          lwt::ui::help_clean
          ;;
        rename|rn)
          lwt::ui::help_rename
          ;;
        config|cfg)
          lwt::ui::help_config
          ;;
        hook)
          lwt::ui::help_hook
          ;;
        doctor)
          lwt::ui::help_doctor
          ;;
        "")
          lwt::ui::help_main
          ;;
        *)
          lwt::ui::error "Unknown help topic: $1"
          return 1
          ;;
      esac
      ;;
    *)
      lwt::ui::error "Unknown command: $cmd"
      lwt::ui::hint "Run: lwt help"
      lwt::ui::hint "Automation examples: lwt help automation"
      return 1
      ;;
  esac
}
