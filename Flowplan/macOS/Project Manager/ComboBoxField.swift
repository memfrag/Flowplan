//
//  Copyright © 2026 Apparata AB. All rights reserved.
//

import SwiftUI
import AppKit

/// A text field that suggests previously-used values: it completes inline as you type and offers the
/// full list from a dropdown, while still accepting anything you type.
///
/// SwiftUI has no combo box on macOS, so this wraps `NSComboBox`. Editing is reported continuously
/// via the binding, but `onCommit` only fires when the value is settled — picking from the list, or
/// finishing editing — so callers can treat it as "the user chose this" rather than "the user typed
/// another character".
struct ComboBoxField: NSViewRepresentable {

    @Binding var text: String

    var placeholder: String = ""

    /// The values offered for completion and in the dropdown.
    var completions: [String]

    var onCommit: (String) -> Void

    func makeNSView(context: Context) -> NSComboBox {
        let comboBox = NSComboBox()
        comboBox.completes = true
        comboBox.usesDataSource = false
        comboBox.delegate = context.coordinator
        comboBox.placeholderString = placeholder
        comboBox.stringValue = text
        comboBox.addItems(withObjectValues: completions)
        return comboBox
    }

    func updateNSView(_ comboBox: NSComboBox, context: Context) {
        // Keep the coordinator's view of the binding current — it's a struct, so a stale copy would
        // write through to an outdated binding.
        context.coordinator.parent = self

        // Only assign when different: assigning unconditionally would fight the field mid-edit.
        if comboBox.stringValue != text {
            comboBox.stringValue = text
        }
        if comboBox.objectValues as? [String] != completions {
            comboBox.removeAllItems()
            comboBox.addItems(withObjectValues: completions)
        }
        comboBox.placeholderString = placeholder
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    final class Coordinator: NSObject, NSComboBoxDelegate {

        var parent: ComboBoxField

        init(_ parent: ComboBoxField) {
            self.parent = parent
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let comboBox = notification.object as? NSComboBox else { return }
            parent.text = comboBox.stringValue
        }

        func comboBoxSelectionDidChange(_ notification: Notification) {
            guard let comboBox = notification.object as? NSComboBox else { return }
            // `stringValue` hasn't caught up to the selection yet, so read the item directly.
            let index = comboBox.indexOfSelectedItem
            guard index >= 0, let value = comboBox.itemObjectValue(at: index) as? String else { return }
            parent.text = value
            parent.onCommit(value)
        }

        func controlTextDidEndEditing(_ notification: Notification) {
            guard let comboBox = notification.object as? NSComboBox else { return }
            parent.text = comboBox.stringValue
            parent.onCommit(comboBox.stringValue)
        }
    }
}
