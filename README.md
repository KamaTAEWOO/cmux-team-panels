# team-panels

**A cmux-based team-agent skill for Claude Code** — the Planner (PM/Lead) analyzes the task and picks only the specialist roles it needs, running them sequentially in an isolated workspace.

From a pool of 12 specialist roles (Planner · Researcher · Architect · DBA · Designer · UX Writer · Developer · Security · Code Reviewer · DevOps · Tester · Tech Writer), the Planner automatically composes the right combination. Each role runs as an independent `claude -p` process in its own panel, and when the final role finishes, the entire workspace is auto-closed (output files are preserved).

## Why this skill

Stuffing every perspective (planning, design, implementation, review…) into a single context causes predictable problems:

- **Context saturation**: role prompts bleed into each other and each output gets worse
- **Biased judgment**: the same agent both designs and reviews — it won't challenge its own decisions
- **Broken chains**: trying to do everything at once leads to skipped steps

team-panels spins up each specialist as a **separate `claude -p` process** with a clean, role-specific prompt, passing only the outputs of previous stages as context. All results are persisted to files, and the whole chain runs in a new cmux workspace so your current work area stays untouched.

## Key features

- **Isolated workspace**: the entire chain runs inside a freshly created cmux workspace → zero impact on your current work
- **Planner as team lead**: the Planner picks the necessary specialists via a `<next-roles>` marker
- **Focus preservation**: after spawning the new workspace, focus is restored to your original workspace
- **Sequential chain**: each panel spawns the next role's panel when it finishes
- **Clean shutdown**: once the last role finishes, the whole workspace is closed (output `.md` files remain on disk)
- **Default-chain fallback**: if the Planner leaves `<next-roles>` empty, a default chain of `03(Architect) · 05(Designer) · 07(Developer) · 11(Tester)` is forced

## Requirements

- [cmux](https://github.com/ibberson/cmux) terminal (binary path: `/Applications/cmux.app/Contents/Resources/bin/cmux`)
- [Claude Code](https://claude.com/claude-code) CLI
- Must run from inside a cmux terminal session (`$CMUX_WORKSPACE_ID` must be set)

## Install

Clone anywhere and run the installer:

```bash
git clone https://github.com/KamaTAEWOO/team-panels.git
cd team-panels
./install.sh
```

This follows the same convention as `ui-ux-pro-max`: the skill definition lives at `~/.claude/skills/team-panels.md` while resource scripts live at `~/.claude/skills/team-panels/scripts/`.

### What the installer does

```
~/.claude/skills/
├── team-panels.md          ← skill definition (frontmatter + usage)
└── team-panels/
    └── scripts/
        ├── run.sh          ← entry point (called by the skill)
        └── role.sh         ← per-panel role runner
```

## Usage

Invoke from inside a Claude Code session as a slash command:

```
/team-panels design a simple counter web app
/team-panels security review for the payment API
/team-panels prepare release
```

Claude Code may also auto-invoke it when it detects the intent in natural language ("let's do this as a team", "split into panels", etc.).

### Execution flow

```
/team-panels "<task description>"
  ↓
New cmux workspace is created (named: team-panels)
  ↓
[Planner] panel runs — analyzes requirements, picks follow-up roles
  ↓
<next-roles>03,05,07,11</next-roles>   ← emitted by Planner
  ↓
[Architect] → [Designer] → [Developer] → [Tester] run sequentially
  ↓
After 5s wait, the workspace is closed (output files remain)
```

## Role pool

| # | Role | Output |
|:---:|---|---|
| 01 | Planner (PM/Lead) | requirements, user stories, acceptance criteria, follow-up role selection |
| 02 | Researcher | market/competitor/user insights, reference cases |
| 03 | Architect | system diagrams, data flow, tech stack rationale |
| 04 | DBA | entities, schema, indexes, migration strategy |
| 05 | Designer | screen flow, components, interactions, wireframes |
| 06 | UX Writer | copy, error/success/empty-state text, tone & manner |
| 07 | Developer | file structure, function signatures, pseudocode, error handling |
| 08 | Security | STRIDE threats, OWASP checks, authn/authz, sensitive data handling |
| 09 | Code Reviewer | risks, improvement checklist, recommended refactors |
| 10 | DevOps/SRE | CI/CD, env configs, monitoring, rollback strategy |
| 11 | Tester (QA) | test pyramid, cases, automation scope |
| 12 | Tech Writer | README, API spec, onboarding guide |

## Recommended combinations

The Planner auto-selects a `<next-roles>` combination based on task type.

| Task type | Recommended combo |
|---|---|
| Simple copy/text edit | `06` |
| Simple web app (counter/memo/timer) | `03,05,07,11` (default chain) |
| General web feature | `02,03,05,07,09,11` |
| Feature with a database | `02,03,04,05,07,09,11` |
| Security-sensitive feature | `02,03,04,08,07,09,11` |
| Release / operationalization | `09,11,10,12` |
| Factual Q&A / one-line answer | `<next-roles></next-roles>` (Planner only) |

## Output location

Each run creates a unique timestamped work directory.

```
~/.cmux-team/20260419-104555/
├── TASK.md              # original task description
├── plan.tsv             # role execution plan
├── prompts/             # per-role system prompts
│   ├── 01.txt
│   ├── 02.txt
│   └── ...
└── outputs/             # per-role output (main results)
    ├── 01-Planner.md
    ├── 03-Architect.md
    ├── 05-Designer.md
    ├── 07-Developer.md
    └── 11-Tester.md
```

Even after the workspace closes, files under `outputs/` stay on disk — you can read them anytime.

## Repo layout

```
team-panels/
├── team-panels.md   # Claude Code skill metadata
├── scripts/
│   ├── run.sh       # entry point — creates workspace + runs first panel
│   └── role.sh      # per-panel single-role runner
├── install.sh       # copies files into ~/.claude/skills/
└── README.md        # this file
```

- `run.sh`: takes the task, creates the workdir, writes the 12-role definitions into `plan.tsv`, then runs the Planner role in the first terminal of a new workspace. Returns immediately so your focus isn't stolen.
- `role.sh`: runs inside each panel — executes `claude -p` for its role, saves the output, reads `plan.tsv` to spawn the next role's panel. If it's the last role, it closes the whole workspace.

## How it works

### The Planner chooses follow-up roles

The Planner prompt requires a `<next-roles>NUMBER,NUMBER,...</next-roles>` marker on the last line of its output. Only the listed role numbers run, in order.

If the tag is empty (`<next-roles></next-roles>`) or missing, the **default chain `03,05,07,11` is forced** as a safety fallback.

### Previous-stage outputs are passed forward

Each role collects all previously produced files under `outputs/` and injects them into the "previous stages" section of its own prompt. So the Designer reads the Planner's output, the Developer reads Planner + Architect + Designer, and so on.

### Focus restoration

Right after creating the new workspace, `run.sh` calls `select-workspace` to bring focus back to the original workspace. Every time a mid-chain role spawns the next panel, focus is restored again — your active work area is never hijacked.

### Fault tolerance

- If a role fails, the log is preserved in its output file and the next panel still opens.
- The workspace is cleanly closed even in partial-failure states.

## Limitations

- Only works inside a cmux terminal session (`$CMUX_WORKSPACE_ID` is required)
- The cmux binary path is hardcoded (`/Applications/cmux.app/Contents/Resources/bin/cmux`) — edit `run.sh` / `role.sh` if needed
- Each `claude -p` is launched with `--dangerously-skip-permissions` (file writes are auto-approved)
- Tested on macOS

## License

MIT

## Contributing

Issues and PRs welcome.
