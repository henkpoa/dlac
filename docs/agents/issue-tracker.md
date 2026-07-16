# Issue tracker: GitHub

Issues and PRDs for dlac live as GitHub issues on **henkpoa/dlac** (public). Use the
`gh` CLI for all operations; it infers the repo from `git remote -v` inside the clone.

## Conventions

- **Create an issue**: `gh issue create --title "..." --body "..."` (heredoc for multi-line bodies).
- **Read an issue**: `gh issue view <n> --comments`.
- **List issues**: `gh issue list --state open --json number,title,labels`.
- **Comment**: `gh issue comment <n> --body "..."`.
- **Labels**: `gh issue edit <n> --add-label "..."` / `--remove-label "..."`.
- **Close**: `gh issue close <n> --comment "..."`.

## Pull requests as a request surface

**No.** dlac is maintainer-driven; external PRs are not a triage surface. `/triage`
reads only issues.

## Event-driven agent — what makes an issue "ready for agent" actionable

`.github/workflows/issue-agent.yml` dispatches a cloud Claude agent when an issue gains
the `ready-for-agent` label **and** its title does not start with `PRD`. The agent reads
the issue plus the binding design docs, implements on a branch, runs the Lua suite, and
opens a PR that `Closes #<n>`.

- **Dispatch idiom:** creating an issue *with* the label already fires the event, so
  create issues unlabeled and toggle the label to dispatch:
  `gh issue edit <n> --remove-label ready-for-agent && gh issue edit <n> --add-label ready-for-agent`.
- **PRD umbrellas are skipped** by the gate (title starts with `PRD`) — they are planning
  artifacts decomposed via `/to-issues`, never implemented wholesale.
- **Effort tier:** default runs Opus 4.8; add `agent:max` for the hardest FFXI/engine
  issues (raises the turn budget). Packet-level work is local-only in this project and
  must never be labeled `ready-for-agent`.
- **Auth:** the workflow uses the `CLAUDE_CODE_OAUTH_TOKEN` repo secret
  (`claude setup-token` → `gh secret set`), which bills runs against the Claude
  subscription rather than metered API.

## When a skill says "publish to the issue tracker"

Create a GitHub issue on henkpoa/dlac.

## When a skill says "fetch the relevant ticket"

`gh issue view <n> --comments`.
