import AppKit
import UniformTypeIdentifiers

/// File dialogs around BoardIO (UI only, not unit tested).
extension BoardIO {
    static func export(_ board: Board, as format: Format = .json) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: format.ext) ?? .plainText]
        panel.nameFieldStringValue = "\(board.name).\(format.ext)"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try data(board, as: format).write(to: url, options: .atomic) }
        catch { alert("Export impossible", error.localizedDescription) }
    }

    /// Asks for a file and returns the board it contains.
    static func importBoard() -> Board? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        guard let data = try? Data(contentsOf: url), let b = decode(data) else {
            alert("Fichier invalide", "Ce fichier n'est pas un tableau Kanban au format JSON."); return nil
        }
        return b
    }

    private static func alert(_ title: String, _ text: String) {
        let a = NSAlert(); a.messageText = title; a.informativeText = text; a.runModal()
    }
}
