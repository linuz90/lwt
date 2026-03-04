# lwt — Light Worktrees

Shell-based CLI (`lwt.sh`) for managing git worktrees. Single file, ~1300 lines of zsh/bash.

## Testing

After editing any command in `lwt.sh`, always test it before considering the change done:

```bash
source lwt.sh && lwt <command> [args]
```

This catches runtime errors (bad math expressions, missing variables, syntax issues) that aren't visible from reading the code alone.

## Structure

All commands live in `lwt.sh` as `lwt::cmd::<name>()` functions. Key sections:

- **UI helpers** (`lwt::ui::*`): error, warn, hint, header, success, step — use unicode symbols (✗, ⚠, ✓, ›)
- **Git utilities** (`lwt::git::*`): repo detection, default branch resolution, stale fetch
- **Status** (`lwt::status::*`): merge detection, per-worktree flags, gh mode
- **Worktree display** (`lwt::worktree::*`): parallel status computation for list/selectors
- **Commands** (`lwt::cmd::*`): add, switch, list, remove, clean, rename, doctor

## Dependencies

- Required: `git`, `fzf`, `zsh`
- Strongly recommended: `gh` (squash-merge detection, PR recreation on rename, PR tags in list)
- Optional: `claude`, `codex`, `gemini` CLIs
