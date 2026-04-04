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

lwt::git::restack_parent_key() {
  printf 'lwt.internal.restack-parent\n'
}

lwt::git::enable_worktree_config() {
  local repo_path="${1:-.}"

  git -C "$repo_path" config --local extensions.worktreeConfig true >/dev/null 2>&1
}

lwt::git::normalize_branch_ref() {
  local ref="${1:-}"
  local branch=""

  [[ -n "$ref" ]] || return 1

  case "$ref" in
    refs/heads/*)
      branch="${ref#refs/heads/}"
      git show-ref --verify --quiet "refs/heads/$branch" 2>/dev/null || return 1
      printf '%s\n' "$branch"
      return 0
      ;;
    refs/remotes/origin/*)
      branch="${ref#refs/remotes/origin/}"
      git show-ref --verify --quiet "refs/remotes/origin/$branch" 2>/dev/null || return 1
      printf 'origin/%s\n' "$branch"
      return 0
      ;;
    origin/*)
      branch="${ref#origin/}"
      git show-ref --verify --quiet "refs/remotes/origin/$branch" 2>/dev/null || return 1
      printf 'origin/%s\n' "$branch"
      return 0
      ;;
  esac

  if git show-ref --verify --quiet "refs/heads/$ref" 2>/dev/null; then
    printf '%s\n' "$ref"
    return 0
  fi

  if git show-ref --verify --quiet "refs/remotes/origin/$ref" 2>/dev/null; then
    printf 'origin/%s\n' "$ref"
    return 0
  fi

  return 1
}

lwt::git::default_branch_ref() {
  local normalized_ref=""

  if [[ -n "$LWT_DEFAULT_BASE_REF" ]]; then
    normalized_ref=$(lwt::git::normalize_branch_ref "$LWT_DEFAULT_BASE_REF" 2>/dev/null || true)
    [[ -n "$normalized_ref" ]] && {
      printf '%s\n' "$normalized_ref"
      return 0
    }
  fi

  [[ -n "$LWT_DEFAULT_BRANCH" ]] || return 1
  normalized_ref=$(lwt::git::normalize_branch_ref "$LWT_DEFAULT_BRANCH" 2>/dev/null || true)
  [[ -n "$normalized_ref" ]] || return 1
  printf '%s\n' "$normalized_ref"
}

lwt::git::branch_name_from_ref() {
  local ref="${1:-}"

  [[ -n "$ref" ]] || return 1

  case "$ref" in
    refs/heads/*)
      printf '%s\n' "${ref#refs/heads/}"
      ;;
    refs/remotes/origin/*)
      printf '%s\n' "${ref#refs/remotes/origin/}"
      ;;
    origin/*)
      printf '%s\n' "${ref#origin/}"
      ;;
    *)
      printf '%s\n' "$ref"
      ;;
  esac
}

lwt::git::set_restack_parent() {
  local repo_path="${1:-.}"
  local parent_ref="${2:-}"
  local git_key=""

  [[ -n "$parent_ref" ]] || return 1

  git_key=$(lwt::git::restack_parent_key) || return 1
  lwt::git::enable_worktree_config "$repo_path" || return 1
  git -C "$repo_path" config --worktree "$git_key" "$parent_ref"
}

lwt::git::get_restack_parent() {
  local repo_path="${1:-.}"
  local git_key=""

  git_key=$(lwt::git::restack_parent_key) || return 1
  git -C "$repo_path" config --worktree --get "$git_key" 2>/dev/null
}

lwt::git::operation_in_progress() {
  local repo_path="${1:-.}"
  local git_path=""

  git_path=$(git -C "$repo_path" rev-parse --git-path rebase-merge 2>/dev/null) || return 1
  [[ -d "$git_path" ]] && {
    printf 'rebase\n'
    return 0
  }

  git_path=$(git -C "$repo_path" rev-parse --git-path rebase-apply 2>/dev/null) || return 1
  [[ -d "$git_path" ]] && {
    printf 'rebase\n'
    return 0
  }

  git_path=$(git -C "$repo_path" rev-parse --git-path MERGE_HEAD 2>/dev/null) || return 1
  [[ -f "$git_path" ]] && {
    printf 'merge\n'
    return 0
  }

  git_path=$(git -C "$repo_path" rev-parse --git-path CHERRY_PICK_HEAD 2>/dev/null) || return 1
  [[ -f "$git_path" ]] && {
    printf 'cherry-pick\n'
    return 0
  }

  git_path=$(git -C "$repo_path" rev-parse --git-path REVERT_HEAD 2>/dev/null) || return 1
  [[ -f "$git_path" ]] && {
    printf 'revert\n'
    return 0
  }

  return 1
}
