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


---

## Everyone Is Welcome at JahvaScript

**Different backgrounds. Different experiences. One community.**

At JahvaScript, we believe open source is for everyone.

Whether you're an experienced engineer, a student, a beginner,
or someone with an idea, you're welcome here.

We value peace, respect, accessibility, creativity, learning,
and constructive collaboration.

Contributions of all kinds matter: code, documentation, testing,
bug reports, accessibility improvements, questions, and suggestions.

Participation is open to people of every background, belief,
identity, ability, and experience level.

**Every contribution counts. Every voice deserves respect.**

### Our Community Standards

- [Code of Conduct](https://github.com/Jahvascript/.github/blob/main/CODE_OF_CONDUCT.md)
- [Contribution Guidelines](https://github.com/Jahvascript/.github/blob/main/CONTRIBUTING.md)
- [Community Support](https://github.com/Jahvascript/.github/blob/main/SUPPORT.md)
- [Accessibility and Inclusion](https://github.com/Jahvascript/.github/blob/main/ACCESSIBILITY.md)

Community reporting: jahvascripts@gmail.com

*JahvaScript — Code with purpose. Build with unity.*
