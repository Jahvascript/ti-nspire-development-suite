# Software Verification

Last local verification: November 24, 2026.

## NspireDesk

- Rust unit tests: 6 passed, 0 failed.
- Offline Rust compilation: passed.
- Complete macOS application build: passed.
- USB protocol simulation and native tests: passed.
- Swift application self-test: passed.
- Code-signing verification: passed.
- Physical calculator communication: not yet verified.

## TNSStudio

- Complete macOS application build: passed.
- Luna and Lua compilation: passed.
- Document handling and application self-tests: passed.
- Code-signing verification: passed.

## PrecalculusStudio

- Lua 5.1 test suite: 2,666 assertions passed.
- TNS compilation: passed.
- Generated TNS matches existing artifact byte-for-byte.
- Physical TI-Nspire hardware compatibility: not yet verified.

## Release Limitations

- Fresh-clone reproducibility has not yet been tested.
- NspireDesk's Rust dependency bootstrap requires an
  initial online dependency download.
- Subsequent supported builds can operate offline.
- Third-party components retain their separate licenses.
- School assessment materials are not included.

These results establish local software verification,
not production certification or hardware compatibility.
