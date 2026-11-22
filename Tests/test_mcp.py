import importlib.util, io, json, os, sys, tempfile, unittest

HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("kanba_mcp", os.path.join(HERE, "..", "tools", "mcp.py"))
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)

COLS = [{"id": "todo", "name": "À faire", "color": "gray"}, {"id": "doing", "name": "En cours", "color": "blue"}, {"id": "done", "name": "Terminé", "color": "green"}]
B1, B2 = "11111111-1111-1111-1111-111111111111", "22222222-2222-2222-2222-222222222222"

def card(i, title, status="todo", **kw): return {"id": f"C{i}", "title": title, "notes": "", "priority": 1, "tags": [], "status": status, **kw}

class Base(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(); self.dir = self.tmp.name
        m.PATH = os.path.join(self.dir, "boards.json"); m.PROP = os.path.join(self.dir, "proposal.json")
        m.ACTOR, m.proposed = "claude", False
        self.boards = [{"id": B1, "name": "Main", "columns": [dict(c) for c in COLS], "cards": [
            card(1, "one"), card(2, "two"), card(3, "three", "doing", priority=2, tags=["x"], notes="Hello", due=86400.0,
                                                  agents=[{"name": "claude", "model": "Opus 5.5", "effort": "high"}]), card(4, "four", "done")]},
            {"id": B2, "name": "Other", "columns": [{"id": "a", "name": "En cours", "color": "red"}, {"id": "b", "name": "Z", "color": "pink"}], "cards": []}]
        self.write({"selected": B1, "boards": self.boards})
    def tearDown(self): self.tmp.cleanup()
    def write(self, d): json.dump(d, open(m.PATH, "w"))
    def real(self): return json.load(open(m.PATH))
    def prop(self): return json.load(open(m.PROP))
    def b(self, i=0): return self.prop()["boards"][i]
    def cards(self, i=0): return [c["title"] for c in self.b(i)["cards"]]

class Helpers(Base):
    def test_same_and_lookups(self):
        d = m.load()
        self.assertTrue(m.same("MAIN", "x", "main"))
        self.assertEqual(m.board_of(d)["id"], B1)
        self.assertEqual(m.board_of(d, "other")["id"], B2)
        self.assertEqual(m.board_of({"selected": "stale", "boards": d["boards"]})["id"], B1)
        with self.assertRaises(ValueError): m.board_of({"selected": "", "boards": []})
        with self.assertRaises(ValueError): m.board_of(d, "nope")
        self.assertEqual(m.col_of(d["boards"][0], "EN COURS")["id"], "doing")
        with self.assertRaises(ValueError): m.col_of(d["boards"][0], "nope")
        self.assertEqual(m.find_card(d, "c2")[1]["title"], "two")
        with self.assertRaises(ValueError): m.find_card(d, "nope")

    def test_dates(self):
        self.assertIsNone(m.to_secs(""))
        self.assertEqual(m.to_secs("2001-01-02"), 86400)
        self.assertEqual(m.to_secs("2001-01-02T00:00:00Z"), 86400)
        self.assertEqual(m.to_secs("2001-01-02T01:00:00+01:00"), 86400)
        self.assertEqual(m.to_iso(86400), "2001-01-02T00:00:00Z")

    def test_agents(self):
        self.assertEqual(m.agent("me"), {"name": "me", "model": "", "effort": ""})
        self.assertEqual(m.agent({"name": "codex", "model": "GPT-5", "effort": "max"}), {"name": "codex", "model": "GPT-5", "effort": "max"})
        with self.assertRaises(ValueError): m.agent({"model": "x"})
        c = {"agents": [{"name": "Claude", "model": "Opus 5.5"}]}
        self.assertTrue(m.has_agent(c, "opus")); self.assertTrue(m.has_agent(c, "CLAUDE")); self.assertFalse(m.has_agent(c, "gemini"))
        self.assertFalse(m.has_agent({}, "me"))

    def test_load_and_save_use_the_proposal(self):
        d = m.load(); self.assertNotIn("_p", d)
        d["boards"][0]["name"] = "Changed"; m.save(d)
        self.assertEqual(self.real()["boards"][0]["name"], "Main")   # boards.json is never touched
        p = self.prop(); self.assertEqual((p["actor"], p["boards"][0]["name"], p["base"][0]["name"]), ("claude", "Changed", "Main"))
        d = m.load(); self.assertIn("_p", d); d["boards"][0]["name"] = "Again"; m.save(d)
        self.assertEqual(self.prop()["base"][0]["name"], "Main"); self.assertEqual(self.b()["name"], "Again")   # base stays the original

class Cards(Base):
    def test_get_boards_and_filters(self):
        out = m.get_boards({})
        self.assertEqual((out["selected"], len(out["boards"])), (B1, 2))
        main = out["boards"][0]; self.assertEqual((main["done_column"], main["closed"], main["parent"]), ("Terminé", False, None))
        c3 = next(c for c in main["cards"] if c["id"] == "C3")
        self.assertEqual((c3["position"], c3["column"], c3["priority"], c3["due"], c3["agents"][0]["model"]), (1, "En cours", "high", "2001-01-02T00:00:00Z", "Opus 5.5"))
        self.assertEqual(m.get_boards({"board": "Other"})["boards"][0]["cards"], [])
        ids = lambda **a: [c["id"] for c in m.get_boards({"board": "Main", **a})["boards"][0]["cards"]]
        self.assertEqual(ids(query="hello"), ["C3"]); self.assertEqual(ids(priority="high"), ["C3"]); self.assertEqual(ids(tag="x"), ["C3"])
        self.assertEqual(ids(agent="opus"), ["C3"]); self.assertEqual(ids(agent="gemini"), [])
        self.assertEqual(len(ids()), 4)
        self.assertEqual(next(c for c in m.get_boards({"board": "Main"})["boards"][0]["cards"] if c["id"] == "C2")["position"], 2)
        self.boards[0]["cards"].append(card(9, "orphan", "gone")); self.write({"selected": B1, "boards": self.boards})
        self.assertIsNone(next(c for c in m.get_boards({})["boards"][0]["cards"] if c["id"] == "C9")["column"])

    def test_add_card(self):
        r = m.add_card({"title": "new", "notes": "# md", "priority": "high", "tags": ["t"], "due": "2001-01-02", "column": "doing",
                        "agents": ["me", {"name": "claude", "model": "Opus 5.5", "effort": "high"}], "position": 1})
        c = next(c for c in self.b()["cards"] if c["id"] == r["id"])
        self.assertEqual((c["priority"], c["tags"], c["due"], c["status"], len(c["agents"])), (2, ["t"], 86400, "doing", 2))
        self.assertEqual(self.cards(), ["one", "two", "new", "three", "four"])   # position 1 of "doing" = before "three"
        m.add_card({"title": "other", "board": "Other"})
        self.assertEqual(self.b(1)["cards"][0]["status"], "a")
        m.add_card({"title": "z", "column": "done", "position": 9})
        self.assertEqual(self.cards()[-1], "z")
        m.add_card({"title": "first in empty", "column": "En cours", "board": "Other", "position": 1})
        d = m.load(); b = d["boards"][1]; b["cards"] = []; m.save(d)   # placing in an empty column
        m.add_card({"title": "e", "board": "Other", "position": 1}); self.assertEqual(self.cards(1), ["e"])

    def test_update_card(self):
        m.update_card({"card_id": "C1", "title": "uno", "notes": "n", "priority": "low", "tags": ["a"], "due": "2001-01-02", "column": "doing", "agents": []})
        c = self.b()["cards"][0]; self.assertEqual((c["title"], c["priority"], c["status"], c["due"], c["agents"]), ("uno", 0, "doing", 86400, []))
        m.update_card({"card_id": "C1", "due": ""}); self.assertNotIn("due", self.b()["cards"][0])
        m.update_card({"card_id": "C3", "position": 1}); self.assertEqual(self.cards()[:2], ["three", "uno"])
        m.update_card({"card_id": "C2", "to_board": "main"})   # same board: nothing moves
        m.update_card({"card_id": "C3", "to_board": "Other"})   # "En cours" exists there
        self.assertEqual((self.cards(1), self.b(1)["cards"][0]["status"]), (["three"], "a"))
        m.update_card({"card_id": "C1", "to_board": "Other", "column": "Z"})
        self.assertEqual(self.b(1)["cards"][-1]["status"], "b")
        m.update_card({"card_id": "C4", "to_board": "Other"})   # "Terminé" does not exist there: first column
        self.assertEqual(self.b(1)["cards"][-1]["status"], "a")

    def test_reorder_delete_clear(self):
        m.reorder_cards({"column": "todo", "card_ids": ["C2"]}); self.assertEqual(self.cards()[:2], ["two", "one"])
        m.reorder_cards({"column": "todo", "card_ids": ["C1", "C2"]}); self.assertEqual(self.cards()[:2], ["one", "two"])
        with self.assertRaises(ValueError): m.reorder_cards({"column": "todo", "card_ids": ["C3"]})
        with self.assertRaises(ValueError): m.reorder_cards({"column": "todo", "card_ids": ["C1", "C1"]})
        m.delete_card({"card_id": "C1"}); self.assertNotIn("one", self.cards())
        self.assertIn("1 cards", m.clear_last_column({})); self.assertNotIn("four", self.cards())

class Columns(Base):
    def test_columns(self):
        cid = m.add_column({"name": "Review", "color": "red"})["id"]; self.assertEqual(self.b()["columns"][-1]["color"], "red")
        m.add_column({"name": "Plain", "board": "Other"}); self.assertEqual(self.b(1)["columns"][-1]["color"], "gray")
        m.update_column({"column": cid, "name": "QA"}); m.update_column({"column": "QA", "color": "teal"})
        self.assertEqual((self.b()["columns"][-1]["name"], self.b()["columns"][-1]["color"]), ("QA", "teal"))
        m.update_column({"column": "QA"})
        m.delete_column({"column": "QA"}); self.assertEqual(len(self.b()["columns"]), 3)
        m.delete_column({"column": "todo"})   # first column: cards go to the next one
        self.assertEqual({c["status"] for c in self.b()["cards"]}, {"doing", "done"})
        d = m.load(); d["boards"][1]["columns"] = d["boards"][1]["columns"][:1]; m.save(d)
        with self.assertRaises(ValueError): m.delete_column({"column": "a", "board": "Other"})

class Boards(Base):
    def test_add_board(self):
        r = m.add_board({"name": "T"}); b = self.prop()["boards"][-1]
        self.assertEqual((b["id"], b["columns"], b["cards"], self.prop()["selected"]), (r["id"], m.DEFAULT_COLS, [], r["id"]))
        r = m.add_board({"name": "C", "columns": ["A", "B", "C", "D", "E", "F", "G", "H", "I"], "cards": [{"title": "x", "column": "B", "agents": ["me"]}]})
        b = self.prop()["boards"][-1]; self.assertEqual((len(b["columns"]), b["columns"][8]["color"], b["cards"][0]["status"]), (9, "gray", b["columns"][1]["id"]))
        r = m.add_board({"name": "Phase", "parent": "Main"}); p = self.prop()["boards"][-1]
        self.assertEqual((p["parent"], [c["id"] for c in p["columns"]]), (B1, ["todo", "doing", "done"]))
        with self.assertRaises(ValueError): m.add_board({"name": "Sub", "parent": "Phase"})
        m.add_board({"name": "Own cols", "parent": "Main", "columns": ["Only"]}); self.assertEqual(len(self.prop()["boards"][-1]["columns"]), 1)

    def test_update_select_delete(self):
        m.update_board({"board": "Other", "name": "Renamed", "closed": True}); self.assertEqual((self.b(1)["name"], self.b(1)["closed"]), ("Renamed", True))
        m.update_board({"board": "Renamed", "closed": False}); self.assertNotIn("closed", self.b(1))
        m.update_board({"board": "Renamed"})
        self.boards[1]["closed"] = True; self.write({"selected": B1, "boards": self.boards}); os.remove(m.PROP)
        self.assertEqual(m.select_board({"board": "Other"}), "ok")
        self.assertEqual(self.real()["selected"], B2); self.assertNotIn("closed", self.real()["boards"][1])
        m.update_board({"board": "Other", "name": "Y"})   # proposal exists now: select touches both files
        m.select_board({"board": "Main"}); self.assertEqual((self.real()["selected"], self.prop()["selected"]), (B1, B1))
        m.delete_board({"board": "Y"}); self.assertEqual([x["id"] for x in self.prop()["boards"]], [B1])
        m.add_board({"name": "Ph", "parent": "Main"}); m.delete_board({"board": "Main"}); self.assertEqual(self.prop()["boards"], [])
        d = m.load(); self.assertEqual(d["boards"], [])

    def test_delete_selected_board_switches(self):
        m.delete_board({"board": "Main"}); self.assertEqual(self.prop()["selected"], B2)

class Export(Base):
    def test_exports(self):
        out = os.path.join(self.dir, "x.json")
        self.assertEqual(m.export_board({"path": out}), out)
        f = json.load(open(out)); self.assertEqual((f["format"], f["name"], len(f["cards"])), ("kanban", "Main", 4)); self.assertEqual(f["cards"][2]["due"], "2001-01-02T00:00:00Z")
        with self.assertRaises(ValueError): m.export_board({"path": out})
        m.export_board({"path": out, "overwrite": True})
        csv_path = os.path.join(self.dir, "x.csv"); m.export_board({"path": csv_path, "format": "csv"})
        text = open(csv_path, encoding="utf-8").read()
        self.assertTrue(text.startswith("﻿Column,Title,Notes,Priority,Due,Tags,Agents")); self.assertIn("claude · Opus 5.5 · high", text); self.assertIn("2001-01-02", text)
        md_path = os.path.join(self.dir, "x.md"); m.export_board({"path": md_path, "format": "markdown", "board": "Main"})
        md = open(md_path).read()
        self.assertIn("- [ ] **three** — Priority: High · due 2001-01-02 · #x · agents: claude · Opus 5.5 · high\n  Hello", md); self.assertIn("- [x] **four**", md)
        with self.assertRaises(ValueError): m.export_board({"path": os.path.join(self.dir, "x.bin"), "format": "pdf"})

    def test_import(self):
        out = os.path.join(self.dir, "i.json"); m.export_board({"path": out})
        r = m.import_board({"path": out}); b = self.prop()["boards"][-1]
        self.assertEqual((b["id"], len(b["cards"]), self.prop()["selected"]), (r["id"], 4, r["id"])); self.assertNotEqual(b["cards"][0]["id"], "C1")
        self.assertEqual(b["cards"][2]["due"], 86400)
        f = json.load(open(out)); f["cards"][0]["status"] = "gone"; json.dump(f, open(out, "w"))
        m.import_board({"path": out}); self.assertEqual(self.prop()["boards"][-1]["cards"][0]["status"], "todo")
        json.dump({"format": "nope"}, open(out, "w"))
        with self.assertRaises(ValueError): m.import_board({"path": out})

class Protocol(Base):
    def rpc(self, method, **params): return m.handle({"method": method, "params": params})

    def test_handle(self):
        r = self.rpc("initialize", clientInfo={"name": "gemini-cli"}, protocolVersion="2025-01-01")
        self.assertEqual((m.ACTOR, r["protocolVersion"], r["serverInfo"]["version"]), ("gemini-cli", "2025-01-01", "3"))
        self.assertEqual(self.rpc("initialize")["protocolVersion"], "2024-11-05"); self.assertEqual(m.ACTOR, "claude")
        names = [t["name"] for t in self.rpc("tools/list")["tools"]]
        self.assertIn("update_card", names); self.assertEqual(len(names), len(m.TOOLS))
        ok = self.rpc("tools/call", name="get_boards", arguments={"agent": "opus"})
        self.assertNotIn("isError", ok); self.assertNotIn("Change proposed", ok["content"][0]["text"])
        done = self.rpc("tools/call", name="update_board", arguments={"board": "Main", "name": "N"})
        self.assertIn("Change proposed", done["content"][0]["text"]); self.assertTrue(done["content"][0]["text"].startswith("ok"))
        self.assertEqual(self.rpc("tools/call", name="select_board", arguments={"board": "N"})["content"][0]["text"], "ok")
        self.assertEqual(self.rpc("tools/call", name="clear_last_column")["content"][0]["text"], "1 cards deleted\n[Change proposed: the user must approve it in the Kanba app before it is applied.]")
        err = self.rpc("tools/call", name="update_card", arguments={"card_id": "zzz"})
        self.assertTrue(err["isError"]); self.assertIn("card not found", err["content"][0]["text"])
        self.assertEqual(self.rpc("ping"), {})
        with self.assertRaises(KeyError): self.rpc("nope")

    def test_main_loop(self):
        lines = [{"jsonrpc": "2.0", "method": "notifications/initialized"}, {"jsonrpc": "2.0", "id": 1, "method": "ping"}, {"jsonrpc": "2.0", "id": 2, "method": "bogus"}]
        out = io.StringIO(); m.main(io.StringIO("\n".join(json.dumps(x) for x in lines) + "\n"), out)
        r = [json.loads(x) for x in out.getvalue().splitlines()]
        self.assertEqual((len(r), r[0]["result"], r[1]["error"]["code"]), (2, {}, -32601))

if __name__ == "__main__": unittest.main()
