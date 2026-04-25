# Light Worktrees (`lwt`)

Git worktrees are powerful, but the default workflow is awkward: too many commands to create one, too little visibility into what is safe to delete, and too much friction when you just want to jump into parallel work.

`lwt` makes worktrees feel like they should have felt all along: fast to create, easy to switch, and safe to clean up. It also bakes in the workflows that matter in practice, like opening your editor, booting a dev server, or handing a fresh worktree straight to Claude, Codex, or Gemini.

Create a worktree in one command. Remove it with a safety summary that shows merge state, dirty files, and unpushed commits before anything destructive happens.

![lwt demo](assets/demo.gif)

## Why `lwt`

- Create a worktree and hand it to one or more AI agents in a single command
- Run multiple agents in parallel — first gets your shell, the rest auto-open in terminal splits
- Boot dev servers, test watchers, and linters alongside agents without manual window management
- Jump between worktrees with fuzzy search instead of memorizing paths
- Remove worktrees with a clear safety check that shows merge state, dirty files, and unpushed commits
- Keep everything organized under a predictable `../.worktrees/<project>/<branch>` layout

## Install

Requires `zsh`, `git`, and `fzf`. You'll also want [`gh`](https://cli.github.com/) for full functionality (see [Requirements](#requirements)).

```bash
git clone https://github.com/linuz90/lwt.git ~/.lwt
echo 'source ~/.lwt/lwt.sh' >> ~/.zshrc
source ~/.zshrc
```

Verify everything is set up:

```bash
lwt doctor
```

Implementation note: `lwt.sh` remains the only entrypoint you source. It loads the implementation from `lib/*.sh` internally.

## Usage

```bash
lwt add (a)        [branch] [-s] [-d] [-e] [-yolo]
                   [--from <ref> | --from-current]
                   [--claude ["prompt"]] [--codex ["prompt"]] [--gemini ["prompt"]]
                   [--agents list ["prompt"]] [--<agent-combo> ["prompt"]]
                   [--split "cmd"] [--tab "cmd"]
lwt checkout (co)  [query] [-e]
lwt switch (s)     [query] [-e]
lwt path           [query]
lwt list (ls)      [--porcelain]
lwt merge          [target-branch] [--keep-worktree] [--keep-branch] [--no-push]
lwt restack (rs)   [--onto <ref>] [-y|--yes]
lwt remove (rm)    [query] [-y|--yes] [-f|--force] [--delete-remote]
lwt clean          [-n]
lwt rename (rn)    <new-name>
lwt config (cfg)   [show|get|set|add|unset] [--global|--local]
lwt doctor
lwt help           [command|automation]
```

`--<agent-combo>` means any hyphenated mix of supported agents, for example `--claude-codex`, `--codex-gemini`, or `--claude-codex-gemini`. The combo shares a single prompt across all agents.

Examples:

| Command                                              | Description                                                         |
| ---------------------------------------------------- | ------------------------------------------------------------------- |
| `lwt a feat-onboarding -s -e`                        | Start a feature branch, install deps, and open it in your editor    |
| `lwt a feat-login --codex "fix the OAuth callback bug"` | Create a worktree and hand the bugfix straight to Codex          |
| `lwt a feat-auth --agents claude,codex "implement refresh token rotation"` | Run Claude here and open Codex beside it with the same prompt |
| `lwt a feat-checkout --claude-codex-gemini "review the current checkout flow and propose the best refactor plan"` | Get three independent takes on the same problem in parallel |
| `lwt a feat-api --codex "implement webhook retries" -d` | Let Codex work while the app boots in a split         |
| `lwt a feat-search --split "pnpm test --watch" --tab "pnpm lint --watch"` | Open watch sessions alongside the new worktree |
| `lwt a feat-auth --claude-codex "implement refresh token rotation"` | Use the shorter alias for the same two-agent flow |
| `lwt a feat-auth --claude "implement refresh token rotation" --codex "investigate edge cases"` | Different prompts per agent; first runs here, second in split |
| `lwt a`                                              | Create a worktree with a random branch name                         |
| `lwt a existing-remote-branch`                       | Bring an existing local or remote branch under `lwt` management without a confirmation prompt |
| `lwt a feat-auth-alt --from feat-auth`               | Create a new worktree branch from `feat-auth` instead of the default branch |
| `lwt a feat-auth-alt --from-current`                 | Create a new worktree branch from the current worktree's committed `HEAD` |
| `lwt co restream`                                    | Pick an open PR matching `restream` and create its worktree         |
| `lwt co auth -e`                                     | Pull an open PR into its own worktree and open it in your editor    |
| `lwt s auth -e`                                      | Jump to a worktree and open it in your editor                       |
| `lwt path auth`                                      | Print the exact absolute path for an existing worktree              |
| `lwt ls`                                             | List worktrees and show remembered parents as `← parent: <branch>` when available |
| `lwt merge`                                          | Squash-merge the current worktree into the configured target branch |
| `lwt rs`                                             | Rebase the current worktree onto its remembered parent, or fall back to the default branch in the summary |
| `lwt rs --onto feat-auth --yes`                      | Rebase the current child worktree onto an explicit branch non-interactively |
| `lwt rm feat-auth --yes`                             | Remove a worktree without stopping for the delete confirmation      |
| `lwt rm feat-auth --yes --force`                     | Also discard local changes and force local branch cleanup           |
| `lwt clean -n`                                       | Preview merged worktrees before deleting anything                   |
| `lwt rn new-api-name`                                | Rename the current worktree and branch together                     |
| `lwt config set dev-cmd "pnpm --filter web dev"`     | Persist the repo's preferred dev command                            |

Branch creation rules:

- `lwt a <branch>` creates a new branch from the repo default branch when `<branch>` does not exist yet
- `lwt a <branch>` checks out that branch into a worktree when `<branch>` already exists locally or on `origin`
- `lwt a <branch> --from <ref>` creates a new branch from that explicit ref
- `lwt a <branch> --from-current` creates a new branch from the current worktree's committed `HEAD`
- when `--from` points at a local branch or `origin/<branch>`, `lwt` remembers that parent for later `lwt restack`
- when `lwt a <branch>` creates a new branch from the repo default branch, `lwt` also remembers that default branch for later `lwt restack`
- `--from-current` does not carry over uncommitted changes; commit or stash/apply them first if needed

## Agents And Automation

If an agent or script is driving `lwt`, prefer explicit targets over picker flows:

- `lwt add <branch>` is non-interactive, even when the branch already exists locally or on `origin`
- `lwt add <branch>` creates from the repo default branch unless that branch already exists, in which case it checks the existing branch out into a worktree
- `lwt add <branch> --from <ref>` is the explicit way to branch from something other than the repo default branch
- `lwt add <branch> --from-current` branches from the current worktree's committed `HEAD`; uncommitted changes stay where they are
- `lwt restack --yes` skips only the confirmation prompt; it still refuses dirty worktrees, detached `HEAD`, and unresolved targets
- `lwt add`, `lwt checkout`, and `lwt switch` print the resolved absolute worktree path and a ready-to-run `cd` command
- `lwt path <branch>` prints the exact absolute path for an existing worktree
- `lwt ls --porcelain` prints stable `path<TAB>branch` pairs for scripts
- `lwt ls` and the interactive `lwt switch` picker show remembered parent info as `← parent: <branch>` when available
- human-readable `lwt ls`, the interactive `lwt switch` picker, and `lwt checkout` show a red `⚠ PR conflicts` badge when GitHub already reports a conflicted open PR
- `lwt ls --porcelain` stays stable for scripts and omits stack annotations

Example stacked label in human-readable output:

```text
feat-child ← parent: feat-parent
```
- `lwt remove <branch> --yes` skips the delete confirmation and bypasses `fzf` when the query exactly matches a branch, worktree path, or worktree directory name
- `lwt remove <branch> --yes --force` also discards local changes and force-deletes the local branch when needed
- `lwt remove <branch> --yes --delete-remote` also deletes the remote branch or closes the open PR without prompting

Avoid bare `lwt rm`, `lwt switch`, and `lwt checkout` in automation unless you are intentionally running them in a real TTY, because those flows rely on `fzf`.

`-yolo` and `lwt config set agent-mode yolo` only affect Claude/Codex/Gemini permissions. They do not bypass `lwt` command confirmations.

When `--from` or `--from-current` is used, `lwt` only applies that start point while creating a new branch. If the target branch already exists locally or on `origin`, `lwt` errors instead of silently ignoring the requested base.

`lwt restack` only operates on the current linked worktree. It does not pick another worktree for you, restack descendants, inspect PR stacks, auto-stash changes, or auto-push anything.

## Remote-Aware Status

`lwt` fetches from remotes before showing status, so what you see is always current:

- **merged** — branch is merged (including squash-merge detection via `gh`)
- **dirty** — uncommitted changes in the worktree
- **unpushed** — local commits not yet on the remote
- **behind** — remote has commits you haven't pulled
- **PR conflicts** — GitHub says the open PR cannot merge cleanly; shown as a red `⚠ PR conflicts` badge in human-facing `list`, `switch`, and `checkout` output

This matters most during `remove` — you'll see exactly what you'd lose before confirming.

## Merge

`lwt merge` is intentionally opinionated:

- if the branch has an open PR, `lwt` merges that PR through GitHub with `gh pr merge --squash`
- otherwise it falls back to a local squash merge
- after either path, it cleans up the source worktree and branch by default

If GitHub rejects the PR merge because bypass/admin privileges are required, `lwt` keeps the error output visible and offers an interactive retry with `--admin`.

If GitHub already reports the PR as conflicted, `lwt merge` fails before the confirmation prompt and points you back to the source worktree to resolve and push the branch first. In a real TTY with an installed agent, that conflict path can also offer to launch the agent directly in the source worktree with a targeted prompt. The same GitHub conflict signal also powers the red `⚠ PR conflicts` badge in `lwt ls`, `lwt switch`, and `lwt checkout`.

By default it merges into:

1. `merge-target` if configured
2. otherwise the repo default branch

Typical usage:

```bash
lwt merge
lwt merge release
lwt merge --keep-worktree
lwt merge --admin
```

## Restack

`lwt restack` is a narrow stacked-branch convenience, not a stack manager. It exists for the common case where you created a child branch with `lwt add child --from parent` and later need to rebase that child onto the updated parent. It also covers the common "my branch started from `main` and now `main` moved on" cleanup flow.

Automatic target selection is intentionally strict:

- if `lwt` created the current branch with `--from <branch>` or `--from origin/<branch>`, it remembers that parent
- if `lwt` created the current branch from the repo default branch, it remembers that default branch too
- older worktrees with no remembered parent can still fall back to the repo default branch in the restack summary
- otherwise you must pass `--onto <ref>` explicitly
- the command only acts on the current linked worktree and never guesses another target from history, PR state, or commit ancestry

Safety checks run before any history rewrite:

- must be inside a linked worktree, not the main repo worktree
- current branch must not be detached
- the worktree must be clean, including untracked files
- no rebase, merge, cherry-pick, or revert can already be in progress
- target must resolve and must not be the current branch

Before confirming, `lwt restack` also shows how many commits the current branch is behind and ahead of the chosen target so the rewrite is explicit in plain Git terms. If the branch is already up to date with the target, `lwt` exits cleanly without prompting or rebasing.

When `git merge-tree` predicts content conflicts against the chosen target, that same summary also shows a red likely-conflicts warning before you confirm. This is a preflight heuristic, not a full dry-run rebase, so treat it as early warning rather than a guarantee.

For older worktrees that predate remembered default-branch metadata, `lwt restack` warns first and uses the repo default branch in the restack summary unless you pass `--onto`. That keeps the stale-branch-on-`main` case convenient without making `--yes` or automation silently guess.

Typical usage:

```bash
lwt restack
lwt rs
lwt restack --onto invite-onboarding-step
lwt rs --yes
```

If the rebase hits conflicts, `lwt` stops immediately and leaves you in the normal Git flow for that worktree:

```bash
git rebase --continue
git rebase --abort
```

In a real TTY with an installed agent, that conflict path can also offer to launch the agent directly in the conflicted worktree with a targeted prompt.

## AI Agent Launch

Spin up a worktree and immediately hand it off to an AI coding agent:

```bash
lwt a feat-api --claude "add retries to webhook sender"
lwt a feat-api --codex "implement OAuth callback handling"
lwt a feat-ui --gemini "refactor profile page layout"
```

The worktree is created, your shell `cd`s into it, and the agent starts working in an isolated checkout that cannot interfere with your main repository state. `lwt` also prints the exact absolute worktree path before the agent starts, so subprocess-driven tools can continue in the right checkout without guessing.

Single-agent flags are shorthand for `--agents` with one item, so `--claude`, `--codex`, and `--gemini` still work exactly as before. The prompt is optional. Passing one of those flags by itself launches that agent interactively in the new worktree.

For multiple agents with the same prompt, use `--agents` or a hyphen alias:

```bash
lwt a feat-auth --agents claude,codex "implement refresh token rotation"
lwt a feat-auth --claude-codex "implement refresh token rotation"
lwt a feat-auth --codex-gemini "compare two refactor approaches"
```

This is best when you want multiple independent takes on the same prompt: reviews, plans, audits, debugging hypotheses, or implementation attempts.

When more than one agent is requested, `lwt` uses the current shell for the first agent and opens one split per remaining agent when terminal automation is available. If split automation is unavailable, `lwt` still launches the first runnable agent and prints manual launch commands for the rest.

Each agent flag accepts its own prompt, so you can give different agents different jobs:

```bash
lwt a feat-auth --claude "implement refresh token rotation" --codex "investigate edge cases in the auth flow"
```

The first agent flag determines which agent runs in your current shell; the rest open in splits. To swap who gets the main shell, just swap the flag order:

```bash
lwt a feat-auth --codex "investigate edge cases" --claude "implement refresh token rotation"
```

By default, agents launch in interactive mode. Pass `-yolo` to auto-approve all agent actions for that run, or set it globally:

```bash
lwt config set agent-mode yolo
```

## Terminal Automation

`lwt add` can open the sessions you usually need right after the worktree is ready:

```bash
lwt a feat-api --split "pnpm test --watch"
lwt a feat-api --tab "pnpm lint --watch"
lwt a feat-api --codex "fix auth" -d
lwt a feat-auth --agents claude,codex "fix auth edge cases"
```

What each flag does:

- `--split "cmd"` runs any command in a new terminal split inside the new worktree
- `--tab "cmd"` runs any command in a new terminal tab inside the new worktree
- `--dev` / `-d` resolves the repo's dev command and runs it in place; auto-promotes to a split when an agent occupies the current shell

Agent placement is automatic based on flag order: the first agent runs in your current shell, additional agents open in splits.

You can combine multiple session flags in one command if you want the worktree, app, tests, and agents to come up together.

Recommended workflows:

```bash
# You code in the current shell, app boots in a split
lwt a feat-checkout -d

# Codex works in the current shell, dev server runs beside it
lwt a feat-billing --codex "fix invoice retry handling" -d

# Claude runs in the current shell, Codex opens beside it
lwt a feat-auth --agents claude,codex "implement refresh token rotation"

# Different prompts per agent
lwt a feat-auth --claude "implement refresh tokens" --codex "review the auth flow"

# One extra split for tests, one extra tab for linting
lwt a feat-search --split "pnpm test --watch" --tab "pnpm lint --watch"

# Claude in the main shell, dev and tests in splits
lwt a feat-api --claude "fix auth" -d --split "pnpm test --watch"
```

Today this supports Ghostty and iTerm2 on macOS. `lwt` auto-detects the current terminal from `TERM_PROGRAM`, or you can pin one explicitly:

```bash
lwt config set terminal ghostty
```

Use `lwt doctor` to confirm whether terminal automation is available and which driver was detected.

## Copy Extra Files On Create

For simple project-specific bootstrapping, use `copy-on-create` instead of a hook.

Each configured path is repo-relative:

- Files are copied into the same relative path in the new worktree
- Directories are copied recursively into the same relative path
- Missing paths warn and are skipped

This is the simplest way to seed extra local-only files like browser auth state:

```bash
lwt config add copy-on-create apps/typefully-web/.browser-auth.json
```

That applies to both `lwt add` and `lwt checkout`, after actual `.env` files (for example `.env`, `.env.local`, `.env.production.local`) are copied and before editors, terminals, or agents launch. Template/example files like `.env.example` are skipped.

Use hooks only when you need conditional or scripted behavior.

## Advanced Hooks

Most users can ignore this section if `copy-on-create` is enough.

`lwt` has a lightweight hook layer for teams that want a bit of automation around worktree lifecycle events. If a hook file exists, it runs automatically:

Use this only when a repo repeatedly needs the same scripted step:

- `post-create`: warm a cache, generate a derived file, run a tiny bootstrap
- `post-switch`: print the local app URL or open something helpful
- `pre-merge`: run a fast final check before `lwt merge`

- User hooks live in `~/.config/lwt/hooks`
- Repo hooks live in `.lwt/hooks` and travel with the repository
- A single-file hook like `.lwt/hooks/post-create` runs first for that event
- A directory like `.lwt/hooks/post-create.d/` runs every file in lexical order after that

Current lifecycle events:

- `post-create` — after the worktree exists and setup has finished, before the editor, terminal sessions, or agents launch
- `post-switch` — after `lwt switch`, and after `add`/`checkout` move you into the new worktree
- `pre-merge` / `post-merge` — around `merge`

Hook failures are treated as hard failures for the active workflow. That is intentional: if your bootstrap, cleanup, or rename automation is important enough to hook in, `lwt` should stop instead of carrying on half-configured.

The `lwt hook` command is there mostly for debugging and discovery:

```bash
lwt hook list
lwt hook path post-create
lwt hook run pre-merge
```

Each hook runs with these environment variables available:

- `LWT_HOOK_EVENT`
- `LWT_REPO_ROOT`
- `LWT_WORKTREE_PATH`
- `LWT_BRANCH`
- `LWT_DEFAULT_BRANCH`
- `LWT_DEFAULT_BASE_REF`

Some events also expose extra context such as `LWT_MAIN_WORKTREE_PATH`, `LWT_REMOVED_WORKTREE_PATH`, `LWT_OLD_BRANCH`, `LWT_NEW_BRANCH`, `LWT_OLD_WORKTREE_PATH`, and `LWT_NEW_WORKTREE_PATH`.

Example `post-create` hook:

```bash
#!/usr/bin/env zsh
set -euo pipefail

[[ -f .env.example && ! -f .env.local ]] && cp .env.example .env.local
[[ -f package.json ]] && pnpm test -- --runInBand
```

Example layout:

```text
.lwt/
  hooks/
    post-create
    post-switch.d/
      10-copy-cache
      20-open-dashboard
```

## Dependency Setup

New worktrees don't share `node_modules` with your main checkout. Pass `-s`/`--setup` to auto-install dependencies after creating a worktree:

```bash
lwt a feat-api -s                # create worktree + install deps
```

`lwt` detects your package manager from the lockfile — pnpm, bun, yarn, or npm.

When using an agent flag (`--agents`, `--claude`, `--codex`, `--gemini`, or any combo alias), dependencies are always installed automatically since agents need a working environment.

`--dev` also forces setup before launching the dev command. The dev command resolves in this order:

1. `lwt config set dev-cmd ...`
2. Root `package.json` `scripts.dev`, run with the detected package manager

For monorepos or custom workflows, set it explicitly:

```bash
lwt config set dev-cmd "pnpm --filter web dev"
```

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
- `--yes` skips the delete confirmation prompt for explicit automation
- `--force` discards local changes if needed and force-deletes the local branch when it still has unmerged work
- Remote branch and PR cleanup stay opt-in unless `--delete-remote` is passed
- Offers local and remote branch cleanup after removal

## Bulk Cleanup

`lwt clean` finds all merged worktrees and removes them in one go — worktrees, local branches, and remote branches. Uses the same merge detection as `lwt list` (including squash-merge via `gh`).

Use `lwt clean -n` to preview what would be removed without deleting anything.

## Rename

`lwt rename <new-name>` renames a worktree's branch and moves its directory to match — atomically. If called from inside a linked worktree, it renames that one. Otherwise an fzf picker is shown.

If the branch has been pushed, you'll be prompted to rename the remote branch too. When `gh` is available, open PRs are automatically recreated on the new branch (the old PR is closed with a cross-reference). If an AI agent is running in the worktree, you'll be warned that it will need to be restarted after the rename.

## Editor Integration

Pass `-e` to open the worktree in your editor after creating or switching.

Resolution order:

1. `--editor-cmd "..."` (per command)
2. `lwt config set editor ...`
3. `LWT_EDITOR`
4. `VISUAL`
5. `EDITOR`

Recommended setup:

```bash
lwt config set editor zed
```

## Config

`lwt config` is the canonical way to inspect and update settings:

```bash
lwt config show
lwt config set editor zed
lwt config set agent-mode yolo
lwt config set dev-cmd "pnpm --filter web dev"
lwt config set merge-target release
lwt config add copy-on-create apps/typefully-web/.browser-auth.json
```

Defaults are opinionated:

- `editor`, `agent-mode`, and `terminal` write to global Git config by default
- `dev-cmd` and `merge-target` write to the current repo by default

Supported keys:

- `editor`
- `agent-mode`
- `dev-cmd`
- `terminal`
- `merge-target`
- `copy-on-create` (repeatable, repo-relative path copied by `add` and `checkout`)

`lwt config show` intentionally hides advanced/internal settings. The default view is meant to stay small.

## Requirements

Required: `git`, `fzf`, `zsh`

Strongly recommended:

- `gh` — used by `list`, `remove`, `clean`, and `rename`. Enables squash-merge detection so merged worktrees are correctly identified, and recreates open PRs when renaming branches. Without `gh`, these features degrade gracefully but you lose visibility and risk orphaned PRs.

Optional:

- `claude`, `codex`, `gemini` CLIs — for agent launch
- macOS + `osascript` + Ghostty or iTerm2 — for split/tab automation

## License

MIT
