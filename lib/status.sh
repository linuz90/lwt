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
  local dir="${2:-}"  # optional worktree dir for SHA verification
  [[ -z "$branch" || "$branch" == "(detached)" ]] && return 1
  [[ "$branch" == "$LWT_DEFAULT_BRANCH" || "$branch" == "main" || "$branch" == "master" ]] && return 1

  lwt::status::init_gh_mode
  if [[ "$LWT_GH_MODE" != "ok" ]]; then
    return 1
  fi

  # Get the most recent merged PR's head SHA to verify it matches this branch.
  # Matching by name alone causes false positives when a branch is recreated
  # after a previous same-named branch was merged and deleted.
  local pr_head_sha
  pr_head_sha=$(gh pr list --head "$branch" --state merged --json headRefOid -q '.[0].headRefOid' 2>/dev/null)
  [[ -z "$pr_head_sha" ]] && return 1

  # If we have a worktree dir, verify the merged PR's commit is reachable
  # from the current branch. A recreated branch won't contain the old commits.
  if [[ -n "$dir" ]]; then
    if ! git -C "$dir" merge-base --is-ancestor "$pr_head_sha" HEAD 2>/dev/null; then
      return 1
    fi
  fi

  return 0
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

  if lwt::status::is_merged "$branch" "$dir"; then
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
