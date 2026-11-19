# Contributing to Kanba

Thanks for helping out! Small, focused pull requests are easiest to review.

## Setup

```bash
git clone https://github.com/PerretWilliam/kanba.git && cd kanba
swift build          # compile
./build.sh           # build and sign Kanba.app
```

Requires macOS 26+ and Swift 6 (the code builds in Swift 5 language mode).

## Guidelines

- Keep it simple: prefer SwiftUI/stdlib features over new dependencies. The MCP server must stay stdlib-only Python 3.
- Match the existing style (compact, no needless abstractions).
- The on-disk format is documented in [CLAUDE.md](CLAUDE.md). Don't break existing `boards.json` files.
- AI-driven changes must keep going through `proposal.json` — never write `boards.json` from the MCP server (except `select_board`).
- Test your change by running the app. For the MCP server, pipe JSON-RPC lines into `python3 tools/mcp.py` and check the proposal appears in the app. Use a copy of your data (`~/Library/Application Support/Kanban/`) when experimenting.

## Pull requests

1. Fork and create a branch from `master`.
2. Describe what changed and why; add a screenshot for UI changes.
3. Make sure `./build.sh` succeeds.

## Reporting bugs

Open an issue with your macOS version, what you did, what you expected and what happened. Screenshots help.
