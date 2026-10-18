---
description: "TypeScript style guide"
applyTo: "**/*.{mts,cts,ts,tsx}"
---

Repo-specific guidance trumps these instructions

- Avoid type assertions (`as`) when practical—use `satisfies`, restructure so assertions aren't necessary, or guard with a runtime check that throws
  - `as const` is fine
- Prefer `interface` over `type`
- Prefer `extends` over intersection types (`&`)
