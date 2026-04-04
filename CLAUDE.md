# lwt — Light Worktrees

Shell-based CLI for managing git worktrees. `lwt.sh` is the public entrypoint and sources the implementation from `lib/*.sh`.

## Testing

After editing `lwt.sh` or any file in `lib/`, always test through the public entrypoint before considering the change done:

```bash
source lwt.sh && lwt <command> [args]
```

This catches runtime errors (bad math expressions, missing variables, syntax issues) that aren't visible from reading the code alone.

For interactive commands such as `merge`, `remove`, `rename`, `restack`, and `clean`, test with a TTY/PTY so confirmation prompts behave like a real shell session.

## zsh Footguns

- Do not use `status` as a local variable name. In `zsh`, `$status` is a read-only special parameter for the last exit code.
- Prefer names like `exit_code`, `result_code`, or `merge_status` instead.

## Merge Behavior

- `lwt merge` has two paths:
  - Open PR exists: merge the PR through GitHub with `gh pr merge --squash`
  - No PR exists: fall back to the local squash-merge flow
- When a PR exists, GitHub is the source of truth. Do not replace the PR merge with a local `git merge --squash` flow that only approximates the result.
- Keep the UX explicit about which path is being used.
- If GitHub requires bypass/admin privileges, keep that explicit and preserve a clear `--admin` path.
- The local fallback path requires a clean main worktree because it modifies it directly.
- The PR path should not be blocked by a dirty main worktree; dirtiness only affects syncing local `main` afterward.

## Structure

Use `lwt.sh` as the only entrypoint. It sources these modules in order:

- `lib/core.sh`: globals, dependency checks, UI helpers, shared shell/utils
- `lib/git.sh`: repo detection, default branch resolution, stale fetch
- `lib/config.sh`: config keys, defaults, scopes, and persistence helpers
- `lib/status.sh`: merge detection, per-worktree flags, gh mode
- `lib/worktree.sh`: worktree discovery, creation, display rows
- `lib/editor.sh`: editor resolution and launch
- `lib/project.sh`: package manager detection, script lookup, dependency install, dev command resolution
- `lib/terminal.sh`: terminal driver detection and split/tab automation
- `lib/agent.sh`: agent launch and command construction
- `lib/hooks.sh`: advanced hook discovery and execution
- `lib/help.sh`: CLI help text
- `lib/commands.sh`: `lwt::cmd::*`, checkout helpers, and dispatch

Keep modules as pure function definitions and shared globals. Do not source individual `lib/*.sh` files directly in tests or docs.

## Product Notes

- `lwt config show` should stay focused on core settings. Advanced/internal hook settings belong behind `--all` or `lwt hook`.
- Hooks are an advanced feature, not part of the main mental model. Avoid surfacing them prominently in the default UX.
- `lwt add <branch>` should stay non-interactive when the branch already exists locally or on `origin`; checking out an existing branch is the expected path, not a risky edge case.
- `lwt add` should default to the repo default branch, with explicit ancestry behind opt-in flags such as `--from <ref>` or `--from-current`.
- Once a branch has remembered parent metadata, `lwt list` and the `lwt switch` picker should surface it by default as `← parent: <branch>`; use that explicit label shape rather than a bare arrow/value pair.
- `lwt restack` should stay scoped to the current linked worktree. Automatic target selection applies to branches created with `lwt add --from <branch>` and to branches `lwt add` created from the repo default branch. Older worktrees without remembered metadata may fall back to the repo default branch in the restack summary, but automation should still stay explicit with `--onto`.
- Agent-facing flows should print absolute worktree paths explicitly; do not rely on in-process `cd` state or path-free summaries.
- `lwt remove` should preserve a clear automation path: `--yes` skips the delete prompt, `--force` handles dirty/unmerged local cleanup, and remote cleanup stays explicit behind `--delete-remote`.
- The first-contact UX for `lwt` / `lwt --help` should teach automation-safe patterns early because agents discover the tool through help output, not just humans.

## Dependencies

- Required: `git`, `fzf`, `zsh`
- Strongly recommended: `gh` (squash-merge detection, PR recreation on rename, PR tags in list)
- Optional: `claude`, `codex`, `gemini` CLIs
- Optional for split/tab automation: macOS, `osascript`, and Ghostty or iTerm2
