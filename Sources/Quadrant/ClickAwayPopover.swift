import SwiftUI

/// Keeps a popover open until its form has handled an outside-click cancel request.
private struct ClickAwayPopoverModifier<Popup: View>: ViewModifier {
    @Binding var isPresented: Bool
    @State private var cancelRequest = 0
    @State private var isClosing = false
    let popup: (Int, @escaping () -> Void) -> Popup

    func body(content: Content) -> some View {
        content.popover(isPresented: Binding(
            get: { isPresented },
            set: { visible in
                guard !visible, isPresented, !isClosing else { return }
                cancelRequest += 1
            }
        ), arrowEdge: .bottom) {
            popup(cancelRequest) {
                isClosing = true
                isPresented = false
            }
        }
        .onChange(of: isPresented) { _, visible in
            if visible { isClosing = false }
        }
    }
}

extension View {
    func clickAwayPopover<Popup: View>(
        isPresented: Binding<Bool>,
        @ViewBuilder content: @escaping (Int, @escaping () -> Void) -> Popup
    ) -> some View {
        modifier(ClickAwayPopoverModifier(isPresented: isPresented, popup: content))
    }
}
