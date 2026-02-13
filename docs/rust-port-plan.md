# Rust Port Plan for Whitaker's Words

## Phase 0: Project Setup & Data Migration

**Set up the Rust workspace:**

```
whitakers-words-rs/
├── Cargo.toml                  # workspace root
├── crates/
│   ├── latin-types/            # Phase 1 — enums, structs (≈ latin_utils)
│   ├── latin-data/             # Phase 2 — data loading & indexing
│   ├── latin-parser/           # Phase 3 — core parse engine (≈ words_engine)
│   └── words-cli/              # Phase 5 — CLI binary (≈ commands)
├── data/
│   ├── dictionary.json         # converted from DICTLINE.GEN
│   ├── inflections.json        # converted from INFLECTS.LAT
│   ├── addons.json             # converted from ADDONS.LAT
│   └── uniques.json            # converted from UNIQUES.LAT
└── tests/
    └── regression/             # captured baseline from original program
```

**Convert data files first** (write a one-off Rust or Python script):
- Parse the fixed-width formats of `DICTLINE.GEN` (39,338 entries), `INFLECTS.LAT` (3,207 rules), `ADDONS.LAT`, and `UNIQUES.LAT`
- Emit clean JSON (or consider embedding with `include_str!` + `serde` for a single-binary distribution)
- Validate round-trip: parsed → serialized → re-parsed with no data loss

**Capture regression baseline**: Run the original Ada `bin/words` against a large test corpus (the existing 4 test inputs plus a broader word list), save the output. This is the ground truth for the entire port.

## Phase 1: Type System (`latin-types` crate) — ~1,000 lines

Port `latin_utils-inflections_package.ads` + `latin_utils-dictionary_package.ads`. This is almost entirely type definitions and maps very naturally to Rust.

**Ada discriminated unions → Rust enums:**

```rust
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub enum Quality {
    Noun { decl: Declension, case: Case, number: Number, gender: Gender },
    Verb { conj: Conjugation, tense: Tense, voice: Voice, mood: Mood, person: Person, number: Number },
    Adjective { decl: Declension, case: Case, number: Number, gender: Gender, comparison: Comparison },
    Adverb { comparison: Comparison },
    Pronoun { decl: Declension, case: Case, number: Number, gender: Gender },
    // ... Vpar, Supine, Prep, Conj, Interj, Numeral
}
```

**Key enums** (all small, `Copy`, `serde`-derivable):
- `PartOfSpeech` (16 variants), `Case` (8), `Gender` (5), `Number` (3), `Tense` (7), `Voice` (3), `Mood` (6), `Comparison` (4)
- `DictionaryKind`, `Age`, `Frequency`, `Area`, `Geography`, `Source`

**Key structs:**
- `Inflection` — quality + stem_key + ending + age + frequency
- `DictionaryEntry` — 4 stems + part entry + translation + meaning
- `Stem` — `String` (no longer fixed-width 18-char)

**Design notes:**
- Derive `serde::Serialize/Deserialize` on everything for JSON data loading
- Keep `Copy` on small enums, `Clone` on larger structs
- Use `&str`/`String` instead of fixed-width character arrays

## Phase 2: Data Layer (`latin-data` crate) — ~800 lines

Replaces `support_utils` + the binary file loading machinery. The original program uses binary files (`STEMFILE.GEN`, `INDXFILE.GEN`) with Ada record layout for direct-access I/O. In Rust, we load JSON into in-memory indices instead.

**Core struct:**

```rust
pub struct LatinData {
    pub entries: Vec<DictionaryEntry>,
    pub stem_index: HashMap<[u8; 2], Vec<StemRef>>,  // 2-char prefix → entries
    pub inflections_by_ending: HashMap<String, Vec<Inflection>>,
    pub prefixes: Vec<PrefixEntry>,
    pub suffixes: Vec<SuffixEntry>,
    pub tackons: Vec<TackonEntry>,
    pub uniques: HashMap<String, Vec<UniqueEntry>>,
}
```

**Key decisions:**
- **Embed data at compile time** using `include_str!` + lazy deserialization, or load at runtime from a data directory. Compile-time embedding gives a single binary (great for distribution) but increases compile times. Recommendation: support both via a feature flag.
- **Indexing**: Build a `HashMap` keyed on 2-character stem prefix (matching the original `INDXFILE` concept) for O(1) lookup instead of binary search
- **Inflection index**: Group inflections by ending string for O(1) lookup during decomposition (the original loads them into 5 sections and does sequential scans)

## Phase 3: Parsing Engine (`latin-parser` crate) — ~3,000 lines

This is the heart of the project. Port `words_engine-word_package.adb` (1,956 lines), `words_engine-parse.adb` (1,239 lines), `words_engine-tricks.adb` (1,077 lines), and `words_engine-list_sweep.adb` (651 lines).

**Critical architectural change: eliminate global mutable state.** The original Ada code uses package-level global arrays (`Sa`, `Ssa`, `Pdl`) and global file handles. In Rust:

```rust
pub struct Parser<'a> {
    data: &'a LatinData,
    config: ParseConfig,
}

impl<'a> Parser<'a> {
    pub fn analyze_word(&self, word: &str) -> Vec<Analysis> { ... }
    pub fn analyze_text(&self, text: &str) -> Vec<WordAnalysis> { ... }
}
```

All intermediate state lives on the stack or in local `Vec`s. The `Parser` borrows `LatinData` immutably, making it `Send + Sync` (thread-safe for free).

**Sub-modules:**

| Module | Ada source | Responsibility |
|--------|-----------|----------------|
| `decompose` | `Run_Inflections` in word_package | Split word into all (stem, ending, inflection) candidates |
| `lookup` | `Search_Dictionaries` in word_package | Find dictionary entries matching candidate stems |
| `validate` | `Reduce_Stem_List` in word_package | Check grammar agreement between entry and inflection |
| `tricks` | `words_engine-tricks.adb` | Spelling variations (ae↔e, u↔v, j↔i, h-drop, syncope) |
| `compounds` | `Compounds_With_Sum` in parse | Detect participle + sum constructions |
| `sweep` | `words_engine-list_sweep.adb` | Rank/prune results (prefer common forms, trim duplicates) |
| `english` | `words_engine-english_support_package` | English→Latin reverse lookup |
| `format` | `words_engine-list_package.adb` | Format analysis results as text |

**Porting order within this phase:**
1. `decompose` — pure string splitting + inflection table lookup
2. `lookup` — HashMap lookup, stem normalization (v↔u, j↔i)
3. `validate` — grammar rule matching
4. `sweep` — result ranking
5. `tricks` — spelling variation pipeline (port the ~40 trick patterns from `trick_tables`)
6. `compounds` — multi-word analysis
7. `english` — reverse lookup
8. `format` — output formatting (match the original output format for regression testing)

**After each sub-module**: run regression tests against the captured baseline.

## Phase 4: Testing & Validation — ongoing throughout

**Unit tests** (per sub-module):
- `decompose("amaverunt")` returns candidates including stem="amav", ending="erunt"
- `lookup("amav")` finds the "amo" entry
- `validate(amo_entry, 3rd_pl_perf_ind)` returns true
- Trick tests: `ae→e`, syncope patterns

**Integration tests** (whole pipeline):
- Port the 4 existing test cases (01_aeneid, 02_ius, 03_qualdupes, 04_english)
- Run the original program and new program on a large corpus, diff output
- Target: <1% output divergence (differences should only be ordering/formatting, not missing analyses)

**Property-based tests** (bonus):
- Any word that the original program parses should also parse in the new version
- Roundtrip: for known dictionary entries, generate all valid inflected forms and verify they parse back

## Phase 5: CLI (`words-cli` crate) — ~400 lines

Port `words_main.adb` + `process_input.adb`. Use `clap` for argument parsing.

```
words "amo"              # single word
words input.txt          # file mode
words input.txt out.txt  # file-to-file
words                    # interactive REPL
```

Support the original command prefixes (`@` for file include, `#` for parameters, `~` for language toggle, `?` for help) for backwards compatibility. Use `rustyline` or similar for interactive line editing.

## Phase 6: Enhancements (post-port)

Once the core port is validated against the original:

- **Unicode/macron support** — extend the data format to include macron annotations
- **WebAssembly target** — the stateless `Parser` architecture makes this trivial with `wasm-pack`
- **Library crate** — publish `latin-parser` as a reusable Rust crate on crates.io
- **Web API** — thin `axum`/`actix` wrapper around `Parser`
- **JSON output mode** — structured output alongside the traditional text format
- **Performance** — parallelize multi-word analysis with `rayon` (the immutable `&LatinData` borrow makes this trivial)

## Estimated Scope

| Crate | Lines (est.) | Key dependencies |
|-------|-------------|-----------------|
| `latin-types` | ~1,000 | `serde` |
| `latin-data` | ~800 | `serde_json` |
| `latin-parser` | ~3,000 | — |
| `words-cli` | ~400 | `clap`, `rustyline` |
| Data converter | ~500 | (one-off script) |
| Tests | ~1,000 | — |
| **Total** | **~6,700** | |

The Rust version will be significantly shorter than the 27,670-line Ada codebase because:
- No auto-generated I/O boilerplate (serde handles this)
- No binary file format machinery (JSON/in-memory)
- No fixed-width string padding
- Rust enums replace Ada discriminated records + separate IO packages
- Standard library provides `HashMap`, `Vec`, string handling

## Recommended Approach

**Build bottom-up, test continuously.** Each phase produces a working, tested artifact. The data converter validates the data migration. The type crate compiles and round-trips through serde. The parser crate passes unit tests. The CLI matches the original program's output. At no point are you building on unverified foundations.

The single biggest risk is **subtle parsing differences** — the original algorithm has many edge cases in grammar validation and result ranking. The regression test suite is your safety net. Capture extensive baselines before writing any Rust code.
