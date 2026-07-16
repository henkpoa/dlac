# Triage labels

The engineering skills speak in five canonical triage roles; this maps them to the label
strings on henkpoa/dlac.

| Canonical role    | dlac label        | Meaning                                            |
| ----------------- | ----------------- | -------------------------------------------------- |
| `needs-triage`    | `needs-triage`    | Maintainer needs to evaluate                       |
| `needs-info`      | `needs-info`      | Waiting on reporter                                |
| `ready-for-agent` | `ready-for-agent` | Fully specified, AFK-ready — dispatches the agent  |
| `ready-for-human` | `ready-for-human` | Needs human implementation (e.g. packet / GM work) |
| `wontfix`         | `wontfix`         | Will not be actioned                               |

## dlac-specific tier label

| Label       | Meaning                                                                            |
| ----------- | ---------------------------------------------------------------------------------- |
| `agent:max` | Raise the agent's turn budget for hard FFXI/engine issues. Applied *alongside* `ready-for-agent`; `issue-agent.yml` reads it. Absent = Opus 4.8 default tier. |

Only `ready-for-agent` and `agent:max` are load-bearing for the CI agent; the other four
power `/triage`'s human workflow. `wontfix` already exists among GitHub's default labels.
