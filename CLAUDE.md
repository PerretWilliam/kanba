# Kanba

macOS SwiftUI app (`./build.sh`). Data: `~/Library/Application Support/Kanban/boards.json`.
The app live-reloads this file (manual edits are fine). MCP tools do NOT write to it: they write `proposal.json` (base + proposed state), the app shows a diff and the user approves (all or change by change). Only `select_board` is immediate.
MCP server `kanban` (`tools/mcp.py`, stdlib only, user scope: `claude mcp add --scope user kanban -- python3 <path>/tools/mcp.py`): get_boards (search/filters), add_card, update_card, delete_card, clear_last_column, add_column, update_column, delete_column, add_board (initial columns + cards = templates), update_board, select_board, delete_board, export_board, import_board. Prefer it over editing the file by hand.

Format: `{"selected": "<board uuid>", "boards": [Board]}`
- Board: `{id: uuid, name, parent?: board uuid (set = a phase, i.e. a sub-board of that board; one level only), columns: [{id, name, color}], cards: [Card]}`; colors: gray blue green orange purple pink teal red; the last column means "done".
- Card: `{id: uuid (new uppercase uuid4), title, notes, priority: 0|1|2 (low/medium/high), due?: seconds since 2001-01-01 UTC, status: column id, tags: [string]}`.
- Invalid JSON = change ignored. `boards` may be empty (the app then shows its welcome page).
