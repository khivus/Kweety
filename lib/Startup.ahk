#Requires AutoHotkey v2.0

class KweetyStartup {
    __New(linkPath := unset, command := unset) {
        this.LinkPath := IsSet(linkPath) ? linkPath : A_Startup "\Kweety.lnk"
        this.Command := IsSet(command) ? command : KweetyStartup.MakeCommand(A_IsCompiled, A_ScriptFullPath, A_AhkPath)
    }

    static MakeCommand(compiled, scriptPath, interpreterPath) {
        SplitPath(scriptPath, , &directory)
        return {Target: compiled ? scriptPath : interpreterPath,
            Args: compiled ? "--background" : '"' scriptPath '" --background',
            Directory: directory}
    }

    IsEnabled() => !!FileExist(this.LinkPath)

    SetEnabled(enabled) {
        if !enabled {
            if FileExist(this.LinkPath)
                FileDelete(this.LinkPath)
            return
        }
        temp := this.LinkPath ".tmp.lnk"
        cmd := this.Command
        try {
            FileCreateShortcut(cmd.Target, temp, cmd.Directory, cmd.Args, "Kweety — запуск в трее")
            FileMove(temp, this.LinkPath, true)
        } finally {
            if FileExist(temp)
                FileDelete(temp)
        }
    }
}
