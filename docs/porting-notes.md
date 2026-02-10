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

### Layer 1: Data Layer
```
Dictionary
├── Entry: stems[], part_of_speech, grammar, meaning
├── Load from JSON/SQLite
└── Index by stem prefix for fast lookup

Inflections
├── Rule: ending, grammatical_properties, stem_key
├── Organized by ending for fast matching
└── Load from JSON/YAML

Addons
├── Prefixes, Suffixes, Tackons
└── Word formation rules
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

### Dictionary (DICTLINE.GEN → JSON)

**Before (fixed-width):**
```
abac               abac                N      2 1 M T   E E X C E small table...
```

**After (JSON):**
```json
{
  "lemma": "abacus",
  "stems": ["abac", "abac", null, null],
  "pos": "noun",
  "declension": 2,
  "gender": "masculine",
  "meaning": "small table for cruets",
  "age": "late",
  "frequency": "rare"
}
```

### Inflections (INFLECTS.LAT → JSON)

**Before:**
```
N     1 1 NOM S C  1 1 a         X A
```

**After:**
```json
{
  "pos": "noun",
  "declension": 1,
  "case": "nominative",
  "number": "singular",
  "ending": "a",
  "stem_key": 1
}
```

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

1. **Start with data migration**
   - Convert DICTLINE.GEN to JSON
   - Convert INFLECTS.LAT to JSON
   - Write validation scripts

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
