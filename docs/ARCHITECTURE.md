# Architecture

Peekie is a small AppKit and SwiftUI app with no third-party dependencies. This document explains how the pieces fit together and records the decisions that are not obvious from reading the code. The source has no explanatory comments on purpose, so anything that would otherwise be a comment lives here.

## Layout

| File | Responsibility |
| --- | --- |
| `main.swift`, `AppDelegate.swift` | Entry point, app lifecycle, main menu, launch behaviour |
| `NoteWindow.swift` | The borderless-titlebar, translucent note window and its pin button |
| `NoteWindowController.swift` | Owns all open notes: opening, closing, saving, restoring, show and hide, click away |
| `NoteModel.swift` | Links a window to its text view; holds initial content and change callbacks |
| `NoteView.swift` | SwiftUI content: blur, tint and the editor |
| `NoteTextEditor.swift` | `NoteTextView` (the editor) and its SwiftUI wrapper |
| `VisualEffectView.swift` | `BlurView`, the adjustable behind-window blur |
| `CodeHighlighter.swift` | Fenced code blocks and syntax colours |
| `MathEvaluator.swift` | Inline maths |
| `NoteExporter.swift` | Text, Markdown, RTF and RTFD export |
| `NoteStore.swift` | Saving notes between launches |
| `HotKey.swift`, `QuickCapture.swift` | Global shortcuts and selection capture |
| `Preferences.swift` | Preference keys, defaults, shortcut definitions |
| `SettingsView.swift`, `ShortcutRecorder.swift` | The Settings window and shortcut recording |
| `StatusItemController.swift` | The optional menu bar icon |
| `MenuBuilder.swift`, `LoginItem.swift` | Shared menu items, launch at login |

## App lifecycle

Peekie is an accessory app (`LSUIElement`), so it has no Dock icon. The activation policy switches to regular while the Settings window is open and back to accessory when it closes.

The main menu is built in code. It is invisible while Peekie is an accessory app, but its key equivalents still work, and that is what provides `⌘C`, `⌘V`, `⌘W` and the formatting shortcuts to the focused note. This is why the app uses an AppKit entry point instead of a SwiftUI `App`: a SwiftUI `App` replaces the main menu.

The three configurable in-app shortcuts (`MenuShortcut`) are applied to menu items by identifier, whenever preferences change.

Launching the app from Finder shows Settings. A launch by the login item stays invisible. The login-item check uses the launch Apple event, with a system-uptime fallback.

## Global shortcuts

Global shortcuts use Carbon's `RegisterEventHotKey`, which needs no Accessibility permission. Each action has its own id, and one event handler dispatches by id. While a shortcut is being recorded in Settings, all global shortcuts are unregistered so that pressing the existing combination is captured instead of triggering it.

## The note window and the blur

`NoteWindow` is a titled window with a transparent title bar, full-size content view and a hidden title, so the traffic lights remain and the content runs edge to edge. The content is an `NSHostingView` showing `NoteView`.

### Why `BlurView` exists

The background is a behind-window `NSVisualEffectView`. It only offers fixed materials, and its stock look is too heavy: it blurs with a radius of 30, boosts saturation by 2.4 and stacks grey tint layers on top, so the desktop is unrecognisable. Peekie wants an adjustable blur.

An earlier version used `CGSSetWindowBackgroundBlurRadius` (the call Terminal uses). It gives a real variable radius but the blur is a rectangle that ignores the window's rounded corners, which shows as square edges. A blur view inside the window is clipped to the window shape by the system, so `BlurView` subclasses `NSVisualEffectView` and adjusts its internal backdrop layer instead:

- It finds the `CABackdropLayer` and its `gaussianBlur` filter.
- Core Animation ignores an in-place change to the existing filter objects, so it builds a **new** `gaussianBlur` filter through `CAFilter` and assigns a **new array** to `filters`. Mutating the old filter and reassigning the same array does nothing on screen.
- It drops the `colorSaturate` filter and hides the sibling layers, which are the material's own tint.
- The system rebuilds these layers on appearance changes, so the settings are re-applied shortly after each change. Layout passes do not rebuild anything.
- If the layer structure is not recognised, for example after a future macOS change, it falls back to fading the standard blur.

This depends on private Core Animation classes reached through key-value coding. It is the reason Peekie cannot be on the Mac App Store, and it is covered by the `Blur` tests, which will fail if a macOS update changes the structure.

### Tint, opacity and accessibility

`NoteView` draws a flat tint over the blur. The tint is dark slate in dark mode and off-white in light mode, at the user's opacity. With Reduce Transparency the blur is removed and the tint is fully opaque. With Increase Contrast the opacity is at least 0.9.

The light or dark mode is set app-wide through `NSApp.appearance`, so notes and Settings always agree.

## The editor

`NoteTextView` is an `NSTextView` built explicitly on TextKit 1 (with its own `NSLayoutManager`), because the editor relies on layout manager APIs for checkbox hit testing and attachment layout.

### Fonts and the default text colour

Text uses the system font at a size from Settings plus a per-note zoom. Bold and italic are symbolic traits on the font, so the code reads them back from the font rather than keeping a second record. Changing the size or design rebuilds every run's font while preserving its traits.

**Text with no colour attribute is drawn black**, whatever the appearance, so plain text would be unreadable on a dark note. Default text therefore carries an explicit colour, `NoteTextView.defaultColour` (the label colour, which is white in dark mode). That colour is stripped when copying, saving and exporting, so pasted text does not arrive as invisible white text in a light document and a note saved in dark mode is not white-on-white when restored in light mode. Colours the user picked on purpose are kept.

### Typing behaviour

The editor hooks `insertText` and `insertNewline`:

- `- `, `* ` and `[] ` at the start of a line become a bullet or checkbox. Return continues a list, and Return on an empty item ends it.
- A `=` typed at the end of a line evaluates the trailing arithmetic with `MathEvaluator`. The evaluator is a small hand-written parser, because `NSExpression` raises Objective-C exceptions on malformed input.
- Inside a fenced code block none of this happens, and Return keeps the current indentation.

Checkbox clicks and `⌘`-click links are handled in `mouseDown`, using the layout manager to check that the click landed on the glyph itself.

Pasting is plain text by default so a note keeps its own look. Copied images, and image files copied in Finder, are inserted as images.

### Code blocks

Fences stay in the text as ordinary characters, so a note copies out as Markdown. `CodeHighlighter` finds blocks (an unclosed fence runs to the end so the block looks right while you type) and styles them: monospaced font, a background card and token colours from a small tokenizer with a table of languages. Highlighting is debounced and runs after each change, and it remembers what it styled last time so styling is removed when a fence disappears. The highlighter never goes through the undo manager.

### Images

An image is inserted as an `NSTextAttachment` built from PNG data, so a saved note stores a compact PNG. It starts at a modest size: at most 60% of the note's width and height. Right-click offers Small, Medium, Large and Actual Size.

Two RTFD quirks shape the code:

- The format **forgets an attachment's displayed size**. `NoteStore` therefore saves each image's width in the note's metadata, in order, and `NoteTextView.load` applies them.
- A restored note is created before the window lays out its text view, so the view has no width at that moment. Sizing images then would squash them to a tiny thumbnail. Image normalisation is skipped until the view has a real width, and afterwards it only shrinks images that are wider than the note.

## Saved notes

With **Save notes between launches** on, `NoteWindowController` saves each note 0.8 seconds after a change, and when a window moves or resizes. `NoteStore` writes two files per note into `~/Library/Application Support/Peekie/Notes` (permissions `0700`): `<id>.note`, the RTFD data, and `<id>.json`, with the frame, zoom, pinned state and image widths.

Closing a note deletes its files, except when the app is quitting, when every open note is flushed to disk first. Turning the setting off deletes everything. Empty notes are never saved. The last ten closed notes are kept in memory only, for `⇧⌘T`.

## Quick capture

`QuickCapture` posts `⌘C` to the frontmost app with `CGEvent`, which needs the Accessibility permission. It saves the clipboard first, waits for the pasteboard change count to move, reads the text, and restores the clipboard. If the change count never moves, nothing was selected and the clipboard is left alone.

## Settings

`SettingsView` is a grouped SwiftUI form hosted in an `NSWindow` owned by `SettingsWindowController`. Preferences use `@AppStorage`, and the controllers observe `UserDefaults` changes to apply them live. The default value of each preference is registered at launch in `PrefDefault`.

## Signing and permissions

macOS ties the Accessibility permission to the app's code signature. An ad hoc signature is a hash of the exact binary, so every rebuild loses the permission. Signing with an Apple Development certificate gives a stable identity based on the bundle identifier and certificate, which is why `install.sh` prefers one when it can find it.

Release DMGs are signed ad hoc, so they are not notarized, and macOS asks for a confirmation on first launch.

## Testing

`scripts/test.sh` compiles `Tests/*.swift` together with the app sources (except `main.swift`) into one executable and runs it with a suite name:

- `logic`: pure logic with no window.
- `editor`: the text view inside an offscreen window.
- `window`: real note windows, the blur layers and the controllers.

The test process uses its own preference domain and a temporary notes folder. Some tests render a view to a bitmap and measure pixels, for example to check that text is white and that an image is drawn at the size the code claims.
