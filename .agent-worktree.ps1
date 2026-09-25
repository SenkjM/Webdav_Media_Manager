# .agent-worktree.ps1
# Manage per-agent git worktrees so multiple agents can work on separate
# branches in separate directories without checking out the same files.
#
# Usage:
#   ./agent-worktree.ps1 new    <name> [base-branch]   # create .agents/<name> on new branch <name>
#   ./agent-worktree.ps1 attach <name> <existing-branch> [base]  # create worktree tracking an existing branch
#   ./agent-worktree.ps1 list
#   ./agent-worktree.ps1 path   <name>                 # print the worktree path
#   ./agent-worktree.ps1 remove <name>                # remove worktree + delete its branch

param(
  [Parameter(Position=0, Mandatory=$true)] [string] $Command,
  [Parameter(Position=1)] [string] $Name,
  [Parameter(Position=2)] [string] $Branch,
  [Parameter(Position=3)] [string] $Base = "HEAD"
)

$ErrorActionPreference = "Stop"
$root  = (git rev-parse --show-toplevel).Trim()
if (-not $root) { Write-Error "Not inside a git repository."; exit 1 }
$agentsDir = Join-Path $root ".agents"

switch ($Command) {
  "new" {
    if (-not $Name) { Write-Error "NAME required"; exit 1 }
    $wt = Join-Path $agentsDir $Name
    git worktree add $wt -b $Name $Base
    Write-Output "Created worktree at: $wt  (branch: $Name)"
  }
  "attach" {
    if (-not $Name -or -not $Branch) { Write-Error "NAME and BRANCH required"; exit 1 }
    $wt = Join-Path $agentsDir $Name
    git worktree add $wt $Branch
    Write-Output "Attached worktree at: $wt  (tracks branch: $Branch)"
  }
  "list" {
    git worktree list
  }
  "path" {
    if (-not $Name) { Write-Error "NAME required"; exit 1 }
    $wt = Join-Path $agentsDir $Name
    if (Test-Path $wt) { Write-Output $wt } else { Write-Error "No worktree named $Name"; exit 1 }
  }
  "remove" {
    if (-not $Name) { Write-Error "NAME required"; exit 1 }
    $wt = Join-Path $agentsDir $Name
    git worktree remove --force $wt
    # delete the branch too (force, since unmerged)
    git branch -D $Name 2>$null
    Write-Output "Removed worktree $Name"
  }
  default {
    Write-Error "Unknown command: $Command"; exit 1
  }
}
