#Requires AutoHotkey v2.0
#Warn VarUnset, StdOut
#Include ..\lib\Core.ahk
#Include ..\lib\TextTools.ahk
#Include ..\lib\Punto.ahk
#Include ..\lib\Paste.ahk
#Include ..\lib\Rich.ahk

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
    Verify(KweetyText.Layout("Ghbdtn, vbh!") == "Приветб мир!", "layout conversion preserves typed case and key positions")
    Verify(KweetyText.Layout("привет") == "ghbdtn", "reverse layout")
    Verify(KweetyText.Layout("ЖЭБЮЁ") == ':"<>~', "shifted punctuation layout conversion")
    Verify(KweetyText.Case("привет мир") == "Привет Мир", "title case")
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
    KweetyStore.Save(testDir "\settings.ini", cfg)
    loaded := KweetyStore.Load(testDir "\settings.ini")
    Verify(loaded.Items[1].Rtf == rich.Rtf && loaded.Items[1].Html == rich.Html, "rich payload storage round trip")
    Verify(loaded.Excluded[2] == cfg.Excluded[2] && loaded.LayoutKey == cfg.LayoutKey, "exclusions and hotkeys storage round trip")
    legacyPath := testDir "\legacy.ini"
    legacy := "[Kweety]`r`nVersion=1`r`nCount=1`r`nEnabled=1`r`nSpace=1`r`nEnter=1`r`nTab=0`r`n[Snippet1]`r`nTrigger=fff`r`nText=" KweetyCore.Encode("Старый шаблон") "`r`n"
    FileAppend(legacy, legacyPath, "UTF-16")
    legacyLoaded := KweetyStore.Load(legacyPath)
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
    FileDelete(testDir "\settings.ini")
    DirDelete(testDir)
    ; Fixed independent fixture generated from the documented PSRF algorithm.
    fixture := A_ScriptDir "\fixtures\punto-replace.dat"
    imported := KweetyPunto.Read(fixture)
    Verify(imported.Length = 2 && imported[1].Trigger == "zz", "PSRF record decoding")
    Verify(imported[1].Text == "Привет`nмир😀", "PSRF multiline Unicode decoding")
    merge := KweetyPunto.Merge([{Trigger: "яя", Text: "Existing"}], imported)
    Verify(merge.Added = 1 && merge.Skipped.Length = 1, "import conflicts across layouts do not overwrite")
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
