#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.10"
# dependencies = ["mcp>=2,<3"]
# ///
"""MCP server (stdio, official Python SDK) for the Kanban app. Writes proposal.json; the app shows a diff the user validates."""
import json, os, uuid, datetime as dt
from typing import Annotated, Literal, NotRequired, TypedDict
from pydantic import Field
from mcp.server.mcpserver import MCPServer, Context
from mcp.server.mcpserver.exceptions import ToolError

DEFAULT_DIR = os.path.expanduser("~/Library/Application Support/Kanban")

def data_dir():  # KANBA_DATA, else the folder chosen in the app (folder.txt), else the default one
    try: chosen = open(os.path.join(DEFAULT_DIR, "folder.txt")).read().strip()
    except OSError: chosen = ""
    return os.environ.get("KANBA_DATA") or chosen or DEFAULT_DIR

PATH = os.path.join(data_dir(), "boards.json")
EPOCH = dt.datetime(2001, 1, 1, tzinfo=dt.timezone.utc)  # Swift Date reference
COLORS = "gray blue green orange purple pink teal red".split()
PRIO = {"low": 0, "medium": 1, "high": 2}
DEFAULT_COLS = [{"id": "todo", "name": "À faire", "color": "gray"}, {"id": "doing", "name": "En cours", "color": "blue"},
                {"id": "done", "name": "Terminé", "color": "green"}]

PROP = os.path.join(os.path.dirname(PATH), "proposal.json")  # pending changes, validated by the user in the app
FILTER = os.path.join(os.path.dirname(PATH), "filter.json")  # one-shot: the app applies it in memory, then deletes it
ACTOR, proposed = "claude", False

def write(path, obj):
    open(path + ".tmp", "w").write(json.dumps(obj)); os.replace(path + ".tmp", path)

def load():  # the state as the AI sees it: pending proposal if any, else the real boards
    if os.path.exists(PROP):
        p = json.load(open(PROP)); return {"selected": p["selected"], "boards": p["boards"], "_p": p}
    return json.load(open(PATH))

def save(d):  # never touches boards.json: the app shows a diff and the user accepts or refuses
    global proposed
    p = d.pop("_p", None) or {"base": json.load(open(PATH))["boards"]}
    p.update(actor=ACTOR, boards=d["boards"], selected=d["selected"])
    write(PROP, p); proposed = True

def same(ref, *vals): return any(ref.lower() == v.lower() for v in vals)

def board_of(d, ref=None):
    if ref is None:  # the tab on screen (falls back to the first board if the id is stale)
        if not d["boards"]: raise ValueError("there are no boards: create one with add_board")
        return next((b for b in d["boards"] if b["id"] == d["selected"]), d["boards"][0])
    for b in d["boards"]:
        if same(ref, b["id"], b["name"]): return b
    raise ValueError(f"board not found: {ref} (have: {[b['name'] for b in d['boards']]})")

def col_of(b, ref):
    for c in b["columns"]:
        if same(ref, c["id"], c["name"]): return c
    raise ValueError(f"column not found: {ref} (have: {[c['name'] for c in b['columns']]})")

def find_card(d, cid):
    for b in d["boards"]:
        for c in b["cards"]:
            if same(cid, c["id"]): return b, c
    raise ValueError(f"card not found: {cid}")

def to_secs(s):  # ISO date/datetime -> seconds since 2001, "" -> None
    if not s: return None
    t = dt.datetime.fromisoformat(s.replace("Z", "+00:00"))
    return (t if t.tzinfo else t.replace(tzinfo=dt.timezone.utc)).__sub__(EPOCH).total_seconds()

def to_iso(secs): return (EPOCH + dt.timedelta(seconds=secs)).strftime("%Y-%m-%dT%H:%M:%SZ")

def agent(x):  # "claude" or {"name": "claude", "model": "Opus 5.5", "effort": "high"} -> stored form
    x = {"name": x} if isinstance(x, str) else x
    if not x.get("name"): raise ValueError("an agent needs a name (e.g. claude, codex, gemini, me)")
    return {"name": x["name"], "model": x.get("model", ""), "effort": x.get("effort", "")}

def has_agent(c, q): return any(q.lower() in (g["name"] + " " + g.get("model", "")).lower() for g in c.get("agents", []))

def apply(c, a, b):
    if "agents" in a: c["agents"] = [agent(x) for x in a["agents"]]
    if "title" in a: c["title"] = a["title"]
    if "notes" in a: c["notes"] = a["notes"]
    if "priority" in a: c["priority"] = PRIO[a["priority"]]
    if "tags" in a: c["tags"] = a["tags"]
    if "due" in a:
        v = to_secs(a["due"])
        if v is None: c.pop("due", None)
        else: c["due"] = v
    if "column" in a: c["status"] = col_of(b, a["column"])["id"]

def place(b, c, pos):  # card order = array order: put c at 1-based position pos among its column's cards
    b["cards"] = [x for x in b["cards"] if x is not c]
    col = [x for x in b["cards"] if x["status"] == c["status"]]
    i = b["cards"].index(col[max(pos, 1) - 1]) if col and pos <= len(col) else (b["cards"].index(col[-1]) + 1 if col else len(b["cards"]))
    b["cards"].insert(i, c)

def mkcard(b, a):
    c = {"id": str(uuid.uuid4()).upper(), "title": "", "notes": "", "priority": 1, "tags": [], "status": b["columns"][0]["id"]}
    apply(c, a, b); return c

def mkcols(names): return [{"id": str(uuid.uuid4()), "name": n, "color": COLORS[i % 8]} for i, n in enumerate(names)]

# ---- reading (also covers the app's search + filters) ----
def get_boards(a):
    d = load(); q = a.get("query", "").lower()
    def keep(c):
        return (not q or q in " ".join([c["title"], c.get("notes", "")] + c.get("tags", [])).lower()) \
            and ("priority" not in a or c.get("priority", 1) == PRIO[a["priority"]]) and ("tag" not in a or a["tag"] in c.get("tags", [])) \
            and ("agent" not in a or has_agent(c, a["agent"]))
    boards = [board_of(d, a["board"])] if "board" in a else d["boards"]
    return {"selected": board_of(d)["id"], "boards": [{
        "id": b["id"], "name": b["name"], "parent": b.get("parent"), "closed": bool(b.get("closed")), "columns": [{"id": c["id"], "name": c["name"], "color": c["color"]} for c in b["columns"]],
        "done_column": b["columns"][-1]["name"],
        "cards": [{"position": 1 + sum(1 for y in b["cards"][:b["cards"].index(c)] if y["status"] == c["status"]),
                   "id": c["id"], "title": c["title"], "column": next((x["name"] for x in b["columns"] if x["id"] == c["status"]), None),
                   "priority": ["low", "medium", "high"][c.get("priority", 1)], "tags": c.get("tags", []), "agents": c.get("agents", []), "notes": c.get("notes", ""),
                   "due": to_iso(c["due"]) if "due" in c else None} for c in b["cards"] if keep(c)]} for b in boards]}

# ---- cards ----
def add_card(a):
    d = load(); b = board_of(d, a.get("board")); c = mkcard(b, a); b["cards"].append(c)
    if "position" in a: place(b, c, a["position"])
    save(d); return {"id": c["id"]}

def update_card(a):
    d = load(); b, c = find_card(d, a["card_id"])
    if "to_board" in a:  # move to another board: same-named column if any, else the first; 'column' overrides
        t = board_of(d, a["to_board"])
        if t is not b:
            old = next(x["name"] for x in b["columns"] if x["id"] == c["status"])
            b["cards"].remove(c); t["cards"].append(c); b = t
            c["status"] = next((x["id"] for x in t["columns"] if x["name"].lower() == old.lower()), t["columns"][0]["id"])
    apply(c, a, b)
    if "position" in a: place(b, c, a["position"])
    save(d); return "ok"

def reorder_cards(a):  # card_ids first, in that order, at the top of the column; unlisted cards keep their order after them
    d = load(); b = board_of(d, a.get("board")); col = col_of(b, a["column"])["id"]
    ids = [find_card(d, i)[1] for i in a["card_ids"]]
    if any(c["status"] != col for c in ids) or len({c["id"] for c in ids}) != len(ids): raise ValueError("card_ids must be distinct cards of that column")
    slots = [i for i, c in enumerate(b["cards"]) if c["status"] == col]
    seq = ids + [b["cards"][i] for i in slots if b["cards"][i] not in ids]
    for i, c in zip(slots, seq): b["cards"][i] = c
    save(d); return "ok"

def delete_card(a):
    d = load(); b, c = find_card(d, a["card_id"]); b["cards"].remove(c); save(d); return "ok"

def clear_last_column(a):  # the app's trash button
    d = load(); b = board_of(d, a.get("board")); last = b["columns"][-1]["id"]; n = len(b["cards"])
    b["cards"] = [c for c in b["cards"] if c["status"] != last]; save(d); return f"{n - len(b['cards'])} cards deleted"

# ---- columns ----
def add_column(a):
    d = load(); b = board_of(d, a.get("board")); c = {"id": str(uuid.uuid4()), "name": a["name"], "color": a.get("color", "gray")}
    b["columns"].append(c); save(d); return {"id": c["id"]}

def update_column(a):
    d = load(); c = col_of(board_of(d, a.get("board")), a["column"])
    c["name"] = a.get("name", c["name"]); c["color"] = a.get("color", c["color"]); save(d); return "ok"

def delete_column(a):  # same rule as the app: its cards go to the left neighbour (or the new first column)
    d = load(); b = board_of(d, a.get("board")); c = col_of(b, a["column"])
    if len(b["columns"]) == 1: raise ValueError("cannot delete the last column")
    i = b["columns"].index(c); target = b["columns"][1 if i == 0 else i - 1]["id"]
    for k in b["cards"]:
        if k["status"] == c["id"]: k["status"] = target
    b["columns"].remove(c); save(d); return "ok"

# ---- boards (tabs) ----
def add_board(a):
    d = load()
    parent = board_of(d, a["parent"]) if a.get("parent") else None   # phase = sub-board of a top-level board
    if parent and parent.get("parent"): raise ValueError("phases cannot have phases: pass the top-level board")
    b = {"id": str(uuid.uuid4()).upper(), "name": a["name"], "cards": [], "columns": mkcols(a["columns"]) if a.get("columns") else (list(parent["columns"]) if parent else DEFAULT_COLS)}
    if parent: b["parent"] = parent["id"]
    b["cards"] = [mkcard(b, c) for c in a.get("cards", [])]
    d["boards"].append(b); d["selected"] = b["id"]; save(d); return {"id": b["id"]}

def update_board(a):  # closed=true hides the tab (still listed by get_boards and in the app's Projets menu); false reopens it
    d = load(); b = board_of(d, a["board"])
    if "name" in a: b["name"] = a["name"]
    if "closed" in a:
        if a["closed"]: b["closed"] = True
        else: b.pop("closed", None)
    save(d); return "ok"

def select_board(a):  # UI state, not data: applied immediately
    b = board_of(load(), a["board"])
    for path in (PATH, PROP):
        if os.path.exists(path):
            x = json.load(open(path)); x["selected"] = b["id"]
            for y in x["boards"]:
                if y["id"] == b["id"]: y.pop("closed", None)   # selecting a closed board reopens it
            write(path, x)
    return "ok"

def set_filter(a):  # screen state, not data: handed to the app through a one-shot file it deletes; no argument clears it
    f = {k: a[k] for k in ("tag", "agent", "query") if a.get(k)}
    if "priority" in a: f["priority"] = PRIO[a["priority"]]
    write(FILTER, f); return {"filter": f}

def delete_board(a):
    d = load(); b = board_of(d, a["board"])
    d["boards"] = [x for x in d["boards"] if x is not b and x.get("parent") != b["id"]]   # a board takes its phases with it
    if d["selected"] not in {x["id"] for x in d["boards"]} and d["boards"]: d["selected"] = d["boards"][0]["id"]
    save(d); return "ok"

# ---- export (json = app's share format, csv, markdown) / import (json) ----
def _ag(g): return " · ".join(x for x in (g["name"], g.get("model", ""), g.get("effort", "")) if x)

def _csv(b):
    import csv, io
    names = {c["id"]: c["name"] for c in b["columns"]}; buf = io.StringIO(); w = csv.writer(buf, lineterminator="\r\n")
    w.writerow(["Column", "Title", "Notes", "Priority", "Due", "Tags", "Agents"])
    for col in b["columns"]:
        for c in b["cards"]:
            if c["status"] == col["id"]:
                w.writerow([names[col["id"]], c["title"], c.get("notes", ""), ["Low", "Medium", "High"][c.get("priority", 1)], to_iso(c["due"])[:10] if "due" in c else "", ", ".join(c.get("tags", [])), "; ".join(_ag(g) for g in c.get("agents", []))])
    return "\ufeff" + buf.getvalue()

def _md(b):
    out = [f"# {b['name']}"]
    for col in b["columns"]:
        out += ["", f"## {col['name']}", ""]
        for c in b["cards"]:
            if c["status"] != col["id"]: continue
            meta = [f"Priority: {['Low', 'Medium', 'High'][c.get('priority', 1)]}"] + ([f"due {to_iso(c['due'])[:10]}"] if "due" in c else []) + ([" ".join("#" + t for t in c["tags"])] if c.get("tags") else []) + (["agents: " + ", ".join(_ag(g) for g in c["agents"])] if c.get("agents") else [])
            out.append(f"- [{'x' if col is b['columns'][-1] else ' '}] **{c['title']}** — {' · '.join(meta)}")
            out += [f"  {l}" for l in c.get("notes", "").splitlines() if l.strip()]
    return "\n".join(out) + "\n"

def export_board(a):
    d = load(); b = board_of(d, a.get("board")); p = os.path.expanduser(a["path"]); fmt = a.get("format", "json")
    if os.path.exists(p) and not a.get("overwrite"): raise ValueError(f"{p} exists (pass overwrite=true)")
    if fmt == "csv": open(p, "w", encoding="utf-8", newline="").write(_csv(b))
    elif fmt == "markdown": open(p, "w", encoding="utf-8").write(_md(b))
    elif fmt == "json":
        cards = [{**c, **({"due": to_iso(c["due"])} if "due" in c else {})} for c in b["cards"]]
        json.dump({"format": "kanban", "version": 1, "name": b["name"], "columns": b["columns"], "cards": cards}, open(p, "w"), indent=2, sort_keys=True, ensure_ascii=False)
    else: raise ValueError("format must be json, csv or markdown")
    return p

def import_board(a):
    f = json.load(open(os.path.expanduser(a["path"])))
    if f.get("format") != "kanban" or not f.get("columns"): raise ValueError("not a Kanban board file")
    d = load(); ids = {c["id"] for c in f["columns"]}
    cards = [{**c, "id": str(uuid.uuid4()).upper(), "status": c["status"] if c.get("status") in ids else f["columns"][0]["id"],
              **({"due": to_secs(c["due"])} if c.get("due") else {})} for c in f.get("cards", [])]
    b = {"id": str(uuid.uuid4()).upper(), "name": f["name"], "columns": f["columns"], "cards": cards}
    d["boards"].append(b); d["selected"] = b["id"]; save(d); return {"id": b["id"]}

# ---- MCP layer: typed signatures give the tools' JSON schemas; the logic above takes plain dicts ----
server = MCPServer("kanban", version="4")

Color = Literal["gray", "blue", "green", "orange", "purple", "pink", "teal", "red"]
Priority = Literal["low", "medium", "high"]
Board = Annotated[str | None, Field(description="board name or id (default: the tab on screen)")]
Column = Annotated[str | None, Field(description="column name or id")]
Position = Annotated[int | None, Field(description="1-based rank within its column; 1 = do first. Default: last.")]
Due = Annotated[str | None, Field(description="ISO date, '' to clear")]

class AgentSpec(TypedDict):
    name: str
    model: NotRequired[str]
    effort: NotRequired[str]

Agents = Annotated[list[str | AgentSpec] | None, Field(description=(
    "Who is assigned: any number of agents, each {name, model?, effort?}. name = an AI (claude, codex, chatgpt, gemini, copilot, cursor, windsurf, mistral, deepseek, grok, "
    "perplexity, llama, qwen, kimi, zed, cline, aider, opencode, goose, or any other name) or 'me' for the user. model = free text (e.g. 'Opus 5.5', 'GPT-6.2 Sol', 'Gemini 4 Carbon'). "
    "effort = minimal | low | medium | high | xhigh | max (Claude and OpenAI: low..max; Gemini: minimal..xhigh; free text accepted). Replaces the whole list; [] clears it. A plain string means just the name."))]

class CardSpec(TypedDict):  # starter card of add_board: same fields as add_card
    title: str
    notes: NotRequired[str]
    priority: NotRequired[Priority]
    due: NotRequired[str]
    tags: NotRequired[list[str]]
    agents: NotRequired[list[str | AgentSpec]]
    column: NotRequired[str]
    position: NotRequired[int]

def run(fn, ctx, args):  # the client's name is who the app shows as the author of the proposal
    global ACTOR, proposed
    info = getattr(ctx.session.client_params, "client_info", None)
    ACTOR = (info and info.name) or "claude"; proposed = False
    try: out = fn({k: v for k, v in args.items() if k != "ctx" and v is not None})
    except Exception as e: raise ToolError(f"{type(e).__name__}: {e}") from e   # the SDK hides other exceptions: the client needs the reason to correct itself
    text = out if isinstance(out, str) else json.dumps(out, ensure_ascii=False)
    return text + "\n[Change proposed: the user must approve it in the Kanba app before it is applied.]" if proposed else text

@server.tool(name="get_boards")
def _get_boards(ctx: Context, board: Board = None, query: str | None = None, priority: Priority | None = None, tag: str | None = None,
                agent: Annotated[str | None, Field(description="only cards assigned to this agent (name or model, e.g. 'claude', 'me', 'opus')")] = None) -> str:
    """List boards (tabs, including closed ones: 'closed': true) with columns and cards (notes are Markdown; agents = assignees). The last column of a board is its 'done' column. Optional search/filter like the app's. Card order = priority order."""
    return run(get_boards, ctx, locals())

@server.tool(name="add_card")
def _add_card(ctx: Context, title: str, board: Board = None, position: Position = None, notes: str | None = None, priority: Priority | None = None,
              due: Due = None, tags: list[str] | None = None, agents: Agents = None, column: Column = None) -> str:
    """Add a card (default: first column of the tab on screen). notes accept Markdown (headings, lists, - [ ] tasks, **bold**, `code`, code blocks, links), rendered in the app's card panel."""
    return run(add_card, ctx, locals())

@server.tool(name="reorder_cards")
def _reorder_cards(ctx: Context, column: str, card_ids: list[str], board: Board = None) -> str:
    """Set the priority order of cards in a column: card_ids go first, in that order (position 1 = do first); other cards follow. Cards are listed by get_boards in this order."""
    return run(reorder_cards, ctx, locals())

@server.tool(name="update_card")
def _update_card(ctx: Context, card_id: str, to_board: Board = None, position: Position = None, title: str | None = None, notes: str | None = None,
                 priority: Priority | None = None, due: Due = None, tags: list[str] | None = None, agents: Agents = None, column: Column = None) -> str:
    """Edit a card; 'column' moves it within its board, 'to_board' moves it to another board (or phase)."""
    return run(update_card, ctx, locals())

@server.tool(name="delete_card")
def _delete_card(ctx: Context, card_id: str) -> str:
    """Delete a card."""
    return run(delete_card, ctx, locals())

@server.tool(name="clear_last_column")
def _clear_last_column(ctx: Context, board: Board = None) -> str:
    """Delete every card of the board's last ('done') column — the app's trash button."""
    return run(clear_last_column, ctx, locals())

@server.tool(name="add_column")
def _add_column(ctx: Context, name: str, board: Board = None, color: Color | None = None) -> str:
    """Add a column at the end."""
    return run(add_column, ctx, locals())

@server.tool(name="update_column")
def _update_column(ctx: Context, column: str, board: Board = None, name: str | None = None, color: Color | None = None) -> str:
    """Rename and/or recolor a column."""
    return run(update_column, ctx, locals())

@server.tool(name="delete_column")
def _delete_column(ctx: Context, column: str, board: Board = None) -> str:
    """Delete a column; its cards move to the left neighbour. Not the last column."""
    return run(delete_column, ctx, locals())

@server.tool(name="add_board")
def _add_board(ctx: Context, name: str, parent: Board = None, columns: list[str] | None = None, cards: list[CardSpec] | None = None) -> str:
    """Create a board (tab) and switch to it. With parent (a top-level board's id or name) it becomes a phase (sub-board) of that board, with the parent's columns by default. Optional columns (names) and starter cards (same fields as add_card) — use it to recreate any template."""
    return run(add_board, ctx, locals())

@server.tool(name="update_board")
def _update_board(ctx: Context, board: str, name: str | None = None, closed: bool | None = None) -> str:
    """Rename a board and/or close it (closed=true: hides the tab, nothing is deleted, it stays in the app's Projets menu) or reopen it (closed=false)."""
    return run(update_board, ctx, locals())

@server.tool(name="select_board")
def _select_board(ctx: Context, board: str) -> str:
    """Switch the app to this tab (reopens it if it was closed)."""
    return run(select_board, ctx, locals())

@server.tool(name="set_filter")
def _set_filter(ctx: Context, priority: Priority | None = None, tag: str | None = None, agent: str | None = None, query: str | None = None) -> str:
    """Filter what the app shows on the current tab, like the user's search field and filter button: any of priority, tag, agent (e.g. 'claude', 'me', or part of a model name) and query (text in title, notes, tags, agents). Replaces the current filter; call it with no argument to clear it. Applied immediately and only on screen (nothing is saved): it is dropped when the tab changes or the app restarts. get_boards (with the same fields) only reads, it does not change the screen."""
    return run(set_filter, ctx, locals())

@server.tool(name="delete_board")
def _delete_board(ctx: Context, board: str) -> str:
    """Close a board (tab) or phase and delete its cards (a board's phases go with it). Deleting the last one shows the app's welcome page."""
    return run(delete_board, ctx, locals())

@server.tool(name="export_board")
def _export_board(ctx: Context, path: str, board: Board = None, format: Literal["json", "csv", "markdown"] | None = None, overwrite: bool | None = None) -> str:
    """Export a board to a file: json (app's share format, re-importable, default), csv (one row per card, opens in Excel) or markdown."""
    return run(export_board, ctx, locals())

@server.tool(name="import_board")
def _import_board(ctx: Context, path: str) -> str:
    """Import a board from a JSON file exported by the app or export_board, as a new tab."""
    return run(import_board, ctx, locals())

if __name__ == "__main__": server.run()  # pragma: no cover
