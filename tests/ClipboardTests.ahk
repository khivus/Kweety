#Requires AutoHotkey v2.0
#ClipboardTimeout 50
#Include ..\lib\Paste.ahk
#Include ..\lib\Rich.ahk

; Explicit integration check. No target windows or keyboard input are used.
; It briefly sets demo data, then restores the original multi-format clipboard.
paste := KweetyPaste()
try {
    rich := KweetyRich.FromRuns([{Text: "Проверка 😀`nВторая строка", Color: "FF0000", Bold: true, Italic: true, Underline: false}])
    if !paste.Prepare(rich.Text, rich.Rtf, rich.Html)
        throw Error("Не удалось подготовить HTML/RTF-буфер.")
    if !(A_Clipboard == KweetyPaste.ClipboardText(rich.Text))
        throw Error("Обычный текст буфера не совпал.")
    html := KweetyWindowsClipboard.ReadFormat("HTML Format", "UTF-8")
    rtf := KweetyWindowsClipboard.ReadFormat("Rich Text Format", "CP0")
    if !InStr(html, rich.Html) || !InStr(rtf, "\red255\green0\blue0;")
        throw Error("HTML или RTF не прочитан из системного буфера.")
    if !paste.Restore()
        throw Error("Буфер занят при восстановлении.")
    FileAppend("PASS: Windows clipboard Unicode + HTML + RTF; original clipboard restored`n", "*", "UTF-8")
    ExitApp(0)
} catch as err {
    paste.Restore()
    FileAppend(err.Message "`n" err.Stack "`n", "**", "UTF-8")
    ExitApp(1)
}
