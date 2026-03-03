# Light Worktrees (`lwt`)

Git worktrees are powerful but clunky to manage — creating, switching, and cleaning them up involves too many git commands and zero visibility into what's safe to delete. `lwt` wraps the sharp edges into a small, opinionated CLI that stays out of your way.

One command to create a worktree. One command to remove it — with a clear safety summary showing merge status, dirty files, and unpushed commits so you never lose work by accident.

## Install

Requires `zsh`, `git`, and `fzf`.

```bash
git clone https://github.com/linuz90/lwt.git ~/Code/lwt
echo 'source ~/Code/lwt/lwt.sh' >> ~/.zshrc
source ~/.zshrc
```

Verify everything is set up:

```bash
lwt doctor
```

## Usage

```bash
lwt add [branch] [-e] [-claude|-codex|-gemini "prompt"]
lwt switch [query] [-e]
lwt list
lwt remove [query]
lwt clean [-n]
lwt rename <new-name>
lwt doctor
lwt help [command]
```

Examples:

```bash
lwt add                          # auto-named branch (e.g. swift-reef, calm-jade)
lwt add feat-onboarding          # create a worktree with a named branch
lwt add feat-onboarding -e       # same, but open in your editor
lwt switch auth -e               # fuzzy-find and switch to a worktree
lwt list                         # see all worktrees with live status
lwt remove                       # pick a worktree to safely remove
lwt clean                        # remove all merged worktrees at once
lwt clean -n                     # dry run — see what would be removed
lwt rename new-api-name          # rename current worktree + branch
```

## Remote-Aware Status

`lwt` fetches from remotes before showing status, so what you see is always current:

- **merged** — branch is merged (including squash-merge detection via `gh`)
- **dirty** — uncommitted changes in the worktree
- **unpushed** — local commits not yet on the remote
- **behind** — remote has commits you haven't pulled

This matters most during `remove` — you'll see exactly what you'd lose before confirming.

## AI Agent Launch

Spin up a worktree and immediately hand it off to an AI coding agent — one command:

```bash
lwt add feat-api -claude "add retries to webhook sender"
lwt add feat-api -codex "implement OAuth callback handling"
lwt add feat-ui -gemini "refactor profile page layout"
```

The worktree is created, your shell `cd`s into it, and the agent starts working. Each agent gets its own isolated worktree so it can't interfere with your main checkout.

## Worktree Layout

`lwt add` creates worktrees in:

```text
../.worktrees/<project>/<branch>
```

This keeps your project root and sibling repos clean while making worktrees easy to find and bulk-manage.

## Safe Removal

`lwt remove` never silently deletes work:

- Shows a safety summary first (merge status, dirty state, push state)
- Uses `git worktree remove` as the primary path
- Only forces removal after explicit confirmation
- Offers local and remote branch cleanup after removal

## Bulk Cleanup

`lwt clean` finds all merged worktrees and removes them in one go — worktrees, local branches, and remote branches. Uses the same merge detection as `lwt list` (including squash-merge via `gh`).

Use `lwt clean -n` to preview what would be removed without deleting anything.

## Rename

`lwt rename <new-name>` renames a worktree's branch and moves its directory to match — atomically. If called from inside a linked worktree, it renames that one. Otherwise an fzf picker is shown.

If the branch has been pushed, you'll be prompted to rename the remote branch too. If an AI agent is running in the worktree, you'll be warned that it will need to be restarted after the rename.

## Editor Integration

Pass `-e` to open the worktree in your editor after creating or switching.

Resolution order:

1. `--editor-cmd "..."` (per command)
2. `git config lwt.editor`
3. `LWT_EDITOR`
4. `VISUAL`
5. `EDITOR`

Recommended setup:

```bash
git config --global lwt.editor "zed"
```

## Requirements

Required: `git`, `fzf`, `zsh`

Optional:
- `gh` — enables squash-merge detection in status
- `claude`, `codex`, `gemini` CLIs — for agent launch

## License

MIT
