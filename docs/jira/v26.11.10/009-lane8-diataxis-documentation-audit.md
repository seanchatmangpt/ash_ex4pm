# ash_ex4pm: Lane 8 — Diátaxis Documentation Framework Audit & Ergonomics

- Standing: OPEN
- Created: 2026-11-11 (v26.11.10 release wave)
- Assignee: Dave Thomas (The Pragmatic Programmer & Documentation Specialist)
- Source: `docs/diataxis/**`, `docs/INDEX.md`, `README.md`, `mix.exs:81-93`
- Evidence: HEAD commit `14a4271` added doc-hdit scaffolded skeletons; `mix.exs:docs/0` references 6 core Diátaxis extras files.

## Context & Objectives

As authors of *The Pragmatic Programmer*, we believe that code without accessible, accurate, and empathetic documentation fails its primary purpose: empowering developers. The Diátaxis framework organizes technical documentation into four distinct quadrants:

```
                  PRACTICAL FOCUS
                         │
          Tutorials      │    How-to Guides
       (learning-oriented) (problem-oriented)
  ───────────────────────┼────────────────────────
         Explanation     │     Reference
     (understanding-oriented) (information-oriented)
                         │
                 THEORETICAL FOCUS
```

### Current Documentation Status in `ash_ex4pm`
1. **Tutorials**: `docs/diataxis/tutorials/emit-ocel-events-from-an-ash-resource.md` provides an initial end-to-end walkthrough, but lacks copy-pasteable runnable Elixir snippets with standard mix test fixtures.
2. **How-To Guides**: `docs/diataxis/how-to/run-a-receipted-ash-action.md` covers basic BRCE execution, but needs recipes for multi-object relationships, custom attribute history tracking, and Reactor middleware setup.
3. **Reference**: `docs/diataxis/reference/` contains 25 generated markdown files under `generated/` (`ashex4pm_enginerun.md`, `ashex4pm_dsl.md`, etc.). These require verification to ensure all Spark DSL options and types match the actual implementation in `AshEx4pm.Dsl`.
4. **Explanation**: `docs/diataxis/explanation/architecture.md` and `docs/PRD-ARD-v26.10.2.md` provide deep architectural context, but need alignment with the new OTP supervision tree and ETS ring buffer design.

## Work to complete

1. Audit all 6 extras documents configured in `mix.exs:docs/0`:
   - `README.md`
   - `docs/INDEX.md`
   - `docs/diataxis/index.md`
   - `docs/diataxis/reference/api.md`
   - `docs/diataxis/explanation/architecture.md`
   - `docs/PRD-ARD-v26.10.2.md`
2. Validate that all code samples in tutorials and how-tos execute without syntax or deprecation errors.
3. Verify cross-links between Diátaxis documents and HexDocs module links (`ex_doc`).
4. Ensure `docs/examples/ferroplan_proof.exs` is runnable via `elixir docs/examples/ferroplan_proof.exs`.
5. Run `mix docs` to verify that documentation builds cleanly with zero broken internal reference links.

## Acceptance

- `mix docs` runs cleanly and outputs valid HTML documentation in `doc/`.
- Zero broken internal anchors or references across all Diátaxis documentation pages.
- Every quadrant (Tutorials, How-To, Reference, Explanation) contains verified, runnable Elixir examples.

## History

- 2026-11-11 | OPEN | survey finding | Diátaxis audit and developer ergonomics blueprint established by Dave Thomas.
