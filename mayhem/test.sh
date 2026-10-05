#!/usr/bin/env bash
#
# deno_lint/mayhem/test.sh — RUN the FUZZED crate's own unit suite (`cargo test -p deno_lint`)
# and emit a CTRF summary. exit 0 iff no test failed.
#
# PATCH-grade oracle: the fuzz target drives `deno_lint::linter::Linter::lint_file` — the parse
# (deno_ast/swc) + lint-rule pipeline. deno_lint ships hundreds of unit tests (one per rule under
# src/rules/*.rs, plus control-flow/ignore-directive/js-regex suites) that assert EXACT diagnostic
# output (rule codes, message text, span line/col, hints) for known JS/TS inputs. A no-op /
# "exit(0)" / output-altering patch to the linter or a rule CANNOT pass these asserts. This script
# only RUNS the suite via `cargo test`; it never builds the fuzz target.
#
# Run with NORMAL flags (RUSTFLAGS cleared — no sanitizer) on the image's default nightly
# toolchain, so the oracle stays honest and fast.
set -uo pipefail
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH
: "${SRC:=/mayhem}"
: "${MAYHEM_JOBS:=$(nproc)}"
cd "$SRC"

# emit_ctrf <tool> <passed> <failed> [skipped] [pending] [other]
emit_ctrf() {
  local tool="$1" passed="$2" failed="$3" skipped="${4:-0}" pending="${5:-0}" other="${6:-0}"
  local tests=$(( passed + failed + skipped + pending + other ))
  cat > "${CTRF_REPORT:-$SRC/ctrf-report.json}" <<JSON
{
  "results": {
    "tool": { "name": "$tool" },
    "summary": { "tests": $tests, "passed": $passed, "failed": $failed, "pending": $pending, "skipped": $skipped, "other": $other }
  }
}
JSON
  printf 'CTRF {"results":{"tool":{"name":"%s"},"summary":{"tests":%d,"passed":%d,"failed":%d,"pending":%d,"skipped":%d,"other":%d}}}\n' \
    "$tool" "$tests" "$passed" "$failed" "$pending" "$skipped" "$other"
  [ "$failed" -eq 0 ]
}

if ! command -v cargo >/dev/null 2>&1; then
  echo "cargo not available — cannot run the test suite" >&2
  emit_ctrf "cargo-test" 0 1 0; exit 2
fi

# The committed Cargo.lock pins ahash 0.7.6 (2021), whose build.rs unconditionally turns on the
# nightly-only `stdsimd` feature gate for ANY nightly compiler; that gate name was removed from
# rustc well before this image's nightly-2025-09-05, so ahash 0.7.6 fails to compile under it
# (E0635 unknown feature). ahash 0.7.8 (2024) guards the same gate behind `rustc <= 1.77.9` and
# is still inside swc_common's `ahash = "0.7.4"` requirement, so bump to it (container-local;
# never touches the committed Cargo.lock).
cargo update -p ahash --precise 0.7.8

# Reader::at()'s non-unicode path (src/js_regex/reader.rs) feeds a UTF-16 surrogate half straight
# into std::char::from_u32_unchecked — never a valid char, and THIS BACKPORT'S BUG (CWE-617
# reachable assertion; the fuzz target, mayhem/lint, reaches the same code with --debug-assertions
# and is meant to abort on it). This UPSTREAM commit's rustc silently tolerated the invalid char;
# std gained a runtime precondition check for exactly this well after 2022, so several unrelated
# unit tests now abort on it under the image's nightly-2025-09-05 before they reach their actual
# assertions. Disable that check for the oracle run only (-C ub-checks=no) so the suite judges
# deno_lint's rule/diagnostic correctness as it did at this commit, not this later toolchain's
# stricter std.
echo "=== cargo test -p deno_lint --lib (deno_lint parser + lint-rule unit suite) ==="
out="$(RUSTFLAGS="-Z ub-checks=no" cargo test -p deno_lint --lib --no-fail-fast --jobs "$MAYHEM_JOBS" 2>&1)"; rc=$?
echo "$out"

PASSED=0; FAILED=0; IGNORED=0
while read -r p f i; do
  PASSED=$(( PASSED + p )); FAILED=$(( FAILED + f )); IGNORED=$(( IGNORED + i ))
done < <(printf '%s\n' "$out" \
  | sed -n 's/^test result:.* \([0-9][0-9]*\) passed; \([0-9][0-9]*\) failed; \([0-9][0-9]*\) ignored.*/\1 \2 \3/p')

if [ "$(( PASSED + FAILED + IGNORED ))" -eq 0 ]; then
  echo "could not parse any 'test result:' lines; using cargo exit code $rc" >&2
  [ "$rc" -eq 0 ] && { emit_ctrf "cargo-test" 1 0 0; exit 0; }
  emit_ctrf "cargo-test" 0 1 0; exit 1
fi

emit_ctrf "cargo-test" "$PASSED" "$FAILED" "$IGNORED"
