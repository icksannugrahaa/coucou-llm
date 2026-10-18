#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/coucou-anthropic-connection.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
swiftc -parse-as-library NotchBuddy/Sources/App/AnthropicConnection.swift \
    tests/AnthropicConnectionTests.swift -o "$TEST_DIR/anthropic-connection-tests"
"$TEST_DIR/anthropic-connection-tests"
