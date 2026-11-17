#Requires AutoHotkey v2.0

class KweetyWindowsClipboard {
    static InternalSequence := -1
    static MarkInternal() => KweetyWindowsClipboard.InternalSequence := DllCall("GetClipboardSequenceNumber", "UInt")
    Capture() => ClipboardAll()
    Sequence() => DllCall("GetClipboardSequenceNumber", "UInt")
    Write(text) {
        A_Clipboard := text
        KweetyWindowsClipboard.MarkInternal()
    }
    Restore(data) {
        A_Clipboard := data
        KweetyWindowsClipboard.MarkInternal()
    }

    static ReadFormat(name, encoding := "CP0") {
        format := DllCall("RegisterClipboardFormat", "Str", name, "UInt")
        if !DllCall("OpenClipboard", "Ptr", A_ScriptHwnd)
            return ""
        try {
            handle := DllCall("GetClipboardData", "UInt", format, "Ptr")
            if !handle
                return ""
            pointer := DllCall("GlobalLock", "Ptr", handle, "Ptr")
            if !pointer
                return ""
            try {
                size := DllCall("GlobalSize", "Ptr", handle, "UPtr")
                if size > 8000000
                    throw Error("Слишком большой объём форматированного текста.")
                return RTrim(StrGet(pointer, size, encoding), Chr(0))
            } finally DllCall("GlobalUnlock", "Ptr", handle)
        } finally DllCall("CloseClipboard")
    }

    WriteRich(text, rtf, html) {
        this.Write(text)
        if !DllCall("OpenClipboard", "Ptr", A_ScriptHwnd)
            throw Error("Буфер обмена занят.")
        try {
            if rtf != ""
                this.AddFormat("Rich Text Format", rtf, "CP0")
            if html != ""
                this.AddFormat("HTML Format", KweetyRich.ClipboardHtml(html), "UTF-8")
        } finally {
            DllCall("CloseClipboard")
            KweetyWindowsClipboard.MarkInternal()
        }
    }

    AddFormat(name, value, encoding) {
        format := DllCall("RegisterClipboardFormat", "Str", name, "UInt")
        size := StrPut(value, encoding)
        handle := DllCall("GlobalAlloc", "UInt", 0x42, "UPtr", size, "Ptr")
        if !handle
            throw Error("Недостаточно памяти для буфера обмена.")
        pointer := DllCall("GlobalLock", "Ptr", handle, "Ptr")
        if !pointer {
            DllCall("GlobalFree", "Ptr", handle)
            throw Error("Не удалось подготовить буфер обмена.")
        }
        StrPut(value, pointer, size, encoding)
        DllCall("GlobalUnlock", "Ptr", handle)
        if !DllCall("SetClipboardData", "UInt", format, "Ptr", handle, "Ptr") {
            DllCall("GlobalFree", "Ptr", handle)
            throw Error("Не удалось записать оформление в буфер обмена.")
        }
    }
}

class KweetyPaste {
    __New(clipboard := unset) {
        this.Clipboard := IsSet(clipboard) ? clipboard : KweetyWindowsClipboard()
        this.Pending := false
        this.Saved := ""
        this.Expected := 0
        this.RestoreCallback := this.Restore.Bind(this)
    }

    static CanPaste(text) => text != ""

    static ClipboardText(text) {
        ; CF_UNICODETEXT uses CRLF. Preserve blank and trailing lines as well.
        return StrReplace(StrReplace(StrReplace(text, "`r`n", "`n"), "`r", "`n"), "`n", "`r`n")
    }

    static PasteKeys(eraseCount) {
        if !IsInteger(eraseCount) || eraseCount < 1 || eraseCount > 40
            throw Error("Некорректная длина сокращения.")
        return "{Backspace " eraseCount "}^v"
    }

    Prepare(text, rtf := "", html := "") {
        ; Mail/browser processes can hold the clipboard briefly during input.
        Loop 5 {
            if this.TryPrepare(text, rtf, html)
                return true
            if A_Index < 5
                Sleep(25)
        }
        return false
    }

    TryPrepare(text, rtf := "", html := "") {
        if !KweetyPaste.CanPaste(text)
            return false
        wroteClipboard := false
        try {
            ; A second expansion must retain the ORIGINAL clipboard, not our text.
            saved := this.Pending && this.Clipboard.Sequence() = this.Expected
                ? this.Saved : this.Clipboard.Capture()
            this.Saved := saved
            if rtf != "" || html != "" {
                wroteClipboard := true
                this.Clipboard.WriteRich(KweetyPaste.ClipboardText(text), rtf, html)
            } else
                this.Clipboard.Write(KweetyPaste.ClipboardText(text))
            this.Expected := this.Clipboard.Sequence()
            this.Saved := saved
            this.Pending := true
            this.Retries := 0
            return true
        } catch {
            if wroteClipboard {
                this.Pending := true
                this.Expected := this.Clipboard.Sequence()
                this.Retries := 0
                this.Restore()
            }
            return false ; Leave the abbreviation untouched if the clipboard is busy.
        }
    }

    SeedOriginal(snapshot) {
        this.Saved := snapshot
        this.Pending := true
        this.Expected := this.Clipboard.Sequence()
        this.Retries := 0
    }

    ScheduleRestore() {
        ; Let Discord and other asynchronous paste handlers read the clipboard.
        ; This is a timer, NOT a blocking sleep on the expansion path.
        SetTimer(this.RestoreCallback, -2000)
    }

    Restore(*) {
        if !this.Pending
            return true
        if this.Clipboard.Sequence() = this.Expected {
            try this.Clipboard.Restore(this.Saved)
            catch {
                this.Retries += 1
                if this.Retries <= 3
                    SetTimer(this.RestoreCallback, -100)
                return false
            }
        }
        ; If the user copied something meanwhile, their new clipboard wins.
        this.Pending := false
        this.Saved := ""
        return true
    }
}

class KweetyHistory {
    __New(watch := true) {
        this.Items := []
        this.Handler := this.Changed.Bind(this)
        if watch {
            OnClipboardChange(this.Handler)
            this.Changed(1)
        }
    }

    Changed(kind) {
        if !kind || DllCall("GetClipboardSequenceNumber", "UInt") = KweetyWindowsClipboard.InternalSequence
            return
        try {
            this.Remember(ClipboardAll())
        }
    }

    Remember(entry) {
        if !entry.Size || entry.Size > 16000000
            return
        this.Items.InsertAt(1, entry)
        if this.Items.Length > 20
            this.Items.Pop()
    }

    Get(index) {
        if index < 1 || index > this.Items.Length
            throw Error("В истории Kweety пока нет записи №" index ". Копируйте данные при запущенной программе.")
        return this.Items[index]
    }
}
