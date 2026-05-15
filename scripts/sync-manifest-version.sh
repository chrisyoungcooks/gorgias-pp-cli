#!/usr/bin/env bash
# sync-manifest-version.sh — rewrite manifest.json's "version" field so the
# MCPB bundle advertises the same version as the binary inside it. Called
# from .goreleaser.yaml's before.hooks BEFORE any archive is built; the
# updated manifest.json is then packaged with the goreleaser-built binaries.
#
# Usage: sync-manifest-version.sh <version>
#
# The version arg comes from goreleaser as {{ .Version }} — the git tag (or
# snapshot ID). On portability: written in POSIX sh with sed, works on
# Linux/macOS goreleaser runners without depending on jq.
set -euo pipefail

if [ "$#" -lt 1 ]; then
  echo "usage: $0 <version>" >&2
  exit 2
fi

VERSION="$1"
TARGET="${MANIFEST_PATH:-manifest.json}"

if [ ! -f "$TARGET" ]; then
  echo "manifest not found at $TARGET (cwd=$(pwd))" >&2
  exit 1
fi

# Rewrite the first "version": "..." field in the manifest. Only the first
# match is replaced to avoid clobbering any later "version" keys nested in
# user_config (there aren't any today, but be defensive).
tmp="$(mktemp)"
awk -v ver="$VERSION" '
  BEGIN { done = 0 }
  done == 0 && /"version":[[:space:]]*"[^"]*"/ {
    sub(/"version":[[:space:]]*"[^"]*"/, "\"version\": \"" ver "\"")
    done = 1
  }
  { print }
' "$TARGET" > "$tmp"
mv "$tmp" "$TARGET"

echo "manifest version → $VERSION"
