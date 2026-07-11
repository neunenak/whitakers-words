# Porting Notes

Notes and considerations for porting Whitaker's WORDS to a modern language.

## Current State Assessment

### Strengths
- Complete Latin morphology coverage (~39,000 dictionary entries)
- Robust inflection system (~3,200 rules)
- Clever "tricks" system for spelling variations
- English-to-Latin reverse lookup
- Compound verb detection

### Weaknesses
- Heavy reliance on global mutable state
- Tightly coupled I/O (parsing and printing interleaved)
- Fixed-width data formats (fragile, hard to edit)
- No Unicode support (can't represent macrons)
- Binary file formats tied to Ada record layout

## Recommended Architecture for Port

See `docs/rust-port-plan.md` for the current, concrete plan. The summary below is kept for historical context; the JSON/SQLite data-migration idea it describes was superseded — `DICTLINE.GEN` etc. stay as the source of truth and are parsed as text directly (see "Data Files Stay Text, Stay Source of Truth" in the port plan).

### Layer 1: Data Layer
```
Dictionary
├── Entry: stems[], part_of_speech, grammar, meaning
├── Parsed directly from DICTLINE.GEN text (no derived format)
└── Index by stem prefix for fast lookup

Inflections
├── Rule: ending, grammatical_properties, stem_key
├── Parsed directly from INFLECTS.LAT text (no derived format)
└── Organized by ending for fast matching

Addons
├── Prefixes, Suffixes, Tackons
└── Word formation rules, parsed directly from ADDONS.LAT
```

### Layer 2: Parsing Engine
```
Parser (stateless, pure functions)
├── decompose(word) → [(stem, ending, inflection)]
├── lookup(stem) → [DictionaryEntry]
├── validate(entry, inflection) → bool
└── analyze(word) → [ParseResult]

Tricks
├── spelling_variations(word) → [word]
└── syncope_patterns(word) → [word]
```

### Layer 3: API Layer
```
LatinAnalyzer
├── analyze_word(word) → [Analysis]
├── analyze_text(text) → [WordAnalysis]
└── lookup_english(word) → [LatinEntry]

Analysis
├── word: string
├── lemma: string
├── part_of_speech: POS
├── grammar: GrammarInfo
└── meaning: string
```

### Layer 4: Interface Layer
```
CLI, Web API, Library bindings
```

## Data Format Migration

**Superseded** — there is no migration. `DICTLINE.GEN` and `INFLECTS.LAT` are hand-maintained via the `HOWTO.txt` workflow (SORTER, CHECK, DUPS, LINEDICT); a Rust port parses their fixed-width text directly rather than converting them to JSON, so the checked-in files remain the single source of truth. See `docs/rust-port-plan.md`.

## Key Algorithms to Port

### 1. Stem+Ending Decomposition
```python
def decompose(word: str) -> List[Tuple[str, str, Inflection]]:
    results = []
    for ending_len in range(1, 8):
        if ending_len > len(word):
            break
        stem = word[:-ending_len]
        ending = word[-ending_len:]
        for infl in inflections_by_ending.get(ending, []):
            results.append((stem, ending, infl))
    return results
```

### 2. Dictionary Lookup
```python
def lookup(stem: str) -> List[DictEntry]:
    prefix = stem[:2].lower()
    candidates = stem_index.get(prefix, [])
    return [e for e in candidates if normalize(e.stem) == normalize(stem)]

def normalize(s: str) -> str:
    return s.lower().replace('v', 'u').replace('j', 'i')
```

### 3. Grammar Validation
```python
def validates(entry: DictEntry, infl: Inflection) -> bool:
    if entry.pos != infl.pos:
        return False
    if entry.pos == 'noun':
        return entry.declension == infl.declension
    # ... similar for other POS
```

## Language Candidates

### Rust
- **Pros**: Fast, safe, good for CLI tools, WebAssembly target
- **Cons**: Steeper learning curve, verbose

### Python
- **Pros**: Rapid development, easy data manipulation, good NLP ecosystem
- **Cons**: Slower, dependency management

### TypeScript
- **Pros**: Web-native, good tooling, JSON-friendly
- **Cons**: Runtime overhead, less suitable for heavy computation

### Go
- **Pros**: Simple, fast compilation, good CLI support
- **Cons**: Less expressive type system

## Recommended Approach

1. **Start with the data layer**
   - Write a fixed-width parser for DICTLINE.GEN (no format conversion)
   - Write a fixed-width parser for INFLECTS.LAT (no format conversion)
   - Validate parsed counts/spot-checks against the known entry counts

2. **Build core parser**
   - Implement decomposition
   - Implement dictionary lookup
   - Implement grammar validation
   - Test against known inputs

3. **Add tricks system**
   - Port spelling variations
   - Port syncope handling

4. **Add compound detection**
   - Multi-word verb handling

5. **Build interfaces**
   - CLI matching original behavior
   - Web API for integration
   - Library for embedding

## Testing Strategy

1. **Capture baseline**: Run original WORDS on test corpus, save output
2. **Unit tests**: Test individual functions (decompose, lookup, validate)
3. **Integration tests**: Compare new output to baseline
4. **Regression tests**: Ensure tricks/edge cases work

## Open Questions

- Should macrons be added to dictionary? (Significant editorial work)
- What output format? (JSON, plain text, both?)
- Offline-first or server-based?
- Mobile support needed?
