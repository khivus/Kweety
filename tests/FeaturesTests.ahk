#Requires AutoHotkey v2.0
#Warn VarUnset, StdOut
#Include ..\lib\Core.ahk
#Include ..\lib\TextTools.ahk
#Include ..\lib\Punto.ahk
#Include ..\lib\Paste.ahk
#Include ..\lib\Rich.ahk
#Include ..\lib\Shortcut.ahk
#Include ..\lib\Layout.ahk
#Include ..\lib\InputLanguage.ahk

count := 0
Verify(value, message) {
    global count
    if !value
        throw Error(message)
    count += 1
}
Reject(call, message) {
    failed := false
    try call.Call()
    catch
        failed := true
    Verify(failed, message)
}
try {
    ; VK_LMENU, VK_LSHIFT, and VK_RSHIFT exercise both press and release orders.
    for shift in [0xA0, 0xA1] {
        for pressOrder in [[0xA4, shift], [shift, 0xA4]] {
            for releaseOrder in [[0xA4, shift], [shift, 0xA4]] {
                inputLanguage := KweetyInputLanguage()
                Verify(inputLanguage.Track(pressOrder[1], false) = "", "first modifier passes through")
                Verify(inputLanguage.Track(pressOrder[2], false) = "mask", "second modifier masks Alt")
                Verify(inputLanguage.Track(pressOrder[2], false) = "", "repeat does not rearm layout switch")
                Verify(inputLanguage.Track(releaseOrder[1], true) = "switch", "switch on first modifier release")
                Verify(inputLanguage.Track(releaseOrder[2], true) = "", "second release does not switch again")
            }
        }
    }
    inputLanguage.Track(0xA4, false), inputLanguage.Track(0xA0, false)
    inputLanguage.Track(0x09, false)  ; Alt+Shift+Tab must keep its usual meaning.
    Verify(inputLanguage.Track(0xA0, true) = "" && inputLanguage.Track(0xA4, true) = "", "third key cancels switch")
    inputLanguage.Track(0xA0, false)
    Verify(inputLanguage.Track(0xA5, false) = "" && inputLanguage.Track(0xA0, true) = "", "right Alt is excluded")
    Verify(KweetyShortcut.Normalize("+^F") == "^+f", "Ctrl Shift F accepted and canonicalized")
    Verify(KweetyShortcut.Normalize("!а") == "!f" && KweetyShortcut.Normalize("!в") == "!d", "legacy Cyrillic shortcuts use their physical letter keys")
    Verify(KweetyShortcut.Binding("^+f") == "$^+vk46", "letter shortcut registration uses a layout-independent key code")
    Verify(KweetyShortcut.Normalize("!^f") == KweetyShortcut.Normalize("^!F"), "modifier order does not bypass duplicate detection")
    Verify(KweetyShortcut.Normalize("#f8") == "#f8", "Windows modifier supported")
    Verify(KweetyShortcut.Normalize("^Esc") == KweetyShortcut.Normalize("^Escape"), "key aliases canonicalized for duplicate detection")
    Reject(() => KweetyShortcut.Normalize("+f"), "Shift alone cannot replace ordinary typing")
    Reject(() => KweetyShortcut.Normalize("^Ctrl"), "modifier cannot be the main key")
    history := KweetyHistory(false)
    firstCopy := Buffer(10), secondCopy := Buffer(20), thirdCopy := Buffer(30)
    history.Remember(firstCopy), history.Remember(secondCopy), history.Remember(thirdCopy)
    Verify(history.Get(2) = secondCopy && history.Get(3) = firstCopy, "history indexes newest first")
    Verify(history.Get(2) = secondCopy, "reading history never reorders entries")
    Reject(() => history.Get(4), "missing history entry rejected")
    Loop 25
        history.Remember(Buffer(A_Index))
    Verify(history.Items.Length = 20 && history.Get(20).Size = 6, "history retains latest twenty entries")
    shortcutGui := Gui()
    shortcut := KweetyShortcut(shortcutGui, "^+f")
    Verify(shortcut.Value == "^+f", "explicit modifier controls round trip Ctrl Shift F")
    shortcut.Clear()
    Verify(shortcut.Value == "", "shortcut can be disabled")
    shortcutGui.Destroy()
    layoutGui := Gui()
    area := layoutGui.AddEdit("w540 h160")
    footer := layoutGui.AddButton("xm y+10 w140", "Save")
    layout := KweetyLayout.Enable(layoutGui, area)
    footer.GetPos(, &footerY)
    layout.Resize(layoutGui, 0, layout.Width + 200, layout.Height + 100)
    area.GetPos(, , &areaW, &areaH)
    footer.GetPos(, &movedY)
    Verify(areaW = 740 && areaH = 260 && movedY = footerY + 100, "resize grows content and anchors footer")
    layout.Resize(layoutGui, 0, layout.Width, layout.Height - 80)
    area.GetPos(, , &areaW, &areaH)
    Verify(areaW = 540 && areaH = 80, "resize can shrink workspace without accumulated drift")
    layoutGui.Destroy()
    Verify(KweetyText.Layout("Ghbdtn, vbh!") == "Приветб мир!", "layout conversion preserves typed case and key positions")
    Verify(KweetyText.Layout("привет") == "ghbdtn", "reverse layout")
    Verify(KweetyText.Layout("ЖЭБЮЁ") == ':"<>~', "shifted punctuation layout conversion")
    preview := KweetyRich.Preview(KweetyRich.FromRuns([
        {Text: "first`n", Color: "FF0000", Bold: true, Italic: false, Underline: false},
        {Text: "second`nthird", Color: "0000FF", Bold: false, Italic: true, Underline: true}]))
    Verify(preview.Text == "first ↵ second ↵ third", "preview preserves all lines inline")
    Verify(InStr(preview.Rtf, "\red255\green0\blue0;") && InStr(preview.Rtf, "\red0\green0\blue255;"), "preview preserves run colors")
    Verify(KweetyText.InvertCase("aB Яё! 123") == "Ab яЁ! 123", "invert mixed Latin and Cyrillic case")
    Verify(KweetyText.Case("привет мир") == "ПРИВЕТ МИР", "lowercase switches directly to uppercase")
    Verify(KweetyText.Case("Привет Мир") == "ПРИВЕТ МИР", "upper case")
    Verify(KweetyText.Case("ПРИВЕТ МИР") == "привет мир", "lower case")
    Verify(KweetyText.Excluded(["Discord.exe"], "DISCORD.EXE"), "case independent executable exclusion")
    Verify(!KweetyText.Excluded(["code.exe"], "notcode.exe"), "exclusions are exact")
    Verify(KweetyText.Matches({Trigger: "fff", Text: "Тестовый ответ"}, "ааа"), "search alternate layout")
    Verify(KweetyText.Matches({Trigger: "fff", Text: "Тестовый ответ"}, "ОТВЕТ"), "search full text insensitive")
    html := '<div style="color:rgb(255,0,0)"><b>ВНИМАНИЕ &amp; &#128512;</b><br><i>Вторая строка</i></div><script>alert(1)</script>'
    rich := KweetyRich.FromRuns(KweetyRich.HtmlRuns(html))
    Verify(InStr(rich.Text, "ВНИМАНИЕ & 😀"), "HTML entity and emoji import")
    Verify(!InStr(rich.Text, "alert"), "HTML scripts discarded")
    Verify(rich.Text == "ВНИМАНИЕ & 😀`nВторая строка", "HTML import does not invent a trailing line")
    Verify(InStr(rich.Rtf, "\red255\green0\blue0;"), "red RTF color")
    Verify(InStr(rich.Html, "font-weight:bold") && InStr(rich.Html, "font-style:italic"), "HTML bold italic output")
    packet := KweetyRich.ClipboardHtml(rich.Html)
    RegExMatch(packet, "StartFragment:(\d+)", &start)
    RegExMatch(packet, "EndFragment:(\d+)", &finish)
    bytes := Buffer(StrPut(packet, "UTF-8"))
    StrPut(packet, bytes, "UTF-8")
    Verify(StrGet(bytes.Ptr + Integer(start[1]), Integer(finish[1]) - Integer(start[1]), "UTF-8") == rich.Html, "CF_HTML UTF8 byte offsets")
    hidden := Gui()
    nativeEditor := KweetyRichEdit(hidden, "w600 h240", rich)
    exported := nativeEditor.Export()
    Verify(InStr(exported.Text, "ВНИМАНИЕ & 😀"), "native RichEdit Unicode stream round trip")
    Verify(InStr(exported.Html, "color:#FF0000"), "native RichEdit red format preserved")
    Verify(InStr(exported.Html, "font-weight:bold") && InStr(exported.Html, "font-style:italic"), "native RichEdit bold and italic preserved")
    Verify(!nativeEditor.Dirty(), "export does not dirty unchanged document")
    range := Buffer(8, 0)
    NumPut("Int", 0, "Int", 4, range)
    SendMessage(0x437, 0, range, nativeEditor.Hwnd)
    nativeEditor.Format("underline")
    nativeEditor.Format("color", "0000FF")
    changed := nativeEditor.Export()
    Verify(InStr(changed.Html, "color:#0000FF") && InStr(changed.Html, "text-decoration:underline"), "editor applies selected color and underline")
    Verify(nativeEditor.Dirty(), "format-only change marks editor dirty")
    plainEditor := KweetyRichEdit(hidden, "w500 h100", {Text: "Первая`r`n`r`nВторая 😀"})
    plainExport := plainEditor.Export()
    Verify(plainExport.Text == "Первая`n`nВторая 😀", "plain template editing preserves blank lines and Unicode")
    hidden.Destroy()
    testDir := A_Temp "\Kweety-features-" DllCall("GetCurrentProcessId")
    DirCreate(testDir)
    cfg := KweetyStore.Defaults()
    cfg.Items[1] := rich
    cfg.Items[1].Trigger := "warn"
    cfg.Excluded := ["Discord.exe", "C:\Тест\Редактор.exe"]
    cfg.LayoutKey := "^!F8"
    cfg.Items[1].Formatting := true
    cfg.InvertCaseKey := "^!i"
    KweetyStore.Save(testDir "\settings.ini", cfg)
    loaded := KweetyStore.Load(testDir "\settings.ini")
    Verify(!loaded.AltShiftSwitch, "Alt+Shift switching is off by default")
    cfg.Immediate := 1, cfg.Space := 0, cfg.Enter := 0, cfg.Tab := 0
    cfg.AltShiftSwitch := 1
    cfg.HistoryKey1 := "^!2", cfg.HistoryIndex1 := 7
    KweetyStore.Save(testDir "\immediate.ini", cfg)
    instant := KweetyStore.Load(testDir "\immediate.ini")
    Verify(instant.AltShiftSwitch = 1, "Alt+Shift opt-in persists")
    Verify(instant.Immediate && !instant.Space && !instant.Enter && !instant.Tab, "immediate expansion works without terminators")
    Verify(instant.HistoryKey1 == "^!2" && instant.HistoryIndex1 = 7, "arbitrary history index and shortcut persist")
    cfg.Immediate := 0
    Reject(() => KweetyStore.Save(testDir "\invalid.ini", cfg), "terminator required when immediate mode off")
    cfg.Space := 1
    cfg.HistoryIndex1 := 21
    Reject(() => KweetyStore.Save(testDir "\invalid.ini", cfg), "out of range history index rejected")
    cfg.HistoryIndex1 := 7
    Verify(loaded.Items[1].Formatting && loaded.InvertCaseKey == "^!i", "formatting opt-in and inversion shortcut persist")
    Verify(loaded.Items[1].Rtf == rich.Rtf && loaded.Items[1].Html == rich.Html, "rich payload storage round trip")
    Verify(loaded.Excluded[2] == cfg.Excluded[2] && loaded.LayoutKey == cfg.LayoutKey, "exclusions and hotkeys storage round trip")
    legacyPath := testDir "\legacy.ini"
    legacy := "[Kweety]`r`nVersion=1`r`nCount=1`r`nEnabled=1`r`nSpace=1`r`nEnter=1`r`nTab=0`r`n[Snippet1]`r`nTrigger=fff`r`nText=" KweetyCore.Encode("Старый шаблон") "`r`n"
    FileAppend(legacy, legacyPath, "UTF-16")
    legacyLoaded := KweetyStore.Load(legacyPath)
    Verify(!legacyLoaded.AltShiftSwitch, "legacy settings do not opt in")
    Verify(legacyLoaded.Items[1].Text == "Старый шаблон" && legacyLoaded.LayoutKey == "" && legacyLoaded.CaseKey == "" && legacyLoaded.MenuKey == "" && legacyLoaded.Excluded.Length = 0, "old v1 configuration does not assign hotkeys")
    assigned := StrReplace(FileRead(testDir "\settings.ini"), "HotkeysOptIn=1`r`n", "")
    assigned := RegExReplace(assigned, "m)^LayoutKey=[^\r\n]*", "LayoutKey=" KweetyCore.Encode("^!l"))
    assigned := RegExReplace(assigned, "m)^CaseKey=[^\r\n]*", "CaseKey=" KweetyCore.Encode("^!u"))
    assigned := RegExReplace(assigned, "m)^MenuKey=[^\r\n]*", "MenuKey=" KweetyCore.Encode("^!Space"))
    legacyFile := FileOpen(legacyPath, "w", "UTF-16")
    legacyFile.Write(assigned)
    legacyFile.Close()
    legacyLoaded := KweetyStore.Load(legacyPath)
    Verify(legacyLoaded.LayoutKey == "" && legacyLoaded.CaseKey == "" && legacyLoaded.MenuKey == "", "previous default assignments removed on upgrade")
    cfg.LayoutKey := "^!l"
    KweetyStore.Save(legacyPath, cfg)
    Verify(KweetyStore.Load(legacyPath).LayoutKey == "^!l", "explicit later hotkey assignment retained")
    FileDelete(legacyPath)
    FileDelete(legacyPath ".bak")
    preferencesPath := testDir "\preferences.xml"
    FileAppend('<PuntoSwitcherSettings version="7"><RunAtStartup>Yes</RunAtStartup><ReplaceOnSpace>No</ReplaceOnSpace><ReplaceOnEnterAndTab>Yes</ReplaceOnEnterAndTab><ProgramsExceptions>code.exe;Discord.exe</ProgramsExceptions></PuntoSwitcherSettings>', preferencesPath, "UTF-8")
    preferences := KweetyPunto.Preferences(preferencesPath)
    Verify(preferences.Startup = 1 && !preferences.Keys["Space"] && preferences.Keys["Enter"] && preferences.Keys["Tab"], "compatible Punto preferences decoded")
    Verify(preferences.Excluded.Length = 2 && preferences.Excluded[2] == "Discord.exe", "plain executable exclusions decoded")
    FileDelete(preferencesPath)
    FileAppend('<!DOCTYPE x [<!ENTITY x SYSTEM "file:///C:/not-allowed">]><PuntoSwitcherSettings>&x;</PuntoSwitcherSettings>', preferencesPath, "UTF-8")
    Reject(() => KweetyPunto.Preferences(preferencesPath), "external XML entities rejected")
    FileDelete(preferencesPath)
    FileDelete(testDir "\immediate.ini")
    FileDelete(testDir "\settings.ini")
    DirDelete(testDir)
    ; Fixed independent fixture generated from the documented PSRF algorithm.
    fixture := A_ScriptDir "\fixtures\punto-replace.dat"
    imported := KweetyPunto.Read(fixture)
    Verify(imported.Length = 2 && imported[1].Trigger == "zz", "PSRF record decoding")
    Verify(imported[1].Text == "Привет`nмир😀", "PSRF multiline Unicode decoding")
    merge := KweetyPunto.Merge([{Trigger: "яя", Text: "Existing"}], imported)
    Verify(merge.Added = 1 && merge.Skipped.Length = 1, "import conflicts across layouts do not overwrite")
    starter := KweetyStore.Defaults().Items
    merge := KweetyPunto.Merge(starter, imported)
    Verify(merge.RemovedStarter = 1 && merge.Added = 2 && merge.Items.Length = 2, "import replaces demo and counts only incoming templates")
    Verify(starter.Length = 1 && starter[1].Text == "тестовый текст", "preview leaves current templates intact for cancellation")
    merge := KweetyPunto.Merge(starter, [{Trigger: "ааа", Text: "Imported replacement"}])
    Verify(merge.Added = 1 && !merge.Skipped.Length && merge.Items[1].Text == "Imported replacement", "demo aliases do not block Punto templates")
    merge := KweetyPunto.Merge([{Trigger: "fff", Text: "Custom text"}], [{Trigger: "ааа", Text: "Incoming"}])
    Verify(!merge.RemovedStarter && !merge.Added && merge.Skipped.Length = 1, "customized demo is preserved and conflicts still apply")
    merge := KweetyPunto.Merge([{Trigger: "fff", Text: "тестовый текст", Rtf: "custom formatting"}], imported)
    Verify(!merge.RemovedStarter && merge.Items.Length = 3, "formatted demo is user content")
    merge := KweetyPunto.Merge([{Trigger: "fff", Text: "Привет это тестовое сообщение"}], imported)
    Verify(merge.RemovedStarter = 1 && merge.Added = 2, "legacy demo removed during import")
    merge := KweetyPunto.Merge(starter, [])
    Verify(merge.Items.Length = 0 && merge.Added = 0, "empty import has no negative added count")
    cfg := KweetyStore.Defaults()
    cfg.Items := merge.Items
    persistencePath := A_Temp "\Kweety-import-" A_TickCount ".ini"
    try {
        KweetyStore.Save(persistencePath, cfg)
        Verify(KweetyStore.Load(persistencePath).Items.Length = 0, "removed demo does not reappear after restart")
    } finally {
        if FileExist(persistencePath)
            FileDelete(persistencePath)
    }
    bad := Buffer(4, 0)
    Reject(() => KweetyPunto.Decode(bad), "unknown Punto format rejected")
    raw := FileRead(fixture, "RAW")
    NumPut("UInt", 0xFFFFFFF0, raw, 4)
    Reject(() => KweetyPunto.Decode(raw), "truncated record rejected")
    FileAppend("PASS: " count " feature checks`n", "*", "UTF-8")
    ExitApp(0)
} catch as err {
    FileAppend(err.Message "`n" err.Stack "`n", "**", "UTF-8")
    ExitApp(1)
}
