# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Whitaker's WORDS is a Latin-English dictionary with inflectional morphology support, written in Ada. The original author (Colonel William Whitaker) passed away in 2010; this is a preservation/maintenance effort. The goal is to get it building reliably and eventually port to a more modern language/architecture.

## Build Commands

```bash
# Full build (compiles Ada code + generates dictionary data files)
make

# Build only executables (faster, use when not changing dictionary data)
make commands

# Build a single program
make words       # Main dictionary program
make makedict    # Dictionary builder
make sorter      # Stem list sorter

# Run tests
make test

# Clean build artifacts
make clean       # Everything including data files
make clean_data  # Just generated data files
```

## Running the Program

```bash
bin/words              # Interactive mode
bin/words "amo"        # Single word lookup
bin/words input.txt    # Process file
bin/words in.txt out.txt  # File to file
```

## Build Dependencies

- GPRBuild (Ada project manager)
- GNAT (Ada compiler, version 4.9+ required for 64-bit)

**Using Nix (recommended):**
```bash
nix develop    # Enter dev shell with all dependencies
make           # Build
```

**On Debian/Ubuntu:**
```bash
apt-get install gprbuild gnat
```

## Architecture

### Library Structure (dependency order)

1. **latin_utils** - Core Latin language types and utilities
   - Inflection types (Part_Of_Speech_Type, Case_Type, Number_Type, Gender_Type, etc.)
   - Dictionary types (Dictionary_Kind, Area_Type, Age_Type, Frequency_Type)
   - Stem types (18-char max stems, 80-char meanings)

2. **support_utils** - Application support (depends on latin_utils)
   - Word parameters and configuration
   - Addons and uniques handling

3. **words_engine** - Core parsing engine (depends on support_utils)
   - `Words_Engine.Parse` - Main entry point: `Parse_Line()` and `Analyse_Line()`
   - Inflection matching, tricks (spelling variants), list processing

4. **commands** - Executables (depends on words_engine)
   - `words.adb` - Main program entry point
   - `words_main.adb` - Command-line handling and mode dispatch
   - Various dictionary generation tools (makedict, makestem, etc.)

### Data Files

Source dictionary data (checked in):
- `DICTLINE.GEN` - Main dictionary (~39k entries), fixed-width format
- `INFLECTS.LAT` - Inflection rules
- `ADDONS.LAT` - Prefixes, suffixes, tackons
- `UNIQUES.LAT` - Irregular forms

Generated at build time:
- `STEMFILE.GEN`, `INDXFILE.GEN` - Compiled stem lookup
- `INFLECTS.SEC` - Compiled inflections
- `EWDSFILE.GEN`, `EWDSLIST.GEN` - English-to-Latin reverse index

### Key Types (in latin_utils-inflections_package.ads)

- `Part_Of_Speech_Type` - N, V, Adj, Adv, Prep, Conj, Pron, Num, etc.
- `Stem_Type` - String(1..18), space-padded
- `Meaning_Type` - String(1..80), space-padded

## Ada Style Notes

The code uses strict compiler warnings (`-gnatwae -Wall`) and style checking. GPR files define the build with static libraries by default.

## Documentation

See `docs/` for detailed architecture documentation:
- `docs/architecture.md` - Module structure and control flow
- `docs/data-formats.md` - Dictionary and inflection file formats
- `docs/parsing-algorithm.md` - Core Latin parsing algorithm
- `docs/porting-notes.md` - Notes for porting to modern languages

## Known Issues

- **Test `04_english` fails**: The English-to-Latin reverse lookup test produces correct results but in a different order than expected. The expected output was captured on an older system with different sorting behavior. Needs updating to match current output.
