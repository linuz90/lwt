# Colors
if [[ -n "${NO_COLOR:-}" || ! -t 1 || ! -t 2 ]]; then
  _lwt_red=""
  _lwt_green=""
  _lwt_yellow=""
  _lwt_orange=""
  _lwt_dim=""
  _lwt_bold=""
  _lwt_reset=""
else
  _lwt_red=$'\033[1;31m'
  _lwt_green=$'\033[32m'
  _lwt_yellow=$'\033[33m'
  _lwt_orange=$'\033[38;5;208m'
  _lwt_dim=$'\033[2m'
  _lwt_bold=$'\033[1m'
  _lwt_reset=$'\033[0m'
fi

typeset -g LWT_DEFAULT_BRANCH=""
typeset -g LWT_DEFAULT_BASE_REF=""
typeset -g LWT_GH_MODE=""
typeset -g LWT_GH_NOTICE_PRINTED=0
typeset -g LWT_LAST_WORKTREE_PATH=""
typeset -g LWT_LAST_WORKTREE_CREATED_NEW_BRANCH="false"
typeset -g LWT_LAST_GH_MERGE_OUTPUT=""

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

lwt::ui::detail() {
  local label="$1"
  shift
  printf '  %s%-5s%s %s\n' "$_lwt_dim" "${label}:" "$_lwt_reset" "$*"
}

lwt::utils::count_noun() {
  local count="$1"
  local singular="$2"
  local plural="${3:-${singular}s}"

  if [[ "$count" == "1" ]]; then
    printf '%s %s' "$count" "$singular"
  else
    printf '%s %s' "$count" "$plural"
  fi
}

lwt::ui::confirm() {
  local prompt="$1"
  local assume_yes="${2:-false}"
  local noninteractive_hint="${3:-}"

  if [[ "$assume_yes" == "true" ]]; then
    return 0
  fi

  if [[ ! -t 0 ]]; then
    lwt::ui::error "Confirmation required for this command."
    [[ -n "$noninteractive_hint" ]] && lwt::ui::hint "$noninteractive_hint"
    return 2
  fi

  if read -rq "?$prompt "; then
    echo
    return 0
  fi

  echo
  return 1
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
    lwt::utils::is_actual_env_file "$file" || continue
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

lwt::utils::is_actual_env_file() {
  local path="$1"
  local base="${path:t}"
  local suffix part
  local -a parts

  [[ "$base" == ".env" || "$base" == .env.* ]] || return 1

  suffix="${base#.env}"
  [[ -z "$suffix" ]] && return 0

  # Keep recursive env copying focused on real runtime env files and avoid
  # pulling repo-tracked templates like `.env.example` into new worktrees.
  [[ "$suffix" == .* ]] || return 1
  suffix="${suffix#.}"
  [[ -n "$suffix" ]] || return 1

  parts=("${(@s:.:)suffix}")
  for part in "${parts[@]}"; do
    [[ -n "$part" ]] || return 1
    case "$part:l" in
      example|examples|sample|samples|template|templates)
        return 1
        ;;
    esac
  done

  return 0
}

lwt::utils::copy_configured_paths() {
  local repo_root="$1"
  local target="$2"
  local configured_paths=""
  local rel src dest dest_dir
  local copied_count=0

  configured_paths=$(lwt::config::get_effective "copy-on-create" 2>/dev/null)
  [[ -z "$configured_paths" || "$configured_paths" == "(unset)" ]] && return 0

  while IFS= read -r rel; do
    [[ -n "$rel" && "$rel" != "(unset)" ]] || continue

    while [[ "$rel" == ./* ]]; do
      rel="${rel#./}"
    done
    while [[ "$rel" == */ ]]; do
      rel="${rel%/}"
    done

    if [[ -z "$rel" || "$rel" == "." || "$rel" == ".." ]]; then
      lwt::ui::warn "Skipping invalid copy-on-create path."
      continue
    fi

    case "$rel" in
      /*)
        lwt::ui::warn "Skipping absolute copy-on-create path: $rel"
        continue
        ;;
    esac

    case "/$rel/" in
      */../*)
        lwt::ui::warn "Skipping copy-on-create path outside repo: $rel"
        continue
        ;;
    esac

    src="$repo_root/$rel"
    dest="$target/$rel"
    dest_dir="$(dirname "$dest")"

    if [[ ! -e "$src" ]]; then
      lwt::ui::warn "Configured copy-on-create path not found: $rel"
      continue
    fi

    mkdir -p "$dest_dir" || return 1
    if [[ -d "$src" ]]; then
      mkdir -p "$dest" || return 1
      cp -R "$src"/. "$dest"/ || return 1
    else
      cp "$src" "$dest" || return 1
    fi
    ((copied_count++))
  done <<< "$configured_paths"

  if ((copied_count > 0)); then
    local s="s"; ((copied_count == 1)) && s=""
    lwt::ui::step "Copied $copied_count configured path$s"
  fi
}

lwt::shell::quote() {
  printf '%q' "$1"
}
