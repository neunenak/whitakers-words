# Rust Port Plan for Whitaker's Words

## Scope

This plan ports the **query/analysis engine** — the `words.adb` → `words_engine` → `latin_utils` pipeline that answers "what is this Latin word?" It does not port the Ada dictionary-maintenance toolchain (`makedict`, `wakedict`, `makestem`, `makeewds`, `makeefil`, `makeinfl`, `sorter`, `check`, `dups`, `dictpage`, ...). Those tools exist to edit and validate `DICTLINE.GEN`/`INFLECTS.LAT`/etc. and to produce the Ada program's binary caches (`DICTFILE.GEN`, `STEMFILE.GEN`, `INFLECTS.SEC`, `EWDSFILE.GEN`). The workflow in `HOWTO.txt` for maintaining the dictionary stays exactly as Whitaker designed it — Ada, fixed-width text, SORTER/CHECK/DUPS and all. The Rust port only needs to *read* whatever `DICTLINE.GEN` currently contains.

## Data Files Stay Text, Stay Source of Truth

`DICTLINE.GEN`, `INFLECTS.LAT`, `ADDONS.LAT`, and `UNIQUES.LAT` are the human-edited source files (see `docs/data-formats.md`); everything else the Ada build produces (`DICTFILE.GEN`, `STEMFILE.GEN`, `INDXFILE.GEN`, `INFLECTS.SEC`, `EWDSFILE.GEN`) is a derived binary cache in Ada's own record layout, rebuilt from the text sources by `makedict`/`makestem`/`makeinfl`/etc.

The Rust port has no reason to introduce a second derived format (e.g. JSON). Converting `DICTLINE.GEN` to JSON would mean either maintaining it as a second copy of the dictionary (drifts the moment someone edits `DICTLINE.GEN` through the normal Ada workflow) or regenerating it as a build step (which just re-adds the binary-cache problem the port should be getting rid of, plus a lossy round-trip risk on 39k hand-maintained entries). Instead:

- **Rust parses the fixed-width text directly** — `DICTLINE.GEN`, `INFLECTS.LAT`, `ADDONS.LAT`, `UNIQUES.LAT` — using the column layouts documented in `docs/data-formats.md`. No conversion step, no generated intermediate files, no second source of truth.
- **No Ada-style binary cache either.** Parsing 39k dictionary lines and 3.2k inflection rules into `HashMap`-based indices at startup is a few milliseconds of work in Rust — there's no need to replicate `STEMFILE.GEN`/`INDXFILE.GEN`/`INFLECTS.SEC` as a separate on-disk format the way Ada's direct-access I/O required. The in-memory index is rebuilt fresh from text every run.
- **Drop the EWDS generation phase entirely.** The Ada pipeline runs `makeewds` then `makeefil` to precompute `EWDSLIST.GEN`/`EWDSFILE.GEN` for English→Latin lookup. In Rust, build that reverse index in memory at load time by scanning `MEAN` fields while parsing `DICTLINE.GEN` — one pass, no separate generation phase, no generated file to keep in sync.
- **Embed the text files at compile time** with `include_str!` for single-binary distribution (they're already checked into the repo and the dictionary is ~6 MB — trivial to embed). Parse once at process startup into the in-memory indices described in Phase 2.

This means the Rust build pipeline is just: compile → parse text at startup → serve. No `wakedict`/`makestem`/`makeewds`/`makeefil`/`makeinfl` equivalents, no generated data files, no "did I forget to regenerate X after editing DICTLINE.GEN" class of bug.

## Package Layout

A single Cargo package, not a workspace. The whole port is targeted at ~5,000-6,000 lines (see estimate below) — a multi-crate workspace would be pure ceremony at that size. One lib target for parsing, one bin target for the CLI, in the same package:

```
whitakers-words-rs/
├── Cargo.toml
├── src/
│   ├── lib.rs           # public API: LatinData, Parser, Analysis
│   ├── types.rs         # Phase 1 — enums, structs (≈ latin_utils)
│   ├── data.rs          # Phase 2 — text parsing & in-memory indices (≈ support_utils)
│   ├── parser/          # Phase 3 — core parse engine (≈ words_engine)
│   │   ├── mod.rs
│   │   ├── decompose.rs
│   │   ├── lookup.rs
│   │   ├── validate.rs
│   │   ├── tricks.rs
│   │   ├── compounds.rs
│   │   ├── sweep.rs
│   │   ├── english.rs
│   │   └── format.rs
│   └── main.rs          # Phase 5 — CLI binary (≈ commands), `use whitakers_words::...`
├── data/                 # DICTLINE.GEN, INFLECTS.LAT, ADDONS.LAT, UNIQUES.LAT
│                         # (symlink or copy of the existing checked-in files)
└── tests/
    └── regression/       # captured baseline from the original Ada program
```

If `latin-parser` later earns a life of its own (crates.io publish, WASM target — see Phase 6), it can be split out of `lib.rs` into its own crate then. No reason to pay for that separation up front.

**Capture regression baseline first**: run the original Ada `bin/words` against a large test corpus (the existing 4 test inputs plus a broader word list) and save the output. This is the ground truth for the entire port, independent of everything else below.

## Phase 1: Type System (`types.rs`) — ~1,000 lines

Port `latin_utils-inflections_package.ads` + `latin_utils-dictionary_package.ads`. This is almost entirely type definitions and maps very naturally to Rust.

**Ada discriminated unions → Rust enums:**

```rust
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Quality {
    Noun { decl: Declension, case: Case, number: Number, gender: Gender },
    Verb { conj: Conjugation, tense: Tense, voice: Voice, mood: Mood, person: Person, number: Number },
    Adjective { decl: Declension, case: Case, number: Number, gender: Gender, comparison: Comparison },
    Adverb { comparison: Comparison },
    Pronoun { decl: Declension, case: Case, number: Number, gender: Gender },
    // ... Vpar, Supine, Prep, Conj, Interj, Numeral
}
```

**Key enums** (all small, `Copy`):
- `PartOfSpeech` (16 variants), `Case` (8), `Gender` (5), `Number` (3), `Tense` (7), `Voice` (3), `Mood` (6), `Comparison` (4)
- `DictionaryKind`, `Age`, `Frequency`, `Area`, `Geography`, `Source`

**Key structs:**
- `Inflection` — quality + stem_key + ending + age + frequency
- `DictionaryEntry` — 4 stems + part entry + translation + meaning
- `Stem` — `String` (no longer fixed-width 18-char)

**Design notes:**
- Use `&str`/`String` instead of fixed-width character arrays
- Keep `Copy` on small enums, `Clone` on larger structs
- No `serde` needed here unless Phase 6's JSON output mode happens — don't add it speculatively

## Phase 2: Data Layer (`data.rs`) — ~700 lines

Replaces `support_utils` and the binary file loading machinery. Parses the four text source files directly into in-memory indices — see "Data Files Stay Text" above for why there's no intermediate format.

**Core struct:**

```rust
pub struct LatinData {
    pub entries: Vec<DictionaryEntry>,
    pub stem_index: HashMap<[u8; 2], Vec<StemRef>>,   // 2-char prefix → entries
    pub inflections_by_ending: HashMap<String, Vec<Inflection>>,
    pub prefixes: Vec<PrefixEntry>,
    pub suffixes: Vec<SuffixEntry>,
    pub tackons: Vec<TackonEntry>,
    pub uniques: HashMap<String, Vec<UniqueEntry>>,
    pub english_index: HashMap<String, Vec<EntryRef>>, // built from MEAN while parsing DICTLINE.GEN
}

impl LatinData {
    pub fn load() -> Self {
        // parse the include_str!()-embedded DICTLINE.GEN / INFLECTS.LAT /
        // ADDONS.LAT / UNIQUES.LAT text and build all indices in one pass
    }
}
```

**Key decisions:**
- Parse the fixed-width columns per `docs/data-formats.md` directly — no `serde`, no JSON, no generated intermediate.
- **Indexing**: `HashMap` keyed on 2-character stem prefix (matching the original `INDXFILE` concept) for O(1) lookup instead of binary search.
- **Inflection index**: group inflections by ending string for O(1) lookup during decomposition (the original loads them into 5 disk-efficiency sections and does sequential scans — irrelevant in memory).
- **English index**: built in the same pass over `DICTLINE.GEN`, replacing the `makeewds`/`makeefil` pipeline entirely.

## Phase 3: Parsing Engine (`parser/`) — ~3,000 lines

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

## Phase 5: CLI (`main.rs`) — ~400 lines

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
- **Split out a library crate** — if `latin-parser` needs to be reused outside this binary (published to crates.io, embedded elsewhere), pull `lib.rs` + its modules into their own crate at that point. Not before.
- **Web API** — thin `axum`/`actix` wrapper around `Parser`
- **JSON output mode** — structured output alongside the traditional text format (this is where `serde` earns its place, on output, not on the source data)
- **Performance** — parallelize multi-word analysis with `rayon` (the immutable `&LatinData` borrow makes this trivial)

## Estimated Scope

| Module | Lines (est.) | Key dependencies |
|--------|-------------|-----------------|
| `types.rs` | ~1,000 | — |
| `data.rs` | ~700 | — |
| `parser/` | ~3,000 | — |
| `main.rs` | ~400 | `clap`, `rustyline` |
| Tests | ~1,000 | — |
| **Total** | **~6,100** | |

The Rust version will be significantly shorter than the 27,670-line Ada codebase because:
- No binary file format machinery — text is parsed straight into memory
- No generated intermediate files or conversion tooling to write and maintain
- No fixed-width string padding
- Rust enums replace Ada discriminated records + separate IO packages
- Standard library provides `HashMap`, `Vec`, string handling

## Recommended Approach

**Build bottom-up, test continuously.** Each phase produces a working, tested artifact. `types.rs` compiles standalone. `data.rs` parses the real `DICTLINE.GEN`/`INFLECTS.LAT`/`ADDONS.LAT`/`UNIQUES.LAT` and its indices can be spot-checked against known entries. The parser module passes unit tests. The CLI matches the original program's output. At no point are you building on unverified foundations, and at no point is there a derived data format that can drift from the checked-in source files.

The single biggest risk is **subtle parsing differences** — the original algorithm has many edge cases in grammar validation and result ranking. The regression test suite is your safety net. Capture extensive baselines before writing any Rust code.
