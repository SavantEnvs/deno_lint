#![no_main]
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
