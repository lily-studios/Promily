# Changelog

All notable Promily changes are documented here.

## 1.2.0 - 2026-09-14

### Added

- Promise cancellation recovery with `promise.catchCancel()` and `promise.catchCancelReturn()`.
- Independent consumer branches with `promise.fork()` / `Promily.fork()`. Cancelling a branch does not cancel its source Promise.
- Consumer-local token binding with `promise.withCancellation()` / `Promily.withCancellation()`.
- Settlement side effects with `promise.tapCancel()` and `promise.tapSettled()`.
- `Promily.mapSettled()` with bounded concurrency and per-mapper resolution/rejection/cancellation results.
- `Promily.propsSettled()` for keyed all-settled behavior.
- Async-predicate collection helpers: `Promily.filter()`, `Promily.find()`, and `Promily.partition()`.
- `Promily.firstResolved()` for lazy sequential fallback tasks.
- `Promily.rejectAfter()` for cancellable delayed rejection.
- Exported `partitionResult<T>` type.
- Every exported `module.*` function in `src` now includes structured `---@param`, `---@return`, `---@generic`, and behavior comments where applicable. New Promise instance methods include matching core documentation.
- Regression coverage expanded to 62 tests.

### Fixed

- Disconnecting the last rejection-handling observer before a source rejects no longer permanently suppresses unhandled-rejection reporting; active rejection observers are reference-counted and duplicate reports are prevented.

### Changed

- Version bumped to `1.2.0`.
- Single-flight consumers now use the public `fork()` primitive directly.
- README/API indexes and production-audit counts updated for the expanded Promise API.

### Lifecycle behavior

- `fork()` and `withCancellation()` detach their consumer observer on cancellation and never silently cancel caller-owned shared source work.
- `mapSettled()` cancels only Promily-owned mapper wrapper Promises when the aggregate itself is cancelled. Adopted caller-owned Promises remain externally owned.
- `firstResolved()` starts fallback tasks lazily and stops creating new work as soon as one task resolves.

## 1.1.0 - 2026-09-14

### Added

- `Promily.createQueue(options)` with bounded concurrency, optional pending limits, `clear`, `close`, `delete`, counters, and `onIdle`.
- `Promily.createSemaphore(limit)` with `acquire`, `tryAcquire`, reusable permits, counters, and `use`.
- `Promily.createSingleFlight()` for deduplicating concurrent work by string/number key while isolating consumer cancellation.
- `Promily.deadline(source, deadlineTime, reason?)` and `promise.deadline(deadlineTime, reason?)`.
- `promise.onCancel(callback)` returning a disconnectable connection.
- `Promily.diagnostics.getPending(limit?)`, `getLongestPending(limit?)`, and `getStats()`.
- Promise result timing metadata: `createdAt`, `settledAt`, and `pendingFor`.
- Shared structured error contracts for aggregate, cancellation, queue, semaphore, and single-flight failures.
- Studio test project at `test.project.json`.
- Regression coverage expanded to 41 tests.

### Fixed

- Resolving a Promise with another pending Promise now locks resolution so a later `reject()` or second `resolve()` cannot override the first resolution decision.
- Indirect Promise-adoption cycles are detected and rejected instead of remaining permanently pending.
- Throwing observer callbacks are isolated so one observer cannot prevent later observers from receiving settlement.
- `map` now cancels Promily-owned mapper wrappers when the aggregate stops, while still not cancelling caller-owned adopted Promises.
- Queue and semaphore waiters are removed/ignored safely when consumers cancel before execution/acquisition.
- Semaphore `use()` no longer leaks permits when cancellation races with permit delivery.
- `fromProperty`, `fromAttribute`, and `fromChild` subscribe before their initial state scan/recheck, closing lost-event race windows.
- `fromProperty` safely rejects invalid property names instead of leaving a connection or executor cleanup hazard.
- Cancellation listeners are isolated with protected calls.
- Duplicate timeout rejection call removed.
- Numeric controls now reject NaN, infinity, fractional concurrency/attempt/count values, and other invalid limits.
- Removed stray `.DS_Store` from the package.

### Changed

- Version bumped to `1.1.0`.
- README package layout, API counts, test counts, release gate, and sourcemap instructions now match the repository.
- Generated `sourcemap.json` remains ignored so it cannot become stale.

## 1.0.0

- Initial Promily Promise implementation with strict Luau typing, cancellation, scopes, collection combinators, timing/retry helpers, Roblox adapters, inspection, and dependency-free tests.
