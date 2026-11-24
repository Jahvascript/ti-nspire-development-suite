#!/bin/bash
set -euo pipefail

backend="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source_dir="$(cd "$backend/.." && pwd)"
project="$(cd "$source_dir/.." && pwd)"
vendor="$source_dir/vendor"
config="$backend/.cargo/config.toml"

command -v cargo >/dev/null || {
  echo "ERROR: Install the Rust/Cargo toolchain first."
  exit 1
}

mkdir -p "$backend/.cargo" "$project/build/cargo-home"

export CARGO_HOME="$project/build/cargo-home"
export CARGO_TARGET_DIR="$project/build/rust-target"

if [ -d "$vendor" ] && [ -f "$config" ]; then
  echo "Using existing offline vendor configuration."

elif [ -f "$config" ]; then
  echo "ERROR: Existing Cargo config has no vendor directory."
  exit 1

elif [ -d "$vendor" ]; then
  cat > "$config" <<'EOF'
[source.crates-io]
replace-with = "vendored-sources"
[source.vendored-sources]
directory = "../vendor"
EOF
  echo "Configured existing offline vendor cache."

else
  echo "Downloading locked Rust dependencies (internet required)."
  cd "$backend"

  tmp="$(mktemp "$backend/.cargo/vendor-config.XXXXXX")"
  trap 'rm -f "$tmp"' EXIT

  if ! cargo vendor --locked --versioned-dirs ../vendor > "$tmp"; then
    echo "ERROR: Dependency download failed."
    exit 1
  fi

  mv "$tmp" "$config"
  trap - EXIT
  echo "Local offline vendor cache prepared."
fi

echo "Running offline Rust tests..."
cd "$backend"
cargo test --locked --offline
echo "SUCCESS: Offline Rust dependencies verified."
