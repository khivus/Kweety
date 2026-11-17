#Requires AutoHotkey v2.0
#ClipboardTimeout 50
#Include ..\lib\Paste.ahk
#Include ..\lib\Rich.ahk

; Explicit integration check. No target windows or keyboard input are used.
; It briefly sets demo data, then restores the original multi-format clipboard.
original := ClipboardAll()
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
    history := KweetyHistory()
    history.Items := []
    A_Clipboard := "Kweety history A"
    Sleep(100)
    A_Clipboard := "Kweety history B"
    Sleep(100)
    if history.Items.Length != 2
        throw Error("Clipboard observer did not record two external copies")
    if !paste.Prepare("Internal expansion")
        throw Error("Cannot prepare internal expansion")
    Sleep(100)
    paste.Restore()
    Sleep(100)
    if history.Items.Length != 2
        throw Error("Internal clipboard changes polluted history")
    saved := ClipboardAll()
    paste.SeedOriginal(saved)
    paste.Clipboard.Restore(history.Get(2))
    paste.Expected := paste.Clipboard.Sequence()
    if A_Clipboard != "Kweety history A"
        throw Error("Second newest clipboard entry was not restored")
    paste.Restore()
    Sleep(100)
    if A_Clipboard != "Kweety history B" || history.Items.Length != 2
        throw Error("History paste changed current clipboard or history ordering")
    OnClipboardChange(history.Handler, 0)
    paste.Clipboard.Restore(original)
    FileAppend("PASS: Windows clipboard Unicode + HTML + RTF; history ordering and internal change suppression; original clipboard restored`n", "*", "UTF-8")
    ExitApp(0)
} catch as err {
    paste.Restore()
    try paste.Clipboard.Restore(original)
    FileAppend(err.Message "`n" err.Stack "`n", "**", "UTF-8")
    ExitApp(1)
}
