#!/usr/bin/env bash
#
# deno_lint/mayhem/build.sh — build the deno_lint fuzz target as a sanitized libFuzzer binary
# (cargo-fuzz + ASan via RUSTFLAGS, OSS-Fuzz Rust path). The fuzzed code is the `deno_lint`
# crate: the target drives `deno_lint::linter::Linter::lint`, which parses arbitrary JS/TS
# source via deno_ast/swc and then runs every lint rule over the AST. Our additive cargo-fuzz
# crate lives at mayhem/fuzz/; cargo-fuzz targets it via `--fuzz-dir mayhem/fuzz`.
set -euo pipefail
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH
: "${SRC:=/mayhem}"
: "${MAYHEM_JOBS:=$(nproc)}"
export MAYHEM_JOBS CARGO_BUILD_JOBS="$MAYHEM_JOBS"
cd "$SRC"

FUZZ_DIR="mayhem/fuzz"
FUZZ_TARGETS=()
for f in "$FUZZ_DIR"/fuzz_targets/*.rs; do FUZZ_TARGETS+=("$(basename "${f%.*}")"); done
[ "${#FUZZ_TARGETS[@]}" -gt 0 ] || { echo "ERROR: no fuzz targets under $FUZZ_DIR/fuzz_targets/" >&2; exit 1; }
TRIPLE="x86_64-unknown-linux-gnu"

# ASan is enabled the Rust way, through RUSTFLAGS -Zsanitizer=address below — NOT via clang's
# $SANITIZER_FLAGS / $CFLAGS, which rustc ignores, so they are deliberately not threaded here.
# Debug-info contract (SPEC §6.2 item 10): fuzz binaries must carry .debug_info at DWARF < 4.
# -Cdebuginfo=1 alone emits DWARF 5 on the image's nightly, so thread $RUST_DEBUG_FLAGS (overridable
# by the base image) and pin the DWARF version explicitly.
: "${RUST_DEBUG_FLAGS:=-C debuginfo=2 -C force-frame-pointers=yes -C llvm-args=--dwarf-version=3}"
# Three things are required together for the DWARF<4 gate; each alone is insufficient:
#   1. this RUSTFLAGS pin, for our own Rust CUs;
#   2. CFLAGS/CXXFLAGS -gdwarf-3 below, for the libFuzzer C/C++ objects the cc crate builds (clang
#      defaults to DWARF-5);
#   3. objcopy --strip-debug over the prebuilt std rlibs + sanitizer runtime archives in the
#      Dockerfile — -Zdwarf-version cannot rewrite those, and their CUs would otherwise be the
#      binary's FIRST CU, which is precisely what verify-repo.sh reads.
# Also note a stale `target/` masks all of this: a cached build silently keeps the old DWARF-5
# objects, so the Dockerfile/build must not reuse one (a clean build dir is assumed here).
export RUST_DEBUG_FLAGS
export RUSTFLAGS="${RUSTFLAGS:-} --cfg fuzzing -Zsanitizer=address $RUST_DEBUG_FLAGS"
# libfuzzer-sys compiles a bundled libFuzzer via the cc crate (clang -> DWARF-5 by default); force
# DWARF-3 on those C/C++ objects too, so no compilation unit in the linked binary is >= 4.
export CFLAGS="${CFLAGS:-} -gdwarf-3"
export CXXFLAGS="${CXXFLAGS:-} -gdwarf-3"
echo "=== cargo fuzz build (image-default nightly, ASan via RUSTFLAGS) ==="
echo "RUSTFLAGS=$RUSTFLAGS"
echo "targets: ${FUZZ_TARGETS[*]}"
for t in "${FUZZ_TARGETS[@]}"; do
  echo "--- building fuzz target: $t ---"
  cargo fuzz build --fuzz-dir "$FUZZ_DIR" -O --debug-assertions "$t"
  bin="$SRC/$FUZZ_DIR/target/$TRIPLE/release/$t"
  [ -x "$bin" ] || { echo "ERROR: fuzz binary not found at $bin" >&2; exit 1; }
  cp "$bin" "/mayhem/$t"; echo "built /mayhem/$t"
done

echo "build.sh complete:"; ls -la "/mayhem/${FUZZ_TARGETS[@]}" 2>&1 || true
