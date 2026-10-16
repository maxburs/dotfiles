---
name: codebase-design
description: >
  Vocabulary and conventions for deep modules — a lot of behavior behind a small
  interface. Use when the user wants to design or improve a module's interface,
  find deepening opportunities, decide what a folder should expose, or make code
  more testable or AI-navigable. Also use when the user says "deep module", "make
  this a module", "what's the public API of this folder", "too many exports", or
  "test through the public interface".
---

# Codebase Design

Design **deep modules**: a lot of behavior behind a small interface, placed at a clean seam, testable through that interface. Use this language and these principles wherever code is being designed or restructured. The aim is leverage for callers, locality for maintainers, and testability for everyone.

## Glossary

Use these terms exactly: don't substitute "component," "service," "API," or "boundary." Consistent language is the whole point.

**Module**: Anything with an interface and an implementation. Deliberately scale-agnostic: a function, class, package, or tier-spanning slice.

**Interface**: Everything a caller must know to use the module correctly: the type signature, but also invariants, ordering constraints, thrown errors, required configuration, etc.

**Implementation**: Inside of a module—it's code. Does not include public types.

**Depth**: Leverage at the interface. The amount of behavior a caller (or test) can exercise per unit of interface they have to learn. A module is **deep** when a large amount of behavior sits behind a small interface, **shallow** when the interface is nearly as complex as the implementation.

**Leverage**: What callers get from depth. More capability per unit of interface they learn.

**Locality**: What maintainers get from depth. Change, bugs, knowledge, and verification concentrate in one place rather than spreading across callers.

## Best practices

- Bias towards organizing code where it's used / by feature, instead of by type
  - For example, a page-specific hook should be inside a page-specific folder along with the page component itself
- A deep, multi-file module enforces its public interface through file naming: a file with no consumer outside its own folder is private, and says so in its name

## The convention

| | |
|---|---|
| `foo.ts` | Public. Anything may import it. |
| `_foo.ts` | Private to its folder **and everything nested under it**. |
| `_foo/bar.ts` | bar.ts is private to the folder `_foo/` is in |

ESLint enforces it (`no-restricted-imports`, `privateModuleImport` in
`.eslintrc.js`). The pattern exempts purely-upward specifiers, so:

- `./_foo` — sibling, allowed
- `./_foo/bar.ts` — sibling folder, allowed
- `../_foo`, `../../_foo` — a nested helper reading its module's internals, allowed
- `../sibling/_foo` — sideways into another folder, **banned**
- `./nested/_foo` — down into a child's internals, **banned**
- `@tmsl/…/_foo`, `#src/…/_foo` — **banned**


## Test through the front door

Tests are callers. A test that reaches past the public interface misses the depth
it was supposed to prove and pins the implementation in place.

An internal test has to earn its place, and only one argument does that: **the
front door cannot observe this.**

Not valid reasons to test internals: it is fiddly to set up, it would need a
fixture builder. Build the fixture helper, so that a case is one line.

