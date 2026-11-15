#!/usr/bin/env bash
set -euo pipefail
TASK_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export FLUTTER_SUPPRESS_ANALYTICS=true
export PUB_CACHE="${PUB_CACHE:-/workspace/.pub-cache}"
export XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-/workspace/.config}"
export ANALYZER_STATE_LOCATION_OVERRIDE="${ANALYZER_STATE_LOCATION_OVERRIDE:-/workspace/.dartServer}"
export GRADLE_USER_HOME="${GRADLE_USER_HOME:-/workspace/.gradle}"
export ANDROID_USER_HOME="${ANDROID_USER_HOME:-/workspace/.android}"
export ANDROID_SDK_ROOT="${ANDROID_SDK_ROOT:-/workspace/toolchains/android-sdk}"
export JAVA_HOME="${JAVA_HOME:-/workspace/toolchains/jdk21}"
FLUTTER_BIN="${FLUTTER_BIN:-/workspace/toolchains/flutter/bin/flutter}"
cd "$TASK_ROOT"
exec "$FLUTTER_BIN" "$@"
