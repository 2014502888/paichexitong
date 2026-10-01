import SwiftUI
import UIKit

struct TapToDismissModifier: ViewModifier {
    func body(content: Content) -> some View {
        content.background(
            Color(.systemBackground)
                .onTapGesture {
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                }
        )
    }
}

extension View {
    func tapToDismissKeyboard() -> some View {
        modifier(TapToDismissModifier())
    }
}