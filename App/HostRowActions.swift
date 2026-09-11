import SwiftUI
import TermCore

/// Native row gestures and a context menu share the same actions and confirmation.
struct HostRowActions: ViewModifier {
    let host: TermCore.Host
    let edit: () -> Void
    let remove: () -> Void
    let duplicate: () -> Void
    var disconnect: (() -> Void)? = nil
    @State private var confirmingRemoval = false

    func body(content: Content) -> some View {
        content
            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                Button("Edit", systemImage: "pencil", action: edit).tint(.blue)
                Button("Duplicate", systemImage: "plus.square.on.square", action: duplicate).tint(.indigo)
            }
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                if let disconnect {
                    Button("Disconnect", systemImage: "xmark.circle", action: disconnect).tint(.orange)
                }
                // This button opens confirmation; only the dialog performs removal.
                Button("Remove", systemImage: "trash") { confirmingRemoval = true }.tint(.red)
            }
            .contextMenu {
                Button("Edit host", systemImage: "pencil", action: edit)
                Button("Duplicate host", systemImage: "plus.square.on.square", action: duplicate)
                if let disconnect { Button("Disconnect", systemImage: "xmark.circle", action: disconnect) }
                Button("Remove host", systemImage: "trash", role: .destructive) { confirmingRemoval = true }
            }
            .confirmationDialog("Remove \(host.name)?", isPresented: $confirmingRemoval, titleVisibility: .visible) {
                Button("Remove host", role: .destructive, action: remove)
                Button("Cancel", role: .cancel) {}
            } message: {
                #if os(macOS)
                Text("Remove this saved host from your synced devices. SSH keys, AWS profiles, and external terminal windows remain.")
                #else
                Text("Remove this saved host from your synced devices and close its app sessions. SSH keys and AWS profiles remain. Remote tmux sessions are not deleted.")
                #endif
            }
    }
}
