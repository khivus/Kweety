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
    Sleep(250)
    history.Items := []
    for index, value in ["Kweety history A", "Kweety history B", "Kweety history C"] {
        A_Clipboard := value
        deadline := A_TickCount + 1000
        while history.Items.Length < index && A_TickCount < deadline
            Sleep(20)
        if history.Items.Length != index
            throw Error("Clipboard observer did not record copy " index)
    }
    A_Clipboard := "Kweety history C"
    Sleep(250)
    if history.Items.Length != 3
        throw Error("Repeated newest clipboard content shifted history indexes")
    if !paste.Prepare("Internal expansion")
        throw Error("Cannot prepare internal expansion")
    Sleep(100)
    paste.Restore()
    Sleep(100)
    if history.Items.Length != 3
        throw Error("Internal clipboard changes polluted history")
    for index, expected in ["Kweety history C", "Kweety history B", "Kweety history A"] {
        paste.SeedOriginal(ClipboardAll())
        paste.Clipboard.Restore(history.Get(index))
        paste.Expected := paste.Clipboard.Sequence()
        if A_Clipboard != expected
            throw Error("Wrong clipboard entry at history index " index)
        paste.Restore()
        Sleep(100)
        if A_Clipboard != "Kweety history C" || history.Items.Length != 3
            throw Error("History paste changed current clipboard or history ordering")
    }
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
