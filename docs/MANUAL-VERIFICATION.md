# Manual verification

Automated checks cover storage, text compilation, clipboard ownership and retry,
rich-text conversion, shortcut composition, layout geometry, and startup. They
do not establish compatibility with Mail.ru or any other live editor.

Use the newly built `dist/Kweety.exe` or run `Kweety.ahk` with AutoHotkey v2.

- With EVE-X-Preview and the other AHK app running, enable Kweety's Alt+Shift
  layout switching. In an external editor, switch with left Alt and either Shift,
  trying both press and release orders. The language should change once, focus
  should stay in the editor, and no menu should open. Check that EVE-X-Preview's
  normal window-switching shortcuts still work.

- Open shortcut settings. Assign Ctrl+Shift+F to template search by selecting Ctrl,
  Shift, and F; save and use it in an external editor. Search should open. Select
  a template and insert it: focus should return to the original editor.
- Reopen settings and restart Kweety: the shortcut should remain assigned. Try
  assigning it to another command too: saving should reject the duplicate. Clear
  it and save: the command should stop responding to that shortcut. Check an
  existing Ctrl+Alt shortcut and a standalone function key as regressions.
- Resize and maximize/restore the main window, new/edit template window,
  shortcut/exclusion settings, and template picker. Lists, search fields, text
  areas and the exclusion field should expand; bottom actions should remain
  visible. Shrink to the minimum size: controls should not overlap.
- Open Import Punto and select a replace.dat file. Resize the preview: the
  template list and text previews should expand and the import buttons remain
  reachable. Cancel: existing templates and settings should remain unchanged.
- In a Mail.ru draft, test short, multiline, and long templates with Ctrl+V on.
  Type each abbreviation followed by Space, then repeat with Enter and enabled
  Tab. The abbreviation should disappear and the complete text appear once;
  the draft should not be sent. Check blank lines, emoji and literal `{Enter}!^+#`.
- Repeat in Mail.ru with Ctrl+V off, including a saved formatted template. Text
  should appear without formatting, line breaks should remain, and embedded
  tabs should not move focus out of the message. Repeat several times to check
  the reported intermittent failure. Do not type while a template is being sent.
- With Ctrl+V on, insert a colored/bold template into a rich-text draft: supported
  formatting should remain. With it off, the same template should be plain text.
  Reopen the template: the saved formatting should still be present.
- Copy unrelated text before expanding a template in clipboard mode. After two
  seconds, paste elsewhere: the original copied text should return. Repeat while
  copying new text during those two seconds: the new copy should win. Also test
  consecutive expansions and confirm that the original clipboard is restored.
- Test layout correction and case conversion on selected text and the last word
  with no selection. The correct text should replace the selection/word and the
  clipboard should recover. Test Ctrl+Shift combinations for these commands too.
- Repeat basic insertion in another editor. Pause Kweety and test an excluded
  program: abbreviations and feature shortcuts should remain inactive. Resume
  and remove the exclusion: both should work again. Confirm the insertion mode
  survives restart, tray reopening still works, and editing/search/deleting works.

If Mail.ru still fails, record the browser/version, insertion mode, template
format, and whether the trigger remains, disappears, or leaves partial text.
