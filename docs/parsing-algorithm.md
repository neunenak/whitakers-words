# Whitaker's WORDS Parsing Algorithm

This document describes the core parsing algorithm for Latin word analysis.

## Overview

The parser works by **exhaustive decomposition**: it generates ALL morphologically valid stem+ending splits, then filters by dictionary lookup and grammatical validation.

## Main Algorithm (Parse_Latin_Word)

Located in `words_engine-parse.adb`, lines 862-951.

### Pass 1: Direct Lookup

```
1. Check for Roman numerals
2. Call Word() for standard dictionary search
3. Try_Slury() for unknown proper names
4. Syncope() for contracted verb forms (if enabled)
5. Handle enclitics (-que, -ne, -ve, -est)
```

### Pass 2: Tricks (if Pass 1 found nothing)

```
If word not found AND not capitalized:
    Try_Tricks() - apply spelling variations
    Handle enclitics on modified word
```

### Pass 3: Compound Detection

```
If next word is a form of "sum" (to be):
    Check for participle + auxiliary compounds
    E.g., "amatus est" → passive perfect
```

## Stem + Ending Decomposition

Located in `word_package.adb`, `Run_Inflections` procedure.

```
For ending_length = 1 to 7:
    Look up inflection section based on word's final letter
    For each inflection with matching ending:
        stem = word[0 .. word_length - ending_length]
        if stem_length <= 18:
            store (stem, inflection_record) in candidate array
```

**Example for "amicitiae":**
```
Try ending "e" (1 char) → stem "amicitia" → check inflections
Try ending "ae" (2 chars) → stem "amiciti" → check inflections
Try ending "iae" (3 chars) → stem "amicit" → check inflections  ← matches!
...
```

## Dictionary Search

Located in `word_package.adb`, `Dictionary_Search` procedure.

```
For each candidate stem:
    Binary search in STEMFILE.GEN using INDXFILE.GEN indices
    For each matching dictionary entry:
        Add to Pruned Dictionary List (PDL)
```

**Index structure:** First two letters of stem map to index range in stem file.

## Grammar Validation

Located in `word_package.adb`, `Reduce_Stem_List` procedure.

```
For each dictionary entry in PDL:
    For each candidate inflection:
        If stem lengths match:
            If part of speech compatible:
                If grammatical properties agree:
                    Add to final results
```

**Compatibility rules:**
- Noun inflections must match noun entries
- Verb inflections must match verb entries
- Declension/conjugation numbers must match
- Gender must be compatible (or common gender)

## The Tricks System

Located in `words_engine-tricks.adb`.

When standard lookup fails, applies systematic spelling variations:

### 1. Flip (Initial Substitution)
Replace initial consonant with variant.
```
Example: "h" ↔ "" (aspirate handling)
```

### 2. Flip_Flop (Bidirectional)
Try both directions of a substitution.

### 3. Internal (Substring Replacement)
Replace pattern anywhere in word.
```
Example: "ae" ↔ "e" (classical vs. medieval spelling)
```

### 4. Syncope (Vowel Contraction)
Handle contracted perfect tense forms.
```
"amavisti" → "amasti" (drop -vi-)
"audivit" → "audiit" → "audit"
```

**Patterns:**
- `ii` ↔ `ivi`
- `as/es/is/os` ↔ `avis/evis/ivis/ovis`
- `ar/er/or` ↔ `aver/ever/over`

## Prefix/Suffix Handling

### Apply_Prefix
```
For each known prefix:
    If word starts with prefix:
        reduced_stem = word - prefix
        Search dictionary for reduced_stem
        If found:
            Store prefix + base word as compound entry
            (Only first matching prefix is used)
```

### Apply_Suffix
```
For each known suffix:
    If stem ends with suffix pattern:
        base = stem - suffix
        Search dictionary for base
        If found:
            Store base + suffix as derived entry
            (All matching suffixes are tried)
```

## Compound Verb Detection

Located in `words_engine-parse.adb`, `Compounds_With_Sum` procedure.

Detects multi-word verb constructions:

| Pattern | Meaning |
|---------|---------|
| Perf. Pass. Participle + sum/es/est | Passive perfect ("was loved") |
| Fut. Act. Participle + sum | Periphrastic future ("is about to love") |
| Participle + esse/fuisse | Perfect infinitive compound |
| Supine + iri | Future passive infinitive |

## Key Data Structures

### Parse_Record
```ada
type Parse_Record is record
   Stem  : Stem_Type;           -- The stem text (max 18 chars)
   IR    : Inflection_Record;   -- Grammatical info
   D_K   : Dictionary_Kind;     -- Source dictionary
   MNPC  : Dict_IO.Count;       -- Dictionary entry pointer
end record;
```

### Inflection_Record
```ada
type Inflection_Record is record
   Qual   : Quality_Record;     -- Case/tense/mood/etc.
   Key    : Stem_Key_Type;      -- Which stem slot to use
   Ending : Ending_Record;      -- The suffix
   Age    : Age_Type;
   Freq   : Frequency_Type;
end record;
```

### Quality_Record (discriminated union)
```ada
type Quality_Record (Pofs : Part_Of_Speech_Type) is record
   case Pofs is
      when N => Decl, Case, Number, Gender
      when V => Conj, Tense, Voice, Mood, Person, Number
      when Adj => Decl, Case, Number, Gender, Comparison
      ...
   end case;
end record;
```

## Character Equivalence

Throughout parsing, these characters are treated as equivalent:
- `u` ↔ `v` (Latin had no distinction)
- `i` ↔ `j` (Latin had no distinction)

This is handled by the `Equ()` function in word_package.adb.

## Performance Characteristics

- **Inflection matching**: O(n) where n = number of inflection rules (~3000)
- **Dictionary search**: O(log m) where m = dictionary size (~40,000)
- **Overall per word**: O(n + k log m) where k = number of candidate stems

The indexed binary search makes dictionary lookup fast despite the large dictionary size.

## Porting Recommendations

1. **Separate concerns**: The current code mixes parsing, dictionary lookup, and output formatting. A clean port should separate these.

2. **Replace global state**: The extensive use of global arrays (`Sa`, `Ssa`, `Pdl`) makes the code hard to reason about. Use function parameters and return values.

3. **Structured output**: Return parse results as structured data, not formatted strings.

4. **Unicode**: Add support for macrons (ā, ē, ī, ō, ū) which are essential for disambiguation.

5. **Test harness**: Build regression tests from known-good output before refactoring.
