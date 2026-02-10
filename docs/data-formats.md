# Whitaker's WORDS Data Formats

This document describes the data files used by Whitaker's WORDS.

## Source Files (Human-Editable)

### DICTLINE.GEN (Main Dictionary)

~39,000 entries, fixed-width format.

**Format:**
```
Columns 1-18:   Stem 1 (lemma)
Columns 19-36:  Stem 2 (genitive/other form)
Columns 37-54:  Stem 3 (often blank)
Columns 55-72:  Stem 4 (often blank)
Column 73+:     Part of speech + grammatical codes + meaning
```

**Example:**
```
abac               abac                N      2 1 M T          E E X C E small table for cruets...
```

**Part of Speech codes:** N, V, ADJ, ADV, PREP, CONJ, INTERJ, PRON, NUM, PACK, TACKON, PREFIX, SUFFIX

**Grammatical codes vary by POS:**
- Nouns: Declension (1-5), Variant, Gender (M/F/N/C), Noun_Kind
- Verbs: Conjugation (1-4), Variant, Verb_Kind (TRANS/INTRANS/DEP/etc.)
- Adjectives: Declension, Comparison (POS/COMP/SUPER)

**Translation metadata:**
- Age: X (all), A (archaic), B (early), C (classical), D (late), E (later), F (medieval), G (scholar), H (modern)
- Area: X (all), A (agriculture), B (biology), D (drama), E (ecclesiastic), etc.
- Geo: X (all), A (Africa), B (Britain), G (Germany), etc.
- Frequency: A (very frequent) through F (very rare), plus I (inscription), M (graffiti), N (Pliny)
- Source: single letter indicating dictionary source

### INFLECTS.LAT (Inflection Rules)

~3,200 rules defining Latin morphology.

**Format:**
```
POS  Decl Var  Case Num Gen  Key1 Key2  Ending  Age Freq
N    1    1    NOM  S   C    1    1     a       X   A     -- 1st decl nominative singular
V    3    1    PRES ACTIVE IND 1 S     3 1     o   X   A  -- 3rd conj present active indicative 1st singular
```

**Fields:**
- Part of speech
- Declension/Conjugation number
- Variant
- Grammatical properties (case/tense/voice/mood/person/number)
- Stem key positions (which of the 4 stems to use)
- Ending string (up to 7 characters)
- Age and frequency codes

### ADDONS.LAT (Word Formation Rules)

Prefixes, suffixes, and enclitic particles.

**Format:**
```
PREFIX ex
V V
from, out of, utterly

SUFFIX -ness
N N
quality of
```

### UNIQUES.LAT (Exception Words)

~230 irregular forms not covered by standard rules.

**Format:**
```
agantur
V      3 1 PRES PASSIVE SUB 3 P  IMPERS
let them be treated
```

## Generated Binary Files

### Build Pipeline

```
DICTLINE.GEN ──[wakedict]──→ DICTFILE.GEN
             ──[sorter]────→ STEMLIST.GEN
STEMLIST.GEN ──[makestem]──→ STEMFILE.GEN + INDXFILE.GEN
INFLECTS.LAT ──[makeinfl]──→ INFLECTS.SEC
DICTLINE.GEN ──[makeewds]──→ EWDSLIST.GEN
EWDSLIST.GEN ──[makeefil]──→ EWDSFILE.GEN
```

### STEMFILE.GEN + INDXFILE.GEN

Binary indexed stem database for O(log n) lookup.

**INDXFILE.GEN structure:**
- Index arrays for stem lookup by first 1-2 characters
- `Bdlf/Bdll`: First/last index for single-letter prefixes
- `Ddlf/Ddll`: First/last index for two-letter prefixes

**STEMFILE.GEN structure:**
- Sequential `Dictionary_Stem` records
- Each record: stem string + part entry + key info

### DICTFILE.GEN

Binary dictionary entries indexed by entry number.

**Record structure (Dictionary_Entry):**
```ada
Stems(1..4) : Stem_Type;        -- 4 stems, 18 chars each
Part        : Part_Entry;       -- POS + grammatical details
Tran        : Translation_Record;  -- Age/Area/Geo/Freq/Source
Mean        : Meaning_Type;     -- Definition, 80 chars
```

### INFLECTS.SEC

Binary inflection rules organized by word ending.

**Structure:** 5 sections indexed by final letter:
- Section 1: endings in a, c, d, e, i
- Section 2: endings in m, n, o, r
- Section 3: endings in s
- Section 4: endings in t, u
- Section 5: zero-length endings

Each section contains up to 2000 `Inflection_Record` entries.

### EWDSFILE.GEN

Binary English-to-Latin reverse index for English lookups.

## File Sizes

| File | Size | Entries |
|------|------|---------|
| DICTLINE.GEN | 5.9 MB | 39,338 |
| INFLECTS.LAT | 126 KB | 3,207 |
| ADDONS.LAT | 34 KB | 1,200 |
| UNIQUES.LAT | 8.9 KB | 228 |
| DICTFILE.GEN | 6.8 MB | 39,338 |
| STEMFILE.GEN | 3.4 MB | - |
| INFLECTS.SEC | 112 KB | - |
| EWDSFILE.GEN | 8.0 MB | ~149,000 |

## Runtime Data Loading

At startup, `Initialize_Word_Package` loads:

1. `INFLECTS.SEC` → inflection sections (binary)
2. `STEMFILE.GEN` + `INDXFILE.GEN` → stem database with indices
3. `DICTFILE.GEN` → dictionary entries
4. `UNIQUES.LAT` → exception words (into memory)
5. `ADDONS.LAT` → prefix/suffix/tackon arrays (into memory)
6. `EWDSFILE.GEN` → English-Latin mapping (optional)

## Porting Considerations

**For a modern port, consider:**

1. **JSON/SQLite for dictionary**: Replace fixed-width text + binary with structured format
2. **Embedded data**: Bundle dictionary as binary resource or fetch from network
3. **Simplified inflections**: The 5-section organization was for disk efficiency; in-memory can be simpler
4. **Unicode support**: Original uses ASCII only; modern port should handle macrons (ā, ē, ī, ō, ū)
