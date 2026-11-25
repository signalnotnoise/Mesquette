# Engineering Standards — Mesquette

The baseline bar. Day-to-day agent workflow, hard product invariants, and
build commands live in [`AGENTS.md`](../AGENTS.md); architecture and
dependencies live in [`knowledge-graph.md`](knowledge-graph.md). Where this
doc and AGENTS.md overlap, AGENTS.md is the imperative short form — don't
restate rules here, link to them.

## 1. Core Principles

- **Simplest viable solution.** Complexity must be justified by a real
  requirement, never hypothetical future needs.
- **Optimize for the next maintainer.** Explicit, readable code; no
  reverse-engineering required.
- **Scoped changes.** Smallest complete change; no unrequested refactors
  or unrelated edits.

## 2. Architecture & Swift Idioms

- Respect the boundaries in AGENTS.md (Director is UI-agnostic, shells own
  rendering, runtimes are vendored — never patch `Vendor/` in place).
- Prefer value types and composition; `class` only where identity or an
  Apple framework requires it (`AppModel`, view models, actors for stores).
- One responsibility per file, but don't split cohesive helpers just to
  satisfy a rule — synchronized groups make new files cheap anyway.
- Swift naming conventions; `guard` / early returns over deep nesting.
- Persisted shapes are contracts: `GenerationRecord`, asset-pack
  manifests, and bundle formats change only with an explicit migration.

## 3. Concurrency, Performance & Memory

- UI state on `@MainActor`; **nothing slow runs on it** — model loads,
  MLX inference, Vision/CoreImage prep, mesh export, downloads. Use
  actors (runtime stores), `@concurrent`, or MLX's own off-main paths.
- Structured concurrency; cancellation is a first-class outcome for every
  long operation (generation, planning timeouts, downloads).
- Deliberate exceptions are documented, not improvised: runtime stores
  cache loaded models for process lifetime by design, and the named
  `Task.sleep` uses in AGENTS.md (GPU foreground settle, Director
  timeouts) are the only sanctioned sleeps.
- Meshes and tensors are large: avoid copies, prefer in-place buffers,
  and remember iOS/visionOS jetsam limits when adding caches.
- Measure with Instruments before optimizing; record significant
  trade-offs in the commit or wiki.

## 4. Weights, Models & Provenance (Mesquette-specific)

- **Never ship weights in the app or the repo.** Weights come from pinned
  Hugging Face revisions (or Apple-hosted asset packs in signed Release
  builds), are SHA-256 verified against published checksums before use,
  and are stamped for offline reuse. A pin bump is a reviewed change with
  new digests, never a floating `main`.
- **Parity before claims.** A runtime/backend is "working" only with
  recorded evidence at its layer: component tensors → end-to-end mesh →
  through-the-app generation. Bit-exact where the upstream allows it;
  state tolerances where it doesn't.
- **Licenses travel with conversions.** Converted weights keep upstream
  terms (MIT for Shap-E/CLIP/TripoSR); update `THIRD_PARTY_NOTICES.md`
  with every new model or dependency, after checking redistribution and
  territory terms — not just code license.
- Treat prompts, user images, and downloaded manifests as untrusted
  input; verify before loading, fail closed.

## 5. Error Handling & Observability

- Failures are explicit and typed at boundaries (`DirectorError`,
  `HFBundleError`, runtime load errors). No silent `try?` without a
  comment saying why the value is disposable; no empty `catch`.
- User-facing errors are short and safe; diagnostic context goes to logs.
- Log with `os.Logger` (subsystem = bundle id): lifecycle events, loads,
  downloads, exports, Director decisions. Hot loops stay quiet. Anything
  containing user prompts or paths is `privacy: .private`. Never log
  tokens or credentials.

## 6. Testing & Honest Verification

Mesquette's verification ladder, weakest to strongest:

1. **Build** — `xcodebuild` macOS must be warning-free at the source.
2. **Unit tests** in `MesquetteTests/` for deterministic logic (planner,
   layout, checksums, gating). Note: the target is visionOS-only and
   run on macOS via the shared scheme; immersive/hardware behavior
   remains manual-verification territory.
3. **Through-the-app evidence** — drive `ContentViewModel`/`AppModel`
   headlessly against real weights and record concrete outputs (mesh
   counts, topology, digests). A library-only pass is not an app pass.
4. **UI by eye** — viewport, pin interaction, and first-launch flows are
   verified in the running app by a human until UI automation exists.

Rules: reproduce before fixing; add regression coverage with the fix;
never weaken a test to get green; and always report which rung each claim
reached — **verified / not tested / blocked**, never fabricated.

## 7. Security & Dependencies

- No hardcoded secrets; local `.env` files are gitignored and
  `*.env.example` files are template-only.
- Least-privilege entitlements; never disable App Sandbox to work around
  a problem — find the entitlement or redesign.
- New dependencies need a stated need plus license, maintenance, and
  macOS/iOS/visionOS support review.

## 8. Documentation & Repo Hygiene

- Document the *why*: invariants, coordinate-space and data-format
  assumptions, concurrency guarantees. Skip comments restating code.
- Knowledge graph sync is part of the change (AGENTS.md has the rule and
  the command); subsystem behavior changes update `docs/wiki/` too.
- Never commit `DerivedData/`, weights, packaged asset packs, or local
  env files. Fix warnings at the source instead of suppressing them.

## 9. Significant Changes

Before a major architectural or breaking change, document: problem &
motivation, options considered, impact (platforms, memory/perf, security,
compatibility), and rollout/rollback. A short section in the relevant
wiki page or PR description is enough.

## 10. Definition of Done

- Requirements met; AGENTS.md invariants intact.
- Code clean and warning-free; knowledge graph updated and its check green.
- Tests added/updated; the highest runnable rung of §6 actually ran.
- Limitations and unverified areas stated plainly in the report.
