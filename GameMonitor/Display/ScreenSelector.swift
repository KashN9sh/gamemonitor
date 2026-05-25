import AppKit

struct ScreenOption: Identifiable, Hashable {
    let id: Int
    let name: String
    let screen: NSScreen
}

enum ScreenSelector {
    static func allScreens() -> [ScreenOption] {
        NSScreen.screens.enumerated().map { index, screen in
            let name = screen.localizedName
            let size = screen.frame.size
            let label = "\(name) (\(Int(size.width))×\(Int(size.height)))"
            return ScreenOption(id: index, name: label, screen: screen)
        }
    }

    static func pixelSize(for screen: NSScreen) -> (width: Int, height: Int) {
        let scale = screen.backingScaleFactor
        return (
            Int(screen.frame.width * scale),
            Int(screen.frame.height * scale)
        )
    }

    static func preferredScreen(savedID: Int?) -> NSScreen? {
        let screens = NSScreen.screens
        if let savedID, savedID >= 0, savedID < screens.count {
            return screens[savedID]
        }

        if let studio = screens.first(where: {
            $0.localizedName.localizedCaseInsensitiveContains("studio")
        }) {
            return studio
        }

        return NSScreen.main
    }
}
