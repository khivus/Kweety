#Requires AutoHotkey v2.0
#Include ..\lib\Core.ahk

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
    longText := ""
    Loop 12000
        longText .= "Я😀 "
    cfg := KweetyStore.Defaults()
    cfg.Items[1].Text := longText "`nВторая строка"
    path := A_Temp "\Kweety-test-" DllCall("GetCurrentProcessId") "\settings.ini"
    KweetyStore.Save(path, cfg)
    loaded := KweetyStore.Load(path)
    Assert(loaded.Items[1].Text == cfg.Items[1].Text, "long text persistence beyond INI API limit")
    Assert(loaded.Enter && loaded.Space && !loaded.Tab, "default keys persisted")
    loaded.Tab := 1
    loaded.Enabled := 0
    KweetyStore.Save(path, loaded)
    Assert(FileExist(path ".bak"), "backup created")
    Assert(!KweetyStore.Load(path).Enabled && KweetyStore.Load(path).Tab, "options persisted")
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
    FileAppend("PASS: " checks " checks`n", "*", "UTF-8")
    ExitApp(0)
} catch as err {
    FileAppend(err.Message "`n" err.Stack "`n", "**", "UTF-8")
    ExitApp(1)
}
