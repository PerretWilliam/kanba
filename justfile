# Kanba tasks. `just` lists them.
default:
    @just --list

# Build Kanba.app (VERSION=1.2.3 just build to stamp a version)
build:
    ./build.sh

# Run all tests
test:
    swift test

# Tests + the 100% line-coverage gate on the logic layer (including the MCP server)
cover:
    tools/swift-coverage.sh

# Re-download the AI logos (Simple Icons) into Sources/Kanban/Model/Logos.swift
logos:
    tools/fetch-logos.sh

# Cut a release: `just release 1.2.0` bumps the VERSION file, checks, commits and pushes; only that change makes GitHub Actions build, tag vX.Y.Z and publish.
release version:
    #!/bin/sh
    set -e
    case "{{version}}" in [0-9]*.[0-9]*.[0-9]*) ;; *) echo "version must look like 1.2.3"; exit 1;; esac
    [ "$(git branch --show-current)" = main ] || { echo "release from main"; exit 1; }
    [ -z "$(git status --porcelain)" ] || { echo "working tree not clean"; exit 1; }
    git pull --ff-only
    just cover
    echo "{{version}}" > VERSION
    git commit -qam "Release {{version}}"
    git push origin main
    echo "VERSION is now {{version}}: the Release workflow tags v{{version}} and publishes Kanba.app."
