import AppKit

@MainActor
enum MenuBarIconRenderer {
    static func image(percentage: Int, charging: Bool, paused: Bool) -> NSImage {
        let source = Bundle.main.url(forResource: "MenuBarBoltTemplate", withExtension: "png")
            .flatMap(NSImage.init(contentsOf:))
            ?? NSImage(systemSymbolName: "bolt.fill", accessibilityDescription: "Kurrenchi")!
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            source.draw(in: NSRect(x: 1, y: 1, width: 16, height: 16),
                        from: .zero, operation: .sourceOver, fraction: 1)
            return true
        }
        image.isTemplate = true
        return image
    }
}
