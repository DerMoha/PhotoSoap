import SwiftUI

struct NativeGlassButtonStyle: ViewModifier {
    var isProminent = false

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            if isProminent {
                content.buttonStyle(.glassProminent)
            } else {
                content.buttonStyle(.glass)
            }
        } else if isProminent {
            content.buttonStyle(.borderedProminent)
        } else {
            content.buttonStyle(.bordered)
        }
    }
}
