# Amao Harness

Amao Harness is a local engineering workflow for long-term software and research projects.

Its purpose is to improve the reliability of AI-assisted engineering while keeping temporary agent artifacts isolated from the shared project repository.

---

## Rule 0 — Harness and Project Isolation

**Harness is local; product code is shared.**

Amao Harness is an external engineering layer, not part of the product itself.

Local agent instructions, intermediate reviews, temporary plans, and interaction records must not be committed to the shared project repository unless explicitly promoted into official project documentation.

Typical local-only files include:

```text
AGENTS.md
docs/agents/
```

These files should be excluded locally through:

```text
.git/info/exclude
```

Do not modify the team's `.gitignore` merely for Amao Harness.

Do not create a nested Git repository inside the target project.

The target project's existing Git repository remains the only repository responsible for version-controlling the project.

---

## Rule 1 — GPT–Codex Review Harness

Non-trivial engineering tasks should follow the review process below before implementation.

### Stage 1 — GPT Initial Design

GPT produces:

- algorithm or engineering approach;
- module decomposition;
- implementation steps;
- expected interfaces;
- acceptance criteria.

### Stage 2 — Codex Repository Grounding Review

Codex inspects the actual local repository and checks:

- whether assumed interfaces actually exist;
- whether file paths and module structures are correct;
- whether existing implementations can be reused;
- whether dependencies and data formats match;
- whether GPT made incorrect assumptions about the project.

During this stage:

**Review only. Do not modify code.**

### Stage 3 — GPT Revision and Codex Minimality Review

GPT revises the design based on the grounding review.

Codex performs a second review focused on:

- redundant steps;
- duplicated implementations;
- unnecessary abstractions;
- excessive changes;
- opportunities to reuse existing code;
- whether the proposed change is the smallest reasonable implementation.

### Stage 4 — Final Specification, Implementation and Verification

GPT freezes the final engineering specification.

Codex then performs the implementation.

After implementation, Codex reports:

- modified files;
- relevant diff summary;
- tests performed;
- test results;
- deviations from the specification;
- unresolved failures or risks.

The implementation is considered complete only after confirming that the resulting behavior matches the original engineering objective.

---

## Agent Interaction Files

For long-running projects, task-specific interaction artifacts are stored locally under:

```text
docs/agents/<sub_task_name>/
├── persistent/
├── working/
└── scratch/
```

### `persistent/`

Contains information worth retaining after the task is complete, such as:

- final specifications;
- important engineering decisions;
- implementation summaries;
- validated conclusions.

### `working/`

Contains active intermediate material, such as:

- review feedback;
- revised proposals;
- investigation notes.

These files may be deleted after the task is completed.

### `scratch/`

Contains disposable temporary material.

Files in this directory may be deleted at any time once they are no longer required.

---

## Rule 2 — Core Promotion and Experimental Isolation

Only stable, reusable, release-quality project code may enter:

```text
src/
```

Moving validated code into `src/` is called **promotion** or **入库**.

Experimental implementations must remain outside `src/`.

Before promotion, experimental code may prioritize iteration speed and exploration. After a solution has been validated, it must be cleaned, reviewed, given stable interfaces, and tested before entering `src/`.

Experimental code must remain disposable.

After the validated implementation has been promoted into `src/`, deleting the corresponding experimental implementation must not break the main project.

Therefore:

**`src/` must never depend on disposable experimental code.**

A typical lifecycle is:

```text
idea
  ↓
experiment
  ↓
validation
  ↓
review
  ↓
cleanup
  ↓
promotion into src/
  ↓
delete obsolete experimental code
```

---

## Core Principle

Amao Harness separates three things clearly:

```text
Reasoning and review     → docs/agents/
Experimental exploration → outside src/
Validated project code   → src/
```

The objective is to keep the shared project repository stable while allowing AI agents to explore, review, challenge, and iterate freely in the local engineering workspace.
