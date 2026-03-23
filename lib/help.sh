lwt::ui::help_main() {
  echo "${_lwt_bold}Usage:${_lwt_reset} lwt <command> [options]"
  echo
  lwt::ui::header "Automation"
  echo "  ${_lwt_dim}Agents and scripts should prefer explicit branch/query arguments over picker flows.${_lwt_reset}"
  echo "  ${_lwt_dim}lwt add checks out existing local or origin branches without a confirmation prompt.${_lwt_reset}"
  echo "  lwt a feat-auth                              ${_lwt_dim}Create or re-use a named branch non-interactively${_lwt_reset}"
  echo "  lwt rm feat-auth --yes                       ${_lwt_dim}Remove a worktree without the delete prompt${_lwt_reset}"
  echo "  lwt rm feat-auth --yes --force               ${_lwt_dim}Also discard local changes and force local branch cleanup${_lwt_reset}"
  echo "  lwt help automation                          ${_lwt_dim}See the agent-safe command patterns${_lwt_reset}"
  echo
  lwt::ui::header "Commands"
  echo "  ${_lwt_bold}add, a${_lwt_reset}       ${_lwt_dim}Create or check out a worktree branch${_lwt_reset}"
  echo "  ${_lwt_bold}checkout, co${_lwt_reset} ${_lwt_dim}Pick an open PR and spawn a worktree${_lwt_reset}"
  echo "  ${_lwt_bold}switch, s${_lwt_reset}    ${_lwt_dim}Switch to a worktree via fzf${_lwt_reset}"
  echo "  ${_lwt_bold}list, ls${_lwt_reset}     ${_lwt_dim}List worktrees with live status${_lwt_reset}"
  echo "  ${_lwt_bold}merge${_lwt_reset}        ${_lwt_dim}Squash-merge a worktree into the target branch${_lwt_reset}"
  echo "  ${_lwt_bold}remove, rm${_lwt_reset}   ${_lwt_dim}Remove a worktree safely${_lwt_reset}"
  echo "  ${_lwt_bold}clean${_lwt_reset}        ${_lwt_dim}Remove all merged worktrees at once${_lwt_reset}"
  echo "  ${_lwt_bold}rename, rn${_lwt_reset}   ${_lwt_dim}Rename a worktree and its branch${_lwt_reset}"
  echo "  ${_lwt_bold}config, cfg${_lwt_reset}  ${_lwt_dim}Show and change lwt settings${_lwt_reset}"
  echo "  ${_lwt_bold}doctor${_lwt_reset}       ${_lwt_dim}Check required and optional tooling${_lwt_reset}"
  echo "  ${_lwt_bold}help${_lwt_reset}         ${_lwt_dim}Show command help${_lwt_reset}"
  echo
  lwt::ui::header "Examples"
  echo "  lwt a my-feature                           ${_lwt_dim}Create a new worktree${_lwt_reset}"
  echo "  lwt a existing-branch                      ${_lwt_dim}Check out an existing branch without prompting${_lwt_reset}"
  echo "  lwt a my-feature --claude \"fix...\"         ${_lwt_dim}Create and launch an agent${_lwt_reset}"
  echo "  lwt a my-feature --claude \"fix\" --codex \"review\" ${_lwt_dim}First agent here, second in split${_lwt_reset}"
  echo "  lwt a my-feature -yolo --claude \"fix...\"   ${_lwt_dim}Launch agent with full auto-approve${_lwt_reset}"
  echo "  lwt rm my-feature --yes                    ${_lwt_dim}Remove a worktree without an interactive prompt${_lwt_reset}"
  echo "  lwt rm my-feature --yes --force            ${_lwt_dim}Also discard local changes if needed${_lwt_reset}"
  echo "  lwt a my-feature -e                        ${_lwt_dim}Create and open in editor${_lwt_reset}"
  echo "  lwt a my-feature -s                        ${_lwt_dim}Create and install dependencies${_lwt_reset}"
  echo "  lwt a my-feature -d                        ${_lwt_dim}Run the repo dev command in place${_lwt_reset}"
  echo "  lwt co                                     ${_lwt_dim}Pick an open PR and create its worktree${_lwt_reset}"
  echo "  lwt s                                      ${_lwt_dim}Switch worktree with fzf${_lwt_reset}"
  echo "  lwt ls                                     ${_lwt_dim}List all worktrees${_lwt_reset}"
  echo "  lwt merge                                  ${_lwt_dim}Squash-merge the current worktree into the default branch${_lwt_reset}"
  echo "  lwt config show                            ${_lwt_dim}See effective settings and where they come from${_lwt_reset}"
  echo "  lwt config set dev-cmd \"pnpm dev\"         ${_lwt_dim}Persist the repo dev command${_lwt_reset}"
  echo "  lwt config add copy-on-create apps/typefully-web/.browser-auth.json ${_lwt_dim}Copy extra project files into new worktrees${_lwt_reset}"
  echo
  lwt::ui::header "Config"
  echo "  lwt config set editor zed                   ${_lwt_dim}Editor to open worktrees in${_lwt_reset}"
  echo "  lwt config set agent-mode yolo              ${_lwt_dim}Auto-approve all agent actions${_lwt_reset}"
  echo "  lwt config set dev-cmd \"pnpm dev\"          ${_lwt_dim}Default command for --dev${_lwt_reset}"
  echo "  lwt config set terminal ghostty             ${_lwt_dim}Preferred terminal driver for splits/tabs${_lwt_reset}"
  echo "  lwt config add copy-on-create path/to/file  ${_lwt_dim}Repeatable repo-local copies for add/checkout${_lwt_reset}"
}

lwt::ui::help_automation() {
  echo "${_lwt_bold}Usage:${_lwt_reset} lwt help automation"
  echo
  lwt::ui::header "Prefer Explicit Targets"
  echo "  ${_lwt_dim}Use explicit branch/query args when calling lwt from agents or scripts.${_lwt_reset}"
  echo "  ${_lwt_dim}lwt remove skips fzf when the query exactly matches a branch, worktree path, or worktree directory.${_lwt_reset}"
  echo "  ${_lwt_dim}Bare lwt rm, lwt switch, and lwt checkout still open fzf pickers.${_lwt_reset}"
  echo
  lwt::ui::header "Non-Interactive Patterns"
  echo "  lwt a feat-auth                            ${_lwt_dim}Create a worktree, or check out an existing branch, without confirmation${_lwt_reset}"
  echo "  lwt rm feat-auth --yes                     ${_lwt_dim}Remove the worktree without the delete prompt${_lwt_reset}"
  echo "  lwt rm feat-auth --yes --force             ${_lwt_dim}Also discard local changes and force local branch cleanup${_lwt_reset}"
  echo "  lwt rm feat-auth --yes --delete-remote     ${_lwt_dim}Also delete the remote branch or close the open PR${_lwt_reset}"
  echo
  lwt::ui::header "Agent Notes"
  echo "  ${_lwt_dim}-yolo and agent-mode yolo control Claude/Codex/Gemini permissions, not lwt confirmations.${_lwt_reset}"
  echo "  ${_lwt_dim}If you need picker-based flows, run lwt in a real TTY.${_lwt_reset}"
}

lwt::ui::help_add() {
  echo "${_lwt_bold}Usage:${_lwt_reset} lwt add [branch] [options]"
  echo
  lwt::ui::header "Options"
  echo "  ${_lwt_bold}-s, --setup${_lwt_reset}              ${_lwt_dim}Install dependencies after creating the worktree${_lwt_reset}"
  echo "  ${_lwt_bold}-e, --editor${_lwt_reset}             ${_lwt_dim}Open the worktree in your editor${_lwt_reset}"
  echo "  ${_lwt_bold}--editor-cmd \"cmd\"${_lwt_reset}       ${_lwt_dim}Override editor command for this run${_lwt_reset}"
  echo "  ${_lwt_bold}--claude [\"prompt\"]${_lwt_reset}      ${_lwt_dim}Launch Claude (with optional quoted prompt)${_lwt_reset}"
  echo "  ${_lwt_bold}--codex [\"prompt\"]${_lwt_reset}       ${_lwt_dim}Launch Codex (with optional quoted prompt)${_lwt_reset}"
  echo "  ${_lwt_bold}--gemini [\"prompt\"]${_lwt_reset}      ${_lwt_dim}Launch Gemini (with optional quoted prompt)${_lwt_reset}"
  echo "  ${_lwt_bold}--agents list [\"prompt\"]${_lwt_reset} ${_lwt_dim}Launch agents from a comma-separated list with a shared prompt${_lwt_reset}"
  echo "  ${_lwt_bold}--split \"cmd\"${_lwt_reset}            ${_lwt_dim}Run a command in a new terminal split${_lwt_reset}"
  echo "  ${_lwt_bold}--tab \"cmd\"${_lwt_reset}              ${_lwt_dim}Run a command in a new terminal tab${_lwt_reset}"
  echo "  ${_lwt_bold}-d, --dev${_lwt_reset}                 ${_lwt_dim}Run the repo's dev command (in place, or split if an agent is running)${_lwt_reset}"
  echo "  ${_lwt_bold}-yolo${_lwt_reset}                    ${_lwt_dim}Give agents full auto-approve permissions${_lwt_reset}"
  echo "  ${_lwt_bold}-h, --help${_lwt_reset}               ${_lwt_dim}Show help${_lwt_reset}"
  echo
  lwt::ui::header "Notes"
  echo "  ${_lwt_dim}If branch is omitted, lwt generates a random branch name.${_lwt_reset}"
  echo "  ${_lwt_dim}New branches are created from the resolved default branch.${_lwt_reset}"
  echo "  ${_lwt_dim}Existing local or origin branches are checked out without prompting.${_lwt_reset}"
  echo "  ${_lwt_dim}First agent runs in your shell; additional agents open in splits automatically.${_lwt_reset}"
  echo "  ${_lwt_dim}Each agent flag takes its own prompt: --claude \"fix auth\" --codex \"review tests\"${_lwt_reset}"
  echo "  ${_lwt_dim}Hyphen aliases like --claude-codex share one prompt across all agents in the alias.${_lwt_reset}"
  echo "  ${_lwt_dim}When an agent flag is used, dependencies are always installed.${_lwt_reset}"
  echo "  ${_lwt_dim}Set dev-cmd for monorepos or non-standard dev commands with lwt config set dev-cmd ...${_lwt_reset}"
  echo "  ${_lwt_dim}Use lwt config add copy-on-create <repo-path> for extra files or directories copied into new worktrees.${_lwt_reset}"
  echo "  ${_lwt_dim}Configured directories copy recursively into the same relative path. Use hooks only for scripted logic.${_lwt_reset}"
  echo "  ${_lwt_dim}Split/tab automation currently supports Ghostty and iTerm2 on macOS.${_lwt_reset}"
  echo "  ${_lwt_dim}Set yolo globally with: lwt config set agent-mode yolo${_lwt_reset}"
}

lwt::ui::help_switch() {
  echo "${_lwt_bold}Usage:${_lwt_reset} lwt switch [query] [options]"
  echo
  lwt::ui::header "Options"
  echo "  ${_lwt_bold}-e, --editor${_lwt_reset}           ${_lwt_dim}Open selected worktree in your editor${_lwt_reset}"
  echo "  ${_lwt_bold}--editor-cmd \"cmd\"${_lwt_reset}     ${_lwt_dim}Override editor command for this run${_lwt_reset}"
  echo "  ${_lwt_bold}-h, --help${_lwt_reset}             ${_lwt_dim}Show help${_lwt_reset}"
}

lwt::ui::help_checkout() {
  echo "${_lwt_bold}Usage:${_lwt_reset} lwt checkout [query] [options]"
  echo
  lwt::ui::header "Options"
  echo "  ${_lwt_bold}-e, --editor${_lwt_reset}           ${_lwt_dim}Open the selected worktree in your editor${_lwt_reset}"
  echo "  ${_lwt_bold}--editor-cmd \"cmd\"${_lwt_reset}     ${_lwt_dim}Override editor command for this run${_lwt_reset}"
  echo "  ${_lwt_bold}-h, --help${_lwt_reset}             ${_lwt_dim}Show help${_lwt_reset}"
  echo
  lwt::ui::header "Notes"
  echo "  ${_lwt_dim}Shows only open PRs that do not already have a worktree.${_lwt_reset}"
  echo "  ${_lwt_dim}Use switch to move to an existing worktree.${_lwt_reset}"
  echo "  ${_lwt_dim}Use add when you want to create a worktree from an explicit branch name.${_lwt_reset}"
  echo "  ${_lwt_dim}When checkout creates a new worktree, post-create and post-switch hooks run automatically.${_lwt_reset}"
}

lwt::ui::help_list() {
  echo "${_lwt_bold}Usage:${_lwt_reset} lwt list"
  echo
  echo "  ${_lwt_dim}Shows all worktrees with remote-aware status.${_lwt_reset}"
}

lwt::ui::help_merge() {
  echo "${_lwt_bold}Usage:${_lwt_reset} lwt merge [target-branch] [options]"
  echo
  echo "  ${_lwt_dim}Squash-merges the selected worktree into the target branch.${_lwt_reset}"
  echo "  ${_lwt_dim}If the branch has an open PR, lwt merges that PR through GitHub with gh.${_lwt_reset}"
  echo "  ${_lwt_dim}Defaults to merge-target, or the repo default branch if unset.${_lwt_reset}"
  echo
  lwt::ui::header "Options"
  echo "  ${_lwt_bold}--keep-worktree${_lwt_reset}   ${_lwt_dim}Leave the merged worktree on disk${_lwt_reset}"
  echo "  ${_lwt_bold}--keep-branch${_lwt_reset}     ${_lwt_dim}Keep the merged local and remote branch${_lwt_reset}"
  echo "  ${_lwt_bold}--no-push${_lwt_reset}         ${_lwt_dim}Do not push the target branch after merging${_lwt_reset}"
  echo "  ${_lwt_bold}--admin${_lwt_reset}           ${_lwt_dim}Pass --admin to gh pr merge when merging a PR${_lwt_reset}"
  echo "  ${_lwt_bold}-h, --help${_lwt_reset}        ${_lwt_dim}Show help${_lwt_reset}"
  echo
  lwt::ui::header "Notes"
  echo "  ${_lwt_dim}With an open PR: gh pr merge --squash, then local cleanup.${_lwt_reset}"
  echo "  ${_lwt_dim}Without a PR: local rebase, squash, push, then cleanup.${_lwt_reset}"
  echo "  ${_lwt_dim}If GitHub says bypass/admin is required, lwt offers an interactive retry with --admin.${_lwt_reset}"
}

lwt::ui::help_remove() {
  echo "${_lwt_bold}Usage:${_lwt_reset} lwt remove [query] [options]"
  echo
  lwt::ui::header "Options"
  echo "  ${_lwt_bold}-y, --yes${_lwt_reset}             ${_lwt_dim}Skip the delete confirmation prompt${_lwt_reset}"
  echo "  ${_lwt_bold}-f, --force${_lwt_reset}           ${_lwt_dim}Discard local changes if needed and force local branch cleanup${_lwt_reset}"
  echo "  ${_lwt_bold}--delete-remote${_lwt_reset}       ${_lwt_dim}Delete the remote branch, or close its open PR, without prompting${_lwt_reset}"
  echo "  ${_lwt_bold}-h, --help${_lwt_reset}            ${_lwt_dim}Show help${_lwt_reset}"
  echo
  lwt::ui::header "Notes"
  echo "  ${_lwt_dim}If called inside a linked worktree, that worktree is selected automatically.${_lwt_reset}"
  echo "  ${_lwt_dim}An exact branch/path/directory query removes directly; otherwise an fzf picker is shown.${_lwt_reset}"
  echo "  ${_lwt_dim}Use --yes for agents and scripts. Add --force when dirty worktrees should be discarded too.${_lwt_reset}"
  echo "  ${_lwt_dim}Without --delete-remote, non-interactive removal keeps remote branches and open PRs by default.${_lwt_reset}"
}

lwt::ui::help_clean() {
  echo "${_lwt_bold}Usage:${_lwt_reset} lwt clean [options]"
  echo
  echo "  ${_lwt_dim}Finds all merged worktrees and removes them in one go.${_lwt_reset}"
  echo
  lwt::ui::header "Options"
  echo "  ${_lwt_bold}-n, --dry-run${_lwt_reset}    ${_lwt_dim}Show what would be removed without deleting anything${_lwt_reset}"
  echo "  ${_lwt_bold}-h, --help${_lwt_reset}       ${_lwt_dim}Show help${_lwt_reset}"
  echo
  lwt::ui::header "Notes"
  echo "  ${_lwt_dim}Uses the same merge detection as lwt list (including squash-merge via gh).${_lwt_reset}"
  echo "  ${_lwt_dim}Skips the main repository worktree.${_lwt_reset}"
  echo "  ${_lwt_dim}Prompts for confirmation before deleting unless --dry-run is set.${_lwt_reset}"
}

lwt::ui::help_rename() {
  echo "${_lwt_bold}Usage:${_lwt_reset} lwt rename <new-name>"
  echo
  echo "  ${_lwt_dim}Renames a worktree's branch and moves its directory to match.${_lwt_reset}"
  echo
  echo "  ${_lwt_dim}If called inside a linked worktree, that worktree is selected automatically.${_lwt_reset}"
  echo "  ${_lwt_dim}Otherwise an fzf picker is shown.${_lwt_reset}"
  echo
  lwt::ui::header "Options"
  echo "  ${_lwt_bold}-h, --help${_lwt_reset}    ${_lwt_dim}Show help${_lwt_reset}"
  echo
  lwt::ui::header "Notes"
  echo "  ${_lwt_dim}The main repository worktree cannot be renamed.${_lwt_reset}"
  echo "  ${_lwt_dim}If a remote branch exists, it will be renamed automatically.${_lwt_reset}"
  echo "  ${_lwt_dim}Open PRs are recreated on the new branch when gh is available.${_lwt_reset}"
  echo "  ${_lwt_dim}If an AI agent is running in the worktree, it will need to be restarted.${_lwt_reset}"
}

lwt::ui::help_doctor() {
  echo "${_lwt_bold}Usage:${_lwt_reset} lwt doctor"
  echo
  echo "  ${_lwt_dim}Checks required dependencies, optional integrations, and active hook directories.${_lwt_reset}"
}

lwt::ui::help_config() {
  echo "${_lwt_bold}Usage:${_lwt_reset} lwt config [show|get|set|add|unset] ..."
  echo
  lwt::ui::header "Commands"
  echo "  ${_lwt_bold}show${_lwt_reset}                          ${_lwt_dim}Show the core settings you are expected to care about${_lwt_reset}"
  echo "  ${_lwt_bold}get <key>${_lwt_reset}                     ${_lwt_dim}Print a setting's effective value${_lwt_reset}"
  echo "  ${_lwt_bold}set <key> <value>${_lwt_reset}             ${_lwt_dim}Persist a setting${_lwt_reset}"
  echo "  ${_lwt_bold}add <key> <value>${_lwt_reset}             ${_lwt_dim}Append a value to a repeatable setting${_lwt_reset}"
  echo "  ${_lwt_bold}unset <key>${_lwt_reset}                   ${_lwt_dim}Remove a persisted setting${_lwt_reset}"
  echo
  lwt::ui::header "Scope Flags"
  echo "  ${_lwt_bold}--global${_lwt_reset}                      ${_lwt_dim}Write to ~/.gitconfig${_lwt_reset}"
  echo "  ${_lwt_bold}--local${_lwt_reset}                       ${_lwt_dim}Write to the current repo config${_lwt_reset}"
  echo "  ${_lwt_bold}--all${_lwt_reset}                         ${_lwt_dim}Show advanced/internal settings too${_lwt_reset}"
  echo
  lwt::ui::header "Keys"
  echo "  ${_lwt_bold}editor${_lwt_reset}                        ${_lwt_dim}Global by default${_lwt_reset}"
  echo "  ${_lwt_bold}agent-mode${_lwt_reset}                    ${_lwt_dim}Global by default; interactive or yolo${_lwt_reset}"
  echo "  ${_lwt_bold}dev-cmd${_lwt_reset}                       ${_lwt_dim}Local by default${_lwt_reset}"
  echo "  ${_lwt_bold}terminal${_lwt_reset}                      ${_lwt_dim}Global by default; auto, ghostty, iterm2${_lwt_reset}"
  echo "  ${_lwt_bold}merge-target${_lwt_reset}                  ${_lwt_dim}Local by default${_lwt_reset}"
  echo "  ${_lwt_bold}copy-on-create${_lwt_reset}                ${_lwt_dim}Local by default; repeatable repo-relative file/dir copied by add/checkout${_lwt_reset}"
  echo
  echo "  ${_lwt_dim}Directories configured in copy-on-create are copied recursively into the same relative path.${_lwt_reset}"
  echo "  ${_lwt_dim}Advanced hook settings exist, but they are intentionally hidden from the default output.${_lwt_reset}"
}

lwt::ui::help_hook() {
  echo "${_lwt_bold}Usage:${_lwt_reset} lwt hook <list|path|run> [event]"
  echo
  echo "  ${_lwt_dim}Advanced lifecycle automation. Prefer copy-on-create for simple file or directory copies.${_lwt_reset}"
  echo
  lwt::ui::header "Why"
  echo "  ${_lwt_dim}Use hooks when a repo always needs the same scripted setup or check step at worktree lifecycle moments.${_lwt_reset}"
  echo "  ${_lwt_dim}Good examples: warm a cache on create, print a local URL on switch, run a fast check before merge.${_lwt_reset}"
  echo
  lwt::ui::header "Where"
  echo "  ${_lwt_dim}Repo hooks: .lwt/hooks/<event>${_lwt_reset}"
  echo "  ${_lwt_dim}User hooks: ~/.config/lwt/hooks/<event>${_lwt_reset}"
  echo
  lwt::ui::header "Examples"
  echo "  lwt hook list"
  echo "  lwt hook path post-create"
  echo "  lwt hook run pre-merge"
}
