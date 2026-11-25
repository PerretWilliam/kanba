import Testing
import Foundation
@testable import Kanban

/// The MCP server on a real Store. Lives in StoreTests' suite so it never runs beside another test that sets KANBA_DATA.
extension StoreTests {
    func rpc(_ s: MCPServer, _ method: String, _ params: [String: Any] = [:], id: Any? = 1, session: String? = nil) throws -> (reply: [String: Any]?, session: String?) {
        var m: [String: Any] = ["jsonrpc": "2.0", "method": method, "params": params]
        if let id { m["id"] = id }
        let (text, sid) = s.handle(try JSONSerialization.data(withJSONObject: m), session: session)
        return (try text.map { try #require(JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any]) }, sid)
    }
    func tool(_ s: MCPServer, _ name: String, _ args: [String: Any] = [:], session: String? = nil) throws -> (text: String, isError: Bool) {
        let r = try #require(rpc(s, "tools/call", ["name": name, "arguments": args], session: session).reply?["result"] as? [String: Any])
        return ((r["content"] as? [[String: Any]])?.first?["text"] as? String ?? "", r["isError"] as? Bool ?? false)
    }

    @Test func mcpProtocol() throws {
        let (store, _) = try make()
        let s = MCPServer(store: store)
        let (init1, sid) = try rpc(s, "initialize", ["protocolVersion": "2025-01-01", "clientInfo": ["name": "gemini-cli"]])
        let result = try #require(init1?["result"] as? [String: Any])
        #expect(result["protocolVersion"] as? String == "2025-01-01" && (result["serverInfo"] as? [String: Any])?["name"] as? String == "kanban" && sid != nil)
        #expect(try rpc(s, "initialize").reply?["result"] != nil)   // no params: defaults
        let names = try ((rpc(s, "tools/list").reply?["result"] as? [String: Any])?["tools"] as? [[String: Any]])?.compactMap { $0["name"] as? String } ?? []
        #expect(names.count == 16 && names.contains("update_card"))
        #expect(try rpc(s, "ping").reply?["result"] != nil)
        #expect(try rpc(s, "initialized", id: nil).reply == nil)   // notification: no reply
        #expect(try (rpc(s, "nope").reply?["error"] as? [String: Any])?["code"] as? Int == -32601)
        let (bad, _) = s.handle(Data("garbage".utf8), session: nil)
        #expect(bad?.contains("-32700") == true)

        let ok = try tool(s, "get_boards", session: sid)
        #expect(!ok.isError && !ok.text.contains("Change proposed") && store.proposal == nil)
        let done = try tool(s, "add_card", ["title": "from ai"], session: sid)
        #expect(done.text.hasSuffix(MCPServer.note) && store.proposal?.actor == "gemini-cli" && store.review.count == 1 && store.boards[0].cards.isEmpty)   // proposed, not applied
        let more = try tool(s, "add_card", ["title": "second"], session: "unknown-session")   // unknown session: counted as claude
        #expect(more.text.hasSuffix(MCPServer.note) && store.proposal?.actor == "claude" && store.review.count == 2)
        let err = try tool(s, "update_card", ["card_id": "zzz"], session: sid)
        #expect(err.isError && err.text.contains("card not found"))
        #expect(try tool(s, "update_card", ["card_id": "zzz"]).isError)
        let noName = try rpc(s, "tools/call", [:]).reply?["result"] as? [String: Any]
        #expect(noName?["isError"] as? Bool == true)
        store.accept(Set(store.review.map(\.id)))
        #expect(store.boards[0].cards.count == 2)
    }

    @Test func mcpLiveStateTools() throws {
        let a = Board(name: "A", closed: true), b = Board(name: "B")
        let (store, _) = try make(boards: [a, b], selected: b.id)
        let s = MCPServer(store: store)
        #expect(try tool(s, "select_board", ["board": "A"]).text == "ok")   // immediate: reopens and switches
        #expect(store.selected == a.id && store.boards[0].closed == nil && store.proposal == nil)
        _ = try tool(s, "set_filter", ["tag": "ops"]); #expect(store.filter.tag == "ops")
        _ = try tool(s, "set_filter"); #expect(store.filter.isEmpty)
        #expect(try tool(s, "export_board", ["path": FileManager.default.temporaryDirectory.appendingPathComponent("kanba-\(UUID()).md").path, "format": "markdown"]).isError == false)
        #expect(try tool(s, "export_board", ["path": "/nonexistent-dir/x.json"]).isError)   // write error is reported, not thrown
    }

    @Test func mcpHTTP() throws {
        let (store, _) = try make()
        let s = MCPServer(store: store)
        func req(_ line: String, _ headers: [String] = ["Host: localhost:47821", "Content-Type: application/json"], body: String = "") -> String? {
            let raw = ([line] + headers + ["Content-Length: \(body.utf8.count)", "", body]).joined(separator: "\r\n")
            return s.respond(to: Data(raw.utf8)).map { String(decoding: $0, as: UTF8.self) }
        }
        let ping = #"{"jsonrpc":"2.0","id":1,"method":"ping"}"#
        #expect(req("POST /mcp HTTP/1.1", body: ping)?.hasPrefix("HTTP/1.1 200 OK") == true && req("POST /mcp HTTP/1.1", body: ping)?.hasSuffix(#""result":{}}"#) == true)
        let sess = req("POST /mcp HTTP/1.1", body: #"{"jsonrpc":"2.0","id":1,"method":"initialize"}"#)
        #expect(sess?.contains("Mcp-Session-Id: ") == true)
        #expect(req("POST /mcp HTTP/1.1", body: #"{"jsonrpc":"2.0","method":"notifications/initialized"}"#)?.hasPrefix("HTTP/1.1 202") == true)
        #expect(req("POST /mcp?x=1 HTTP/1.1", ["Host: 127.0.0.1", "content-type: application/json; charset=utf-8"], body: ping)?.hasPrefix("HTTP/1.1 200") == true)
        #expect(req("POST /mcp HTTP/1.1", ["Host: localhost", "Content-Type: application/json", "Origin: http://evil.example"], body: ping)?.hasPrefix("HTTP/1.1 403") == true)   // a web page
        #expect(req("POST /mcp HTTP/1.1", ["Host: evil.example", "Content-Type: application/json"], body: ping)?.hasPrefix("HTTP/1.1 403") == true)   // DNS rebinding
        #expect(req("POST /other HTTP/1.1", body: ping)?.hasPrefix("HTTP/1.1 404") == true)
        #expect(req("GET /mcp HTTP/1.1")?.contains("405") == true && req("GET /mcp HTTP/1.1")?.contains("Allow: POST") == true)
        #expect(req("DELETE /mcp HTTP/1.1")?.hasPrefix("HTTP/1.1 200") == true)
        #expect(req("POST /mcp HTTP/1.1", ["Host: localhost", "Content-Type: text/plain"], body: ping)?.hasPrefix("HTTP/1.1 415") == true)
        #expect(req("BAD", body: "")?.hasPrefix("HTTP/1.1 400") == true)
        #expect(s.respond(to: Data("POST /mcp HTTP/1.1\r\nHost: localhost\r\n".utf8)) == nil)   // headers not complete yet
        #expect(s.respond(to: Data("POST /mcp HTTP/1.1\r\nHost: localhost\r\nContent-Length: 50\r\n\r\n{".utf8)) == nil)   // body not complete yet
        #expect(MCPServer.http(500, "x").starts(with: Data("HTTP/1.1 500 Error".utf8)))
    }
}
