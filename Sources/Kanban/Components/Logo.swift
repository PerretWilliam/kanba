import SwiftUI

// MARK: - Logo (three columns of different heights)

struct Logo: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        let w = r.width * 0.26, heights = [1.0, 0.65, 0.82]
        for (i, h) in heights.enumerated() {
            let x = r.minX + CGFloat(i) * (r.width - w) / 2
            p.addRoundedRect(in: CGRect(x: x, y: r.maxY - r.height * h, width: w, height: r.height * h),
                             cornerSize: CGSize(width: w / 2.5, height: w / 2.5))
        }
        return p
    }
}

struct LogoMark: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(LinearGradient(colors: [Color(white: 0.24), Color(white: 0.09)], startPoint: .top, endPoint: .bottom))
            .overlay(Logo().fill(.white).padding(6))
            .frame(width: 28, height: 28)
    }
}
