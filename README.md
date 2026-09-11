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

## Update Harness

```bash
cd ~/Amao_harness
git pull

./update.sh ~/projects/my_project
```

Amao Harness updates are explicit, not automatic. Existing projects change only
when the user runs `update.sh`. The updater refuses to overwrite a locally
modified `AGENTS.md` or one tracked by the target project's Git repository.

## Create a task workspace

```bash
~/Amao_harness/scripts/new-task.sh . visual_frontend
```

Task names are single path components made from letters, numbers, `.`, `_`, and
`-`.

With the recommended code directories, the project layout looks like this:

```text
project/
├── AGENTS.md
├── docs/
│   └── agents/
│       └── visual_frontend/
│           ├── persistent/
│           ├── working/
│           └── scratch/
├── src/
├── tests/
└── debug/
```

`AGENTS.md` and `docs/agents/` remain local through `.git/info/exclude`; product
code and the team's shared Git files remain unchanged.

Long-term regression checks belong in `tests/`; temporary investigation and
debugging code belong in `debug/`. Code in `src/` must never depend on either.

## Verify

```bash
tests/run.sh
```
