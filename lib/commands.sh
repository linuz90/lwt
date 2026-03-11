lwt::cmd::list() {
  lwt::status::warn_gh_limitations
  lwt::worktree::display_rows | cut -f2-
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
        lwt::ui::success "Created worktree ${ref}."
      fi
      ;;
    *)
      lwt::ui::error "Unknown selection type: $kind"
      return 1
      ;;
  esac

  cd "$dir" || return 1
  if $open_editor; then
    lwt::editor::open "$dir" "$editor_override"
  fi
}

lwt::cmd::add() {
  local branch=""
  local prompt=""
  local open_editor=false
  local run_setup=false
  local yolo=false
  local editor_override=""
  local trailing=""
  local prompt_target=""
  local prompt_target_index=0
  local agent_spec=""
  local normalized_agent=""
  local main_agent=""
  local terminal_driver=""
  local fallback_command=""
  local agent_name=""
  local session_prompt=""
  local session_command=""
  local session_label=""
  local -A requested_agents=()
  local -a agents=()
  local -a runnable_agents=()
  local -a missing_agents=()
  local -a parallel_agents=()
  local -a session_modes=()
  local -a session_kinds=()
  local -a session_payloads=()
  local -a session_prompts=()

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

        agent_spec=$(lwt::agent::normalize_spec "$2" 2>/dev/null) || {
          lwt::ui::error "Unsupported agent list: $2"
          lwt::ui::hint "Supported agents: claude, codex, gemini"
          return 1
        }

        while IFS= read -r normalized_agent; do
          [[ -n "$normalized_agent" ]] && requested_agents[$normalized_agent]=1
        done <<< "$agent_spec"

        prompt_target="main"
        shift
        ;;
      --agents=*)
        agent_spec=$(lwt::agent::normalize_spec "${1#--agents=}" 2>/dev/null) || {
          lwt::ui::error "Unsupported agent list: ${1#--agents=}"
          lwt::ui::hint "Supported agents: claude, codex, gemini"
          return 1
        }

        while IFS= read -r normalized_agent; do
          [[ -n "$normalized_agent" ]] && requested_agents[$normalized_agent]=1
        done <<< "$agent_spec"

        prompt_target="main"
        ;;
      --claude)
        requested_agents[claude]=1
        prompt_target="main"
        ;;
      --codex)
        requested_agents[codex]=1
        prompt_target="main"
        ;;
      --gemini)
        requested_agents[gemini]=1
        prompt_target="main"
        ;;
      --split)
        if [[ -z "$2" ]]; then
          lwt::ui::error "--split expects a command."
          return 1
        fi
        session_modes+=("split")
        session_kinds+=("command")
        session_payloads+=("$2")
        session_prompts+=("")
        shift
        ;;
      --split=*)
        session_modes+=("split")
        session_kinds+=("command")
        session_payloads+=("${1#--split=}")
        session_prompts+=("")
        ;;
      --tab)
        if [[ -z "$2" ]]; then
          lwt::ui::error "--tab expects a command."
          return 1
        fi
        session_modes+=("tab")
        session_kinds+=("command")
        session_payloads+=("$2")
        session_prompts+=("")
        shift
        ;;
      --tab=*)
        session_modes+=("tab")
        session_kinds+=("command")
        session_payloads+=("${1#--tab=}")
        session_prompts+=("")
        ;;
      --tab-dev)
        run_setup=true
        session_modes+=("tab")
        session_kinds+=("dev")
        session_payloads+=("")
        session_prompts+=("")
        ;;
      --tab-claude)
        run_setup=true
        session_modes+=("tab")
        session_kinds+=("agent")
        session_payloads+=("claude")
        session_prompts+=("")
        prompt_target="session"
        prompt_target_index="${#session_modes[@]}"
        ;;
      --tab-codex)
        run_setup=true
        session_modes+=("tab")
        session_kinds+=("agent")
        session_payloads+=("codex")
        session_prompts+=("")
        prompt_target="session"
        prompt_target_index="${#session_modes[@]}"
        ;;
      --tab-gemini)
        run_setup=true
        session_modes+=("tab")
        session_kinds+=("agent")
        session_payloads+=("gemini")
        session_prompts+=("")
        prompt_target="session"
        prompt_target_index="${#session_modes[@]}"
        ;;
      --split-dev)
        run_setup=true
        session_modes+=("split")
        session_kinds+=("dev")
        session_payloads+=("")
        session_prompts+=("")
        ;;
      --split-claude)
        run_setup=true
        session_modes+=("split")
        session_kinds+=("agent")
        session_payloads+=("claude")
        session_prompts+=("")
        prompt_target="session"
        prompt_target_index="${#session_modes[@]}"
        ;;
      --split-codex)
        run_setup=true
        session_modes+=("split")
        session_kinds+=("agent")
        session_payloads+=("codex")
        session_prompts+=("")
        prompt_target="session"
        prompt_target_index="${#session_modes[@]}"
        ;;
      --split-gemini)
        run_setup=true
        session_modes+=("split")
        session_kinds+=("agent")
        session_payloads+=("gemini")
        session_prompts+=("")
        prompt_target="session"
        prompt_target_index="${#session_modes[@]}"
        ;;
      --)
        shift
        while (( $# > 0 )); do
          if [[ "$prompt_target" == "main" ]]; then
            prompt="$prompt${prompt:+ }$1"
          elif [[ "$prompt_target" == "session" && "$prompt_target_index" -gt 0 ]]; then
            session_prompts[$prompt_target_index]="${session_prompts[$prompt_target_index]}${session_prompts[$prompt_target_index]:+ }$1"
          else
            trailing="$trailing${trailing:+ }$1"
          fi
          shift
        done
        break
        ;;
      --*)
        agent_spec=$(lwt::agent::normalize_spec "${1#--}" 2>/dev/null) || {
          lwt::ui::error "Unknown option: $1"
          return 1
        }

        while IFS= read -r normalized_agent; do
          [[ -n "$normalized_agent" ]] && requested_agents[$normalized_agent]=1
        done <<< "$agent_spec"

        prompt_target="main"
        ;;
      -*)
        lwt::ui::error "Unknown option: $1"
        return 1
        ;;
      *)
        if [[ "$prompt_target" == "main" ]]; then
          prompt="$prompt${prompt:+ }$1"
        elif [[ "$prompt_target" == "session" && "$prompt_target_index" -gt 0 ]]; then
          session_prompts[$prompt_target_index]="${session_prompts[$prompt_target_index]}${session_prompts[$prompt_target_index]:+ }$1"
        elif [[ -z "$branch" ]]; then
          branch="$1"
        else
          trailing="$trailing${trailing:+ }$1"
        fi
        ;;
    esac
    shift
  done

  if [[ -z "$branch" ]]; then
    branch=$(lwt::utils::random_branch_name)
  fi

  if [[ -n "$trailing" ]]; then
    lwt::ui::error "Unexpected trailing arguments: $trailing"
    lwt::ui::hint "Wrap commands in --split/--tab, or use an agent flag or --agents before a prompt."
    return 1
  fi

  while IFS= read -r normalized_agent; do
    [[ -n "${requested_agents[$normalized_agent]:-}" ]] && agents+=("$normalized_agent")
  done < <(lwt::agent::supported_list)

  lwt::worktree::create_branch "$branch" true true || return 1
  local target="$LWT_LAST_WORKTREE_PATH"
  [[ -z "$target" ]] && return 1

  cd "$target" || return 1

  if $run_setup || (( ${#agents[@]} > 0 )); then
    lwt::utils::install_dependencies
  fi

  lwt::ui::success "Created worktree ${branch}."

  if $open_editor; then
    lwt::editor::open "$target" "$editor_override"
  fi

  local resolved_yolo="$yolo"
  if [[ "$resolved_yolo" != "true" ]]; then
    local configured_agent_mode
    configured_agent_mode=$(git config --get lwt.agent-mode 2>/dev/null)
    [[ "$configured_agent_mode" == "yolo" ]] && resolved_yolo=true
  fi

  for agent_name in "${agents[@]}"; do
    if lwt::deps::has "$agent_name"; then
      runnable_agents+=("$agent_name")
    else
      missing_agents+=("$agent_name")
    fi
  done

  for agent_name in "${missing_agents[@]}"; do
    lwt::ui::warn "$agent_name is not installed; skipping AI launch."
  done

  if (( ${#session_modes[@]} > 0 || ${#agents[@]} > 1 )); then
    terminal_driver=$(lwt::terminal::resolve_driver 2>/dev/null) || {
      lwt::ui::warn "Terminal automation requested, but no supported terminal driver was detected."
      lwt::ui::hint "Supported today: Ghostty and iTerm2 on macOS."
      lwt::ui::hint "Set one explicitly with: git config lwt.terminal ghostty"
    }
  fi

  if (( ${#runnable_agents[@]} == 1 )); then
    main_agent="${runnable_agents[1]}"
    if (( ${#agents[@]} > 1 )); then
      lwt::ui::warn "Only ${main_agent} is available locally; launching it in the current shell."
    fi
  elif (( ${#runnable_agents[@]} > 1 )); then
    main_agent="${runnable_agents[1]}"

    if [[ -n "$terminal_driver" ]]; then
      parallel_agents=("${runnable_agents[@]:1}")
    else
      lwt::ui::warn "Parallel agent launch requested, but terminal automation is unavailable."
      lwt::ui::hint "Launching ${main_agent} in the current shell and printing commands for the rest."

      for agent_name in "${runnable_agents[@]}"; do
        [[ "$agent_name" == "$main_agent" ]] && continue

        fallback_command=$(lwt::agent::command_string "$agent_name" "$prompt" "$resolved_yolo") || continue
        lwt::ui::hint "Manual launch: cd $(lwt::shell::quote "$target") && $fallback_command"
      done
    fi
  fi

  local i mode kind payload
  for (( i = 1; i <= ${#session_modes[@]}; i++ )); do
    mode="${session_modes[$i]}"
    kind="${session_kinds[$i]}"
    payload="${session_payloads[$i]}"
    session_prompt="${session_prompts[$i]}"
    session_command=""
    session_label=""

    case "$kind" in
      command)
        session_command="$payload"
        session_label="${mode} command"
        ;;
      dev)
        if ! session_command=$(lwt::project::dev_command); then
          lwt::ui::warn "Couldn't resolve a dev command for ${branch}; skipping ${mode}."
          lwt::ui::hint "Set one with: git config lwt.dev-cmd \"pnpm --filter app dev\""
          continue
        fi
        session_label="dev server"
        ;;
      agent)
        if ! session_command=$(lwt::agent::command_string "$payload" "$session_prompt" "$resolved_yolo"); then
          lwt::ui::warn "$payload is not installed; skipping ${mode} launch."
          continue
        fi
        session_label="$payload"
        ;;
      *)
        continue
        ;;
    esac

    if [[ -z "$terminal_driver" ]]; then
      continue
    fi

    lwt::ui::step "Opening ${mode} for ${session_label}..."
    if ! lwt::terminal::launch "$terminal_driver" "$mode" "$target" "$session_command"; then
      lwt::ui::warn "Failed to open ${mode} for ${session_label}."
    fi
  done

  for agent_name in "${parallel_agents[@]}"; do
    session_command=$(lwt::agent::command_string "$agent_name" "$prompt" "$resolved_yolo") || continue

    lwt::ui::step "Opening split for ${agent_name}..."
    if ! lwt::terminal::launch "$terminal_driver" "split" "$target" "$session_command"; then
      lwt::ui::warn "Failed to open split for ${agent_name}."
    fi
  done

  lwt::agent::launch "$main_agent" "$prompt" "$yolo"
}

lwt::cmd::remove() {
  local query=""

  while (( $# > 0 )); do
    case "$1" in
      -h|--help)
        lwt::ui::help_remove
        return 0
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
    if ! lwt::deps::has fzf; then
      lwt::ui::error "fzf is required to pick a worktree. Install with: brew install fzf"
      return 1
    fi

    lwt::status::warn_gh_limitations

    worktree=$(lwt::worktree::display_rows | awk -F'\t' -v main="$main_wt" '$1 != main' | \
      fzf --ansi --height 40% --reverse --prompt="Remove worktree: " --query="$query" \
      --delimiter='\t' --with-nth=2.. | awk -F'\t' '{print $1}')
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

  if ! read -rq "?${_lwt_red}Delete worktree permanently? [y/N]${_lwt_reset} "; then
    echo
    return 0
  fi
  echo

  cd "$main_wt" || return 1

  if ! git worktree remove "$worktree" 2>/dev/null; then
    if ((changed > 0)); then
      if ! read -rq "?${_lwt_red}Worktree has local changes. Force remove and discard them? [y/N]${_lwt_reset} "; then
        echo
        return 0
      fi
      echo
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
    else
      lwt::ui::warn "Branch $branch has unmerged work."
      if read -rq "?${_lwt_red}Force delete local branch? [y/N]${_lwt_reset} "; then
        echo
        git branch -D "$branch" >/dev/null 2>&1 && lwt::ui::step "Deleted local branch $branch"
      else
        echo
        lwt::ui::hint "Kept branch $branch."
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
      if read -rq "?${_lwt_red}Close PR and delete remote branch? [y/N]${_lwt_reset} "; then
        echo
        gh pr close "${_rm_pr_num#PR #}" --delete-branch >/dev/null 2>&1 \
          && lwt::ui::step "Closed $_rm_pr_num and deleted remote branch origin/$branch" \
          || lwt::ui::warn "Failed to close PR or delete remote branch."
      else
        echo
      fi
    else
      # no open PR — just offer remote branch deletion
      printf '  Remote branch %sorigin/%s%s still exists.\n' "$_lwt_bold" "$branch" "$_lwt_reset"
      if read -rq "?${_lwt_red}Delete remote branch? [y/N]${_lwt_reset} "; then
        echo
        git push origin --delete "$branch" 2>/dev/null \
          && lwt::ui::step "Deleted remote branch origin/$branch"
      else
        echo
      fi
    fi
  fi

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
    lwt::ui::hint "    Set with: git config lwt.editor zed"
  fi

  local agent_mode
  agent_mode=$(git config --get lwt.agent-mode 2>/dev/null)
  if [[ -n "$agent_mode" ]]; then
    echo "  ${_lwt_green}✓ agent-mode${_lwt_reset} $agent_mode"
  else
    echo "  ${_lwt_dim}- agent-mode interactive (default)${_lwt_reset}"
  fi

  local dev_cmd
  dev_cmd=$(git config --get lwt.dev-cmd 2>/dev/null)
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
    doctor)
      lwt::cmd::doctor "$@"
      ;;
    help|-h|--help)
      case "$1" in
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
        remove|rm)
          lwt::ui::help_remove
          ;;
        clean)
          lwt::ui::help_clean
          ;;
        rename|rn)
          lwt::ui::help_rename
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
      return 1
      ;;
  esac
}
