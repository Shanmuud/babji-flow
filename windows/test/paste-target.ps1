param([string]$OutputFile)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class TestFocus {
  [DllImport("user32.dll")] static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("kernel32.dll")] static extern uint GetCurrentThreadId();
  [DllImport("user32.dll")] static extern bool AttachThreadInput(uint from, uint to, bool attach);
  [DllImport("user32.dll")] static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] static extern void SwitchToThisWindow(IntPtr h, bool altTab);
  [DllImport("user32.dll")] static extern bool ShowWindow(IntPtr h, int command);
  public static void OwnWindow(IntPtr h) {
    uint owner; GetWindowThreadProcessId(h, out owner);
    if (owner != System.Diagnostics.Process.GetCurrentProcess().Id) throw new Exception("Test window is not ours");
    uint pid; uint foregroundThread=GetWindowThreadProcessId(GetForegroundWindow(),out pid);uint ours=GetCurrentThreadId();
    bool attached=foregroundThread!=ours && AttachThreadInput(ours,foregroundThread,true);
    try { ShowWindow(h,9); SetForegroundWindow(h); SwitchToThisWindow(h,true); } finally { if(attached)AttachThreadInput(ours,foregroundThread,false); }
  }
}
'@
$form = New-Object System.Windows.Forms.Form
$form.Text = 'Babji automated test - disposable text field'
$form.Size = New-Object System.Drawing.Size(600, 280)
$form.StartPosition = 'CenterScreen'
$box = New-Object System.Windows.Forms.TextBox
$box.Multiline = $true
$box.Dock = 'Fill'
$box.Font = New-Object System.Drawing.Font('Segoe UI', 14)
$form.Controls.Add($box)
$box.Add_TextChanged({ [IO.File]::WriteAllText($OutputFile, $box.Text) })
$form.Add_Shown({ $form.Activate(); $box.Focus(); [IO.File]::WriteAllText($OutputFile + '.ready', $form.Handle.ToInt64().ToString()) })
$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 50
$timer.Add_Tick({
  if (Test-Path -LiteralPath ($OutputFile + '.focus')) {
    Remove-Item -LiteralPath ($OutputFile + '.focus')
    [TestFocus]::OwnWindow($form.Handle)
    try { [System.Windows.Automation.AutomationElement]::FromHandle($box.Handle).SetFocus() } catch {}
    $box.Focus()
  }
  if (Test-Path -LiteralPath ($OutputFile + '.shortcut')) {
    Remove-Item -LiteralPath ($OutputFile + '.shortcut')
    if ($form.ContainsFocus) { [System.Windows.Forms.SendKeys]::SendWait('^+{SPACE}') }
  }
})
$timer.Start()
[System.Windows.Forms.Application]::Run($form)
