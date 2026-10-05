#![no_main]
// Mayhem fuzz target for deno_lint — drives the REAL linter entry point
// `deno_lint::linter::Linter::lint` over arbitrary JS/TS source text.
//
// `lint` first parses the source with deno_ast/swc (`parse_program`) and then runs EVERY lint
// rule (`get_all_rules()`) over the resulting AST. So a single input exercises the full
// pipeline: the swc parser, deno_ast's scopes/transforms, and all deno_lint rules.
//
// Backport note: this is the OLD-API counterpart of the live `mayhem` branch's harness (which
// drives `Linter::lint_file`/`LinterOptions`, added long after this commit). At this UPSTREAM
// revision deno_lint 0.33.0 / deno_ast 0.19.0 only exposes `LinterBuilder` + `Linter::lint`, so
// the harness is ported down to that API rather than the current one, matching the mayhemheroes
// fork harness this backport reproduces. Input is a `(u8, String)` so the fuzzer controls both
// the media type (JS/JSX/TS/TSX/JSON/...) and the source text — `libfuzzer-sys`'s `arbitrary`
// derives this from raw bytes.
use libfuzzer_sys::fuzz_target;

use deno_ast::MediaType;
use deno_lint::linter::LinterBuilder;
use deno_lint::rules::get_all_rules;

// Leak detection off at build time (SPEC §6.2 item 15): LeakSanitizer looks this symbol up at startup.
#[no_mangle]
pub extern "C" fn __lsan_is_turned_off() -> i32 {
  1
}

fuzz_target!(|data: (u8, String)| {
  let (media, source_code) = data;

  let media_type = match media % 16 {
    0 => MediaType::JavaScript,
    1 => MediaType::Jsx,
    2 => MediaType::Mjs,
    3 => MediaType::Cjs,
    4 => MediaType::TypeScript,
    5 => MediaType::Mts,
    6 => MediaType::Cts,
    7 => MediaType::Dts,
    8 => MediaType::Dmts,
    9 => MediaType::Dcts,
    10 => MediaType::Tsx,
    11 => MediaType::Json,
    12 => MediaType::Wasm,
    13 => MediaType::TsBuildInfo,
    14 => MediaType::SourceMap,
    _ => MediaType::Unknown,
  };

  let linter = LinterBuilder::default()
    .rules(get_all_rules())
    .media_type(media_type)
    .build();

  // A parse error returns Err (handled gracefully); a successful parse runs all rules. Either
  // way we never panic on our own input — any panic here is a real defect in upstream code.
  let _ = linter.lint("file:///code.ts".to_string(), source_code);
});
