# Sheet Style System

All modals, pickers, action menus, and forms present as bottom sheets. Every sheet uses `SheetStyle` (`LedgeriOS/LedgeriOS/Theme/SheetStyle.swift`) — never set detents or content interaction inline.

## Design Principles

1. **Single fixed height per style.** No multi-snap-point resizing. The sheet opens to one height and stays there.
2. **Content scrolls inside the sheet** where needed — swiping on content scrolls the list, not the sheet.
3. **Tap background to dismiss.** One tap, always.
4. **One `.sheetStyle()` call per sheet.** It bundles the detent, `.presentationContentInteraction(.scrolls)` (where applicable), and `.presentationDragIndicator(.visible)`.

## Styles

| Style | Height | Content Scrolls | Use For |
|---|---|---|---|
| `.quickMenu` | 50% (`.medium`) | No | Sort menu, image source, small action menus (≤6 items) |
| `.selectionMenu` | 65% (`.fraction(0.65)`) | Yes | Filter menus, detail view action menus (7+ items) |
| `.form` | 85% (`.fraction(0.85)`) | Yes | Create/edit forms, sell/reassign modals |
| `.picker` | 65% (`.fraction(0.65)`) | Yes | Space picker, transaction picker, category picker |
| `.fullSheet` | 100% (`.large`) | Yes | Full item browser with search/filter |

## Usage

```swift
.sheet(isPresented: $showForm) {
    MyFormContent(...)
        .sheetStyle(.form)
}
```

## Choosing a Style

- **≤6 static items, no scrolling needed** → `.quickMenu`
- **7+ items or expandable groups** → `.selectionMenu`
- **User fills in fields** → `.form`
- **User picks from a list** → `.picker`
- **Full browse experience with search/filter** → `.fullSheet`

## Rules

- **Never set detents inline.** Always use `.sheetStyle(...)`.
- **`.confirmationDialog()` — destructive confirmations only.** "Delete? Cancel / Confirm" prompts. Not for action menus or pickers.
- **Never use:** `.popover()` (floats on iPad, inconsistent with bottom-sheet convention) or `.fullScreenCover()` (unless explicitly justified — e.g., image gallery, camera).
- **Extract reusable sheet components.** Don't inline sheet content.
- **Sheet-on-sheet sequencing.** Dismiss the first sheet and use `onDismiss` or `.onChange(of:)` to trigger the next. Don't stack sheets.
