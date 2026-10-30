---
description: "JavaScript style guide"
applyTo: "**/*.{mts,mjs,cts,cjs,ts,tsx,js,jsx}"
---

Repo-specific guidance trumps these instructions

- Top-level functions should use the `function` keyword
- Avoid default exports
- Prefer `for` loops over `.forEach()`
- If there's any ambiguity on what we could be checking, use explicit boolean expressions instead of relying on truthy-ness. For example, instead of `!num` write `num === null` so it's clear we're not checking for `0`.
- Prefer numeric equality over greater than / less than operators. For example, write `index === -1` instead of `index < 0`
- Types used in exported declarations’ public signatures should also be exported
- No need to use `Set` with a small number of items—`Array.prototype.includes()` will be faster and let us avoid writing `new Set()`
- Guard expected and impossible (bug) conditions separately: handle expected ones normally (e.g., early `return`), but check impossible ones with `assert()`—falling back to `throw` only if no assert function is available
