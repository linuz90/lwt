# shellcheck shell=bash
# Light Worktrees (lwt) — opinionated git worktree management
#
# https://github.com/linuz90/lwt
#
# Usage: source this file from your shell profile
#   source /path/to/lwt.sh
#
# Commands:
#   lwt add [name] [-e] [--editor-cmd "cmd"] [-claude|-codex|-gemini "prompt"]
#   lwt switch [query] [-e] [--editor-cmd "cmd"]
#   lwt list
#   lwt remove [query]
#   lwt clean [-n]
#   lwt rename <new-name>
#   lwt doctor
#   lwt help [command]

# Colors
_lwt_red=$'\033[1;31m'
_lwt_green=$'\033[32m'
_lwt_yellow=$'\033[33m'
_lwt_orange=$'\033[38;5;208m'
_lwt_dim=$'\033[2m'
_lwt_bold=$'\033[1m'
_lwt_reset=$'\033[0m'

typeset -g LWT_DEFAULT_BRANCH=""
typeset -g LWT_DEFAULT_BASE_REF=""
typeset -g LWT_GH_MODE=""
typeset -g LWT_GH_NOTICE_PRINTED=0

lwt::deps::has() {
  command -v "$1" >/dev/null 2>&1
}

lwt::ui::error() {
  echo "${_lwt_red}✗ $*${_lwt_reset}" >&2
}

lwt::ui::warn() {
  echo "${_lwt_yellow}⚠ $*${_lwt_reset}" >&2
}

lwt::ui::hint() {
  echo "  ${_lwt_dim}$*${_lwt_reset}" >&2
}

lwt::ui::header() {
  echo "${_lwt_bold}$*${_lwt_reset}"
}

lwt::ui::success() {
  echo "${_lwt_green}✓ $*${_lwt_reset}"
}

lwt::ui::step() {
  echo "${_lwt_dim}› $*${_lwt_reset}"
}

lwt::git::ensure_repo() {
  if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    lwt::ui::error "Not inside a Git repository."
    return 1
  fi
}

lwt::git::resolve_default_branch() {
  local origin_head
  origin_head=$(git symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null)

  if [[ -n "$origin_head" ]]; then
    LWT_DEFAULT_BRANCH="${origin_head#origin/}"
  elif git show-ref --verify --quiet refs/heads/main || git show-ref --verify --quiet refs/remotes/origin/main; then
    LWT_DEFAULT_BRANCH="main"
  elif git show-ref --verify --quiet refs/heads/master || git show-ref --verify --quiet refs/remotes/origin/master; then
    LWT_DEFAULT_BRANCH="master"
  else
    LWT_DEFAULT_BRANCH=$(git branch --show-current 2>/dev/null)
  fi

  [[ -z "$LWT_DEFAULT_BRANCH" ]] && LWT_DEFAULT_BRANCH="main"

  if git show-ref --verify --quiet "refs/remotes/origin/$LWT_DEFAULT_BRANCH"; then
    LWT_DEFAULT_BASE_REF="origin/$LWT_DEFAULT_BRANCH"
  elif git show-ref --verify --quiet "refs/heads/$LWT_DEFAULT_BRANCH"; then
    LWT_DEFAULT_BASE_REF="$LWT_DEFAULT_BRANCH"
  else
    LWT_DEFAULT_BASE_REF="HEAD"
  fi
}

lwt::git::fetch_if_stale() {
  local git_dir threshold_sec="${1:-60}"
  git_dir="$(git rev-parse --git-dir 2>/dev/null)" || return 0

  local fetch_head="$git_dir/FETCH_HEAD"
  if [[ -f "$fetch_head" ]]; then
    local now last_fetch age
    now=$(date +%s)
    last_fetch=$(stat -f %m "$fetch_head" 2>/dev/null) || last_fetch=0
    age=$(( now - last_fetch ))
    (( age < threshold_sec )) && return 0
  fi

  git fetch --all --quiet 2>/dev/null
}

lwt::worktree::records() {
  local line wt_path="" branch=""

  while IFS= read -r line || [[ -n "$line" ]]; do
    if [[ -z "$line" ]]; then
      if [[ -n "$wt_path" ]]; then
        [[ -z "$branch" ]] && branch="(detached)"
        printf '%s\t%s\n' "$wt_path" "$branch"
      fi
      wt_path=""
      branch=""
      continue
    fi

    case "$line" in
      worktree\ *)
        wt_path="${line#worktree }"
        ;;
      branch\ refs/heads/*)
        branch="${line#branch refs/heads/}"
        ;;
      branch\ *)
        branch="${line#branch }"
        ;;
      detached)
        branch="(detached)"
        ;;
    esac
  done < <(git worktree list --porcelain)

  if [[ -n "$wt_path" ]]; then
    [[ -z "$branch" ]] && branch="(detached)"
    printf '%s\t%s\n' "$wt_path" "$branch"
  fi
}

lwt::worktree::main_path() {
  local first
  first=$(lwt::worktree::records | head -n 1)
  [[ -z "$first" ]] && return 1
  printf '%s\n' "${first%%$'\t'*}"
}

lwt::status::init_gh_mode() {
  if [[ -n "$LWT_GH_MODE" ]]; then
    return 0
  fi

  if ! lwt::deps::has gh; then
    LWT_GH_MODE="missing"
    return 0
  fi

  if gh auth status -h github.com >/dev/null 2>&1; then
    LWT_GH_MODE="ok"
  else
    LWT_GH_MODE="unauthenticated"
  fi
}

lwt::status::warn_gh_limitations() {
  lwt::status::init_gh_mode

  if ((LWT_GH_NOTICE_PRINTED)); then
    return 0
  fi

  case "$LWT_GH_MODE" in
    missing)
      lwt::ui::warn "gh is not installed; squash-merge detection is unavailable."
      lwt::ui::hint "Install gh: brew install gh"
      ;;
    unauthenticated)
      lwt::ui::warn "gh is not authenticated; squash-merge detection is unavailable."
      lwt::ui::hint "Run: gh auth login"
      ;;
  esac

  LWT_GH_NOTICE_PRINTED=1
}

lwt::status::is_merged() {
  local branch="$1"
  [[ -z "$branch" || "$branch" == "(detached)" ]] && return 1
  [[ "$branch" == "$LWT_DEFAULT_BRANCH" || "$branch" == "main" || "$branch" == "master" ]] && return 1

  local ahead
  ahead=$(git rev-list --count "${LWT_DEFAULT_BASE_REF}..$branch" 2>/dev/null)
  [[ -z "$ahead" || "$ahead" == "0" ]] && return 1

  if git merge-base --is-ancestor "$branch" "$LWT_DEFAULT_BASE_REF" 2>/dev/null; then
    return 0
  fi

  lwt::status::init_gh_mode
  if [[ "$LWT_GH_MODE" != "ok" ]]; then
    return 1
  fi

  local merged_count
  merged_count=$(gh pr list --head "$branch" --state merged --json number -q 'length' 2>/dev/null)
  [[ "$merged_count" -gt 0 ]] 2>/dev/null
}

lwt::status::for_worktree() {
  local dir="$1"
  local branch="$2"
  local changed
  local unpushed=0
  local behind=0
  local merged=false

  changed=$(git -C "$dir" status --porcelain 2>/dev/null | wc -l | tr -d ' ')

  if git -C "$dir" rev-parse --abbrev-ref '@{upstream}' >/dev/null 2>&1; then
    unpushed=$(git -C "$dir" rev-list --count '@{upstream}..HEAD' 2>/dev/null)
    behind=$(git -C "$dir" rev-list --count 'HEAD..@{upstream}' 2>/dev/null)
  fi

  if lwt::status::is_merged "$branch"; then
    merged=true
    printf ' %s✓ merged%s' "$_lwt_green" "$_lwt_reset"
  fi

  ((changed > 0)) && printf ' %s⚠ %d changed%s' "$_lwt_yellow" "$changed" "$_lwt_reset"

  if ! $merged; then
    ((unpushed > 0)) && printf ' %s⚠ %d unpushed%s' "$_lwt_yellow" "$unpushed" "$_lwt_reset"
    ((behind > 0)) && printf ' %s↓ %d behind%s' "$_lwt_dim" "$behind" "$_lwt_reset"
  fi

  # show open PR number if pre-fetched data is available (via LWT_OPEN_PRS_FILE)
  # file format: branch_name\tPR #N\turl (one per line)
  if [[ -n "$LWT_OPEN_PRS_FILE" && -s "$LWT_OPEN_PRS_FILE" ]]; then
    local _pr_label _pr_url _pr_line
    _pr_line=$(awk -F'\t' -v b="$branch" '$1 == b { print $2 "\t" $3; exit }' "$LWT_OPEN_PRS_FILE" 2>/dev/null)
    if [[ -n "$_pr_line" ]]; then
      _pr_label="${_pr_line%%$'\t'*}"
      _pr_url="${_pr_line#*$'\t'}"
      # OSC 8 hyperlink: clickable in supported terminals (iTerm2, Ghostty, etc.)
      printf ' %s\e]8;;%s\e\\%s\e]8;;\e\\%s' "$_lwt_dim" "$_pr_url" "$_pr_label" "$_lwt_reset"
    fi
  fi
}

lwt::worktree::display_rows() {
  setopt local_options no_bg_nice

  local current_dir main_dir tmpdir
  local -a records
  local record wt_path branch
  local idx=1

  lwt::git::fetch_if_stale
  while IFS= read -r record; do
    records+=("$record")
  done < <(lwt::worktree::records)
  [[ ${#records[@]} -eq 0 ]] && return 1

  current_dir=$(git rev-parse --show-toplevel 2>/dev/null)
  main_dir="${records[1]%%$'\t'*}"
  tmpdir=$(mktemp -d)

  # batch-fetch all open PR head branches in a single API call (used by for_worktree)
  # runs before parallel subshells so the file is ready when they read it
  export LWT_OPEN_PRS_FILE="$tmpdir/_open_prs"
  touch "$LWT_OPEN_PRS_FILE"
  lwt::status::init_gh_mode
  if [[ "$LWT_GH_MODE" == "ok" ]]; then
    gh pr list --state open --limit 100 --json headRefName,number,url -q '.[] | "\(.headRefName)\tPR #\(.number)\t\(.url)"' \
      > "$LWT_OPEN_PRS_FILE" 2>/dev/null
  fi

  for record in "${records[@]}"; do
    wt_path="${record%%$'\t'*}"
    branch="${record#*$'\t'}"

    (
      local marker="  "
      local label="$branch"
      local flags

      [[ "$wt_path" == "$current_dir" ]] && marker="* "
      [[ "$wt_path" == "$main_dir" ]] && label="$branch (repo)"
      flags=$(lwt::status::for_worktree "$wt_path" "$branch")

      printf '%s\t%s%s%s\n' "$wt_path" "$marker" "$label" "$flags" > "$tmpdir/$idx"
    ) &

    ((idx++))
  done

  wait

  local j
  for ((j = 1; j < idx; j++)); do
    [[ -f "$tmpdir/$j" ]] && cat "$tmpdir/$j"
  done

  rm -rf "$tmpdir"
  unset LWT_OPEN_PRS_FILE
}

lwt::editor::resolve() {
  local override="$1"
  if [[ -n "$override" ]]; then
    printf '%s\n' "$override"
    return 0
  fi

  local from_git
  from_git=$(git config --get lwt.editor 2>/dev/null)
  [[ -n "$from_git" ]] && {
    printf '%s\n' "$from_git"
    return 0
  }

  [[ -n "$LWT_EDITOR" ]] && {
    printf '%s\n' "$LWT_EDITOR"
    return 0
  }

  [[ -n "$VISUAL" ]] && {
    printf '%s\n' "$VISUAL"
    return 0
  }

  [[ -n "$EDITOR" ]] && {
    printf '%s\n' "$EDITOR"
    return 0
  }

  return 1
}

lwt::editor::open() {
  local target="$1"
  local override="$2"
  local editor_cmd

  editor_cmd=$(lwt::editor::resolve "$override") || {
    lwt::ui::hint "No editor configured. Set one with: git config --global lwt.editor \"zed\""
    lwt::ui::hint "Or set LWT_EDITOR, VISUAL, or EDITOR."
    return 0
  }
  if [[ -z "$editor_cmd" ]]; then
    lwt::ui::warn "Editor configuration is empty."
    return 0
  fi

  local -a cmd_parts
  # zsh-aware shell-like splitting for editor commands such as: code -n
  # shellcheck disable=SC2296
  cmd_parts=("${(z)editor_cmd}")
  if [[ ${#cmd_parts[@]} -eq 0 ]]; then
    lwt::ui::warn "Editor configuration is empty."
    return 0
  fi

  "${cmd_parts[@]}" "$target"
}

lwt::utils::random_branch_name() {
  local -a adjectives=(
    swift calm bold warm cool keen slim fast bright sharp
    clear fresh light quick deep still free wild pure raw
    soft dry flat low neat pale wide dark loud prime
    kind lean true firm safe held rare long next broad
    crisp snug taut dense brisk vivid deft wry agile lucid
  )
  local -a nouns=(
    fox owl elk jay ram bee ant koi yak emu
    oak ash elm bay cove dale reef vale glen moor
    jade onyx ruby flint pearl dusk dawn haze mist glow
    hawk lynx pike wren tern lark colt mare fawn hare
    gust tide surf wave crest blaze spark drift bloom frost
  )
  local adj noun candidate

  # try up to 10 times to find a name not already taken
  local i
  for i in {1..10}; do
    adj="${adjectives[$((RANDOM % ${#adjectives[@]} + 1))]}"
    noun="${nouns[$((RANDOM % ${#nouns[@]} + 1))]}"
    candidate="$adj-$noun"
    if ! git show-ref --verify --quiet "refs/heads/$candidate" 2>/dev/null; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done

  # fallback: append short random suffix
  printf '%s-%s\n' "$candidate" "$((RANDOM % 999))"
}

lwt::utils::copy_env_files() {
  local repo_root="$1"
  local target="$2"
  local env_count=0
  local file rel dest_dir

  while IFS= read -r -d '' file; do
    rel="${file#"$repo_root"/}"
    dest_dir="$target/$(dirname "$rel")"
    mkdir -p "$dest_dir"
    cp "$file" "$dest_dir/" && ((env_count++))
  done < <(find "$repo_root" -type f -name '.env*' -print0 2>/dev/null)

  if ((env_count > 0)); then
    local s="s"; ((env_count == 1)) && s=""
    lwt::ui::step "Copied $env_count .env file$s"
  fi
}

lwt::utils::install_dependencies() {
  if [[ -f "pnpm-lock.yaml" ]]; then
    lwt::ui::step "Installing dependencies..."
    pnpm install
  elif [[ -f "bun.lockb" || -f "bun.lock" ]]; then
    lwt::ui::step "Installing dependencies..."
    bun install
  elif [[ -f "yarn.lock" ]]; then
    lwt::ui::step "Installing dependencies..."
    yarn install
  elif [[ -f "package-lock.json" ]]; then
    lwt::ui::step "Installing dependencies..."
    npm install
  fi
}

lwt::agent::launch() {
  local agent="$1"
  local prompt="$2"
  local yolo="$3"
  [[ -z "$agent" || -z "$prompt" ]] && return 0

  if ! lwt::deps::has "$agent"; then
    lwt::ui::warn "$agent is not installed; skipping AI launch."
    return 0
  fi

  # Resolve yolo mode: flag > git config > default (off)
  if [[ "$yolo" != "true" ]]; then
    local configured
    configured=$(git config --get lwt.agent-mode 2>/dev/null)
    [[ "$configured" == "yolo" ]] && yolo=true
  fi

  lwt::ui::step "Launching $agent..."
  case "$agent" in
    claude)
      if [[ "$yolo" == "true" ]]; then
        claude --dangerously-skip-permissions "$prompt"
      else
        claude "$prompt"
      fi
      ;;
    codex)
      if [[ "$yolo" == "true" ]]; then
        codex --yolo "$prompt"
      else
        codex "$prompt"
      fi
      ;;
    gemini)
      if [[ "$yolo" == "true" ]]; then
        gemini --yolo "$prompt"
      else
        gemini "$prompt"
      fi
      ;;
  esac
}

lwt::ui::help_main() {
  echo "${_lwt_bold}Usage:${_lwt_reset} lwt <command> [options]"
  echo
  lwt::ui::header "Commands"
  echo "  ${_lwt_bold}add, a${_lwt_reset}       ${_lwt_dim}Create or check out a worktree branch${_lwt_reset}"
  echo "  ${_lwt_bold}switch, s${_lwt_reset}    ${_lwt_dim}Switch to a worktree via fzf${_lwt_reset}"
  echo "  ${_lwt_bold}list, ls${_lwt_reset}     ${_lwt_dim}List worktrees with live status${_lwt_reset}"
  echo "  ${_lwt_bold}remove, rm${_lwt_reset}   ${_lwt_dim}Remove a worktree safely${_lwt_reset}"
  echo "  ${_lwt_bold}clean${_lwt_reset}        ${_lwt_dim}Remove all merged worktrees at once${_lwt_reset}"
  echo "  ${_lwt_bold}rename, rn${_lwt_reset}   ${_lwt_dim}Rename a worktree and its branch${_lwt_reset}"
  echo "  ${_lwt_bold}doctor${_lwt_reset}       ${_lwt_dim}Check required and optional tooling${_lwt_reset}"
  echo "  ${_lwt_bold}help${_lwt_reset}         ${_lwt_dim}Show command help${_lwt_reset}"
  echo
  lwt::ui::header "Examples"
  echo "  lwt a my-feature                           ${_lwt_dim}Create a new worktree${_lwt_reset}"
  echo "  lwt a my-feature -e                        ${_lwt_dim}Create and open in editor${_lwt_reset}"
  echo "  lwt a my-feature -s                        ${_lwt_dim}Create and install dependencies${_lwt_reset}"
  echo "  lwt a my-feature -claude \"fix...\"          ${_lwt_dim}Create and launch an agent${_lwt_reset}"
  echo "  lwt a my-feature -yolo -claude \"fix...\"    ${_lwt_dim}Launch agent with full auto-approve${_lwt_reset}"
  echo "  lwt s                                      ${_lwt_dim}Switch worktree with fzf${_lwt_reset}"
  echo "  lwt ls                                     ${_lwt_dim}List all worktrees${_lwt_reset}"
  echo "  lwt rm                                     ${_lwt_dim}Pick and remove a worktree${_lwt_reset}"
  echo
  lwt::ui::header "Config"
  echo "  git config --global lwt.editor code         ${_lwt_dim}Editor to open worktrees in${_lwt_reset}"
  echo "  git config --global lwt.agent-mode yolo     ${_lwt_dim}Auto-approve all agent actions${_lwt_reset}"
}

lwt::ui::help_add() {
  echo "${_lwt_bold}Usage:${_lwt_reset} lwt add [branch] [options]"
  echo
  lwt::ui::header "Options"
  echo "  ${_lwt_bold}-s, --setup${_lwt_reset}            ${_lwt_dim}Install dependencies after creating the worktree${_lwt_reset}"
  echo "  ${_lwt_bold}-e, --editor${_lwt_reset}           ${_lwt_dim}Open the worktree in your editor${_lwt_reset}"
  echo "  ${_lwt_bold}--editor-cmd \"cmd\"${_lwt_reset}     ${_lwt_dim}Override editor command for this run${_lwt_reset}"
  echo "  ${_lwt_bold}-claude \"prompt\"${_lwt_reset}       ${_lwt_dim}Launch Claude after setup${_lwt_reset}"
  echo "  ${_lwt_bold}-codex \"prompt\"${_lwt_reset}        ${_lwt_dim}Launch Codex after setup${_lwt_reset}"
  echo "  ${_lwt_bold}-gemini \"prompt\"${_lwt_reset}       ${_lwt_dim}Launch Gemini after setup${_lwt_reset}"
  echo "  ${_lwt_bold}-yolo${_lwt_reset}                  ${_lwt_dim}Give the agent full auto-approve permissions${_lwt_reset}"
  echo "  ${_lwt_bold}-h, --help${_lwt_reset}             ${_lwt_dim}Show help${_lwt_reset}"
  echo
  lwt::ui::header "Notes"
  echo "  ${_lwt_dim}If branch is omitted, lwt generates a random branch name.${_lwt_reset}"
  echo "  ${_lwt_dim}New branches are created from the resolved default branch.${_lwt_reset}"
  echo "  ${_lwt_dim}When an agent flag is used, dependencies are always installed.${_lwt_reset}"
  echo "  ${_lwt_dim}Set yolo globally with: git config --global lwt.agent-mode yolo${_lwt_reset}"
}

lwt::ui::help_switch() {
  echo "${_lwt_bold}Usage:${_lwt_reset} lwt switch [query] [options]"
  echo
  lwt::ui::header "Options"
  echo "  ${_lwt_bold}-e, --editor${_lwt_reset}           ${_lwt_dim}Open selected worktree in your editor${_lwt_reset}"
  echo "  ${_lwt_bold}--editor-cmd \"cmd\"${_lwt_reset}     ${_lwt_dim}Override editor command for this run${_lwt_reset}"
  echo "  ${_lwt_bold}-h, --help${_lwt_reset}             ${_lwt_dim}Show help${_lwt_reset}"
}

lwt::ui::help_list() {
  echo "${_lwt_bold}Usage:${_lwt_reset} lwt list"
  echo
  echo "  ${_lwt_dim}Shows all worktrees with remote-aware status.${_lwt_reset}"
}

lwt::ui::help_remove() {
  echo "${_lwt_bold}Usage:${_lwt_reset} lwt remove [query]"
  echo
  echo "  ${_lwt_dim}If called inside a linked worktree, that worktree is selected automatically.${_lwt_reset}"
  echo "  ${_lwt_dim}Otherwise an fzf picker is shown.${_lwt_reset}"
}

lwt::ui::help_clean() {
  echo "${_lwt_bold}Usage:${_lwt_reset} lwt clean [options]"
  echo
  echo "  ${_lwt_dim}Finds all merged worktrees and removes them in one go.${_lwt_reset}"
  echo
  lwt::ui::header "Options"
  echo "  ${_lwt_bold}-n, --dry-run${_lwt_reset}    ${_lwt_dim}Show what would be removed without deleting anything${_lwt_reset}"
  echo "  ${_lwt_bold}-h, --help${_lwt_reset}       ${_lwt_dim}Show help${_lwt_reset}"
  echo
  lwt::ui::header "Notes"
  echo "  ${_lwt_dim}Uses the same merge detection as lwt list (including squash-merge via gh).${_lwt_reset}"
  echo "  ${_lwt_dim}Skips the main repository worktree.${_lwt_reset}"
  echo "  ${_lwt_dim}Prompts for confirmation before deleting unless --dry-run is set.${_lwt_reset}"
}

lwt::ui::help_rename() {
  echo "${_lwt_bold}Usage:${_lwt_reset} lwt rename <new-name>"
  echo
  echo "  ${_lwt_dim}Renames a worktree's branch and moves its directory to match.${_lwt_reset}"
  echo
  echo "  ${_lwt_dim}If called inside a linked worktree, that worktree is selected automatically.${_lwt_reset}"
  echo "  ${_lwt_dim}Otherwise an fzf picker is shown.${_lwt_reset}"
  echo
  lwt::ui::header "Options"
  echo "  ${_lwt_bold}-h, --help${_lwt_reset}    ${_lwt_dim}Show help${_lwt_reset}"
  echo
  lwt::ui::header "Notes"
  echo "  ${_lwt_dim}The main repository worktree cannot be renamed.${_lwt_reset}"
  echo "  ${_lwt_dim}If a remote branch exists, it will be renamed automatically.${_lwt_reset}"
  echo "  ${_lwt_dim}Open PRs are recreated on the new branch when gh is available.${_lwt_reset}"
  echo "  ${_lwt_dim}If an AI agent is running in the worktree, it will need to be restarted.${_lwt_reset}"
}

lwt::ui::help_doctor() {
  echo "${_lwt_bold}Usage:${_lwt_reset} lwt doctor"
  echo
  echo "  ${_lwt_dim}Checks required dependencies and optional integrations.${_lwt_reset}"
}

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

lwt::cmd::add() {
  local branch=""
  local agent=""
  local prompt=""
  local open_editor=false
  local run_setup=false
  local yolo=false
  local editor_override=""

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
      -claude)
        agent="claude"
        ;;
      -codex)
        agent="codex"
        ;;
      -gemini)
        agent="gemini"
        ;;
      --)
        shift
        prompt="$*"
        break
        ;;
      -*)
        if [[ -n "$agent" ]]; then
          prompt="$prompt${prompt:+ }$1"
        else
          lwt::ui::error "Unknown option: $1"
          return 1
        fi
        ;;
      *)
        if [[ -n "$agent" ]]; then
          prompt="$prompt${prompt:+ }$1"
        elif [[ -z "$branch" ]]; then
          branch="$1"
        else
          prompt="$prompt${prompt:+ }$1"
        fi
        ;;
    esac
    shift
  done

  if [[ -z "$branch" ]]; then
    branch=$(lwt::utils::random_branch_name)
  fi

  if [[ -z "$agent" && -n "$prompt" ]]; then
    lwt::ui::error "Unexpected trailing arguments: $prompt"
    lwt::ui::hint "Use one of -claude/-codex/-gemini when passing a prompt."
    return 1
  fi

  local repo_root project base target
  repo_root=$(lwt::worktree::main_path) || return 1
  project=$(basename "$repo_root")
  base="$repo_root/../.worktrees/$project"
  target="$base/$branch"

  if [[ -e "$target" ]]; then
    lwt::ui::error "Target path already exists: $target"
    return 1
  fi

  mkdir -p "$base"
  lwt::git::fetch_if_stale

  local start_ref="$LWT_DEFAULT_BASE_REF"
  git rev-parse --verify "$start_ref" >/dev/null 2>&1 || start_ref="HEAD"

  local git_err
  if git show-ref --verify --quiet "refs/heads/$branch" 2>/dev/null; then
    if ! read -rq "?Branch $branch exists locally. Check out into a worktree? [y/N] "; then
      echo
      return 1
    fi
    echo
    git_err=$(git worktree add "$target" "$branch" 2>&1) || {
      lwt::ui::error "Failed to create worktree."
      lwt::ui::hint "$git_err"
      return 1
    }
    lwt::ui::step "Checked out existing branch ${_lwt_bold}$branch${_lwt_reset}"
  elif git show-ref --verify --quiet "refs/remotes/origin/$branch" 2>/dev/null; then
    if ! read -rq "?Branch $branch exists on origin. Check out into a worktree? [y/N] "; then
      echo
      return 1
    fi
    echo
    git_err=$(git worktree add --track -b "$branch" "$target" "origin/$branch" 2>&1) || {
      lwt::ui::error "Failed to create worktree."
      lwt::ui::hint "$git_err"
      return 1
    }
    lwt::ui::step "Checked out existing branch ${_lwt_bold}$branch${_lwt_reset}${_lwt_dim} from origin"
  else
    git_err=$(git worktree add -b "$branch" "$target" "$start_ref" 2>&1) || {
      lwt::ui::error "Failed to create worktree."
      lwt::ui::hint "$git_err"
      return 1
    }
    lwt::ui::step "Created branch ${_lwt_bold}$branch${_lwt_reset}${_lwt_dim} from ${LWT_DEFAULT_BASE_REF}"
  fi

  lwt::utils::copy_env_files "$repo_root" "$target"

  cd "$target" || return 1

  if $run_setup || [[ -n "$agent" ]]; then
    lwt::utils::install_dependencies
  fi

  lwt::ui::success "Created worktree ${branch}."

  if $open_editor; then
    lwt::editor::open "$target" "$editor_override"
  fi

  lwt::agent::launch "$agent" "$prompt" "$yolo"
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

  # detect open PR (used for pre-deletion info and post-deletion cleanup)
  local _rm_pr_num="" _rm_pr_link=""
  lwt::status::init_gh_mode
  if [[ "$LWT_GH_MODE" == "ok" && -n "$branch" ]]; then
    local _rm_pr_raw
    _rm_pr_raw=$(gh pr list --head "$branch" --state open --json number,url -q '.[0] | "PR #\(.number)\t\(.url)"' 2>/dev/null)
    if [[ -n "$_rm_pr_raw" ]]; then
      _rm_pr_num="${_rm_pr_raw%%$'\t'*}"
      _rm_pr_link="${_rm_pr_raw#*$'\t'}"
      printf '  %s\e]8;;%s\e\\%s\e]8;;\e\\ is open on this branch.%s\n' \
        "$_lwt_dim" "$_rm_pr_link" "$_rm_pr_num" "$_lwt_reset"
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
    if [[ -n "$_rm_pr_num" ]]; then
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
  for agent in claude codex gemini; do
    if lwt::deps::has "$agent"; then
      echo "  ${_lwt_green}✓ $agent${_lwt_reset}"
    else
      echo "  ${_lwt_dim}- $agent not found${_lwt_reset}"
    fi
  done

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

lwt() {
  lwt::dispatch "$@"
}
