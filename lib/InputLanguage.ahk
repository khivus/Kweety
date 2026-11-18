#Requires AutoHotkey v2.0

class KweetyInputLanguage {
    Hook := 0
    Callback := 0
    Alt := false
    Shifts := 0
    Cancelled := false

    SetEnabled(enabled) {
        if enabled = !!this.Hook
            return
        if enabled {
            this.Alt := false
            this.Shifts := 0
            this.Cancelled := false
            this.Callback := CallbackCreate(this.OnKey.Bind(this), "Fast", 3)
            module := DllCall("GetModuleHandle", "Ptr", 0, "Ptr")
            this.Hook := DllCall("SetWindowsHookEx", "Int", 13, "Ptr", this.Callback,
                "Ptr", module, "UInt", 0, "Ptr")
            if !this.Hook {
                errorCode := A_LastError
                CallbackFree(this.Callback)
                this.Callback := 0
                throw OSError(errorCode)
            }
        } else {
            if !DllCall("UnhookWindowsHookEx", "Ptr", this.Hook)
                throw OSError()
            CallbackFree(this.Callback)
            this.Callback := 0
            this.Hook := 0
        }
    }

    OnKey(code, message, event) {
        if code = 0 {
            flags := NumGet(event, 8, "UInt")
            if !(flags & 0x10) {  ; Ignore injected keystrokes, including our mask key.
                key := NumGet(event, 0, "UInt")
                up := !!(flags & 0x80)
                action := this.Track(key, up)
                if action = "mask" {
                    ; An unassigned virtual key keeps Alt-up from opening menus.
                    DllCall("keybd_event", "UChar", 0xE8, "UChar", 0, "UInt", 0, "UPtr", 0)
                    DllCall("keybd_event", "UChar", 0xE8, "UChar", 0, "UInt", 2, "UPtr", 0)
                } else if action = "switch" {
                    this.SwitchLayout()
                }
            }
        }
        return DllCall("CallNextHookEx", "Ptr", 0, "Int", code, "UPtr", message, "Ptr", event, "Ptr")
    }

    Track(key, up) {
        chord := this.Alt && this.Shifts
        switch key {
            case 0xA4: this.Alt := !up
            case 0xA0: this.Shifts := up ? this.Shifts & ~1 : this.Shifts | 1
            case 0xA1: this.Shifts := up ? this.Shifts & ~2 : this.Shifts | 2
            default:
                if !up && (this.Alt || this.Shifts)
                    this.Cancelled := true
                return ""
        }
        paired := this.Alt && this.Shifts
        action := ""
        if !chord && paired && !this.Cancelled {
            ; Check modifiers that may already have been held when the gesture began.
            for modifier in [0x11, 0x5B, 0x5C, 0xA5]
                if DllCall("GetAsyncKeyState", "Int", modifier, "Short") < 0
                    this.Cancelled := true
            if !this.Cancelled
                action := "mask"
        } else if chord && !paired && !this.Cancelled {
            action := "switch"
        }
        if !this.Alt && !this.Shifts
            this.Cancelled := false
        return action
    }

    SwitchLayout() {
        ; Send Windows' input-language request to the control that owns keyboard focus.
        foreground := DllCall("GetForegroundWindow", "Ptr")
        if !foreground
            return
        thread := DllCall("GetWindowThreadProcessId", "Ptr", foreground, "Ptr", 0, "UInt")
        if !thread
            return
        info := Buffer(8 + 6 * A_PtrSize + 16, 0)
        NumPut("UInt", info.Size, info)
        if !DllCall("GetGUIThreadInfo", "UInt", thread, "Ptr", info)
            return
        focus := NumGet(info, 8 + A_PtrSize, "Ptr")
        count := DllCall("GetKeyboardLayoutList", "Int", 0, "Ptr", 0, "Int")
        if count < 2
            return
        layouts := Buffer(count * A_PtrSize)
        count := DllCall("GetKeyboardLayoutList", "Int", count, "Ptr", layouts, "Int")
        if count < 2
            return
        current := DllCall("GetKeyboardLayout", "UInt", thread, "Ptr")
        next := NumGet(layouts, 0, "Ptr")
        Loop count {
            if NumGet(layouts, (A_Index - 1) * A_PtrSize, "Ptr") = current {
                next := NumGet(layouts, Mod(A_Index, count) * A_PtrSize, "Ptr")
                break
            }
        }
        DllCall("PostMessage", "Ptr", focus ? focus : foreground,
            "UInt", 0x0050, "UPtr", 2, "Ptr", next)
    }
}
