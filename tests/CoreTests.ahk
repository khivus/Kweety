#Warn VarUnset, StdOut
#Requires AutoHotkey v2.0
#Include ..\lib\Core.ahk
#Include ..\lib\Paste.ahk
#Include ..\lib\Startup.ahk
#Include ..\lib\Rich.ahk

class FakeClipboard {
    Value := "original clipboard"
    Serial := 1
    Captures := 0
    Busy := false
    Capture() {
        if this.Busy
            throw Error("busy")
        this.Captures += 1
        return this.Value
    }
    Sequence() => this.Serial
    Write(value) {
        if this.Busy
            throw Error("busy")
        this.Value := value
        this.Serial += 1
    }
    Restore(value) => this.Write(value)
}

checks := 0
Assert(condition, label) {
    global checks
    if !condition
        throw Error("FAIL: " label)
    checks += 1
}
Throws(callback, label) {
    failed := false
    try callback.Call()
    catch
        failed := true
    Assert(failed, label)
}

try {
    Assert(KweetyCore.Aliases("fff")[2] = "ааа", "English to Russian")
    Assert(KweetyCore.Aliases("ааа")[2] = "fff", "Russian to English")
    Assert(KweetyCore.Aliases("FFF")[1] = "fff", "case insensitive")
    Assert(KweetyCore.Aliases("ё")[2] = Chr(96), "backtick layout key")
    Assert(KweetyCore.Aliases("жэбю")[2] = ";',.", "punctuation layout keys")
    Assert(KweetyCore.Aliases("123_-").Length = 1, "identical aliases deduplicated")
    Throws(() => KweetyCore.Validate([{Trigger: "fff", Text: "a"}, {Trigger: "ааа", Text: "b"}]), "layout collision")
    Throws(() => KweetyCore.Validate([{Trigger: "FFF", Text: "a"}, {Trigger: "fff", Text: "b"}]), "case collision")
    for trigger in ["", "two words", "a:b", "{Enter}", "a`t", "a`n"]
        Throws(() => KweetyCore.Validate([{Trigger: trigger, Text: "a"}]), "invalid abbreviation")
    Throws(() => KweetyCore.Validate([{Trigger: "x", Text: ""}]), "empty body")
    literal := "Привет {Enter} !^+# = \n`t😀"
    Assert(KweetyCore.Decode(KweetyCore.Encode(literal)) == literal, "UTF8 literal round trip")
    Throws(() => KweetyCore.Decode("FFF"), "odd hex rejected")
    Throws(() => KweetyCore.Decode("GG"), "invalid hex rejected")
    plan := KweetyCore.Plan("`r`nПервый`r`n`rВторой`n")
    breaks := 0
    for step in plan {
        if step.Kind = "key" {
            Assert(step.Value == "+{Enter}", "only Shift+Enter is generated")
            breaks += 1
        } else
            Assert(!InStr(step.Value, "`n") && !InStr(step.Value, "`r"), "no newlines in SendText")
    }
    Assert(breaks = 4, "leading trailing and blank lines preserved")
    Assert(KweetyCore.Plan(literal)[1].Value == literal, "command syntax remains literal")
    Assert(KweetyCore.CompileSend("AЯ") == "{U+0041}{U+042F}", "compile literal Unicode")
    Assert(KweetyCore.CompileSend("a`r`n`nb`n") == "{U+0061}+{Enter}+{Enter}{U+0062}+{Enter}", "compiled line endings are Shift+Enter")
    Assert(KweetyCore.CompileSend("`t") == "{Tab}", "tab compatibility")
    encoded := KweetyCore.CompileSend("{Enter}!^+#")
    Assert(!InStr(encoded, "{Enter}"), "literal Enter cannot become a key")
    Assert(!InStr(encoded, "!^+#"), "literal modifiers cannot become shortcuts")
    Assert(KweetyCore.CompileSend("😀") == "{U+D83D}{U+DE00}", "emoji UTF16 surrogate pair preserved")
    Assert(KweetyCore.CompileBatches("a`nб")[1] == KweetyCore.CompileSend("a`nб"), "short template is a single batch")
    boundaryText := ""
    Loop 999
        boundaryText .= "a"
    batches := KweetyCore.CompileBatches(boundaryText "😀z")
    Assert(batches.Length = 2, "long template bounded batches")
    Assert(SubStr(batches[1], -16) == "{U+D83D}{U+DE00}", "surrogate pair stays in one batch")
    joined := ""
    for batch in batches
        joined .= batch
    Assert(joined == KweetyCore.CompileSend(boundaryText "😀z"), "batching loses no characters")
    for text in ["a`nb", "a`rb", "a`tb", "a`bb"]
        Assert(KweetyPaste.CanPaste(text), "multiline and control text uses bulk paste")
    Assert(!KweetyPaste.CanPaste(""), "empty clipboard payload rejected")
    Assert(KweetyPaste.ClipboardText("`nа`r`n`rб`n") == "`r`nа`r`n`r`nб`r`n", "all newline styles normalized without losing blank or trailing lines")
    Assert(KweetyPaste.ClipboardText("{Enter}!^+#`t😀") == "{Enter}!^+#`t😀", "clipboard special symbols remain literal")
    Assert(KweetyPaste.PasteKeys(3) == "{Backspace 3}^v", "bulk path sends only erase and one paste")
    Throws(() => KweetyPaste.PasteKeys(0), "invalid erase count rejected")
    clip := FakeClipboard()
    paste := KweetyPaste(clip)
    Assert(paste.Prepare(literal), "tab-containing literal uses bulk paste")
    Assert(clip.Value == literal, "tab and emoji clipboard content preserved")
    Assert(paste.Prepare("Привет {Enter}!^+#"), "single line fast paste prepared")
    Assert(clip.Value == "Привет {Enter}!^+#", "fast paste content stays literal")
    Assert(paste.Prepare("next expansion") && clip.Captures = 1, "overlapping expansions retain original clipboard")
    Assert(paste.Restore() && clip.Value == "original clipboard", "original clipboard restored")
    Assert(!paste.Pending && paste.Saved == "", "clipboard snapshot released")
    multiline := "`nПривет`r`n`r{Enter}!^+#😀`n"
    Assert(paste.Prepare(multiline), "multiline template uses bulk paste")
    Assert(clip.Value == KweetyPaste.ClipboardText(multiline), "entire multiline template written as one clipboard value")
    Assert(paste.Restore() && clip.Value == "original clipboard", "clipboard restored after multiline paste")
    paste.Prepare("template")
    clip.Write("user copied this")
    paste.Restore()
    Assert(clip.Value == "user copied this", "new user clipboard never overwritten")
    clip.Busy := true
    Assert(!paste.Prepare("busy"), "busy clipboard aborts before typing")
    Assert(clip.Value == "user copied this", "failed preparation leaves clipboard unchanged")
    clip.Busy := false
    longText := ""
    Loop 12000
        longText .= "Я😀 "
    Assert(paste.Prepare(longText "`nВторая строка"), "long multiline template accepted for bulk paste")
    Assert(clip.Value == longText "`r`nВторая строка", "long multiline clipboard content is not truncated")
    paste.Restore()
    cfg := KweetyStore.Defaults()
    cfg.Items[1].Text := longText "`nВторая строка"
    path := A_Temp "\Kweety-test-" DllCall("GetCurrentProcessId") "\settings.ini"
    KweetyStore.Save(path, cfg)
    loaded := KweetyStore.Load(path)
    Assert(loaded.Items[1].Text == cfg.Items[1].Text, "long text persistence beyond INI API limit")
    Assert(loaded.Enter && loaded.Space && !loaded.Tab, "default keys persisted")
    Assert(loaded.FastPaste, "fast paste defaults on")
    loaded.Tab := 1
    loaded.Enabled := 0
    loaded.FastPaste := 0
    KweetyStore.Save(path, loaded)
    Assert(FileExist(path ".bak"), "backup created")
    Assert(!KweetyStore.Load(path).Enabled && KweetyStore.Load(path).Tab, "options persisted")
    Assert(!KweetyStore.Load(path).FastPaste, "fast paste toggle persisted")
    legacy := StrReplace(FileRead(path), "FastPaste=0`r`n", "")
    legacyFile := FileOpen(path, "w", "UTF-16")
    legacyFile.Write(legacy)
    legacyFile.Close()
    Assert(KweetyStore.Load(path).FastPaste, "old settings enable fast paste without migration loss")
    loaded.Space := 0
    loaded.Enter := 0
    loaded.Tab := 0
    Throws(() => KweetyStore.Save(path, loaded), "no trigger keys rejected")
    Assert(KweetyStore.Load(path).Tab, "invalid save leaves old config intact")
    FileDelete(path)
    FileAppend("[Kweety]`nVersion=9", path, "UTF-16")
    Throws(() => KweetyStore.Load(path), "corrupt config rejected")
    FileDelete(path)
    FileDelete(path ".bak")
    SplitPath(path, , &dir)
    DirDelete(dir)
    startupDir := A_Temp "\Kweety-startup-test-" DllCall("GetCurrentProcessId")
    DirCreate(startupDir)
    startupLink := startupDir "\Kweety.lnk"
    command := KweetyStartup.MakeCommand(false, "C:\Folder With Spaces\Kweety.ahk", A_AhkPath)
    Assert(command.Target == A_AhkPath, "source startup uses AHK v2 interpreter")
    Assert(command.Args == '"C:\Folder With Spaces\Kweety.ahk" --background', "source startup quotes path and starts in tray")
    exeCommand := KweetyStartup.MakeCommand(true, "C:\Folder With Spaces\Kweety.exe", A_AhkPath)
    Assert(exeCommand.Target == "C:\Folder With Spaces\Kweety.exe" && exeCommand.Args == "--background", "compiled startup starts executable in tray")
    startup := KweetyStartup(startupLink, command)
    Assert(!startup.IsEnabled(), "startup initially disabled")
    startup.SetEnabled(true)
    FileGetShortcut(startupLink, &target, &workingDir, &args)
    Assert(startup.IsEnabled() && target == command.Target && args == command.Args, "startup shortcut round trip")
    Assert(workingDir == command.Directory, "startup working directory retained")
    startup.SetEnabled(true)
    Assert(!FileExist(startupLink ".tmp.lnk"), "startup update cleans temporary link")
    startup.SetEnabled(false)
    Assert(!startup.IsEnabled(), "startup disable removes only application shortcut")
    startup.SetEnabled(false)
    DirDelete(startupDir)
    FileAppend("PASS: " checks " checks`n", "*", "UTF-8")
    ExitApp(0)
} catch as err {
    FileAppend(err.Message "`n" err.Stack "`n", "**", "UTF-8")
    ExitApp(1)
}
