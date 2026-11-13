import SwiftUI

extension Font {
    static func mono(_ size: CGFloat, _ weight: Weight = .regular) -> Font { .custom("JetBrains Mono", size: size).weight(weight) }
    static func inter(_ size: CGFloat, _ weight: Weight = .regular) -> Font { .custom("Inter", size: size).weight(weight) }
}
