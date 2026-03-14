# Global instructions

This file is loaded by every Claude session across all projects.
Put cross-cutting rules here: coding standards, workflow, communication style, etc.

---

## Development workflow

<!-- Example — replace with your actual process -->

1. Read the task, identify the minimal scope of changes needed.
2. Check existing tests before touching anything.
3. Make changes, run tests, fix failures before moving on.
4. Commit with a clear message explaining *why*, not just *what*.
5. Open a PR when the feature/fix is complete and tests pass.

## Code style

- Prefer explicit over implicit.
- No dead code, no commented-out blocks.
- Keep functions small and focused.

## Communication

- Be concise. Skip preamble and summaries.
- If blocked, say what you tried and what you need.
