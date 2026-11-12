#Requires AutoHotkey v2.0
#SingleInstance Force
#ClipboardTimeout 50
;@Ahk2Exe-SetName Kweety
;@Ahk2Exe-SetDescription Kweety - text expansion
;@Ahk2Exe-SetVersion 0.1.2
#Include lib\Core.ahk
#Include lib\Paste.ahk

SetWorkingDir(A_ScriptDir)
SendMode("Input")
; SendInput can fall back to SendEvent when another AHK keyboard hook is present.
SetKeyDelay(-1, -1)
SetTitleMatchMode(2)
try {
    app := KweetyApp()
} catch as err {
    MsgBox("Не удалось запустить Kweety.`n`n" err.Message, "Kweety", "Iconx")
    ExitApp(1)
}
if A_Args.Length && A_Args[1] = "--smoke-test" {
    app.SmokeTest()
    FileAppend("Startup and hotstring registration OK`n", "*", "UTF-8")
    ExitApp(0)
}
if !(A_Args.Length && A_Args[1] = "--background")
    app.Show()

class KweetyApp {
    __New() {
        this.Path := A_AppData "\Kweety\settings.ini"
        this.Config := KweetyStore.Load(this.Path)
        this.Paste := KweetyPaste()
        OnExit((*) => (this.Paste.Restore(), 0))
        this.Registered := []
        this.Testing := A_Args.Length && A_Args[1] = "--smoke-test"
        this.Condition := (*) => !this.Testing && this.Config.Enabled && !WinActive("ahk_pid " DllCall("GetCurrentProcessId"))
        this.BuildGui()
        this.Apply()
        A_TrayMenu.Delete()
        A_TrayMenu.Add("Открыть Kweety", (*) => this.Show())
        A_TrayMenu.Add("Включить / приостановить", (*) => this.Toggle())
        A_TrayMenu.Add()
        A_TrayMenu.Add("Выход", (*) => ExitApp())
        A_TrayMenu.Default := "Открыть Kweety"
        if !A_IsCompiled && FileExist(A_ScriptDir "\assets\Kweety.ico")
            TraySetIcon(A_ScriptDir "\assets\Kweety.ico")
        A_IconTip := "Kweety — сокращения текста"
    }

    BuildGui() {
        g := this.Window := Gui(, "Kweety 0.1.2 — быстрые ответы")
        g.SetFont("s10", "Segoe UI")
        g.MarginX := 20
        g.MarginY := 16
        g.AddText("xm w730", "Пишите меньше. Говорите больше.")
        this.Enabled := g.AddCheckbox("xm y+14", "Замена сокращений включена")
        this.Enabled.OnEvent("Click", (*) => this.SaveOptions())
        this.FastPaste := g.AddCheckbox("x+26 yp", "Вставлять весь текст целиком (Ctrl+V)")
        this.FastPaste.OnEvent("Click", (*) => this.SaveOptions())
        g.AddText("xm y+18", "Заменять после нажатия:")
        this.Keys := Map()
        for key, label in Map("Space", "Пробел", "Enter", "Enter", "Tab", "Tab") {
            cb := g.AddCheckbox(key = "Space" ? "xm y+10" : "x+24 yp", label)
            cb.OnEvent("Click", (*) => this.SaveOptions())
            this.Keys[key] := cb
        }
        this.ModeHint := g.AddText("xm y+18 w730 c555555", "")
        this.List := g.AddListView("xm y+16 w730 r12 -Multi", ["Сокращение", "В другой раскладке", "Текст"])
        this.List.ModifyCol(1, 130)
        this.List.ModifyCol(2, 170)
        this.List.ModifyCol(3, 405)
        this.List.OnEvent("DoubleClick", (*) => this.Edit())
        g.AddButton("xm y+12 w150 Default", "Добавить").OnEvent("Click", (*) => this.Edit(true))
        g.AddButton("x+10 w150", "Изменить").OnEvent("Click", (*) => this.Edit())
        g.AddButton("x+10 w120", "Удалить").OnEvent("Click", (*) => this.Delete())
        g.AddText("xm y+18 w730 c555555", "Пример: fff или ааа → Привет это тестовое сообщение`nРаботает с отдельными словами, без учёта регистра. Двойной щелчок — изменить.")
        this.Status := g.AddText("xm y+12 w730", "")
        g.AddButton("xm y+14 w170", "Свернуть в трей").OnEvent("Click", (*) => g.Hide())
        g.AddButton("x+10 w150", "Папка настроек").OnEvent("Click", (*) => this.OpenData())
        g.OnEvent("Close", (*) => g.Hide())
        g.OnEvent("Escape", (*) => g.Hide())
        this.Refresh()
    }

    Show() => this.Window.Show()

    SmokeTest() {
        original := this.Config
        testConfig := this.CopyConfig()
        testConfig.Items := []
        Loop Parse "йцукенгшщзхъфывапролджэячсмитьбюё"
            testConfig.Items.Push({Trigger: A_LoopField, Text: "Тест`n{Enter}"})
        this.Config := testConfig
        this.Apply()
        this.Config.Items := []
        this.Apply()
        this.Config := original
        this.Apply()
    }

    Refresh() {
        this.Enabled.Value := this.Config.Enabled
        this.FastPaste.Value := this.Config.FastPaste
        this.ModeHint.Text := this.Config.FastPaste
            ? "Текст вставляется целиком вместе с переносами. Клавиша замены поглощается."
            : "Клавиша замены поглощается. Переносы внутри текста — Shift+Enter."
        for name, cb in this.Keys
            cb.Value := this.Config.%name%
        this.List.Delete()
        for item in this.Config.Items {
            aliases := KweetyCore.Aliases(item.Trigger)
            preview := StrReplace(StrReplace(item.Text, "`r"), "`n", " ↵ ")
            this.List.Add(, item.Trigger, aliases[aliases.Length], SubStr(preview, 1, 180))
        }
        this.Status.Text := (this.Config.Enabled ? "● Работает" : "● Приостановлено") "  ·  Шаблонов: " this.Config.Items.Length
        A_IconTip := "Kweety — " (this.Config.Enabled ? "работает" : "приостановлено")
    }

    Apply() {
        HotIf(this.Condition)
        for name in this.Registered
            Hotstring(name, , "Off")
        this.Registered := []
        endings := (this.Config.Space ? " " : "") (this.Config.Enter ? "`n" : "") (this.Config.Tab ? "`t" : "")
        Hotstring("EndChars", endings)
        for item in this.Config.Items {
            payload := this.Config.FastPaste ? [] : KweetyCore.CompileBatches(item.Text)
            for alias in KweetyCore.Aliases(item.Trigger) {
                ; B0: delete the abbreviation in the SAME send as its replacement.
                name := ":B0OC1X:" alias
                Hotstring(name, this.Expand.Bind(this, payload, StrLen(alias), item.Text), "On")
                this.Registered.Push(name)
            }
        }
        HotIf()
        Hotstring("Reset")
    }

    Expand(payload, eraseCount, text, *) {
        ; Prevent a second expansion from interrupting a long template.
        Critical("On")
        try {
            SetKeyDelay(-1, -1)
            if this.Config.FastPaste {
                if !this.Paste.Prepare(text) {
                    TrayTip("Не удалось получить буфер обмена. Сокращение осталось на месте; повторите его набор.", "Kweety — вставка не выполнена", 2)
                    return
                }
                try SendInput(KweetyPaste.PasteKeys(eraseCount))
                finally this.Paste.ScheduleRestore()
            } else {
                for i, batch in payload
                    SendInput((i = 1 ? "{Backspace " eraseCount "}" : "") batch)
            }
        } finally {
            Hotstring("Reset")
            Critical("Off")
        }
    }

    Persist(cfg) {
        try KweetyStore.Save(this.Path, cfg)
        catch as err {
            MsgBox(err.Message, "Не удалось сохранить", "Iconx")
            return false
        }
        this.Config := cfg
        this.Apply()
        this.Refresh()
        return true
    }

    CopyConfig() => {Enabled: this.Config.Enabled, FastPaste: this.Config.FastPaste, Space: this.Config.Space,
        Enter: this.Config.Enter, Tab: this.Config.Tab, Items: this.Config.Items.Clone()}

    SaveOptions() {
        cfg := this.CopyConfig()
        cfg.Enabled := this.Enabled.Value
        cfg.FastPaste := this.FastPaste.Value
        for name, cb in this.Keys
            cfg.%name% := cb.Value
        if !this.Persist(cfg)
            this.Refresh()
    }

    Toggle() {
        cfg := this.CopyConfig()
        cfg.Enabled := !cfg.Enabled
        this.Persist(cfg)
    }

    OpenData() {
        DirCreate(A_AppData "\Kweety")
        Run('explorer.exe "' A_AppData '\Kweety"')
    }

    Delete() {
        row := this.List.GetNext()
        if !row
            return
        if MsgBox("Удалить «" this.Config.Items[row].Trigger "»?", "Удаление шаблона", "YesNo Icon?") != "Yes"
            return
        cfg := this.CopyConfig()
        cfg.Items.RemoveAt(row)
        this.Persist(cfg)
    }

    Edit(isNew := false) {
        row := isNew ? 0 : this.List.GetNext()
        if !isNew && !row
            return
        original := row ? this.Config.Items[row] : {Trigger: "", Text: ""}
        editor := Gui("+Owner" this.Window.Hwnd, row ? "Изменить шаблон" : "Новый шаблон")
        editor.SetFont("s10", "Segoe UI")
        editor.MarginX := 20
        editor.MarginY := 16
        editor.AddText(, "Сокращение")
        trigger := editor.AddEdit("xm y+6 w580", original.Trigger)
        editor.AddText("xm y+10 w580 c555555", "Буквы, цифры, _ и -. Вторая раскладка добавится автоматически.")
        editor.AddText("xm y+16", "Текст подстановки")
        body := editor.AddEdit("xm y+6 w580 r12 WantTab WantReturn", original.Text)
        editor.AddText("xm y+10 w580 c555555", "Enter создаёт строку. В режиме Ctrl+V переносы вставляются вместе с текстом.`nСимволы вроде {Enter}, ! и + вставляются буквально.")
        close := (*) => this.CloseEditor(editor, trigger, body, original)
        editor.AddButton("xm y+16 w140", "Сохранить").OnEvent("Click", (*) => this.SaveEditor(editor, trigger, body, row))
        editor.AddButton("x+10 w140", "Отмена").OnEvent("Click", close)
        editor.OnEvent("Close", close)
        editor.OnEvent("Escape", close)
        this.Window.Opt("+Disabled")
        editor.Show()
        trigger.Focus()
    }

    CloseEditor(editor, trigger, body, original) {
        if (trigger.Value != original.Trigger || body.Value != original.Text)
            && MsgBox("Закрыть без сохранения изменений?", "Kweety", "YesNo Icon?") != "Yes"
            return true
        return this.FinishEditor(editor)
    }

    FinishEditor(editor) {
        this.Window.Opt("-Disabled")
        editor.Destroy()
        this.Show()
        return true
    }

    SaveEditor(editor, trigger, body, row) {
        cfg := this.CopyConfig()
        item := {Trigger: StrLower(Trim(trigger.Value)), Text: body.Value}
        if row
            cfg.Items[row] := item
        else
            cfg.Items.Push(item)
        if this.Persist(cfg)
            this.FinishEditor(editor)
    }
}
