# CPU sanitizer reproductions

Two independently reproduced findings on USearch `3.0.0-rc.1`, based on commit `7af4705a`.
These programs and scripts diagnose the findings; they do not patch the library.

Tested on macOS / Apple M3 Pro with Apple Clang 21.0.0.21000101, CMake 4.4.5, and Ninja.
Initialize the repository's submodules before running them:

```sh
git submodule update --init --recursive
```

Run from a checkout of this branch:

```sh
bash reproductions/cpu-sanitizers/neon-stack/run.sh
bash reproductions/cpu-sanitizers/enum-layout/run.sh
```

The scripts write builds and logs under the system temporary directory. `REPRO_BUILD_DIR` overrides
that location, and `USEARCH_SOURCE_DIR` selects another source checkout. `YYJSON_SOURCE_DIR` may
point to an existing yyjson source checkout to avoid downloading that pinned dependency again.
The stack reproducer requires Apple Silicon/macOS; the enum reproducer needs Clang and C++20.
No GPU or Python dependencies are required. ASan leak detection is disabled on macOS; address and
undefined-behavior checks remain enabled.

## NEON conversion exceeds a worker's stack in an unoptimized sanitizer build

[`neon-stack/insert.c`](neon-stack/insert.c) inserts eleven ordinary f32 vectors, each with 83
components, into a BF16 angular index. The only input changed between runs is the executor's
thread count. All builds use `USEARCH_MULTIVERSIONED=OFF`, `USEARCH_MARCH=native`, and
`USEARCH_BUILD_SANITIZERS=address`, enabling both ASan and UBSan.

| Build | Executor threads | Observed result |
| --- | --- | --- |
| `-O0 -g`, unchanged headers | 1 | Insertion succeeds |
| `-O0 -g`, unchanged headers | 2 | ASan abort in `__asan_memcpy`, reached from `nk_cast_neon` |
| `-O1 -g`, unchanged headers | 2 | Insertion succeeds |
| `-O0 -g`, temporary noinline dispatch control | 2 | Insertion succeeds |

The worker stack measured here is 536,576 bytes; the main thread has roughly 8 MiB.
A standalone compile with `-fstack-usage` reports 754,240 bytes for `nk_cast_neon` under
`-O0 -fsanitize=address,undefined`. That measurement is for the isolated C conversion helper,
not an exact measurement of the full C++ insertion call chain.

`NUMKONG_INLINE` expands to `always_inline` under Clang. The outer cast inlines
`nk_cast_block_scaled_neon_`, which contains several calls to the large elementwise dispatch
helper. At `-O0`, these dispatch bodies and their temporaries are retained even for an ordinary
f32-to-BF16 call. The resulting stack demand is excessive for a normal macOS worker.

The script's control copies `numkong/include/numkong/cast/neon.h` into a temporary include overlay
and changes only `nk_cast_block_scaled_neon_` and `nk_cast_elementwise_neon_` to `noinline`.
It retains `-O0` and both sanitizers. In the isolated compiler measurement, the three dispatch
frames become 1,024, 226,912, and 123,232 bytes; the public insertion then succeeds.
The source checkout is never modified.

This is a reproducible Debug/sanitizer stack-usage defect. It is not evidence of a heap-buffer
overflow in an optimized production build. A remedy should limit forced inlining at these
boundaries, use appropriately sized worker stacks for this build, or otherwise keep the stack
within its budget. Merely disabling sanitizers would hide the failing configuration.

## Unknown C tape layouts are read as invalid C++ enum values before validation

[`enum-layout/caller.c`](enum-layout/caller.c) is compiled as C11 and fills the real public
`usearch_tape_view_t`. [`enum-layout/callee.cpp`](enum-layout/callee.cpp) includes the repository's
actual `src/basic_punned.cuh` and calls its `known_layout` guard; neither the enum declaration nor
the guard is mirrored in the reproducer.

`usearch_tape_layout_t` declares only values 0 and 1 and has no fixed underlying type in C++.
Its C++ value range is therefore 0 through 1, despite occupying four bytes on this platform.
The C caller can store 2 or 7 in the enum's compatible integer representation. Evaluating that
field as a C++ enum to pass it by value to `known_layout` already has undefined behavior.
The comparison inside the guard runs too late to make that initial load safe.

The existing `test_arrow_tapes` reaches this path through `usearch_sequence_insert` and expects
an unsupported-layout error. Its value 7 triggers UBSan in `accepts_sequences` before that refusal.
Changing the test value to 2 does not solve the problem.

| Configuration using the actual guard | Layout 0/1 | Layout 2/7 |
| --- | --- | --- |
| `-O1 -fsanitize=undefined` | Accepted cleanly | UBSan diagnostic |
| `-O2 -fstrict-enums` | Accepted | Incorrectly accepted |
| `-O2 -fstrict-enums -fsanitize=undefined`, representation guard first | Accepted cleanly | Rejected cleanly |

The `VALIDATE_REPRESENTATION` control copies the member's representation into
`std::underlying_type_t<usearch_tape_layout_t>` with `std::bit_cast`, checks that integer, then calls
the existing helper only for a valid value. This demonstrates a targeted remedy: validate the
representation before any typed enum evaluation. A production change must also avoid passing the
invalid enum by value into its validator; a reference parameter can preserve its representation.

An alternative is a fixed underlying type for the C++ public enum, with a compatible C declaration.
That broader change needs ABI review across the supported compilers. The `-fstrict-enums` experiment
demonstrates that the undefined behavior can affect validation; it does not claim that every
normal release build uses that option.

## Scope of the preceding CPU audit

An optimized ASan/UBSan build also passed 180,000 search combinations across BF16, I8, E4M3, and
binary storage: empty/small datasets, repeated keys, zero vectors, dimensions around packing
boundaries, graph and exact scan traversal, cheap/expensive predicates, and requested result
counts through 10,000. Ordinary checkpoint, cursor, arena, and deferred-call checks passed.
Those results do not establish that every CPU path or platform is free of defects.
