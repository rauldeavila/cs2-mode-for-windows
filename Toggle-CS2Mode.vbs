Set shell = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")

scriptPath = fso.BuildPath(fso.GetParentFolderName(WScript.ScriptFullName), "Toggle-CS2Mode.ps1")
powershellPath = shell.ExpandEnvironmentStrings("%SystemRoot%") & "\System32\WindowsPowerShell\v1.0\powershell.exe"

If Not fso.FileExists(powershellPath) Then
    powershellPath = "powershell.exe"
End If

cmd = Chr(34) & powershellPath & Chr(34) & " -NoProfile -STA -ExecutionPolicy Bypass -WindowStyle Hidden -File " & _
      Chr(34) & scriptPath & Chr(34) & " -Mode Toggle"

shell.Run cmd, 1, False
