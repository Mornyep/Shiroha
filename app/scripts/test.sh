#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
# Use local temporary storage: FileProvider metadata in Documents can prevent xctest signing.
TEST_CACHE=${VN_TEST_CACHE:-$(mktemp -d /private/tmp/VNLauncher-tests.XXXXXX)}
swift test --scratch-path "$TEST_CACHE"
