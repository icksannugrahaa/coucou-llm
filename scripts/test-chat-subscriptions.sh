#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/coucou-chat-subscriptions.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
swiftc -swift-version 6 -strict-concurrency=complete -parse-as-library \
    NotchBuddy/Sources/App/ChatSubscription.swift tests/ChatSubscriptionTests.swift \
    -o "$TEST_DIR/chat-subscription-tests"
"$TEST_DIR/chat-subscription-tests"
