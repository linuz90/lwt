# Light Worktrees (`lwt`)

Git worktrees are powerful but clunky to manage — creating, switching, and cleaning them up involves too many git commands and zero visibility into what's safe to delete. `lwt` wraps the sharp edges into a small, opinionated CLI that stays out of your way.

One command to create a worktree. One command to remove it — with a clear safety summary showing merge status, dirty files, and unpushed commits so you never lose work by accident.

![lwt demo](assets/demo.gif)

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
lwt add (a)      [branch] [-s] [-e] [-yolo] [-claude|-codex|-gemini "prompt"]
lwt switch (s)   [query] [-e]
lwt list (ls)
lwt remove (rm)  [query]
lwt clean        [-n]
lwt rename (rn)  <new-name>
lwt doctor
lwt help         [command]
```

Examples:

| Command | Description |
|---------|-------------|
| `lwt a feat-onboarding` | Create a worktree |
| `lwt a feat-onboarding -s -e` | Create, install deps, open editor |
| `lwt a feat-api -claude "add webhook retries"` | Create and launch an agent |
| `lwt a feat-api -yolo -codex "refactor auth module"` | Agent with full auto-approve |
| `lwt a` | Auto-named branch (e.g. swift-reef) |
| `lwt s auth -e` | Fuzzy-find and switch to a worktree |
| `lwt ls` | List all worktrees with status |
| `lwt rm` | Pick and remove a worktree |
| `lwt clean -n` | Preview merged worktrees to remove |
| `lwt clean` | Remove all merged worktrees |
| `lwt rn new-api-name` | Rename worktree + branch |

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
lwt a feat-api -claude "add retries to webhook sender"
lwt a feat-api -codex "implement OAuth callback handling"
lwt a feat-ui -gemini "refactor profile page layout"
```

The worktree is created, your shell `cd`s into it, and the agent starts working. Each agent gets its own isolated worktree so it can't interfere with your main checkout.

By default, agents launch in interactive mode. Pass `-yolo` to auto-approve all agent actions for that run, or set it globally:

```bash
git config --global lwt.agent-mode yolo
```

## Dependency Setup

New worktrees don't share `node_modules` with your main checkout. Pass `-s`/`--setup` to auto-install dependencies after creating a worktree:

```bash
lwt a feat-api -s                # create worktree + install deps
```

`lwt` detects your package manager from the lockfile — pnpm, bun, yarn, or npm.

When using an agent flag (`-claude`, `-codex`, `-gemini`), dependencies are always installed automatically since agents need a working environment.

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
git config --global lwt.editor zed
```

## Requirements

Required: `git`, `fzf`, `zsh`

Optional:
- `gh` — enables squash-merge detection in status
- `claude`, `codex`, `gemini` CLIs — for agent launch

## License

MIT
# test change
