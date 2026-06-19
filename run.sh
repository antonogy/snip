#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/CodeDrop"

echo "Building..."
swift build

echo "Running..."
swift run CodeDrop
