# TI-Nspire Development Suite

Calculator and desktop software development projects
assembled by Jahvascript.

## Projects

- PrecalculusStudio: Lua-based precalculus application
- NspireDesk: Swift desktop calculator utility
- TNSStudio: Swift and Lua desktop tooling

## Development Status

Source and selected generated files are included for review.

Compatibility, hardware functionality, and end-to-end
build reproducibility have not yet been verified.

NspireDesk and TNSStudio may require external libraries
and additional dependency setup.

## Attribution and Licensing

Original project license files are preserved where present.
Third-party libraries are not included in this initial package.

Licensing and content provenance must be reviewed before
public distribution.

## Developer

Jahvascript
https://github.com/Jahvascript

## NspireDesk dependency setup

NspireDesk uses a Rust backend and Swift desktop interface.

For a fresh clone, install Rust/Cargo and Apple command-line tools,
then run:

```bash
bash NspireDesk/source/backend/bootstrap-rust-deps.sh
```

The first run downloads dependencies using `Cargo.lock`. The
local vendor directory is excluded from Git. Subsequent Rust
tests and builds can run offline.

The full desktop build uses `NspireDesk/source/build.sh`.
The build generates Exit Test Mode.tns from its included
Lua source when needed. The generated file is excluded from Git.

The three projects have passed local tests. Fresh-clone
reproducibility and physical calculator compatibility have
not yet been fully verified.
