---
name: optimize-performance
description: |
  Speed up code with a measure-first workflow: ask the user how to measure
  performance, record a baseline, profile, apply one optimization at a time,
  measure again after every change, and keep a change only when its speedup
  justifies the complexity it adds. Every change must return the same results
  as before, preferably proven by a test; a change that alters results needs
  the user's approval. Every report pairs the before/after numbers with the
  complexity cost.
  Use this skill whenever the user wants to make code faster, reduce latency,
  cut memory use, or improve throughput, or says things like "高速化して",
  "速くして", "パフォーマンス改善", "パフォーマンスチューニング", "重いので直して",
  "optimize this", "make it faster", "speed up", "improve performance",
  "reduce latency".
---

# Optimize Performance

This skill makes code faster without guessing. Every optimization is justified
by a measurement taken before and after the change, and every kept change is
weighed against the complexity it adds.

## Why this exists

Optimizations chosen by intuition often target the wrong code, and even a real
speedup can cost more in maintenance than it saves in runtime. A faster
program that returns a different answer is a bug, not an optimization. This
skill enforces four rules:

1. Agree on the measurement with the user before touching the code.
2. Prove that every change returns the same results as the original code.
   Ask the user before keeping any change that alters the results.
3. Measure before and after every change, under the same conditions.
4. Keep a change only when its measured gain outweighs its complexity.

## Workflow

1. Ask the user how to measure.
2. Lock in the current results.
3. Record the baseline.
4. Profile to find the hotspot.
5. Apply one optimization.
6. Verify the results, then measure again.
7. Decide whether to keep the change.
8. Repeat steps 4 to 7, then report.

## Step 1: Ask the User How to Measure

Never pick the measurement method silently. Inspect the repository first so
the questions can offer concrete options, such as an existing benchmark suite
(`pytest-benchmark`, `go test -bench`, `cargo bench`, `hyperfine`,
`vitest bench`, Google Benchmark) or a slow command the user mentioned.

Then ask the user with `AskUserQuestion`. Cover these points, and skip any
point the user already answered:

- **Command**: the exact command or benchmark that exercises the slow path.
- **Metric**: wall-clock time, CPU time, peak memory, throughput, p50/p99
  latency, binary size, or another number.
- **Workload**: the input data and its size. A realistic workload matters
  more than a large one.
- **Target**: the goal, such as "under 200 ms" or "2x faster". Without a
  target, stop when the next candidate is not worth its complexity.
- **Constraints**: what must not change, such as the public API, memory
  ceiling, or dependencies.
- **Equivalence**: what counts as "the same result". Examples: bit-for-bit
  identical output, floating-point values within a tolerance, or the same
  set of items in any order. Default to bit-for-bit when the user has no
  preference.

If no benchmark exists, propose one: a small script under the scratchpad or a
benchmark file that matches the project's test layout. Get the user's approval
before adding a benchmark to the repository.

## Step 2: Lock In the Current Results

Before changing any code, capture what the code computes today, so every later
change can be checked against it.

Prefer an automated test. Write an equivalence test (also called a
characterization or golden test) when the code allows it:

1. Pick representative inputs, including edge cases such as empty input, a
   single element, duplicates, and the largest realistic size.
2. Run the unmodified code on those inputs and store the outputs as expected
   values or golden files.
3. Write a test that runs the code on the same inputs and compares the
   outputs under the equivalence rule from Step 1.
4. Run the test against the unmodified code and confirm it passes.

Follow the project's test layout and framework. Ask the user before committing
the test to the repository; if the user declines, keep it in the scratchpad
and still run it after every change.

When a test is impractical, for example because the output depends on an
external service, save the output of the benchmark workload to a file and
compare against it with `diff` or a small script instead. Tell the user that
the check is weaker than a test and why no test was written.

Also run the existing test suite once and record which tests pass, so a later
failure can be attributed to a change and not to the starting state.

## Step 3: Record the Baseline

Measure the unmodified code before any change. Record the commit hash with
the numbers so the baseline can be reproduced.

Make the measurement trustworthy:

- Run a warm-up pass first, so caches, JIT, and lazy initialization do not
  skew the first sample.
- Take at least 5 samples, and more when the spread is large. Report the
  median and the spread (min/max or standard deviation), never one run.
- Build with the same flags the user ships, such as release mode or `-O2`.
- Keep the machine state stable. Close heavy background jobs, and note when
  the environment is noisy, such as a shared cloud container.

When the spread is larger than the gain you hope to detect, fix the
measurement before optimizing. For example, raise the sample count, enlarge
the workload, or pin the CPU.

## Step 4: Profile to Find the Hotspot

Locate where the time or memory goes before choosing what to change. Prefer
the profiler that fits the language:

- Python: `cProfile`, `py-spy`, `scalene`.
- Go: `pprof`.
- Rust and C/C++: `perf`, `cargo flamegraph`, `valgrind --tool=callgrind`.
- Node.js: `node --cpu-prof`, `clinic`.
- Shell pipelines: `time` on each stage.

Rank the candidates by their share of the total. A function that takes 5% of
the runtime can never yield more than a 5% gain, however clever the fix.

## Step 5: Apply One Optimization

Change one thing at a time, so each measurement maps to exactly one cause.
Commit or stash each candidate separately so it can be reverted alone.

Try cheap, local changes before invasive ones. A rough order:

1. Remove wasted work: redundant calls, repeated I/O, work inside a loop that
   belongs outside it.
2. Use a better algorithm or data structure, such as a hash map instead of a
   linear scan.
3. Batch I/O or network calls.
4. Add caching or memoization.
5. Add concurrency or parallelism.
6. Rewrite in a lower-level form, such as SIMD, unsafe code, or a native
   extension.

Items later in the list usually add more complexity. Reach for them only when
the earlier items do not meet the target.

## Step 6: Verify the Results, Then Measure Again

Check the results first. Run the equivalence test or output comparison from
Step 2 and the existing test suite. A speed number from code that returns
different results means nothing.

When the results differ, stop and ask the user with `AskUserQuestion` before
going further. Show:

- The inputs whose outputs changed, with the old and new values side by side.
- The size of the difference, such as the largest floating-point error or the
  number of reordered items.
- The cause, such as a different summation order in a parallel reduction, a
  lower-precision type, or an unstable sort.
- The speedup the change would bring, measured separately and labeled as
  unverified.

Keep the change only when the user explicitly accepts the new results. Then
update the equivalence rule or the expected values, and record the accepted
difference in the report. Otherwise revert the change or fix it until the
results match.

Once the results match, run the exact command from Step 3 with the same
workload, build flags, and sample count.

Compute the change against the baseline:

- Speedup = baseline median / new median.
- Improvement (%) = (baseline - new) / baseline * 100.

Treat a difference smaller than the measured spread as noise, not a gain.

## Step 7: Decide Whether to Keep the Change

Weigh the measured gain against the complexity the change introduces. Rate
the complexity on these axes:

- Lines of code added or changed.
- New dependencies, build steps, or platform-specific code.
- New invariants that callers or future editors must maintain, such as cache
  invalidation, thread safety, or ordering assumptions.
- Readability: whether a reader can still follow the logic without comments.
- Test burden: new edge cases that need tests.

Use this guide to decide:

| Measured gain | Low complexity | Medium complexity | High complexity |
| --- | --- | --- | --- |
| Within noise | Revert | Revert | Revert |
| Small (< 10%) | Keep | Revert unless on the critical path | Revert |
| Medium (10% to 2x) | Keep | Keep | Ask the user |
| Large (> 2x) | Keep | Keep | Keep, and document the invariants |

When a change lands in "Ask the user", present the numbers and the complexity
cost, and let the user decide. Revert every rejected change completely,
including helper code and dependencies it pulled in.

A kept change that adds a non-obvious invariant needs a comment that states
the invariant and the measured reason, for example
`// Cache the parsed config. Parsing took 40% of request time in the profile.`

## Step 8: Repeat, Then Report

Return to Step 4 with the new code as the reference. Profile again, because
the hotspot moves after each fix. Stop when one of these holds:

- The target from Step 1 is met.
- The next candidate falls in the "Revert" cells of the decision table.
- The user asks to stop.

Finish with a report in this form:

```markdown
## Performance report

Measurement: `<command>` on `<workload>`, <N> samples, median (min to max).

Equivalence check: `<test name or comparison command>`, rule: <bit-for-bit, tolerance, ...>.

| Step | Change | Time | vs baseline | Results | Complexity | Decision |
| --- | --- | --- | --- | --- | --- | --- |
| 0 | Baseline (<commit>) | 1.20 s (1.18 to 1.25) | - | - | - | - |
| 1 | Hoist regex compile out of loop | 0.80 s (0.79 to 0.82) | 1.50x | Identical | Low: 2 lines | Kept |
| 2 | Parallelize file parsing | 0.74 s (0.70 to 0.90) | 1.62x | Identical | High: thread pool, shared state | Reverted |
| 3 | Sum in float32 | 0.70 s (0.69 to 0.71) | 1.71x | Differs by up to 1e-6 | Low: 1 line | Rejected by user |

Final: 1.20 s to 0.80 s (1.50x). All tests and the equivalence check pass.
```

List the rejected changes too. They record what was tried and why it was not
worth it, which saves the next person from repeating the experiment.

## Important Details

- **No change without a number** — never claim a speedup you did not measure,
  and never keep a change measured only once.
- **Same conditions** — the before and after runs must share the command,
  workload, build flags, and machine. Re-run the baseline if any of them
  changed.
- **Same results** — run the equivalence check and the test suite after every
  change, before measuring speed. Never keep a change that alters the results
  without the user's explicit approval.
- **Report regressions honestly** — if a change makes another metric worse,
  such as memory rising while time falls, include that metric in the report.
