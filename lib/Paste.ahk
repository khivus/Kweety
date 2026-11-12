#Requires AutoHotkey v2.0

class KweetyWindowsClipboard {
    Capture() => ClipboardAll()
    Sequence() => DllCall("GetClipboardSequenceNumber", "UInt")
    Write(text) => A_Clipboard := text
    Restore(data) => A_Clipboard := data
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

    Prepare(text) {
        if !KweetyPaste.CanPaste(text)
            return false
        try {
            ; A second expansion must retain the ORIGINAL clipboard, not our text.
            saved := this.Pending && this.Clipboard.Sequence() = this.Expected
                ? this.Saved : this.Clipboard.Capture()
            this.Clipboard.Write(KweetyPaste.ClipboardText(text))
            this.Expected := this.Clipboard.Sequence()
            this.Saved := saved
            this.Pending := true
            this.Retries := 0
            return true
        } catch {
            return false ; Leave the abbreviation untouched if the clipboard is busy.
        }
    }

    ScheduleRestore() {
        ; Let Discord and other asynchronous paste handlers read the clipboard.
        ; This is a timer, NOT a blocking sleep on the expansion path.
        SetTimer(this.RestoreCallback, -500)
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
