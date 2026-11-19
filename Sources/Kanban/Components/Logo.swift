import SwiftUI

/// Header logo: the app icon itself (it has ~10% transparent margin, hence the oversized frame).
struct LogoMark: View {
    var body: some View {
        Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 36, height: 36).padding(-4)
    }
}
