#![no_main]
use libfuzzer_sys::fuzz_target;

use deno_ast::MediaType;
use deno_lint::{linter::LinterBuilder, rules::get_all_rules};

fuzz_target!(|data: (u8, String)| {
  let (media, source_code) = data;

  let linter_builder = LinterBuilder::default()
    .rules(get_all_rules())
    .media_type(match media % 16 {
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
    });

  let linter = linter_builder.build();

  let _ = linter.lint("code.ts".to_string(), source_code);
});
