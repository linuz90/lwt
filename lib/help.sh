lwt::ui::help_main() {
  echo "${_lwt_bold}Usage:${_lwt_reset} lwt <command> [options]"
  echo
  lwt::ui::header "Commands"
  echo "  ${_lwt_bold}add, a${_lwt_reset}       ${_lwt_dim}Create or check out a worktree branch${_lwt_reset}"
  echo "  ${_lwt_bold}checkout, co${_lwt_reset} ${_lwt_dim}Pick an open PR and spawn a worktree${_lwt_reset}"
  echo "  ${_lwt_bold}switch, s${_lwt_reset}    ${_lwt_dim}Switch to a worktree via fzf${_lwt_reset}"
  echo "  ${_lwt_bold}list, ls${_lwt_reset}     ${_lwt_dim}List worktrees with live status${_lwt_reset}"
  echo "  ${_lwt_bold}remove, rm${_lwt_reset}   ${_lwt_dim}Remove a worktree safely${_lwt_reset}"
  echo "  ${_lwt_bold}clean${_lwt_reset}        ${_lwt_dim}Remove all merged worktrees at once${_lwt_reset}"
  echo "  ${_lwt_bold}rename, rn${_lwt_reset}   ${_lwt_dim}Rename a worktree and its branch${_lwt_reset}"
  echo "  ${_lwt_bold}doctor${_lwt_reset}       ${_lwt_dim}Check required and optional tooling${_lwt_reset}"
  echo "  ${_lwt_bold}help${_lwt_reset}         ${_lwt_dim}Show command help${_lwt_reset}"
  echo
  lwt::ui::header "Examples"
  echo "  lwt a my-feature                           ${_lwt_dim}Create a new worktree${_lwt_reset}"
  echo "  lwt a my-feature -e                        ${_lwt_dim}Create and open in editor${_lwt_reset}"
  echo "  lwt a my-feature -s                        ${_lwt_dim}Create and install dependencies${_lwt_reset}"
  echo "  lwt a my-feature --claude \"fix...\"         ${_lwt_dim}Create and launch an agent${_lwt_reset}"
  echo "  lwt a my-feature --claude \"fix\" --codex \"review\" ${_lwt_dim}First agent here, second in split${_lwt_reset}"
  echo "  lwt a my-feature --claude-codex \"fix...\"   ${_lwt_dim}Launch multiple agents with one prompt${_lwt_reset}"
  echo "  lwt a my-feature -yolo --claude \"fix...\"   ${_lwt_dim}Launch agent with full auto-approve${_lwt_reset}"
  echo "  lwt a my-feature -d                        ${_lwt_dim}Run the repo dev command in place${_lwt_reset}"
  echo "  lwt co                                     ${_lwt_dim}Pick an open PR and create its worktree${_lwt_reset}"
  echo "  lwt s                                      ${_lwt_dim}Switch worktree with fzf${_lwt_reset}"
  echo "  lwt ls                                     ${_lwt_dim}List all worktrees${_lwt_reset}"
  echo "  lwt rm                                     ${_lwt_dim}Pick and remove a worktree${_lwt_reset}"
  echo
  lwt::ui::header "Config"
  echo "  git config --global lwt.editor code         ${_lwt_dim}Editor to open worktrees in${_lwt_reset}"
  echo "  git config --global lwt.agent-mode yolo     ${_lwt_dim}Auto-approve all agent actions${_lwt_reset}"
  echo "  git config --global lwt.dev-cmd \"pnpm dev\" ${_lwt_dim}Default command for --dev${_lwt_reset}"
  echo "  git config --global lwt.terminal ghostty    ${_lwt_dim}Preferred terminal driver for splits/tabs${_lwt_reset}"
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
  echo "  ${_lwt_dim}First agent runs in your shell; additional agents open in splits automatically.${_lwt_reset}"
  echo "  ${_lwt_dim}Each agent flag takes its own prompt: --claude \"fix auth\" --codex \"review tests\"${_lwt_reset}"
  echo "  ${_lwt_dim}Hyphen aliases like --claude-codex share one prompt across all agents in the alias.${_lwt_reset}"
  echo "  ${_lwt_dim}When an agent flag is used, dependencies are always installed.${_lwt_reset}"
  echo "  ${_lwt_dim}Set lwt.dev-cmd for monorepos or non-standard dev commands.${_lwt_reset}"
  echo "  ${_lwt_dim}Split/tab automation currently supports Ghostty and iTerm2 on macOS.${_lwt_reset}"
  echo "  ${_lwt_dim}Set yolo globally with: git config --global lwt.agent-mode yolo${_lwt_reset}"
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
}

lwt::ui::help_list() {
  echo "${_lwt_bold}Usage:${_lwt_reset} lwt list"
  echo
  echo "  ${_lwt_dim}Shows all worktrees with remote-aware status.${_lwt_reset}"
}

lwt::ui::help_remove() {
  echo "${_lwt_bold}Usage:${_lwt_reset} lwt remove [query]"
  echo
  echo "  ${_lwt_dim}If called inside a linked worktree, that worktree is selected automatically.${_lwt_reset}"
  echo "  ${_lwt_dim}Otherwise an fzf picker is shown.${_lwt_reset}"
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
  echo "  ${_lwt_dim}Checks required dependencies and optional integrations.${_lwt_reset}"
}
