# Amao Harness

Amao Harness is a **local engineering harness for AI-assisted development**. It
provides durable agent instructions and a local workspace for engineering tasks
without adding those artifacts to the product repository.

> Harness is local; product code is shared.

## Install

```bash
git clone git@github.com:Amao-yeye/Amao_harness.git ~/Amao_harness

cd ~/projects/my_project
~/Amao_harness/install.sh .
```

The installer locates the Git repository root, copies `AGENTS.md`, creates
`docs/agents/`, and adds both paths to the repository-local
`.git/info/exclude`. It does not change the shared `.gitignore` or overwrite an
existing tracked or conflicting local `AGENTS.md`.

## Create a task workspace

```bash
~/Amao_harness/scripts/new-task.sh . visual_frontend
```

Task names are single path components made from letters, numbers, `.`, `_`, and
`-`.

After creating a task, the project looks like this:

```text
project/
├── AGENTS.md
├── docs/
│   └── agents/
│       └── visual_frontend/
│           ├── persistent/
│           ├── working/
│           └── scratch/
└── src/
```

`AGENTS.md` and `docs/agents/` remain local through `.git/info/exclude`; product
code and the team's shared Git files remain unchanged.

## Verify

```bash
tests/run.sh
```
