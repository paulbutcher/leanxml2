# CLAUDE.md

Project-specific guidance for Claude Code when working in this repo.

## Project

`leanxml2` is a Lean 4 binding to libxml2, in two layers: a thin near-1:1 C
binding (`Leanxml2/FFI.lean` + `c/xml_shim.c`) and an idiomatic layer on top
(`Leanxml2/Doc.lean`, `Types.lean`, `Error.lean`, `XPath.lean`). See
README.md for the two-layer split, the node-lifetime design (and why it
matters for anyone calling `Leanxml2.FFI` directly), and the scope boundary:
what libxml2 functionality is bound so far versus deliberately deferred.
Read the README before changing either layer, and keep it up to date when
scope changes.

## Verifying Lean changes

- After editing a `.lean` file, verify it with `mcp__lean-lsp__lean_diagnostic_messages`
  (or other lean-lsp-mcp tools, e.g. `lean_goal`/`lean_multi_attempt` for
  interactive proof/termination work), if that tool is available in your
  environment.
- Ignore the editor's `<ide_diagnostics>` hook output.
- Before considering a task complete, run both `lake build` and `lake test` from the
  repo root as the final ground truth.
- If a change adds or removes an `import`, use `mcp__lean-lsp__lean_build`
  instead of (or in addition to) plain `lake build`.
- All Lean code should compile without warnings.

## Commenting

- Only add comments which say something over and above what the source code already
  says. Avoid comments which restate what can be derived easily by reading the code.
- This includes header comments for both files and functions. Avoid them unless they
  add real value.
- Do add comments when it's not clear *why* the code is doing what it does just
  from reading the code.
- Don't refer to previous implementations or rejected designs unless doing so is
  essential to understand the code.
- Don't mention project plans, milestones, ticket numbers, or anything similar in
  comments. Comments should remain valid years ahead, when people will not care
  about the process that led to them.
- Don't add comments explaining Lean language features or quirks. Readers of this
  project understand Lean and don't need it explaining to them.
- Never use an emdash (—). Wherever you might use one, use either a comma or a
  semicolon instead.

### License and copyright header

Every file starts with (`//`-style for `.c` files):

```
-- Copyright (c) 2026 Paul Butcher. All rights reserved.
-- Released under Apache 2.0 license as described in the file LICENSE.
```

## Environment

- Installing OS packages should be done by infrastructure external to this project so
  it's controlled. Therefore, never install any OS packages. Always ask before doing
  so. This does not apply to Lean packages (i.e. defined by lake-manifest or lakefile).
- Building requires `libxml2` (with headers) and `pkg-config` to be present
  (discoverable via `pkg-config libxml-2.0`); if either is missing, ask the human
  running you to arrange it rather than installing it yourself.

## Process

- If the user asks a question, JUST answer it. Do not take a question as an
  instruction or recommendation; take it literally, answer it, and stop.
- Never make any source control (git) changes: no checkins, no pushes or pulls,
  no pull requests.
- If asked to create instructions for another Claude agent, assume that that agent
  is running against a fresh checkout of this library, not any library within
  a `.lake` folder.

## Libraries

- If something would be easier to implement as a change to libxml2 itself, or to a
  dependency, stop and ask the user first rather than working around it here.
- If there's any new functionality that is potentially useful to another
  application, either within an existing library or a new one, stop and ask the user
  if we should make the change here or in a library.

## Testing

- Don't write tests which wholely or largely restate literals from the source with no
  computation in between. Before adding a test, ask: could this fail from a real behavior
  regression, or only by retyping the expected value wrong? If only the latter, it's
  not testing anything.
- Don't write tests which validate the functionality of libxml2 itself unless
  explicitly asked to do so, or we have evidence that libxml2 has a bug or
  unexpected behaviour. Assume libxml2 does what it claims to do.
- When creating new code or functionality, always generate tests alongside it, as long
  as those tests comply with the rules above.
- When creating tests, don't only think about traditional example and expected result
  style tests. Also consider whether there would be value in property style tests (via
  Lean's Plausible testing library) or theorems which can be proven. The round-trip
  invariant (`parse ∘ toString ∘ parse` agrees with `parse`) is one such property
  already covered in `Test/Main.lean`; look for more as the library grows.
- Theorems which aren't necessary for the production code should be in test code.

## Lean Code

- Never use a partial function unless it's absolutely essential. Recursion over
  libxml2's C-owned tree pointers (see `Doc.buildNode`) is one of the rare cases
  where it is: there's no structural termination witness Lean can see.
