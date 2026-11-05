#!/usr/bin/env bash
# Build release wheels locally with the same cibuildwheel configuration
# CI uses (`[tool.cibuildwheel]` in pyproject.toml).
#
#   scripts/build-wheels.sh --platform macos     # native macOS wheel
#   scripts/build-wheels.sh --platform linux     # manylinux + musllinux via docker
#   scripts/build-wheels.sh --only cp310-manylinux_aarch64   # one wheel; implies the platform
#
# Output lands in ./wheelhouse. Any extra arguments go to cibuildwheel.
#
# Prerequisites, beyond uv and a rust toolchain:
#   - linux: a running docker (or podman) daemon.
#   - macos: the python.org CPython 3.10 installer, from
#     https://www.python.org/downloads/macos/. cibuildwheel builds with
#     the framework interpreter so the wheel's platform tag is right,
#     and outside CI it refuses to install one itself.
#   - windows: run `uvx cibuildwheel --platform windows` from a clean
#     clone instead; this script assumes a POSIX shell and rsync.
#
# The project is first copied to a scratch directory without build
# artifacts. cibuildwheel copies the whole project tree into the Linux
# containers, and a developer checkout carries gigabytes of `target/`
# and `.venv/`; worse, a container build writing to `target/release/`
# would leave a Linux ELF where the host test-suite looks for the
# native binary.
set -euo pipefail

# Keep in sync with the `pypa/cibuildwheel` pin in
# .github/workflows/wheels.yml.
CIBW_VERSION="${CIBW_VERSION:-4.3.5}"

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
out="${root}/wheelhouse"
stage="$(mktemp -d "${TMPDIR:-/tmp}/west-cibw.XXXXXX")"
trap 'rm -rf "$stage"' EXIT

rsync -a \
    --exclude '/target/' \
    --exclude '/.venv/' \
    --exclude '/.wheel-data/' \
    --exclude '/dist/' \
    --exclude '/wheelhouse/' \
    --exclude '__pycache__/' \
    "${root}/" "${stage}/"

# Host builds (macOS / Windows) run cargo directly, so give them a
# persistent target dir and the second run is incremental. Container
# builds don't see host environment variables and start cold.
export CARGO_TARGET_DIR="${CARGO_TARGET_DIR:-${root}/target/cibw}"

cd "$stage"
uvx --from "cibuildwheel==${CIBW_VERSION}" cibuildwheel --output-dir "$out" "$@"
