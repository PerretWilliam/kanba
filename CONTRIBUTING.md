# Contributing to Kanba

Thanks for helping out! Small, focused pull requests are easiest to review.

## Setup

```bash
git clone https://github.com/PerretWilliam/kanba.git && cd kanba
cd apps/macos && swift build       # compile
just macos build   # build and sign Kanba.app
```

Tasks: `just` lists them (`just macos test`, `just macos cover`, `just macos build`).

Requires macOS 26+ and Swift 6 (the code builds in Swift 5 language mode).

## Guidelines

- Keep it simple: prefer SwiftUI/stdlib features over new dependencies.
- Match the existing style (compact, no needless abstractions).
- The on-disk format is documented in [CLAUDE.md](CLAUDE.md). Don't break existing `boards.json` files.
- AI-driven changes must keep going through a proposal (`Store.propose`) — MCP tools never write the boards directly (only `select_board` and `set_filter`, which are screen state).
- Add tests. `just macos cover` must pass: 100% line coverage of the logic layer (`apps/macos/Sources/Kanban/Model`, `Support/BoardFile.swift`). SwiftUI views are excluded: keep logic out of them so it can be tested.
- AI logos come from [Simple Icons](https://simpleicons.org) (CC0) via `just logos`; never hand-draw a brand logo.
- Test your change by running the app. For the MCP server, run the app and point `npx @modelcontextprotocol/inspector` (or `curl -X POST -H 'Content-Type: application/json' http://localhost:47821/mcp -d '{...}'`) at `http://localhost:47821/mcp`; the proposal appears in the app. Set `KANBA_DATA=/some/empty/folder` (and `KANBA_PORT=47822` for a second instance) to experiment without touching your real boards.

## Pull requests

1. Fork and create a branch from `main`.
2. Describe what changed and why; add a screenshot for UI changes.
3. Make sure `just macos cover` and `just macos build` succeed (CI checks both).

## Releases

The app version is the `VERSION` file. A release only happens when it changes on `main`: `just release 1.2.0` (from a clean `main`) runs the gates, writes `VERSION`, commits and pushes. The Release workflow then tests, builds, zips `Kanba.app` (ad-hoc signed, not notarized: right-click → Open the first time), tags `v1.2.0` and publishes a GitHub Release with the changelog and `SHA256SUMS`. Any other push to `main` builds nothing and tags nothing.

## Reporting bugs

Open an issue with your macOS version, what you did, what you expected and what happened. Screenshots help.
