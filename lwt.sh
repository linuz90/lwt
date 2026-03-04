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
  echo "${_lwt_red}Error:${_lwt_reset} $*" >&2
}

lwt::ui::warn() {
  echo "${_lwt_yellow}Warning:${_lwt_reset} $*" >&2
}

lwt::ui::hint() {
  echo "${_lwt_dim}$*${_lwt_reset}" >&2
}

lwt::ui::header() {
  echo "${_lwt_bold}$*${_lwt_reset}"
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

  ((env_count > 0)) && echo "Copied $env_count .env file(s)"
}

lwt::utils::install_dependencies() {
  if [[ -f "pnpm-lock.yaml" ]]; then
    echo "Running pnpm install..."
    pnpm install
  elif [[ -f "bun.lockb" || -f "bun.lock" ]]; then
    echo "Running bun install..."
    bun install
  elif [[ -f "yarn.lock" ]]; then
    echo "Running yarn install..."
    yarn install
  elif [[ -f "package-lock.json" ]]; then
    echo "Running npm install..."
    npm install
  fi
}

lwt::agent::launch() {
  local agent="$1"
  local prompt="$2"
  [[ -z "$agent" || -z "$prompt" ]] && return 0

  if ! lwt::deps::has "$agent"; then
    lwt::ui::warn "$agent is not installed; skipping AI launch."
    return 0
  fi

  echo "Launching $agent..."
  case "$agent" in
    claude)
      claude --dangerously-skip-permissions "$prompt"
      ;;
    codex)
      codex --full-auto "$prompt"
      ;;
    gemini)
      gemini -y "$prompt"
      ;;
  esac
}

lwt::ui::help_main() {
  cat <<'HELP'
Usage: lwt <command> [options]

Commands:
  add, a       Create or check out a worktree branch
  switch, s    Switch to a worktree via fzf
  list, ls     List worktrees with live status
  remove, rm   Remove a worktree safely
  clean        Remove all merged worktrees at once
  rename, rn   Rename a worktree and its branch
  doctor       Check required and optional tooling
  help         Show command help

Examples:
  lwt add my-feature
  lwt add -e my-feature
  lwt switch feat -e
  lwt list
  lwt remove
  lwt clean
  lwt rename new-name
  lwt doctor
HELP
}

lwt::ui::help_add() {
  cat <<'HELP'
Usage: lwt add [branch] [options]

Options:
  -s, --setup            Install dependencies after creating the worktree
  -e, --editor           Open the worktree in your editor
  --editor-cmd "cmd"     Override editor command for this run
  -claude "prompt"       Launch Claude after setup
  -codex "prompt"        Launch Codex after setup
  -gemini "prompt"       Launch Gemini after setup
  -h, --help             Show help

Notes:
  - If branch is omitted, lwt generates a random branch name.
  - New branches are created from the resolved default branch.
  - When an agent flag is used, dependencies are always installed.
HELP
}

lwt::ui::help_switch() {
  cat <<'HELP'
Usage: lwt switch [query] [options]

Options:
  -e, --editor           Open selected worktree in your editor
  --editor-cmd "cmd"     Override editor command for this run
  -h, --help             Show help
HELP
}

lwt::ui::help_list() {
  cat <<'HELP'
Usage: lwt list

Shows all worktrees with remote-aware status.
HELP
}

lwt::ui::help_remove() {
  cat <<'HELP'
Usage: lwt remove [query]

If called inside a linked worktree, that worktree is selected automatically.
Otherwise an fzf picker is shown.
HELP
}

lwt::ui::help_clean() {
  cat <<'HELP'
Usage: lwt clean [options]

Finds all merged worktrees and removes them in one go.

Options:
  -n, --dry-run    Show what would be removed without deleting anything
  -h, --help       Show help

Notes:
  - Uses the same merge detection as lwt list (including squash-merge via gh).
  - Skips the main repository worktree.
  - Prompts for confirmation before deleting unless --dry-run is set.
HELP
}

lwt::ui::help_rename() {
  cat <<'HELP'
Usage: lwt rename <new-name>

Renames a worktree's branch and moves its directory to match.

If called inside a linked worktree, that worktree is selected automatically.
Otherwise an fzf picker is shown.

Options:
  -h, --help    Show help

Notes:
  - The main repository worktree cannot be renamed.
  - If a remote branch exists, you'll be prompted to rename it too.
  - If an AI agent is running in the worktree, it will need to be restarted.
HELP
}

lwt::ui::help_doctor() {
  cat <<'HELP'
Usage: lwt doctor

Checks required dependencies and optional integrations.
HELP
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
        if [[ -z "$branch" ]]; then
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

  if git show-ref --verify --quiet "refs/heads/$branch" 2>/dev/null; then
    if ! read -rq "?Branch $branch exists locally. Check out into a worktree? [y/N] "; then
      echo
      return 1
    fi
    echo
    git worktree add "$target" "$branch" || return 1
  elif git show-ref --verify --quiet "refs/remotes/origin/$branch" 2>/dev/null; then
    if ! read -rq "?Branch $branch exists on origin. Check out into a worktree? [y/N] "; then
      echo
      return 1
    fi
    echo
    git worktree add --track -b "$branch" "$target" "origin/$branch" || return 1
  else
    git worktree add -b "$branch" "$target" "$start_ref" || return 1
  fi

  lwt::utils::copy_env_files "$repo_root" "$target"

  cd "$target" || return 1

  if $run_setup || [[ -n "$agent" ]]; then
    lwt::utils::install_dependencies
  fi

  if $open_editor; then
    lwt::editor::open "$target" "$editor_override"
  fi

  lwt::agent::launch "$agent" "$prompt"
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
  echo "${_lwt_green}Removed worktree.${_lwt_reset}"

  if [[ -n "$branch" && "$branch" != "$LWT_DEFAULT_BRANCH" && "$branch" != "main" && "$branch" != "master" ]] \
    && git show-ref --verify --quiet "refs/heads/$branch"; then
    if git branch -d "$branch" >/dev/null 2>&1; then
      echo "Deleted branch ${_lwt_bold}$branch${_lwt_reset}."
    elif $merged; then
      git branch -D "$branch" >/dev/null 2>&1 && echo "Deleted branch ${_lwt_bold}$branch${_lwt_reset}."
    else
      lwt::ui::warn "Branch $branch has unmerged work."
      if read -rq "?${_lwt_red}Force delete local branch? [y/N]${_lwt_reset} "; then
        echo
        git branch -D "$branch" >/dev/null 2>&1 && echo "Deleted branch ${_lwt_bold}$branch${_lwt_reset}."
      else
        echo
        echo "Kept branch $branch."
      fi
    fi
  fi

  if $merged && [[ -n "$branch" ]] && git ls-remote --heads origin "$branch" 2>/dev/null | grep -q .; then
    echo "Remote branch ${_lwt_bold}origin/$branch${_lwt_reset} still exists (PR merged)."
    if read -rq "?Delete remote branch? [y/N] "; then
      echo
      git push origin --delete "$branch" 2>/dev/null && echo "Deleted remote branch ${_lwt_bold}origin/$branch${_lwt_reset}."
    else
      echo
    fi
  fi
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
    echo "No merged worktrees found."
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
  echo "${_lwt_green}Cleaned $removed merged worktree(s).${_lwt_reset}"
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

  lwt::ui::header "Rename worktree"
  echo "  ${_lwt_bold}$old_branch${_lwt_reset} → ${_lwt_bold}$new_name${_lwt_reset}"
  echo "  ${_lwt_dim}$worktree${_lwt_reset}"
  $has_remote && echo "  Remote branch ${_lwt_bold}origin/$old_branch${_lwt_reset} exists and will be updated."
  echo
  lwt::ui::warn "If an AI agent is running in this worktree, it will lose its"
  lwt::ui::warn "working directory and may lose conversation history. You'll need"
  lwt::ui::warn "to restart the agent after renaming."

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

  echo "${_lwt_green}Renamed worktree.${_lwt_reset}"

  # handle remote branch
  if $has_remote; then
    if read -rq "?Rename remote branch (push new, delete old)? [y/N] "; then
      echo
      git -C "$new_path" push origin "$new_name" 2>/dev/null \
        && git push origin --delete "$old_branch" 2>/dev/null \
        && git -C "$new_path" branch --set-upstream-to="origin/$new_name" "$new_name" 2>/dev/null \
        && echo "Renamed remote branch ${_lwt_bold}origin/$old_branch${_lwt_reset} → ${_lwt_bold}origin/$new_name${_lwt_reset}."
    else
      echo
      lwt::ui::hint "Remote branch origin/$old_branch was kept. Local branch now tracks nothing."
    fi
  fi
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
  echo "Required tools"

  if lwt::deps::has git; then
    echo "  ${_lwt_green}✓ git${_lwt_reset}"
  else
    echo "  ${_lwt_red}✗ git${_lwt_reset}"
    echo "    Install: https://git-scm.com/downloads"
  fi

  if lwt::deps::has fzf; then
    echo "  ${_lwt_green}✓ fzf${_lwt_reset}"
  else
    echo "  ${_lwt_red}✗ fzf${_lwt_reset}"
    echo "    Install: brew install fzf"
  fi

  echo
  echo "Optional tools"

  if lwt::deps::has gh; then
    if gh auth status -h github.com >/dev/null 2>&1; then
      echo "  ${_lwt_green}✓ gh (authenticated)${_lwt_reset}"
    else
      echo "  ${_lwt_yellow}⚠ gh (not authenticated)${_lwt_reset}"
      echo "    Run: gh auth login"
    fi
  else
    echo "  ${_lwt_yellow}⚠ gh${_lwt_reset}"
    echo "    Install: brew install gh"
    echo "    Needed for squash-merge detection"
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
  echo "Editor resolution order"
  echo "  git config lwt.editor -> LWT_EDITOR -> VISUAL -> EDITOR"

  if $in_repo; then
    local configured_editor
    configured_editor=$(git config --get lwt.editor 2>/dev/null)
    if [[ -n "$configured_editor" ]]; then
      echo "  Current git-config editor: $configured_editor"
    fi
  fi
}

lwt::dispatch() {
  local cmd="${1:-help}"
  shift || true

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
