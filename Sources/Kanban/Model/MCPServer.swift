import Foundation

/// The app's MCP server (Streamable HTTP, JSON responses only): POST http://localhost:<port>/mcp.
/// Tools never write boards.json: changes become a proposal the user reviews in the app (Store.propose).
@MainActor final class MCPServer {
    static let defaultPort: UInt16 = 47821
    static let note = "\n[Change proposed: the user must approve it in the Kanba app before it is applied.]"
    let store: Store
    private var clients: [String: String] = [:]   // session id -> client name (the author shown on its proposals)

    init(store: Store) { self.store = store }

    // MARK: HTTP

    /// Answers one raw HTTP request; nil while it is still incomplete (headers or body not fully received).
    /// Only this machine can connect; a browser page cannot reach it (requests carrying an Origin are refused).
    func respond(to raw: Data) -> Data? {
        guard let end = raw.range(of: Data("\r\n\r\n".utf8)) else { return nil }
        let head = String(decoding: raw[..<end.lowerBound], as: UTF8.self).components(separatedBy: "\r\n")
        let line = head[0].split(separator: " ").map(String.init)
        var h: [String: String] = [:]
        for l in head.dropFirst() { if let c = l.firstIndex(of: ":") { h[l[..<c].lowercased()] = l[l.index(after: c)...].trimmingCharacters(in: .whitespaces) } }
        let length = Int(h["content-length"] ?? "") ?? 0
        let body = raw[end.upperBound...]
        if body.count < length { return nil }
        guard line.count >= 2 else { return Self.http(400, "bad request") }
        let host = (h["host"] ?? "").split(separator: ":").first.map(String.init) ?? ""
        guard h["origin"] == nil, ["localhost", "127.0.0.1", "[::1]"].contains(host) else { return Self.http(403, "forbidden") }
        guard line[1].split(separator: "?").first == "/mcp" else { return Self.http(404, "not found") }
        if line[0] == "DELETE" { return Self.http(200, "") }   // end of session: nothing to free
        guard line[0] == "POST" else { return Self.http(405, "use POST", ["Allow": "POST"]) }
        guard (h["content-type"] ?? "").lowercased().hasPrefix("application/json") else { return Self.http(415, "send application/json") }
        let (reply, session) = handle(Data(body.prefix(length)), session: h["mcp-session-id"])
        guard let reply else { return Self.http(202, "") }
        return Self.http(200, reply, ["Content-Type": "application/json"] .merging(session.map { ["Mcp-Session-Id": $0] } ?? [:]) { a, _ in a })
    }

    static func http(_ code: Int, _ body: String, _ headers: [String: String] = [:]) -> Data { http(code, Data(body.utf8), headers) }
    static func http(_ code: Int, _ body: Data, _ headers: [String: String] = [:]) -> Data {
        let text = [200: "OK", 202: "Accepted", 400: "Bad Request", 403: "Forbidden", 404: "Not Found", 405: "Method Not Allowed", 415: "Unsupported Media Type"][code] ?? "Error"
        var out = "HTTP/1.1 \(code) \(text)\r\nContent-Length: \(body.count)\r\nConnection: close\r\n"
        for (k, v) in headers { out += "\(k): \(v)\r\n" }
        return Data(out.utf8) + Data("\r\n".utf8) + body
    }

    // MARK: JSON-RPC

    /// One JSON-RPC message; nil reply for notifications. Also returns the session id to hand out on `initialize`.
    func handle(_ data: Data, session: String?) -> (String?, String?) {
        guard let m = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return (Self.rpc(NSNull(), error: (-32700, "parse error")), nil) }
        guard let id = m["id"] else { return (nil, nil) }   // notification
        let p = m["params"] as? [String: Any] ?? [:]
        switch m["method"] as? String {
        case "initialize":
            let sid = UUID().uuidString
            clients[sid] = ((p["clientInfo"] as? [String: Any])?["name"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "claude"
            return (Self.rpc(id, result: ["protocolVersion": p["protocolVersion"] as? String ?? "2025-03-26", "capabilities": ["tools": [String: Any]()],
                                          "serverInfo": ["name": "kanban", "version": "4"]]), sid)
        case "tools/list": return (Self.rpc(id, result: ["tools": MCPSchemas.tools]), nil)
        case "tools/call": return (Self.rpc(id, result: call(p, actor: session.flatMap { clients[$0] } ?? "claude")), nil)
        case "ping": return (Self.rpc(id, result: [String: Any]()), nil)
        default: return (Self.rpc(id, error: (-32601, "method not found")), nil)
        }
    }

    private func call(_ p: [String: Any], actor: String) -> [String: Any] {
        let name = p["name"] as? String ?? ""
        var w = Workspace(boards: store.proposal?.boards ?? store.boards, selected: store.selected)
        func reply(_ text: String, error: Bool = false) -> [String: Any] { ["content": [["type": "text", "text": text]], "isError": error] }
        do {
            var text = try w.call(name, p["arguments"] as? [String: Any] ?? [:])
            if let f = w.filter { store.filter = f }
            if let s = w.select { store.reopen(s) }
            if !Workspace.readOnly.contains(name) { store.propose(actor: actor, boards: w.boards); text += Self.note }
            return reply(text)
        } catch let e as MCPError {
            return reply("Error: \(e.message)", error: true)
        } catch {
            return reply("Error: \(error.localizedDescription)", error: true)
        }
    }

    private static func rpc(_ id: Any, result: [String: Any]? = nil, error: (Int, String)? = nil) -> String {
        var o: [String: Any] = ["jsonrpc": "2.0", "id": id]
        if let result { o["result"] = result }
        if let error { o["error"] = ["code": error.0, "message": error.1] }
        return Workspace.json(o)
    }
}
