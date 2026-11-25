import Network
import Foundation

/// Socket glue for MCPServer: a loopback-only TCP listener (UI/IO, not unit tested). KANBA_PORT overrides the port.
@MainActor final class MCPHTTP {
    private static var shared: MCPHTTP?
    private let server: MCPServer
    private var listener: NWListener?

    static func start(_ store: Store) {
        guard shared == nil else { return }
        let port = ProcessInfo.processInfo.environment["KANBA_PORT"].flatMap(UInt16.init) ?? MCPServer.defaultPort
        let h = MCPHTTP(MCPServer(store: store)); shared = h; h.listen(port)
    }
    private init(_ s: MCPServer) { server = s }

    private func listen(_ port: UInt16) {
        let params = NWParameters.tcp
        params.requiredInterfaceType = .loopback
        guard let p = NWEndpoint.Port(rawValue: port), let l = try? NWListener(using: params, on: p) else { return }
        l.stateUpdateHandler = { if case .failed(let e) = $0 { FileHandle.standardError.write(Data("Kanba MCP: port \(port): \(e)\n".utf8)) } }   // e.g. another Kanba already listens
        l.newConnectionHandler = { c in Task { @MainActor in self.serve(c, Data()) } }
        l.start(queue: .main)
        listener = l
    }

    /// Reads until the request is complete, answers, closes.
    private func serve(_ c: NWConnection, _ got: Data) {
        if got.isEmpty { c.start(queue: .main) }
        c.receive(minimumIncompleteLength: 1, maximumLength: 1 << 20) { data, _, done, err in
            Task { @MainActor in
                let all = got + (data ?? Data())
                if let reply = self.server.respond(to: all) { c.send(content: reply, completion: .contentProcessed { _ in c.cancel() }) }
                else if done || err != nil || all.count > 8 << 20 { c.cancel() }
                else { self.serve(c, all) }
            }
        }
    }
}
