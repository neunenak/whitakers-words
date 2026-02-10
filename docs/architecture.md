# Whitaker's WORDS Architecture

This document describes the architecture of Whitaker's WORDS for porting purposes.

## Module Structure

```
src/
├── commands/           Entry points and CLI tools
│   ├── words.adb       Main entry point (thin wrapper)
│   ├── words_main.adb  Argument parsing, mode selection
│   ├── process_input.adb  Main input loop
│   └── make*.adb       Data file generators
│
├── words_engine/       Core parsing engine
│   ├── parse           Line parsing dispatcher
│   ├── word_package    Word analysis, inflection matching
│   ├── list_package    Result formatting
│   ├── tricks          Spelling variation handling
│   └── english_support_package  English-to-Latin
│
├── latin_utils/        Data types and I/O
│   ├── inflections_package  Grammatical types
│   ├── dictionary_package   Dictionary entry types
│   └── strings_package      String utilities
│
└── support_utils/      Configuration and state
    ├── word_parameters      User modes
    ├── addons_package       Prefix/suffix handling
    └── uniques_package      Exception words
```

## Dependency Order

```
latin_utils (no deps)
    ↓
support_utils (depends on latin_utils)
    ↓
words_engine (depends on support_utils)
    ↓
commands (depends on words_engine)
```

## Control Flow

### Startup

1. `words.adb` calls `Words_Main(Developer_Version)`
2. `words_main.adb` parses arguments to determine mode:
   - **Interactive**: No args, read from keyboard
   - **Command_Line_Input**: Words as arguments
   - **Command_Line_Files**: Input/output file paths
3. Calls `Words_Engine.Initialization.Initialize_Engine` to load data
4. Calls `Process_Input(Configuration)` for main loop

### Main Loop (process_input.adb)

```
loop:
  read line
  if line starts with:
    '@' → load file
    '#' → change parameters
    '~' → toggle Latin↔English
    '?' → help (dev mode)
  else:
    Parse_Line(Configuration, Line)
```

### Word Lookup Pipeline

```
Input String
    ↓
Parse_Line (words_engine-parse.adb)
    ↓
Word (word_package.adb)
  ├─ Run_Inflections: generate stem+ending candidates
  ├─ Dictionary_Search: binary search on stem files
  └─ Reduce_Stem_List: validate grammar matches
    ↓
[if no match] Try_Tricks: spelling variations
    ↓
[if next word is "sum"] Compounds_With_Sum
    ↓
Analyse_Word → Word_Analysis result
    ↓
List_Stems → formatted output
```

## Execution Modes

| Variable | Values | Purpose |
|----------|--------|---------|
| Method | Interactive, Command_Line_Input, Command_Line_Files | Input source |
| Language | Latin_To_English, English_To_Latin | Direction |
| Configuration | Developer_Version, User_Version, Only_Meanings | Output verbosity |

## Key Mode Flags (word_parameters.ads)

- `Do_Tricks`: Enable spelling variation matching
- `Do_Compounds`: Enable multi-word verb detection
- `Do_Fixes`: Enable prefix/suffix handling
- `Show_Age`: Display word dating (archaic, classical, etc.)
- `Show_Frequency`: Display usage frequency
- `Do_Only_Meanings`: Suppress grammatical details

## Global State

The codebase relies heavily on global state in package bodies:

- `word_package`: `Sa`, `Ssa` (stem arrays), `Pdl` (dictionary results)
- `word_parameters`: `Mode` array, `Method`, `Language`
- `word_support_package`: Dictionary file handles, index arrays

This is a key refactoring target for porting.

## Public API

The closest thing to a clean API is in `words_engine-parse.ads`:

```ada
procedure Parse_Line (Configuration : Configuration_Type;
                      Input_Line    : String);

function Analyse_Line (Configuration : Configuration_Type;
                       Input_Line    : String)
  return Result_Container.Vector;
```

`Analyse_Line` returns a vector of `Word_Analysis` records without printing.
