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

lwt::worktree::path_for_branch() {
  local target_branch="$1"
  local record wt_path branch

  [[ -z "$target_branch" ]] && return 1

  while IFS= read -r record; do
    wt_path="${record%%$'\t'*}"
    branch="${record#*$'\t'}"

    if [[ "$branch" == "$target_branch" ]]; then
      printf '%s\n' "$wt_path"
      return 0
    fi
  done < <(lwt::worktree::records)

  return 1
}

lwt::worktree::resolve_query() {
  local query="$1"
  local exclude_main="${2:-false}"
  local main_wt=""
  local record wt_path branch wt_name
  local -a matches=()

  [[ -z "$query" ]] && return 1

  if [[ "$exclude_main" == "true" ]]; then
    main_wt=$(lwt::worktree::main_path 2>/dev/null)
  fi

  while IFS= read -r record; do
    wt_path="${record%%$'\t'*}"
    branch="${record#*$'\t'}"
    wt_name="$(basename "$wt_path")"

    [[ "$exclude_main" == "true" && "$wt_path" == "$main_wt" ]] && continue

    if [[ "$query" == "$branch" || "$query" == "$wt_path" || "$query" == "$wt_name" ]]; then
      matches+=("$wt_path")
    fi
  done < <(lwt::worktree::records)

  if (( ${#matches[@]} == 1 )); then
    printf '%s\n' "${matches[1]}"
    return 0
  fi

  if (( ${#matches[@]} > 1 )); then
    return 2
  fi

  return 1
}

lwt::worktree::remember_parent_ref() {
  local worktree_path="$1"
  local start_ref="$2"
  local remembered_parent=""

  [[ -n "$worktree_path" && -n "$start_ref" ]] || return 1

  # Automatic restack must only rely on ancestry that lwt observed as an exact
  # branch ref at creation time. Tags, SHAs, and HEAD stay manual via --onto.
  remembered_parent=$(lwt::git::normalize_branch_ref "$start_ref" 2>/dev/null) || return 1
  lwt::git::set_restack_parent "$worktree_path" "$remembered_parent"
}

lwt::worktree::remembered_parent_ref() {
  local worktree_path="$1"

  [[ -n "$worktree_path" ]] || return 1
  lwt::git::get_restack_parent "$worktree_path"
}

lwt::worktree::stack_label() {
  local worktree_path="$1"
  local remembered_parent=""
  local normalized_parent=""

  [[ -n "$worktree_path" ]] || return 1

  remembered_parent=$(lwt::worktree::remembered_parent_ref "$worktree_path" 2>/dev/null || true)
  [[ -n "$remembered_parent" ]] || return 0

  normalized_parent=$(lwt::git::normalize_branch_ref "$remembered_parent" 2>/dev/null || true)
  if [[ -n "$normalized_parent" ]]; then
    printf ' %s← parent: %s%s' "$_lwt_dim" "$normalized_parent" "$_lwt_reset"
  else
    printf ' %s← parent: %s (stale)%s' "$_lwt_dim" "$remembered_parent" "$_lwt_reset"
  fi
}

lwt::worktree::location_hint() {
  local worktree_path="$1"
  local codex_root="${HOME}/.codex/worktrees/"
  local rest codex_id

  [[ -n "$worktree_path" ]] || return 1

  if [[ "$worktree_path" == "$codex_root"* ]]; then
    rest="${worktree_path#"$codex_root"}"
    codex_id="${rest%%/*}"
    if [[ -n "$codex_id" && "$codex_id" != "$rest" ]]; then
      printf 'codex/%s' "$codex_id"
      return 0
    fi
  fi

  return 1
}

lwt::worktree::detached_label() {
  local worktree_path="$1"
  local short_head=""
  local location_hint=""

  [[ -n "$worktree_path" ]] || return 1

  short_head=$(git -C "$worktree_path" rev-parse --short=9 HEAD 2>/dev/null || true)
  [[ -n "$short_head" ]] || short_head="unknown"

  location_hint=$(lwt::worktree::location_hint "$worktree_path" 2>/dev/null || true)
  if [[ -n "$location_hint" ]]; then
    printf '(detached @ %s · %s)' "$short_head" "$location_hint"
  else
    printf '(detached @ %s)' "$short_head"
  fi
}

lwt::worktree::create_branch() {
  local branch="$1"
  local confirm_existing="${2:-true}"
  local allow_new="${3:-true}"
  local start_ref_override="${4:-}"
  local start_ref_label="${5:-}"
  local repo_root repo_parent project base target
  local start_ref git_err

  LWT_LAST_WORKTREE_PATH=""
  LWT_LAST_WORKTREE_CREATED_NEW_BRANCH="false"
  [[ -z "$branch" ]] && return 1

  repo_root=$(lwt::worktree::main_path) || return 1
  repo_parent="${repo_root:h}"
  project=$(basename "$repo_root")
  base="$repo_parent/.worktrees/$project"
  target="$base/$branch"

  if [[ -e "$target" ]]; then
    lwt::ui::error "Target path already exists: $target"
    return 1
  fi

  mkdir -p "$base"
  lwt::git::fetch_if_stale

  start_ref="$start_ref_override"
  [[ -z "$start_ref" ]] && start_ref="$LWT_DEFAULT_BASE_REF"
  [[ -z "$start_ref_label" ]] && start_ref_label="$start_ref"
  if ! git rev-parse --verify "${start_ref}^{commit}" >/dev/null 2>&1; then
    if [[ -n "$start_ref_override" ]]; then
      lwt::ui::error "Unknown start ref: $start_ref_override"
      lwt::ui::hint "Pass any branch, tag, or commit-ish that resolves locally."
      return 1
    fi
    start_ref="HEAD"
    start_ref_label="$start_ref"
  fi

  if git show-ref --verify --quiet "refs/heads/$branch" 2>/dev/null; then
    # Explicit start-point flags only make sense when creating a new branch. Silently
    # ignoring them for existing branches would make automation look correct while doing
    # the wrong thing.
    if [[ -n "$start_ref_override" ]]; then
      lwt::ui::error "Branch already exists locally: $branch"
      lwt::ui::hint "Pick a new branch name, or run lwt add $branch without an explicit start-point flag."
      return 1
    fi
    if [[ "$confirm_existing" == "true" ]]; then
      if ! read -rq "?Branch $branch exists locally. Check out into a worktree? [y/N] "; then
        echo
        return 1
      fi
      echo
    fi

    git_err=$(git worktree add "$target" "$branch" 2>&1) || {
      lwt::ui::error "Failed to create worktree."
      lwt::ui::hint "$git_err"
      return 1
    }
    lwt::ui::step "Checked out existing branch ${_lwt_bold}$branch${_lwt_reset}"
  elif git show-ref --verify --quiet "refs/remotes/origin/$branch" 2>/dev/null; then
    if [[ -n "$start_ref_override" ]]; then
      lwt::ui::error "Branch already exists on origin: $branch"
      lwt::ui::hint "Pick a new branch name, or run lwt add $branch without an explicit start-point flag."
      return 1
    fi
    if [[ "$confirm_existing" == "true" ]]; then
      if ! read -rq "?Branch $branch exists on origin. Check out into a worktree? [y/N] "; then
        echo
        return 1
      fi
      echo
    fi

    git_err=$(git worktree add --track -b "$branch" "$target" "origin/$branch" 2>&1) || {
      lwt::ui::error "Failed to create worktree."
      lwt::ui::hint "$git_err"
      return 1
    }
    lwt::ui::step "Checked out existing branch ${_lwt_bold}$branch${_lwt_reset}${_lwt_dim} from origin"
  else
    if [[ "$allow_new" != "true" ]]; then
      lwt::ui::error "No existing branch matched: $branch"
      return 1
    fi

    git_err=$(git worktree add -b "$branch" "$target" "$start_ref" 2>&1) || {
      lwt::ui::error "Failed to create worktree."
      lwt::ui::hint "$git_err"
      return 1
    }
    LWT_LAST_WORKTREE_CREATED_NEW_BRANCH="true"
    lwt::ui::step "Created branch ${_lwt_bold}$branch${_lwt_reset}${_lwt_dim} from ${start_ref_label}"
  fi

  lwt::utils::copy_env_files "$repo_root" "$target"
  lwt::utils::copy_configured_paths "$repo_root" "$target" || {
    lwt::ui::error "Failed to copy configured create-time paths."
    return 1
  }
  LWT_LAST_WORKTREE_PATH="$target"
}
lwt::worktree::display_rows() {
  setopt local_options no_bg_nice

  local include_stack="${1:-true}"
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

  # Batch-fetch open PR metadata once so row rendering can show PR links and
  # conflict badges without one GitHub call per worktree.
  export LWT_OPEN_PRS_FILE="$tmpdir/_open_prs"
  touch "$LWT_OPEN_PRS_FILE"
  lwt::status::init_gh_mode
  if [[ "$LWT_GH_MODE" == "ok" ]]; then
    gh pr list --state open --limit 100 --json headRefName,number,url,mergeable,mergeStateStatus \
      -q '.[] | "\(.headRefName)\tPR #\(.number)\t\(.url)\t\(.mergeable // "")\t\(.mergeStateStatus // "")"' \
      > "$LWT_OPEN_PRS_FILE" 2>/dev/null
  fi

  for record in "${records[@]}"; do
    wt_path="${record%%$'\t'*}"
    branch="${record#*$'\t'}"

    (
      local marker="  "
      local label="$branch"
      local flags
      local stack_label=""

      [[ "$wt_path" == "$current_dir" ]] && marker="* "
      [[ "$wt_path" == "$main_dir" ]] && label="$branch (repo)"
      [[ "$branch" == "(detached)" ]] && label="$(lwt::worktree::detached_label "$wt_path")"
      flags=$(lwt::status::for_worktree "$wt_path" "$branch")
      if [[ "$include_stack" == "true" ]]; then
        stack_label=$(lwt::worktree::stack_label "$wt_path")
      fi

      printf '%s\t%s%s%s%s\n' "$wt_path" "$marker" "$label" "$stack_label" "$flags" > "$tmpdir/$idx"
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
