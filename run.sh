#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/Snip"

echo "Building..."
swift build

echo "Running..."
swift run Snip
