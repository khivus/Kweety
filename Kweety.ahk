#Requires AutoHotkey v2.0
#SingleInstance Force
#ClipboardTimeout 250
;@Ahk2Exe-SetName Kweety
;@Ahk2Exe-SetDescription Kweety - text expansion
;@Ahk2Exe-SetVersion 0.4.6
#Include lib\Core.ahk
#Include lib\Paste.ahk
#Include lib\Startup.ahk
#Include lib\TextTools.ahk
#Include lib\Punto.ahk
#Include lib\Rich.ahk
#Include lib\Shortcut.ahk
#Include lib\Layout.ahk
#Include lib\InputLanguage.ahk

SetWorkingDir(A_ScriptDir)
SendMode("Input")
; SendInput can fall back to SendEvent when another AHK keyboard hook is present.
SetKeyDelay(-1, -1)
SetTitleMatchMode(2)
try {
    app := KweetyApp()
    if A_Args.Length && A_Args[1] = "--smoke-test"
        app.SmokeTest()
} catch as err {
    if A_Args.Length && A_Args[1] = "--smoke-test"
        FileAppend(err.Message "`n" err.Stack "`n", "**", "UTF-8")
    else
        MsgBox("Не удалось запустить Kweety.`n`n" err.Message, "Kweety", "Iconx")
    ExitApp(1)
}
if A_Args.Length && A_Args[1] = "--smoke-test" {
    FileAppend("Startup and hotstring registration OK`n", "*", "UTF-8")
    ExitApp(0)
}
if !(A_Args.Length && A_Args[1] = "--background")
    app.Show()

class KweetyApp {
    __New() {
        this.Testing := A_Args.Length && A_Args[1] = "--smoke-test"
        this.Path := this.Testing ? (A_Args.Length >= 2 ? A_Args[2] : "") : A_AppData "\Kweety\settings.ini"
        reset := this.Testing ? (A_Args.Length >= 3 && A_Args[3] = "--reset-config")
            : (A_Args.Length && A_Args[1] = "--reset-config")
        this.Paste := KweetyPaste()
        this.InputLanguage := KweetyInputLanguage()
        this.History := false
        OnExit((*) => (this.Paste.Restore(), 0))
        this.Registered := []
        this.FeatureKeys := []
        this.VisibleItemIndices := Map()
        this.RichEditor := false
        this.CachedWindow := 0
        if !this.Testing
            this.History := KweetyHistory()
        this.Startup := KweetyStartup()
        ; Follow an explicitly enabled startup setting when the EXE is updated/moved.
        if !this.Testing && this.Startup.IsEnabled() {
            try this.Startup.SetEnabled(true)
            catch as err
                MsgBox("Не удалось обновить путь автозапуска.`n`n" err.Message, "Kweety", "Icon!")
        }
        this.Condition := (*) => this.Allowed()
        this.BuildGui()
        recovery := this.LoadStartupConfig(reset)
        this.ResetOptions()
        this.Refresh()
        this.EditorCondition := (*) => IsObject(this.RichEditor) && DllCall("GetFocus", "Ptr") = this.RichEditor.Hwnd
        HotIf(this.EditorCondition)
        Hotkey("^v", (*) => this.RichEditor.PasteFormatted())
        HotIf()
        A_TrayMenu.Delete()
        A_TrayMenu.Add("Открыть Kweety", (*) => this.Show())
        this.TrayLabel := "Состояние замены"
        A_TrayMenu.Add(this.TrayLabel, (*) => this.Toggle())
        A_TrayMenu.Add()
        A_TrayMenu.Add("Выход", (*) => this.CloseOptions(true))
        A_TrayMenu.Default := "Открыть Kweety"
        if !A_IsCompiled && FileExist(A_ScriptDir "\assets\Kweety.ico")
            TraySetIcon(A_ScriptDir "\assets\Kweety.ico")
        this.UpdateTray()
        if recovery != "" {
            if this.Testing
                FileAppend(recovery "`n", "*", "UTF-8")
            else
                MsgBox(recovery, "Kweety — сброс настроек", "Icon!")
        }
    }

    LoadStartupConfig(reset) {
        message := "Запрошен сброс настроек."
        if !reset {
            try {
                this.Config := this.Path = "" ? KweetyStore.Defaults() : KweetyStore.Load(this.Path)
                this.Apply()
                return ""
            } catch as err {
                message := "Не удалось применить настройки:`n" err.Message "`n`nФайл: " this.Path
            }
        }
        this.Config := KweetyStore.Defaults()
        this.Apply()
        message .= "`n`nKweety запущен с настройками по умолчанию."
        try {
            archive := KweetyStore.ArchiveForReset(this.Path)
            if archive != ""
                message .= "`nПрежние настройки и шаблоны сохранены:`n" archive
        } catch as err {
            message .= "`nНе удалось переместить прежний файл настроек:`n" err.Message
        }
        return message
    }

    BuildGui() {
        g := this.Window := Gui(, "Kweety 0.4.6")
        g.SetFont("s10", "Segoe UI")
        g.MarginX := 20
        g.MarginY := 16
        g.AddText("xm w730", "Пишите меньше. Говорите больше.")
        this.Enabled := g.AddCheckbox("xm y+14", "Замена сокращений включена")
        this.FastPaste := g.AddCheckbox("x+26 yp", "Вставлять весь текст целиком (Ctrl+V)")
        this.Autostart := g.AddCheckbox("xm y+12", "Запускать при входе в Windows, свернув в трей")
        g.AddText("xm y+18", "Заменять после нажатия:")
        this.Keys := Map()
        for i, entry in [["Space", "Пробел"], ["Enter", "Enter"], ["Tab", "Tab"]] {
            key := entry[1], label := entry[2]
            cb := g.AddCheckbox(i = 1 ? "xm y+10" : "x+24 yp", label)
            this.Keys[key] := cb
        }
        this.Immediate := g.AddCheckbox("xm y+12", "Сразу после последнего символа сокращения")
        this.Options := Map("Enabled", this.Enabled, "FastPaste", this.FastPaste, "Immediate", this.Immediate)
        for key, cb in this.Keys
            this.Options[key] := cb
        this.ModeHint := g.AddText("xm y+18 w730 c555555", "")
        g.AddText("xm y+14", "Поиск шаблонов:")
        this.Search := g.AddEdit("x+12 yp-3 w550")
        this.Search.OnEvent("Change", (*) => this.FillList())
        this.List := g.AddListView("xm y+12 w730 r8 -Multi", ["Сокращение", "В другой раскладке", "Текст"])
        this.List.ModifyCol(1, 130)
        this.List.ModifyCol(2, 170)
        this.List.ModifyCol(3, 405)
        this.List.OnEvent("DoubleClick", (*) => this.Edit())
        g.AddButton("xm y+12 w150 Default", "Добавить").OnEvent("Click", (*) => this.Edit(true))
        g.AddButton("x+10 w150", "Изменить").OnEvent("Click", (*) => this.Edit())
        g.AddButton("x+10 w120", "Удалить").OnEvent("Click", (*) => this.Delete())
        g.AddText("xm y+14 w730 c555555", "Двойной щелчок — изменить. Цвет и начертание доступны в редакторе шаблона.")
        this.Status := g.AddText("xm y+12 w730", "")
        g.AddButton("xm y+14 w120", "Горячие клавиши").OnEvent("Click", (*) => this.Settings())
        g.AddButton("x+10 w120", "Исключения").OnEvent("Click", (*) => this.Exclusions())
        g.AddButton("xm y+10 w150", "Папка настроек").OnEvent("Click", (*) => this.OpenData())
        g.AddButton("x+10 w140", "Импорт Punto").OnEvent("Click", (*) => this.ImportPunto())
        this.List.GetPos(&listLeft, , &listWidth)
        this.ApplyButton := g.AddButton("x" (listLeft + listWidth - 120 - 10 - 140) " yp w120", "Применить")
        close := g.AddButton("x+10 w140", "Свернуть в трей")
        this.ApplyButton.OnEvent("Click", (*) => this.SaveOptions())
        close.OnEvent("Click", (*) => this.CloseOptions())
        g.OnEvent("Close", (*) => this.CloseOptions())
        g.OnEvent("Escape", (*) => this.CloseOptions())
        for property, control in this.Options
            control.OnEvent("Click", (*) => this.UpdateOptionControls())
        this.Autostart.OnEvent("Click", (*) => this.UpdateOptionControls())
        this.TablePainter := KweetyTablePreview(g, this.List, this)
        KweetyLayout.Enable(g, this.List, this.ApplyButton, close)
    }

    Show() => this.Window.Show()

    SmokeTest() {
        previousX := -1, rowY := -1
        for key in ["Space", "Enter", "Tab"] {
            this.Keys[key].GetPos(&x, &y)
            if (rowY != -1 && y != rowY) || x <= previousX
                throw Error("Клавиши замены должны быть в одной строке: Пробел, Enter, Tab.")
            previousX := x, rowY := y
        }
        original := this.Config
        testConfig := this.CopyConfig()
        testConfig.LayoutKey := "^+f"
        testConfig.CaseKey := "^!F8"
        testConfig.InvertCaseKey := "^!F10"
        testConfig.MenuKey := "#+F9"
        testConfig.AltShiftSwitch := 1
        testConfig.HistoryKey1 := "", testConfig.HistoryKey2 := "", testConfig.HistoryKey3 := ""
        testConfig.Items := []
        Loop Parse "йцукенгшщзхъфывапролджэячсмитьбюё"
            testConfig.Items.Push({Trigger: A_LoopField, Text: "Тест`n{Enter}"})
        testConfig.Items.Push({Trigger: "hello", Text: "Z sort test"}, {Trigger: "café", Text: "A sort test"})
        testConfig.Items.Push({Trigger: "", Text: "C sort test"}, {Trigger: "", Text: "B sort test"})
        this.Config := testConfig
        this.Apply()
        this.Search.Value := "sort test"
        this.FillList()
        this.List.ModifyCol(3, "Sort")
        if this.List.GetText(1, 1) != "café" || this.ItemIndexAt(1) != testConfig.Items.Length - 2
            throw Error("The sorted row did not identify the letter-only abbreviation")
        this.List.Modify(2, "Select Focus")
        editor := this.Edit()
        if this.List.GetText(2, 1) != "" || this.RichEditor.Export().Text != "B sort test"
            throw Error("The selected sorted row opened the wrong picker-only template")
        editor.Destroy()
        this.RichEditor := false
        this.Window.Opt("-Disabled")
        this.Search.Value := ""
        pickerTest := Gui()
        pickerList := pickerTest.AddListView(, ["Сокращение", "Текст"])
        pickerItems := Map()
        this.FillPicker(pickerList, "CAFÉ", pickerItems)
        if pickerList.GetCount() != 1 || pickerList.GetText(1, 1) != "café"
            throw Error("The picker did not find the letter-only abbreviation")
        this.FillPicker(pickerList, "sort test", pickerItems)
        pickerList.ModifyCol(2, "Sort")
        if pickerItems[KweetyApp.ListItemId(pickerList, 2)].Text != "B sort test"
            || pickerItems[KweetyApp.ListItemId(pickerList, 3)].Text != "C sort test"
            throw Error("The sorted picker did not identify both picker-only templates")
        pickerTest.Destroy()
        this.Config.Items := []
        this.Apply()
        this.Config := original
        this.Apply()
        editor := this.Edit(true)
        this.RichEditor.Export()
        editor.Destroy()
        this.RichEditor := false
        this.Window.Opt("-Disabled")
        this.Config := this.CopyConfig()
        this.Config.Immediate := 1
        this.Config.Space := 0, this.Config.Enter := 0, this.Config.Tab := 0
        this.Apply()
        if !this.Immediate.Enabled
            throw Error("Immediate control unavailable")
        this.ResetOptions()
        for key, control in this.Keys
            if control.Enabled
                throw Error("Terminator controls must be disabled in immediate mode")
        this.Config := original
        this.Apply()
        this.ResetOptions()
        this.Refresh()
        exceptions := this.Exclusions()
        exceptions.Destroy()
        this.Window.Opt("-Disabled")
        settings := this.Settings()
        settings.Destroy()
        this.Window.Opt("-Disabled")
        picker := this.Picker()
        picker.Destroy()
        enabled := this.Config.Enabled
        this.Config.Enabled := !enabled
        this.UpdateTray()
        this.Config.Enabled := enabled
        this.UpdateTray()
    }

    Refresh() {
        this.FillList()
        this.Status.Text := (this.Config.Enabled ? "● Работает" : "● Приостановлено") "  ·  Шаблонов: " this.Config.Items.Length
        this.UpdateTray()
    }

    UpdateTray() {
        A_IconTip := "Kweety — замена " (this.Config.Enabled ? "включена" : "выключена")
        if !this.HasOwnProp("TrayLabel")
            return
        label := this.Config.Enabled ? "Замена включена — выключить" : "Замена выключена — включить"
        if label != this.TrayLabel {
            A_TrayMenu.Rename(this.TrayLabel, label)
            this.TrayLabel := label
        }
        if this.Config.Enabled
            A_TrayMenu.Check(label)
        else
            A_TrayMenu.Uncheck(label)
    }

    FillList() {
        this.TablePainter.Cache := Map()
        this.List.Delete(), this.VisibleItemIndices.Clear()
        for index, item in this.Config.Items {
            if !KweetyText.Matches(item, this.Search.Value)
                continue
            aliases := KweetyCore.Aliases(item.Trigger)
            preview := StrReplace(StrReplace(item.Text, "`r"), "`n", " ↵ ")
            row := this.List.Add(, item.Trigger, aliases[aliases.Length], SubStr(preview, 1, 180))
            this.VisibleItemIndices[KweetyApp.ListItemId(this.List, row)] := index
        }
    }

    ItemIndexAt(row) => row ? this.VisibleItemIndices.Get(KweetyApp.ListItemId(this.List, row), 0) : 0

    ; Windows assigns IDs that stay with the rows when the list is sorted.
    static ListItemId(list, row) => SendMessage(0x10B4, row - 1, 0, list.Hwnd) ; LVM_MAPINDEXTOID

    Apply() {
        this.CachedWindow := 0
        HotIf(this.Condition)
        for key in this.FeatureKeys
            Hotkey(key, "Off")
        this.FeatureKeys := []
        for name in this.Registered
            Hotstring(name, , "Off")
        this.Registered := []
        endings := (this.Config.Space ? " " : "") (this.Config.Enter ? "`n" : "") (this.Config.Tab ? "`t" : "")
        Hotstring("EndChars", endings)
        for item in this.Config.Items {
            if item.Trigger = ""
                continue
            payload := this.Config.FastPaste ? [] : KweetyCore.CompileBatches(item.Text)
            for alias in KweetyCore.Aliases(item.Trigger) {
                ; B0: delete the abbreviation in the SAME send as its replacement.
                name := ":" (this.Config.Immediate ? "*" : "") "B0OC1X:" alias
                Hotstring(name, this.Expand.Bind(this, payload, StrLen(alias), item), "On")
                this.Registered.Push(name)
            }
        }
        used := Map()
        for kind, property in Map("layout", "LayoutKey", "case", "CaseKey", "invert", "InvertCaseKey", "menu", "MenuKey") {
            key := KweetyShortcut.Normalize(this.Config.%property%)
            if key = ""
                continue
            if used.Has(StrLower(key))
                throw Error("Горячие клавиши не должны совпадать.")
            used[StrLower(key)] := true
            action := kind = "menu" ? this.Picker.Bind(this) : this.Transform.Bind(this, kind)
            binding := KweetyShortcut.Binding(key)
            Hotkey(binding, action, "On")
            this.FeatureKeys.Push(binding)
        }
        Loop 3 {
            key := KweetyShortcut.Normalize(this.Config.%"HistoryKey" A_Index%)
            if key = ""
                continue
            if used.Has(StrLower(key))
                throw Error("Горячие клавиши не должны совпадать.")
            used[StrLower(key)] := true
            binding := KweetyShortcut.Binding(key)
            Hotkey(binding, this.PasteHistory.Bind(this, this.Config.%"HistoryIndex" A_Index%), "On")
            this.FeatureKeys.Push(binding)
        }
        HotIf()
        Hotstring("Reset")
        this.InputLanguage.SetEnabled(this.Config.AltShiftSwitch)
    }

    Expand(payload, eraseCount, item, *) {
        ; Prevent a second expansion from interrupting a long template.
        Critical("On")
        try {
            target := WinExist("A")
            if !this.WaitForInput(target)
                return
            rich := item.HasOwnProp("Formatting") && item.Formatting && item.HasOwnProp("Rtf") && item.Rtf != ""
            if this.Config.FastPaste {
                if !this.Paste.Prepare(item.Text, rich ? item.Rtf : "", rich && item.HasOwnProp("Html") ? item.Html : "") {
                    TrayTip("Не удалось получить буфер обмена. Сокращение осталось на месте; повторите его набор.", "Kweety — вставка не выполнена", 2)
                    return
                }
                try {
                    if !WinActive("ahk_id " target)
                        return
                    ; Queue deletion and paste together, without per-key delays or
                    ; a visible empty-text pause. Prepare the clipboard first.
                    SendInput(eraseCount ? KweetyPaste.PasteKeys(eraseCount) : "^v")
                }
                finally this.Paste.ScheduleRestore()
            } else {
                ; This path must never use the clipboard, even for rich templates.
                ; Pace ordinary keys and yield between Unicode batches.
                SetKeyDelay(0, 10)
                if eraseCount {
                    SendEvent("{Backspace " eraseCount "}")
                    Sleep(40)
                }
                for batch in payload {
                    if !WinActive("ahk_id " target)
                        break
                    SendEvent(batch)
                    Sleep(10)
                }
            }
        } finally {
            Hotstring("Reset")
            Critical("Off")
        }
    }

    WaitForInput(target) {
        ; Do not paste with a still-held Shift/Alt/trigger key from the shortcut.
        for key in ["Ctrl", "Alt", "Shift", "LWin", "RWin", "Space", "Enter", "Tab"]
            if !KeyWait(key, "T1")
                return false
        return target && WinActive("ahk_id " target)
    }

    Persist(cfg, autostart := unset) {
        previous := this.Config
        startupChanged := false
        try {
            this.Config := cfg
            this.Apply()
            if IsSet(autostart) && autostart != this.Startup.IsEnabled() {
                this.Startup.SetEnabled(autostart)
                startupChanged := true
            }
            KweetyStore.Save(this.Path, cfg)
        }
        catch as err {
            this.Config := previous
            this.Apply()
            message := err.Message
            if startupChanged {
                try this.Startup.SetEnabled(!autostart)
                catch as rollbackError
                    message .= "`n`nНе удалось восстановить автозапуск.`n" rollbackError.Message
            }
            MsgBox(message, "Не удалось сохранить", "Iconx")
            return false
        }
        this.Refresh()
        return true
    }

    CopyConfig() => {Immediate: this.Config.Immediate,
        HistoryKey1: this.Config.HistoryKey1, HistoryKey2: this.Config.HistoryKey2, HistoryKey3: this.Config.HistoryKey3,
        HistoryIndex1: this.Config.HistoryIndex1, HistoryIndex2: this.Config.HistoryIndex2, HistoryIndex3: this.Config.HistoryIndex3, Enabled: this.Config.Enabled, FastPaste: this.Config.FastPaste, Space: this.Config.Space,
        Enter: this.Config.Enter, Tab: this.Config.Tab, Items: this.Config.Items.Clone(),
        LayoutKey: this.Config.LayoutKey, CaseKey: this.Config.CaseKey, InvertCaseKey: this.Config.InvertCaseKey, MenuKey: this.Config.MenuKey,
        AltShiftSwitch: this.Config.AltShiftSwitch, Excluded: this.Config.Excluded.Clone()}

    OptionsChanged() {
        for property, control in this.Options
            if control.Value != this.Config.%property%
                return true
        return this.Autostart.Value != this.Startup.IsEnabled()
    }

    ResetOptions() {
        for property, control in this.Options
            control.Value := this.Config.%property%
        this.Autostart.Value := this.Startup.IsEnabled()
        this.UpdateOptionControls()
    }

    UpdateOptionControls() {
        for key, control in this.Keys
            control.Enabled := !this.Immediate.Value
        this.ModeHint.Text := this.FastPaste.Value
            ? "Ctrl+V: быстрая вставка через буфер, с оформлением, если оно включено у шаблона."
            : "Режим клавиш: обычный текст без оформления, переносы — Shift+Enter. Для совместимости."
        this.ApplyButton.Enabled := this.OptionsChanged()
    }

    SaveOptions() {
        if !this.OptionsChanged()
            return true
        this.Window.Opt("+OwnDialogs")
        cfg := this.CopyConfig()
        for property, control in this.Options
            cfg.%property% := control.Value
        if !this.Persist(cfg, this.Autostart.Value) {
            this.UpdateOptionControls()
            return false
        }
        this.ResetOptions()
        return true
    }

    CloseOptions(exit := false) {
        if this.OptionsChanged() {
            answer := MsgBox("Применить изменения перед закрытием?`n`n«Нет» — закрыть без сохранения.",
                "Несохранённые изменения", "YesNoCancel Default3 Icon? Owner" this.Window.Hwnd)
            if answer = "Cancel" || (answer = "Yes" && !this.SaveOptions())
                return true
            this.ResetOptions()
        }
        if exit
            ExitApp()
        this.Window.Hide()
        return true
    }

    Toggle() {
        cfg := this.CopyConfig()
        followTray := this.Enabled.Value = cfg.Enabled
        cfg.Enabled := !cfg.Enabled
        if this.Persist(cfg) {
            if followTray
                this.Enabled.Value := cfg.Enabled
            this.UpdateOptionControls()
        }
    }

    OpenData() {
        DirCreate(A_AppData "\Kweety")
        Run('explorer.exe "' A_AppData '\Kweety"')
    }

    Delete() {
        selectedRow := this.List.GetNext()
        row := this.ItemIndexAt(selectedRow)
        if !row
            return
        trigger := this.Config.Items[row].Trigger
        name := trigger != "" ? trigger : this.List.GetText(selectedRow, 3)
        if MsgBox("Удалить «" name "»?", "Удаление шаблона", "YesNo Icon?") != "Yes"
            return
        cfg := this.CopyConfig()
        cfg.Items.RemoveAt(row)
        this.Persist(cfg)
    }

    Edit(isNew := false) {
        row := isNew ? 0 : this.ItemIndexAt(this.List.GetNext())
        if !isNew && !row
            return
        original := row ? this.Config.Items[row] : {Trigger: "", Text: ""}
        editor := Gui("+Owner" this.Window.Hwnd, row ? "Изменить шаблон" : "Новый шаблон")
        editor.SetFont("s10", "Segoe UI")
        editor.MarginX := 20
        editor.MarginY := 16
        editor.AddText(, "Сокращение (необязательно)")
        trigger := editor.AddEdit("xm y+6 w580", original.Trigger)
        editor.AddText("xm y+10 w580 c555555", "Оставьте поле пустым для вставки только через «Меню шаблонов».`nДопустимы буквы, цифры, _ и -. Вторая раскладка добавляется автоматически.")
        formatting := editor.AddCheckbox("xm y+16", "Использовать оформление (цвет, жирный, курсив)")
        formatting.Value := original.HasOwnProp("Formatting") && original.Formatting
        editor.Formatting := formatting
        editor.OriginalFormatting := formatting.Value
        editor.AddText("xm y+10", "Текст подстановки")
        editor.AddButton("xm y+6 w50 h30", "Ж").OnEvent("Click", (*) => body.Format("bold"))
        editor.AddButton("x+6 w50 h30", "К").OnEvent("Click", (*) => body.Format("italic"))
        editor.AddButton("x+6 w50 h30", "Ч").OnEvent("Click", (*) => body.Format("underline"))
        color := editor.AddEdit("x+12 w95", "FF0000")
        editor.AddButton("x+6 w75 h30", "Цвет…").OnEvent("Click", (*) => this.SetColor(body, color))
        editor.AddButton("x+6 w200 h30", "Вставить с оформлением").OnEvent("Click", (*) => body.PasteFormatted())
        body := KweetyRichEdit(editor, "xm y+8 w580 h240", original)
        this.RichEditor := body
        editor.AddText("xm y+10 w580 c555555", "Enter создаёт строку. В режиме Ctrl+V переносы вставляются вместе с текстом.`nСимволы вроде {Enter}, ! и + вставляются буквально.")
        close := (*) => this.CloseEditor(editor, trigger, body, original)
        editor.AddButton("xm y+16 w140", "Сохранить").OnEvent("Click", (*) => this.SaveEditor(editor, trigger, body, row))
        editor.AddButton("x+10 w140", "Отмена").OnEvent("Click", close)
        editor.OnEvent("Close", close)
        editor.OnEvent("Escape", close)
        this.Window.Opt("+Disabled")
        KweetyLayout.Enable(editor, body.Control)
        editor.Show(this.Testing ? "Hide" : "")
        if !this.Testing
            trigger.Focus()
        return editor
    }

    CloseEditor(editor, trigger, body, original) {
        if (trigger.Value != original.Trigger || body.Dirty() || editor.Formatting.Value != editor.OriginalFormatting)
            && MsgBox("Закрыть без сохранения изменений?", "Kweety", "YesNo Icon?") != "Yes"
            return true
        return this.FinishEditor(editor)
    }

    FinishEditor(editor) {
        this.Window.Opt("-Disabled")
        this.RichEditor := false
        editor.Destroy()
        this.Show()
        return true
    }

    SaveEditor(editor, trigger, body, row) {
        cfg := this.CopyConfig()
        item := body.Export()
        item.Formatting := editor.Formatting.Value
        item.Trigger := StrLower(Trim(trigger.Value))
        if row
            cfg.Items[row] := item
        else
            cfg.Items.Push(item)
        if this.Persist(cfg)
            this.FinishEditor(editor)
    }

    EditorFormat(kind, *) => this.RichEditor.Format(kind)

    SetColor(body, control) {
        color := Trim(control.Value, " #")
        if !RegExMatch(color, "i)^[0-9a-f]{6}$") {
            MsgBox("Введите цвет: 6 символов, например FF0000 — красный.", "Цвет")
            return
        }
        rgb := Integer("0x" color)
        bgr := ((rgb & 255) << 16) | (rgb & 0xFF00) | ((rgb >> 16) & 255)
        custom := Buffer(64, 0), picker := Buffer(A_PtrSize = 8 ? 72 : 36, 0)
        NumPut("UInt", picker.Size, picker)
        NumPut("Ptr", DllCall("GetParent", "Ptr", body.Hwnd, "Ptr"), picker, A_PtrSize)
        NumPut("UInt", bgr, picker, A_PtrSize * 3)
        NumPut("Ptr", custom.Ptr, picker, A_PtrSize * 4)
        NumPut("UInt", 3, picker, A_PtrSize * 5)
        if !DllCall("comdlg32\ChooseColorW", "Ptr", picker)
            return
        bgr := NumGet(picker, A_PtrSize * 3, "UInt")
        color := Format("{:02X}{:02X}{:02X}", bgr & 255, (bgr >> 8) & 255, (bgr >> 16) & 255)
        control.Value := color
        body.Format("color", color)
    }

    Allowed(hwnd := 0) {
        if this.Testing || !this.Config.Enabled
            return false
        hwnd := hwnd ? hwnd : WinExist("A")
        if !hwnd
            return false
        try {
            if WinGetPID("ahk_id " hwnd) = DllCall("GetCurrentProcessId")
                return false
        } catch
            return false
        if this.CachedWindow != hwnd {
            this.CachedWindow := hwnd
            try {
                this.CachedName := WinGetProcessName("ahk_id " hwnd)
                this.CachedPath := WinGetProcessPath("ahk_id " hwnd)
            } catch {
                this.CachedWindow := 0
                return false
            }
        }
        return !KweetyText.Excluded(this.Config.Excluded, this.CachedName, this.CachedPath)
    }

    Transform(kind, *) {
        Critical("On")
        recoverClipboard := false
        try {
            target := WinExist("A")
            if !target
                return
            ; SendInput manages shortcut modifiers itself, including held keys.
            ; Waiting for physical release made held/repeated shortcuts time out.
            if !this.Paste.Restore()
                return
            snapshot := ClipboardAll()
            recoverClipboard := true
            A_Clipboard := ""
            SendInput("^c")
            if !ClipWait(0.15) {
                SendInput("^+{Left}")
                if !WinActive("ahk_id " target) {
                    A_Clipboard := snapshot
                    recoverClipboard := false
                    return
                }
                SendInput("^c")
                if !ClipWait(0.3) {
                    A_Clipboard := snapshot
                    recoverClipboard := false
                    return
                }
            }
            text := A_Clipboard
            this.Paste.SeedOriginal(snapshot)
            recoverClipboard := false
            replacement := kind = "layout" ? KweetyText.Layout(text) : kind = "invert" ? KweetyText.InvertCase(text) : KweetyText.Case(text)
            if this.Paste.Prepare(replacement) {
                try {
                    if WinActive("ahk_id " target)
                        SendInput("^v")
                }
                finally this.Paste.ScheduleRestore()
            } else
                this.Paste.Restore()
        } catch as err {
            if recoverClipboard {
                this.Paste.SeedOriginal(snapshot)
                this.Paste.Restore()
            }
            TrayTip(err.Message, "Kweety — преобразование не выполнено", 2)
        }
        finally {
            KweetyWindowsClipboard.MarkInternal()
            Hotstring("Reset")
            Critical("Off")
        }
    }

    Settings() {
        dialog := Gui("+Owner" this.Window.Hwnd, "Горячие клавиши")
        dialog.SetFont("s10", "Segoe UI")
        controls := Map()
        altShift := dialog.AddCheckbox("xm w540", "Переключать раскладку по Alt+Shift без активации меню")
        altShift.Value := this.Config.AltShiftSwitch
        controls["AltShiftSwitch"] := altShift
        dialog.AddText("xm w540 c555555", "Отключите Alt+Shift в сочетаниях клавиш для языков ввода Windows. Работает с левым Alt, пока запущен Kweety.")
        for property, label in Map("LayoutKey", "Исправить раскладку выделения / последнего слова", "CaseKey", "Верхний / нижний регистр выделения / последнего слова", "InvertCaseKey", "Инвертировать регистр: аБв → АбВ", "MenuKey", "Открыть поиск шаблонов") {
            dialog.AddText("xm y+12 w500", label)
            controls[property] := KweetyShortcut(dialog, this.Config.%property%)
        }
        indices := Map()
        dialog.AddText("xm y+16 w540", "История буфера Kweety: 1 — последняя запись, 2 — предпоследняя.`nДо 20 записей в памяти, только пока работает Kweety (не Win+V).")
        Loop 3 {
            key := "HistoryKey" A_Index, index := "HistoryIndex" A_Index
            dialog.AddText("xm y+12", "Вставить запись №")
            indices[index] := dialog.AddEdit("x+8 yp-3 w60 Number", this.Config.%index%)
            controls[key] := KweetyShortcut(dialog, this.Config.%key%)
        }
        close := (*) => (this.Window.Opt("-Disabled"), dialog.Destroy(), this.Show())
        dialog.AddButton("xm y+12 w140", "Сохранить").OnEvent("Click", (*) => this.SaveSettings(controls, indices, close))
        dialog.AddButton("x+10 w140", "Отмена").OnEvent("Click", close)
        dialog.OnEvent("Close", close)
        dialog.OnEvent("Escape", close)
        this.Window.Opt("+Disabled")
        dialog.Show(this.Testing ? "Hide" : "")
        return dialog
    }

    SaveSettings(controls, indices, close) {
        cfg := this.CopyConfig()
        try {
            for property, control in controls
                cfg.%property% := control.Value
            for property, control in indices {
                if !RegExMatch(control.Value, "^\d+$") || Integer(control.Value) < 1 || Integer(control.Value) > 20
                    throw Error("Номер записи буфера должен быть от 1 до 20.")
                cfg.%property% := Integer(control.Value)
            }
        } catch as err {
            MsgBox(err.Message, "Горячие клавиши", "Icon!")
            return
        }
        if this.Persist(cfg)
            close.Call()
    }

    Exclusions() {
        dialog := Gui("+Owner" this.Window.Hwnd, "Программы-исключения")
        dialog.SetFont("s10", "Segoe UI")
        dialog.AddText("w540", "Имя EXE или полный путь, по одному в строке.`nВ этих программах отключены сокращения и горячие клавиши.")
        rules := ""
        for rule in this.Config.Excluded
            rules .= rule "`r`n"
        excluded := dialog.AddEdit("xm y+8 w540 r8", rules)
        dialog.AddButton("xm y+8 w200", "Добавить программу…").OnEvent("Click", (*) => this.AddExclusion(excluded))
        close := (*) => (this.Window.Opt("-Disabled"), dialog.Destroy(), this.Show())
        dialog.AddButton("xm y+12 w140", "Сохранить").OnEvent("Click", (*) => this.SaveExclusions(excluded, close))
        dialog.AddButton("x+10 w140", "Отмена").OnEvent("Click", close)
        dialog.OnEvent("Close", close)
        dialog.OnEvent("Escape", close)
        this.Window.Opt("+Disabled")
        KweetyLayout.Enable(dialog, excluded)
        dialog.Show(this.Testing ? "Hide" : "")
        return dialog
    }

    SaveExclusions(excluded, close) {
        cfg := this.CopyConfig()
        cfg.Excluded := []
        for rule in StrSplit(excluded.Value, "`n", "`r")
            if Trim(rule) != ""
                cfg.Excluded.Push(Trim(rule))
        if this.Persist(cfg)
            close.Call()
    }

    PasteHistory(index, *) {
        Critical("On")
        try {
            target := WinExist("A")
            entry := this.History.Get(index)
            if !this.Paste.Restore()
                return
            original := ClipboardAll()
            this.Paste.SeedOriginal(original)
            this.Paste.Clipboard.Restore(entry)
            this.Paste.Expected := this.Paste.Clipboard.Sequence()
            if WinActive("ahk_id " target)
                SendInput("^v")
        } catch as err {
            TrayTip(err.Message, "История буфера Kweety", 2)
        } finally {
            if this.Paste.Pending
                this.Paste.ScheduleRestore()
            Hotstring("Reset")
            Critical("Off")
        }
    }

    AddExclusion(control) {
        path := FileSelect(1, , "Выберите программу-исключение", "Программы (*.exe)")
        if path != "" {
            SplitPath(path, &name)
            control.Value := RTrim(control.Value, "`r`n") (control.Value = "" ? "" : "`r`n") name
        }
    }

    Picker(*) {
        target := WinExist("A")
        if !this.Testing && !this.Allowed(target)
            return
        popup := Gui("+AlwaysOnTop +ToolWindow", "Вставить шаблон — Kweety")
        popup.SetFont("s10", "Segoe UI")
        search := popup.AddEdit("w620")
        list := popup.AddListView("xm y+10 w620 r10 -Multi", ["Сокращение", "Текст"])
        list.ModifyCol(1, 120), list.ModifyCol(2, 470)
        itemsById := Map()
        fill := (*) => this.FillPicker(list, search.Value, itemsById)
        search.OnEvent("Change", fill)
        insert := (*) => this.PickInsert(popup, list, itemsById, target)
        popup.AddButton("xm y+10 w140 Default", "Вставить").OnEvent("Click", insert)
        popup.AddButton("x+10 w140", "Отмена").OnEvent("Click", (*) => popup.Destroy())
        list.OnEvent("DoubleClick", insert)
        popup.OnEvent("Escape", (*) => popup.Destroy())
        popup.OnEvent("Close", (*) => popup.Destroy())
        fill.Call()
        KweetyLayout.Enable(popup, list)
        popup.Show(this.Testing ? "Hide" : "")
        if !this.Testing
            search.Focus()
        return popup
    }

    FillPicker(list, query, itemsById) {
        list.Delete(), itemsById.Clear()
        for item in this.Config.Items {
            if KweetyText.Matches(item, query) {
                row := list.Add(, item.Trigger, SubStr(StrReplace(StrReplace(item.Text, "`r"), "`n", " ↵ "), 1, 100))
                itemsById[KweetyApp.ListItemId(list, row)] := item
            }
        }
        if itemsById.Count
            list.Modify(1, "Select Focus")
    }

    PickInsert(popup, list, itemsById, target) {
        row := list.GetNext()
        if !row || !WinExist("ahk_id " target) || !this.Allowed(target)
            return
        item := itemsById[KweetyApp.ListItemId(list, row)]
        popup.Destroy()
        WinActivate("ahk_id " target)
        if WinWaitActive("ahk_id " target, , 0.5)
            this.Expand(KweetyCore.CompileBatches(item.Text), 0, item)
    }

    ImportPunto() {
        path := FileSelect(1, KweetyPunto.Find(), "Выберите replace.dat Punto Switcher", "Автозамены Punto (replace.dat)")
        if path = ""
            return
        try result := KweetyPunto.Merge(this.Config.Items, KweetyPunto.Read(path))
        catch as err {
            MsgBox(err.Message, "Импорт Punto", "Iconx")
            return
        }
        SplitPath(path, , &directory)
        try preferences := KweetyPunto.Preferences(directory "\preferences.xml")
        catch as err
            preferences := {Keys: Map(), Excluded: [], Startup: -1, Summary: "Настройки не прочитаны: " err.Message}
        dialog := Gui("+Owner" this.Window.Hwnd, "Предпросмотр импорта Punto")
        dialog.SetFont("s10", "Segoe UI")
        dialog.AddText("w720", "Будет добавлено: " result.Added ". Пропущено: " result.Skipped.Length ".`n"
            . (result.RemovedStarter ? "Стандартный тестовый шаблон будет удалён. " : "")
            . "Ваши шаблоны и файлы Punto не изменяются.")
        preview := dialog.AddListView("xm y+12 w720 r7", ["Сокращение", "Текст"])
        preview.ModifyCol(1, 140), preview.ModifyCol(2, 550)
        Loop result.Added {
            item := result.Items[result.Items.Length - result.Added + A_Index]
            preview.Add(, item.Trigger, SubStr(StrReplace(StrReplace(item.Text, "`r"), "`n", " ↵ "), 1, 180))
        }
        issues := ""
        for issue in result.Skipped
            issues .= issue "`r`n"
        dialog.AddEdit("xm y+10 w720 r3 ReadOnly", issues = "" ? "Конфликтов нет." : issues)
        dialog.AddEdit("xm y+10 w720 r4 ReadOnly", preferences.Summary)
        options := dialog.AddCheckbox("xm y+10", "Перенести найденные клавиши замены и программы-исключения")
        options.Enabled := preferences.Keys.Count || preferences.Excluded.Length
        autostart := dialog.AddCheckbox("xm y+10", "Перенести настройку автозапуска (Kweety запускается в трей)")
        autostart.Enabled := preferences.Startup != -1
        close := (*) => (this.Window.Opt("-Disabled"), dialog.Destroy(), this.Show())
        dialog.AddButton("xm y+12 w160", "Импортировать").OnEvent("Click", (*) => this.SaveImport(result, preferences, options.Value, autostart.Value, close))
        dialog.AddButton("x+10 w140", "Отмена").OnEvent("Click", close)
        dialog.OnEvent("Close", close), dialog.OnEvent("Escape", close)
        this.Window.Opt("+Disabled")
        KweetyLayout.Enable(dialog, preview)
        dialog.Show()
    }

    SaveImport(result, preferences, copyOptions, copyStartup, close) {
        cfg := this.CopyConfig(), cfg.Items := result.Items
        if copyOptions {
            for key, value in preferences.Keys
                cfg.%key% := value
            for rule in preferences.Excluded
                if !KweetyText.Excluded(cfg.Excluded, rule)
                    cfg.Excluded.Push(rule)
        }
        oldStartup := this.Startup.IsEnabled()
        followStartup := this.Autostart.Value = oldStartup
        if copyStartup {
            try this.Startup.SetEnabled(preferences.Startup)
            catch as err {
                MsgBox(err.Message, "Не удалось перенести автозапуск", "Iconx")
                return
            }
        }
        if this.Persist(cfg) {
            if followStartup
                this.Autostart.Value := this.Startup.IsEnabled()
            this.UpdateOptionControls()
            close.Call()
        } else if copyStartup
            this.Startup.SetEnabled(oldStartup)
    }
}
