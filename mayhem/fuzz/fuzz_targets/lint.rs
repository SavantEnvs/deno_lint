#![no_main]
// Mayhem fuzz target for deno_lint — drives the REAL linter entry point
// `deno_lint::linter::Linter::lint_file` over arbitrary JS/TS source text.
//
// `lint_file` first parses the source with deno_ast/swc (`parse_program`) and then runs
// EVERY lint rule (`get_all_rules()`) over the resulting AST. So a single input exercises the
// full pipeline: the swc parser, deno_ast's view/scopes/transforms, and all ~90 deno_lint rules.
//
// This is the honest successor of the old mayhemheroes/deno_lint fork target (`lint`), whose
// harness drove the same `Linter::lint_file` API; it is preserved here verbatim against the
// CURRENT upstream API (deno_ast 0.53.2). Input is a `(u8, String)` so the fuzzer controls both
// the media type (JS/JSX/TS/TSX/JSON/...) and the source text — `libfuzzer-sys`'s `arbitrary`
// derives this from raw bytes.
use libfuzzer_sys::fuzz_target;

use std::borrow::Cow;
use std::collections::HashSet;

use deno_ast::MediaType;
use deno_ast::ModuleSpecifier;
use deno_lint::linter::{LintConfig, LintFileOptions, Linter, LinterOptions};
use deno_lint::rules::get_all_rules;

fuzz_target!(|data: (u8, String)| {
  let (media, source_code) = data;

  let rules = get_all_rules();
  let all_rule_codes: HashSet<Cow<'static, str>> =
    rules.iter().map(|r| r.code().into()).collect();

  let linter = Linter::new(LinterOptions {
    rules,
    all_rule_codes,
    custom_ignore_file_directive: None,
    custom_ignore_diagnostic_directive: None,
  });

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
    13 => MediaType::Unknown,
    14 => MediaType::SourceMap,
    _ => MediaType::Unknown,
  };

  let specifier = ModuleSpecifier::parse("file:///code.ts").unwrap();

  // A parse error returns Err (handled gracefully); a successful parse runs all rules. Either
  // way we never panic on our own input — any panic here is a real defect in upstream code.
  let _ = linter.lint_file(LintFileOptions {
    specifier,
    source_code,
    media_type,
    config: LintConfig {
      default_jsx_factory: None,
      default_jsx_fragment_factory: None,
    },
    external_linter: None,
  });
});
