#!/usr/bin/env python3
"""MCP server (stdio, stdlib only) for the Kanban app. Writes proposal.json; the app shows a diff the user validates."""
import json, os, sys, uuid, datetime as dt

PATH = os.path.join(os.path.expanduser(os.environ.get("KANBA_DATA", "~/Library/Application Support/Kanban")), "boards.json")
EPOCH = dt.datetime(2001, 1, 1, tzinfo=dt.timezone.utc)  # Swift Date reference
COLORS = "gray blue green orange purple pink teal red".split()
PRIO = {"low": 0, "medium": 1, "high": 2}
DEFAULT_COLS = [{"id": "todo", "name": "À faire", "color": "gray"}, {"id": "doing", "name": "En cours", "color": "blue"},
                {"id": "done", "name": "Terminé", "color": "green"}]

PROP = os.path.join(os.path.dirname(PATH), "proposal.json")  # pending changes, validated by the user in the app
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

def apply(c, a, b):
    if "title" in a: c["title"] = a["title"]
    if "notes" in a: c["notes"] = a["notes"]
    if "priority" in a: c["priority"] = PRIO[a["priority"]]
    if "tags" in a: c["tags"] = a["tags"]
    if "due" in a:
        v = to_secs(a["due"])
        if v is None: c.pop("due", None)
        else: c["due"] = v
    if "column" in a: c["status"] = col_of(b, a["column"])["id"]

def mkcard(b, a):
    c = {"id": str(uuid.uuid4()).upper(), "title": "", "notes": "", "priority": 1, "tags": [], "status": b["columns"][0]["id"]}
    apply(c, a, b); return c

def mkcols(names): return [{"id": str(uuid.uuid4()), "name": n, "color": COLORS[i % 8]} for i, n in enumerate(names)]

# ---- reading (also covers the app's search + filters) ----
def get_boards(a):
    d = load(); q = a.get("query", "").lower()
    def keep(c):
        return (not q or q in " ".join([c["title"], c.get("notes", "")] + c.get("tags", [])).lower()) \
            and ("priority" not in a or c.get("priority", 1) == PRIO[a["priority"]]) and ("tag" not in a or a["tag"] in c.get("tags", []))
    boards = [board_of(d, a["board"])] if "board" in a else d["boards"]
    return {"selected": board_of(d)["id"], "boards": [{
        "id": b["id"], "name": b["name"], "columns": [{"id": c["id"], "name": c["name"], "color": c["color"]} for c in b["columns"]],
        "done_column": b["columns"][-1]["name"],
        "cards": [{"id": c["id"], "title": c["title"], "column": next((x["name"] for x in b["columns"] if x["id"] == c["status"]), None),
                   "priority": ["low", "medium", "high"][c.get("priority", 1)], "tags": c.get("tags", []), "notes": c.get("notes", ""),
                   "due": to_iso(c["due"]) if "due" in c else None} for c in b["cards"] if keep(c)]} for b in boards]}

# ---- cards ----
def add_card(a):
    d = load(); b = board_of(d, a.get("board")); c = mkcard(b, a); b["cards"].append(c); save(d); return {"id": c["id"]}

def update_card(a):
    d = load(); b, c = find_card(d, a["card_id"]); apply(c, a, b); save(d); return "ok"

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
    b = {"id": str(uuid.uuid4()).upper(), "name": a["name"], "cards": [], "columns": mkcols(a["columns"]) if a.get("columns") else DEFAULT_COLS}
    b["cards"] = [mkcard(b, c) for c in a.get("cards", [])]
    d["boards"].append(b); d["selected"] = b["id"]; save(d); return {"id": b["id"]}

def update_board(a):
    d = load(); board_of(d, a["board"])["name"] = a["name"]; save(d); return "ok"

def select_board(a):  # UI state, not data: applied immediately
    b = board_of(load(), a["board"])
    for path in (PATH, PROP):
        if os.path.exists(path):
            x = json.load(open(path)); x["selected"] = b["id"]; write(path, x)
    return "ok"

def delete_board(a):
    d = load(); b = board_of(d, a["board"])
    d["boards"].remove(b)
    if d["selected"] == b["id"] and d["boards"]: d["selected"] = d["boards"][0]["id"]
    save(d); return "ok"

# ---- export (json = app's share format, csv, markdown) / import (json) ----
def _csv(b):
    import csv, io
    names = {c["id"]: c["name"] for c in b["columns"]}; buf = io.StringIO(); w = csv.writer(buf, lineterminator="\r\n")
    w.writerow(["Column", "Title", "Notes", "Priority", "Due", "Tags"])
    for col in b["columns"]:
        for c in b["cards"]:
            if c["status"] == col["id"]:
                w.writerow([names[col["id"]], c["title"], c.get("notes", ""), ["Low", "Medium", "High"][c.get("priority", 1)], to_iso(c["due"])[:10] if "due" in c else "", ", ".join(c.get("tags", []))])
    return "\ufeff" + buf.getvalue()

def _md(b):
    out = [f"# {b['name']}"]
    for col in b["columns"]:
        out += ["", f"## {col['name']}", ""]
        for c in b["cards"]:
            if c["status"] != col["id"]: continue
            meta = [f"Priority: {['Low', 'Medium', 'High'][c.get('priority', 1)]}"] + ([f"due {to_iso(c['due'])[:10]}"] if "due" in c else []) + ([" ".join("#" + t for t in c["tags"])] if c.get("tags") else [])
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

S = lambda **p: {"type": "object", "properties": p}
STR, ARR, BOOL = {"type": "string"}, {"type": "array", "items": {"type": "string"}}, {"type": "boolean"}
BOARD = {"type": "string", "description": "board name or id (default: the tab on screen)"}
COLOR = {"enum": COLORS}
CARD = dict(title=STR, notes=STR, priority={"enum": list(PRIO)}, due={"type": "string", "description": "ISO date, '' to clear"}, tags=ARR,
            column={"type": "string", "description": "column name or id"})
def T(fn, desc, req=(), **props): return (fn, desc, {**S(**props), "required": list(req)})
TOOLS = {
    "get_boards": T(get_boards, "List boards (tabs) with columns and cards. The last column of a board is its 'done' column. Optional search/filter like the app's.",
                    board=BOARD, query=STR, priority={"enum": list(PRIO)}, tag=STR),
    "add_card": T(add_card, "Add a card (default: first column of the tab on screen).", ["title"], board=BOARD, **CARD),
    "update_card": T(update_card, "Edit a card; 'column' moves it.", ["card_id"], card_id=STR, **CARD),
    "delete_card": T(delete_card, "Delete a card.", ["card_id"], card_id=STR),
    "clear_last_column": T(clear_last_column, "Delete every card of the board's last ('done') column — the app's trash button.", board=BOARD),
    "add_column": T(add_column, "Add a column at the end.", ["name"], board=BOARD, name=STR, color=COLOR),
    "update_column": T(update_column, "Rename and/or recolor a column.", ["column"], board=BOARD, column=STR, name=STR, color=COLOR),
    "delete_column": T(delete_column, "Delete a column; its cards move to the left neighbour. Not the last column.", ["column"], board=BOARD, column=STR),
    "add_board": T(add_board, "Create a board (tab) and switch to it. Optional columns (names) and starter cards (same fields as add_card) — use it to recreate any template.",
                   ["name"], name=STR, columns=ARR, cards={"type": "array", "items": S(**CARD)}),
    "update_board": T(update_board, "Rename a board.", ["board", "name"], board=BOARD, name=STR),
    "select_board": T(select_board, "Switch the app to this tab.", ["board"], board=BOARD),
    "delete_board": T(delete_board, "Close a board (tab) and delete its cards. Deleting the last one shows the app's welcome page.", ["board"], board=BOARD),
    "export_board": T(export_board, "Export a board to a file: json (app's share format, re-importable, default), csv (one row per card, opens in Excel) or markdown.", ["path"], board=BOARD, path=STR, format={"type": "string", "enum": ["json", "csv", "markdown"]}, overwrite=BOOL),
    "import_board": T(import_board, "Import a board from a JSON file exported by the app or export_board, as a new tab.", ["path"], path=STR),
}

def handle(m):
    meth, p = m.get("method"), m.get("params", {})
    global ACTOR, proposed
    if meth == "initialize":
        ACTOR = (p.get("clientInfo") or {}).get("name") or "claude"
        return {"protocolVersion": p.get("protocolVersion", "2024-11-05"), "capabilities": {"tools": {}}, "serverInfo": {"name": "kanban", "version": "2"}}
    if meth == "tools/list":
        return {"tools": [{"name": n, "description": t[1], "inputSchema": t[2]} for n, t in TOOLS.items()]}
    if meth == "tools/call":
        try:
            proposed = False
            out = TOOLS[p["name"]][0](p.get("arguments") or {})
            text = out if isinstance(out, str) else json.dumps(out, ensure_ascii=False)
            if proposed: text += "\n[Change proposed: the user must approve it in the Kanba app before it is applied.]"
            return {"content": [{"type": "text", "text": text}]}
        except Exception as e:
            return {"isError": True, "content": [{"type": "text", "text": f"{type(e).__name__}: {e}"}]}
    if meth == "ping": return {}
    raise KeyError(meth)

for line in sys.stdin:
    m = json.loads(line)
    if "id" not in m: continue  # notification
    try: r = {"result": handle(m)}
    except KeyError: r = {"error": {"code": -32601, "message": "method not found"}}
    print(json.dumps({"jsonrpc": "2.0", "id": m["id"], **r}), flush=True)
