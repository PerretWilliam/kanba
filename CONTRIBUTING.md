# Contributing to Kanba

Thanks for helping out! Small, focused pull requests are easiest to review.

## Setup

```bash
git clone https://github.com/PerretWilliam/kanba.git && cd kanba
swift build          # compile
./build.sh           # build and sign Kanba.app
```

Tasks: `just` lists them (`just test`, `just cover`, `just build`).

Requires macOS 26+ and Swift 6 (the code builds in Swift 5 language mode).

## Guidelines

- Keep it simple: prefer SwiftUI/stdlib features over new dependencies. The MCP server's only dependency is the official `mcp` SDK.
- Match the existing style (compact, no needless abstractions).
- The on-disk format is documented in [CLAUDE.md](CLAUDE.md). Don't break existing `boards.json` files.
- AI-driven changes must keep going through `proposal.json` — never write `boards.json` from the MCP server (except `select_board`).
- Add tests. `just cover` must pass: 100% line coverage of the logic layer (`Sources/Kanban/Model`, `Support/BoardFile.swift`) and of `tools/kanba_mcp.py` (needs `pip install coverage "mcp>=2,<3"`). SwiftUI views are excluded: keep logic out of them so it can be tested.
- AI logos come from [Simple Icons](https://simpleicons.org) (CC0) via `just logos`; never hand-draw a brand logo.
- Test your change by running the app. For the MCP server, run `uv run --script tools/kanba_mcp.py` (or `npx @modelcontextprotocol/inspector uv run --script tools/kanba_mcp.py`) and check the proposal appears in the app. Set `KANBA_DATA=/some/empty/folder` (for both the app and the MCP server) to experiment without touching your real boards.

## Pull requests

1. Fork and create a branch from `main`.
2. Describe what changed and why; add a screenshot for UI changes.
3. Make sure `just cover` and `./build.sh` succeed (CI checks both).

## Releases

Maintainers: `just release 1.2.0` (from a clean `main`) runs the gates, tags `v1.2.0` and pushes it. The Release workflow rebuilds, tests, zips `Kanba.app` (ad-hoc signed, not notarized: right-click → Open the first time), and publishes a GitHub Release with generated notes, `kanba-mcp.py` and `SHA256SUMS`.

## Reporting bugs

Open an issue with your macOS version, what you did, what you expected and what happened. Screenshots help.
