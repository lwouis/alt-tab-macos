import Cocoa

/// Classic keyboard shortcuts like copy-and-paste are missing without a MainMenu
/// see https://stackoverflow.com/a/3746058/2249756
class MainMenu {
    private static var mainMenu: NSMenu!
    private static var menuItemsWithShortcut = [NSMenuItem: String]()
    private static var editMenuItems = Set<NSMenuItem>()

    static func create() {
        mainMenu = NSMenu(title: "Main Menu")
        mainMenu.addItem(appMenuItem())
        mainMenu.addItem(fileMenuItem())
        mainMenu.addItem(editMenuItem())
        mainMenu.addItem(formatMenuItem())
        mainMenu.addItem(windowMenuItem())
        mainMenu.addItem(helpMenuItem())
        App.shared.mainMenu = mainMenu
        rememberMenuItemsWithShortcut()
    }

    static func toggle(_ enabled: Bool) {
        for (item, keyEquivalent) in menuItemsWithShortcut {
            item.keyEquivalent = enabled ? keyEquivalent : ""
        }
    }

    static func toggleEditMenu(_ enabled: Bool) {
        for item in editMenuItems {
            guard let keyEquivalent = menuItemsWithShortcut[item] else { continue }
            item.keyEquivalent = enabled ? keyEquivalent : ""
        }
    }

    private static func rememberMenuItemsWithShortcut() {
        guard let items = mainMenu?.items else { return }
        let editSubmenu = items.first { $0.submenu?.title == "Edit" }?.submenu
        var stack: [(NSMenu, Bool)] = [(mainMenu, false)]
        while let (menu, isEdit) = stack.popLast() {
            let isEditMenu = isEdit || menu === editSubmenu
            for item in menu.items {
                if !item.keyEquivalent.isEmpty {
                    menuItemsWithShortcut[item] = item.keyEquivalent
                    if isEditMenu { editMenuItems.insert(item) }
                }
                if let submenu = item.submenu {
                    stack.append((submenu, isEditMenu))
                }
            }
        }
    }

    // MARK: - Menu builders

    private static func appMenuItem() -> NSMenuItem {
        let menu = NSMenu(title: "AltTab")
        menu.addItem(item("Preferences…", "orderFrontPreferencesPanel:", ","))
        menu.addItem(.separator())
        let servicesItem = NSMenuItem(title: "Services", action: nil, keyEquivalent: "")
        let servicesMenu = NSMenu(title: "Services")
        servicesItem.submenu = servicesMenu
        NSApp.servicesMenu = servicesMenu
        menu.addItem(servicesItem)
        menu.addItem(.separator())
        menu.addItem(item("Show All", "unhideAllApplications:"))
        menu.addItem(.separator())
        menu.addItem(item("Quit AltTab", "terminate:", "q"))
        return menuBarItem(menu)
    }

    private static func fileMenuItem() -> NSMenuItem {
        let menu = NSMenu(title: "File")
        menu.addItem(item("Close", "performClose:", "w"))
        menu.addItem(.separator())
        menu.addItem(item("Page Setup…", "runPageLayout:", "P", [.shift, .command]))
        menu.addItem(item("Print…", "print:", "p"))
        return menuBarItem(menu)
    }

    private static func editMenuItem() -> NSMenuItem {
        let menu = NSMenu(title: "Edit")
        menu.addItem(item("Undo", "undo:", "z"))
        menu.addItem(item("Redo", "redo:", "Z", [.shift, .command]))
        menu.addItem(.separator())
        menu.addItem(item("Cut", "cut:", "x"))
        menu.addItem(item("Copy", "copy:", "c"))
        menu.addItem(item("Paste", "paste:", "v"))
        menu.addItem(item("Paste and Match Style", "pasteAsPlainText:", "V", [.option, .shift, .command]))
        menu.addItem(item("Delete", "delete:"))
        menu.addItem(item("Select All", "selectAll:", "a"))
        menu.addItem(.separator())
        menu.addItem(submenuItem("Find", findMenu()))
        menu.addItem(submenuItem("Spelling and Grammar", spellingMenu()))
        menu.addItem(submenuItem("Substitutions", substitutionsMenu()))
        menu.addItem(submenuItem("Transformations", transformationsMenu()))
        menu.addItem(submenuItem("Speech", speechMenu()))
        return menuBarItem(menu)
    }

    private static func findMenu() -> NSMenu {
        let menu = NSMenu(title: "Find")
        menu.addItem(taggedItem("Find…", "performFindPanelAction:", "f", 1))
        menu.addItem(taggedItem("Find and Replace…", "performFindPanelAction:", "f", 12, [.option, .command]))
        menu.addItem(taggedItem("Find Next", "performFindPanelAction:", "g", 2))
        menu.addItem(taggedItem("Find Previous", "performFindPanelAction:", "G", 3, [.shift, .command]))
        menu.addItem(taggedItem("Use Selection for Find", "performFindPanelAction:", "e", 7))
        menu.addItem(item("Jump to Selection", "centerSelectionInVisibleArea:", "j"))
        return menu
    }

    private static func spellingMenu() -> NSMenu {
        let menu = NSMenu(title: "Spelling")
        menu.addItem(item("Show Spelling and Grammar", "showGuessPanel:", ":"))
        menu.addItem(item("Check Document Now", "checkSpelling:", ";"))
        menu.addItem(.separator())
        menu.addItem(item("Check Spelling While Typing", "toggleContinuousSpellChecking:"))
        menu.addItem(item("Check Grammar With Spelling", "toggleGrammarChecking:"))
        menu.addItem(item("Correct Spelling Automatically", "toggleAutomaticSpellingCorrection:"))
        return menu
    }

    private static func substitutionsMenu() -> NSMenu {
        let menu = NSMenu(title: "Substitutions")
        menu.addItem(item("Show Substitutions", "orderFrontSubstitutionsPanel:"))
        menu.addItem(.separator())
        menu.addItem(item("Smart Copy/Paste", "toggleSmartInsertDelete:"))
        menu.addItem(item("Smart Quotes", "toggleAutomaticQuoteSubstitution:"))
        menu.addItem(item("Smart Dashes", "toggleAutomaticDashSubstitution:"))
        menu.addItem(item("Smart Links", "toggleAutomaticLinkDetection:"))
        menu.addItem(item("Data Detectors", "toggleAutomaticDataDetection:"))
        menu.addItem(item("Text Replacement", "toggleAutomaticTextReplacement:"))
        return menu
    }

    private static func transformationsMenu() -> NSMenu {
        let menu = NSMenu(title: "Transformations")
        menu.addItem(item("Make Upper Case", "uppercaseWord:"))
        menu.addItem(item("Make Lower Case", "lowercaseWord:"))
        menu.addItem(item("Capitalize", "capitalizeWord:"))
        return menu
    }

    private static func speechMenu() -> NSMenu {
        let menu = NSMenu(title: "Speech")
        menu.addItem(item("Start Speaking", "startSpeaking:"))
        menu.addItem(item("Stop Speaking", "stopSpeaking:"))
        return menu
    }

    private static func formatMenuItem() -> NSMenuItem {
        let menu = NSMenu(title: "Format")
        menu.addItem(submenuItem("Font", fontMenu()))
        menu.addItem(submenuItem("Text", textMenu()))
        return menuBarItem(menu)
    }

    private static func fontMenu() -> NSMenu {
        let fontManager = NSFontManager.shared
        let menu = NSMenu(title: "Font")
        menu.addItem(item("Show Fonts", "orderFrontFontPanel:", "t", target: fontManager))
        menu.addItem(taggedItem("Bold", "addFontTrait:", "b", 2, target: fontManager))
        menu.addItem(taggedItem("Italic", "addFontTrait:", "i", 1, target: fontManager))
        menu.addItem(item("Underline", "underline:", "u"))
        menu.addItem(.separator())
        menu.addItem(taggedItem("Bigger", "modifyFont:", "+", 3, target: fontManager))
        menu.addItem(taggedItem("Smaller", "modifyFont:", "-", 4, target: fontManager))
        menu.addItem(.separator())
        menu.addItem(submenuItem("Kern", kernMenu()))
        menu.addItem(submenuItem("Ligatures", ligaturesMenu()))
        menu.addItem(submenuItem("Baseline", baselineMenu()))
        menu.addItem(.separator())
        menu.addItem(item("Show Colors", "orderFrontColorPanel:", "C", [.shift, .command]))
        menu.addItem(.separator())
        menu.addItem(item("Copy Style", "copyFont:", "c", [.option, .command]))
        menu.addItem(item("Paste Style", "pasteFont:", "v", [.option, .command]))
        return menu
    }

    private static func kernMenu() -> NSMenu {
        let menu = NSMenu(title: "Kern")
        menu.addItem(item("Use Default", "useStandardKerning:"))
        menu.addItem(item("Use None", "turnOffKerning:"))
        menu.addItem(item("Tighten", "tightenKerning:"))
        menu.addItem(item("Loosen", "loosenKerning:"))
        return menu
    }

    private static func ligaturesMenu() -> NSMenu {
        let menu = NSMenu(title: "Ligatures")
        menu.addItem(item("Use Default", "useStandardLigatures:"))
        menu.addItem(item("Use None", "turnOffLigatures:"))
        menu.addItem(item("Use All", "useAllLigatures:"))
        return menu
    }

    private static func baselineMenu() -> NSMenu {
        let menu = NSMenu(title: "Baseline")
        menu.addItem(item("Use Default", "unscript:"))
        menu.addItem(item("Superscript", "superscript:"))
        menu.addItem(item("Subscript", "subscript:"))
        menu.addItem(item("Raise", "raiseBaseline:"))
        menu.addItem(item("Lower", "lowerBaseline:"))
        return menu
    }

    private static func textMenu() -> NSMenu {
        let menu = NSMenu(title: "Text")
        menu.addItem(item("Align Left", "alignLeft:", "{"))
        menu.addItem(item("Center", "alignCenter:", "|"))
        menu.addItem(item("Justify", "alignJustified:"))
        menu.addItem(item("Align Right", "alignRight:", "}"))
        menu.addItem(.separator())
        menu.addItem(submenuItem("Writing Direction", writingDirectionMenu()))
        menu.addItem(.separator())
        menu.addItem(item("Show Ruler", "toggleRuler:"))
        menu.addItem(item("Copy Ruler", "copyRuler:", "c", [.control, .command]))
        menu.addItem(item("Paste Ruler", "pasteRuler:", "v", [.control, .command]))
        return menu
    }

    private static func writingDirectionMenu() -> NSMenu {
        let menu = NSMenu(title: "Writing Direction")
        let paragraph = NSMenuItem(title: "Paragraph", action: nil, keyEquivalent: "")
        paragraph.isEnabled = false
        menu.addItem(paragraph)
        menu.addItem(item("\tDefault", "makeBaseWritingDirectionNatural:"))
        menu.addItem(item("\tLeft to Right", "makeBaseWritingDirectionLeftToRight:"))
        menu.addItem(item("\tRight to Left", "makeBaseWritingDirectionRightToLeft:"))
        menu.addItem(.separator())
        let selection = NSMenuItem(title: "Selection", action: nil, keyEquivalent: "")
        selection.isEnabled = false
        menu.addItem(selection)
        menu.addItem(item("\tDefault", "makeTextWritingDirectionNatural:"))
        menu.addItem(item("\tLeft to Right", "makeTextWritingDirectionLeftToRight:"))
        menu.addItem(item("\tRight to Left", "makeTextWritingDirectionRightToLeft:"))
        return menu
    }

    private static func windowMenuItem() -> NSMenuItem {
        let menu = NSMenu(title: "Window")
        menu.addItem(item("Minimize", "performMiniaturize:", "m"))
        menu.addItem(item("Zoom", "performZoom:"))
        menu.addItem(.separator())
        menu.addItem(item("Bring All to Front", "arrangeInFront:"))
        NSApp.windowsMenu = menu
        return menuBarItem(menu)
    }

    private static func helpMenuItem() -> NSMenuItem {
        let menu = NSMenu(title: "Help")
        menu.addItem(item("AltTab Help", "showHelp:", "?"))
        NSApp.helpMenu = menu
        return menuBarItem(menu)
    }

    // MARK: - Helpers

    private static func menuBarItem(_ menu: NSMenu) -> NSMenuItem {
        let item = NSMenuItem(title: menu.title, action: nil, keyEquivalent: "")
        item.submenu = menu
        return item
    }

    private static func submenuItem(_ title: String, _ menu: NSMenu) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.submenu = menu
        return item
    }

    private static func item(_ title: String, _ action: String, _ key: String = "", _ modifiers: NSEvent.ModifierFlags = .command, target: AnyObject? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: Selector(action), keyEquivalent: key)
        item.keyEquivalentModifierMask = key.isEmpty ? [] : modifiers
        item.target = target
        return item
    }

    private static func taggedItem(_ title: String, _ action: String, _ key: String, _ tag: Int, _ modifiers: NSEvent.ModifierFlags = .command, target: AnyObject? = nil) -> NSMenuItem {
        let item = self.item(title, action, key, modifiers, target: target)
        item.tag = tag
        return item
    }
}
