# Kanba tasks. `just` lists them.
default:
    @just --list

# Build Kanba.app (VERSION=1.2.3 just build to stamp a version)
build:
    ./build.sh

# Run all tests (Swift + MCP server)
test:
    swift test
    python3 -m unittest discover -s Tests

# Tests + the 100% line-coverage gate on the logic layer (Swift) and the MCP server (Python)
cover:
    tools/swift-coverage.sh
    tools/py-coverage.sh

# Re-download the AI logos (Simple Icons) into Sources/Kanban/Model/Logos.swift
logos:
    tools/fetch-logos.sh

# Cut a release: `just release 1.2.0` checks, tags vX.Y.Z and pushes the tag; GitHub Actions builds and publishes it.
release version:
    #!/bin/sh
    set -e
    case "{{version}}" in [0-9]*.[0-9]*.[0-9]*) ;; *) echo "version must look like 1.2.3"; exit 1;; esac
    [ "$(git branch --show-current)" = master ] || { echo "release from master"; exit 1; }
    [ -z "$(git status --porcelain)" ] || { echo "working tree not clean"; exit 1; }
    git pull --ff-only
    just cover
    git tag -a "v{{version}}" -m "Kanba {{version}}"
    git push origin "v{{version}}"
    echo "Tag v{{version}} pushed: the Release workflow publishes Kanba.app on GitHub."
