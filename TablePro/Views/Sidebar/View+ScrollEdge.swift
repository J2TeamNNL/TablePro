import SwiftUI

extension View {
    @ViewBuilder
    func hardBottomScrollEdge() -> some View {
        if #available(macOS 26.0, *) {
            scrollEdgeEffectStyle(.hard, for: .bottom)
        } else {
            self
        }
    }
}
