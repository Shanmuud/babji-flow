param([long]$WindowHandle, [int]$ExpectedProcess)
$ErrorActionPreference = 'Stop'
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class OwnedTestWindow {
  [DllImport("user32.dll")] static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("kernel32.dll")] static extern uint GetCurrentThreadId();
  [DllImport("user32.dll")] static extern bool AttachThreadInput(uint from, uint to, bool attach);
  [DllImport("user32.dll")] static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] static extern void SwitchToThisWindow(IntPtr h, bool altTab);
  [DllImport("user32.dll")] static extern bool ShowWindow(IntPtr h, int command);
  public static void Focus(long window, int expected) {
    IntPtr h=new IntPtr(window); uint owner; GetWindowThreadProcessId(h,out owner);
    if(owner!=expected)throw new Exception("Test target process changed");
    uint pid;uint foreground=GetWindowThreadProcessId(GetForegroundWindow(),out pid);uint ours=GetCurrentThreadId();
    bool attached=ours!=foreground&&AttachThreadInput(ours,foreground,true);
    try{ShowWindow(h,9);SetForegroundWindow(h);SwitchToThisWindow(h,true);}finally{if(attached)AttachThreadInput(ours,foreground,false);}
  }
}
'@
[OwnedTestWindow]::Focus($WindowHandle,$ExpectedProcess)
Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes
try { [System.Windows.Automation.AutomationElement]::FromHandle([IntPtr]$WindowHandle).SetFocus() } catch {}
