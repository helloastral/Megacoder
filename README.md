# MegaCoder Skill

MegaCoder is an OpenClaw skill for a two-stage coding workflow:

1. **Codex CLI plans first** (architecture, tasks, open questions)
2. **Claude Code CLI implements** after human approval

This keeps planning and execution separated, with explicit decision tracking.

## Repository contents

- `SKILL.md` — skill definition and orchestration instructions
- `references/workflow.md` — detailed process and guardrails
- `references/prompt-templates.md` — reusable prompts for Codex/Claude
- `scripts/run-codex-plan.sh` — planner runner
- `scripts/run-claude-implement.sh` — implementation runner

## Prerequisites

On the machine running OpenClaw:

- `codex` CLI installed and authenticated
- `claude` CLI installed and authenticated
- Bash shell available

Quick checks:

```bash
which codex
which claude
```

## Install in OpenClaw

### Option A: Clone into workspace skills directory

```bash
cd /root/.openclaw/workspace/skills
git clone https://github.com/helloastral/Megacoder.git mega-coder
```

### Option B: Use packaged file

A packaged skill file can be generated as:

```bash
python3 /usr/lib/node_modules/openclaw/skills/skill-creator/scripts/package_skill.py \
  /root/.openclaw/workspace/skills/mega-coder \
  /root/.openclaw/workspace/skills/dist
```

This produces:

- `/root/.openclaw/workspace/skills/dist/mega-coder.skill`

## Usage

In your project folder, create a hidden state directory and ignore it:

```bash
mkdir -p .megacoder
echo ".megacoder/" >> .gitignore
```

Inside `.megacoder/`, use:

- `ROUGH_DRAFT.md`
- `PLAN.md`
- `QUESTIONS.md`
- `DECISIONS.md`
- `TASKS.md`

Run planning:

```bash
bash /root/.openclaw/workspace/skills/mega-coder/scripts/run-codex-plan.sh /path/to/project
```

Answer questions in `.megacoder/DECISIONS.md` until `.megacoder/QUESTIONS.md` becomes `NONE`.

Then run implementation:

```bash
bash /root/.openclaw/workspace/skills/mega-coder/scripts/run-claude-implement.sh /path/to/project
```

## Recommended workflow in chat

Ask OpenClaw with phrasing like:

- "Use MegaCoder for this project"
- "Run MegaCoder planning first"
- "Continue MegaCoder and start implementation"

## Notes

- Implementation is blocked if `QUESTIONS.md` is not `NONE`
- Keep decisions explicit in `DECISIONS.md`
- Re-run planning whenever scope changes
