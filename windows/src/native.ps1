$ErrorActionPreference = 'Stop'
[Console]::InputEncoding = New-Object System.Text.UTF8Encoding
[Console]::OutputEncoding = New-Object System.Text.UTF8Encoding
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class BabjiNative {
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("user32.dll")] public static extern short GetAsyncKeyState(int key);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] static extern int GetClassName(IntPtr h, System.Text.StringBuilder value, int size);
  public static string WindowClass(IntPtr h) { var value = new System.Text.StringBuilder(256); GetClassName(h,value,256); return value.ToString(); }
  [DllImport("user32.dll")] static extern bool IsWindow(IntPtr h);
  [DllImport("user32.dll")] static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] static extern bool AttachThreadInput(uint from,uint to,bool attach);
  [DllImport("kernel32.dll")] static extern uint GetCurrentThreadId();
  public static void RestoreFromBabji(long target,uint expectedPid,uint babjiPid){
    IntPtr destination=new IntPtr(target);uint owner;GetWindowThreadProcessId(destination,out owner);
    if(!IsWindow(destination)||owner!=expectedPid)throw new Exception("Original app closed or changed. Nothing was inserted.");
    IntPtr foreground=GetForegroundWindow();uint currentPid;uint thread=GetWindowThreadProcessId(foreground,out currentPid);
    if(foreground==destination)return;
    if(currentPid!=babjiPid)throw new Exception("Focus moved to another app. Nothing was inserted.");
    uint ours=GetCurrentThreadId();bool attached=ours!=thread&&AttachThreadInput(ours,thread,true);
    try{if(GetForegroundWindow()!=foreground)throw new Exception("Focus changed again. Nothing was inserted.");SetForegroundWindow(destination);}finally{if(attached)AttachThreadInput(ours,thread,false);}
    if(GetForegroundWindow()!=destination)throw new Exception("Could not return to the original text field.");
    System.Threading.Thread.Sleep(150);
  }
  [DllImport("user32.dll", SetLastError=true)] static extern uint SendInput(uint n, INPUT[] inputs, int size);
  [StructLayout(LayoutKind.Sequential)] struct INPUT { public uint type; public UNION data; }
  [StructLayout(LayoutKind.Explicit)] struct UNION { [FieldOffset(0)] public KEYBOARD key; [FieldOffset(0)] public MOUSE mouse; }
  [StructLayout(LayoutKind.Sequential)] struct KEYBOARD { public ushort vk, scan; public uint flags, time; public UIntPtr extra; }
  [StructLayout(LayoutKind.Sequential)] struct MOUSE { public int x,y; public uint data,flags,time; public UIntPtr extra; }
  public static void Paste(long target) {
    for(int wait=0;wait<60&&GetForegroundWindow().ToInt64()!=target;wait++)System.Threading.Thread.Sleep(20);
    if (GetForegroundWindow().ToInt64()!=target) throw new Exception("Focus changed. Text is available in Babji Flow; nothing was inserted.");
    for (int i=0; i<250 && ((GetAsyncKeyState(0x11)&0x8000)!=0 || (GetAsyncKeyState(0x10)&0x8000)!=0 || (GetAsyncKeyState(0x12)&0x8000)!=0); i++) System.Threading.Thread.Sleep(20);
    if ((GetAsyncKeyState(0x11)&0x8000)!=0 || (GetAsyncKeyState(0x10)&0x8000)!=0 || (GetAsyncKeyState(0x12)&0x8000)!=0) throw new Exception("Release modifier keys before inserting text.");
    if (GetForegroundWindow().ToInt64()!=target) throw new Exception("Focus changed. Text is available in Babji Flow; nothing was inserted.");
    INPUT ctrl=new INPUT(); ctrl.type=1; ctrl.data.key.vk=0x11;
    INPUT v=new INPUT(); v.type=1; v.data.key.vk=0x56;
    INPUT vUp=v; vUp.data.key.flags=2;
    INPUT ctrlUp=ctrl; ctrlUp.data.key.flags=2;
    if (SendInput(4,new INPUT[]{ctrl,v,vUp,ctrlUp},Marshal.SizeOf(typeof(INPUT)))!=4) throw new Exception("Windows blocked paste. Copy the result manually (elevated apps may block input).");
  }
  public static void TypeText(long target, string text) {
    if (GetForegroundWindow().ToInt64() != target) throw new Exception("Focus changed. Text is available in Babji Flow; nothing was inserted.");
    for (int i=0; i<30 && ((GetAsyncKeyState(0x11)&0x8000)!=0 || (GetAsyncKeyState(0x10)&0x8000)!=0 || (GetAsyncKeyState(0x12)&0x8000)!=0); i++) System.Threading.Thread.Sleep(20);
    if ((GetAsyncKeyState(0x11)&0x8000)!=0 || (GetAsyncKeyState(0x10)&0x8000)!=0 || (GetAsyncKeyState(0x12)&0x8000)!=0) throw new Exception("Release modifier keys before inserting text.");
    foreach (char c in text) {
      if (GetForegroundWindow().ToInt64()!=target) throw new Exception("Focus changed while inserting. Review the target field before retrying.");
      INPUT down = new INPUT(); down.type=1;
      if (c=='\n') { down.data.key.vk=13; } else if (c=='\r') { continue; } else { down.data.key.scan=c; down.data.key.flags=4; }
      INPUT up=down; up.data.key.flags|=2;
      if (SendInput(2,new INPUT[]{down,up},Marshal.SizeOf(typeof(INPUT)))!=2) throw new Exception("Windows blocked insertion. Copy the result manually (elevated apps may block input).");
    }
  }
}
'@
while ($null -ne ($line = [Console]::ReadLine())) {
  $request = $null
  try {
    $request = $line | ConvertFrom-Json
    if ($request.action -eq 'capture') {
      $handle = [BabjiNative]::GetForegroundWindow()
      [uint32]$targetProcessId = 0
      [void][BabjiNative]::GetWindowThreadProcessId($handle, [ref]$targetProcessId)
      $processName = ''
      try { $capturedProcess = [System.Diagnostics.Process]::GetProcessById([int]$targetProcessId); $processName = $capturedProcess.ProcessName; $capturedProcess.Dispose() } catch {}
      $result = @{ handle = $handle.ToInt64().ToString(); app = $processName; pid = $targetProcessId; className = [BabjiNative]::WindowClass($handle) }
    } elseif ($request.action -eq 'keys') {
      $pressed = $false
      if ($request.virtualKey -ge 1 -and $request.virtualKey -le 255) { $pressed = (([BabjiNative]::GetAsyncKeyState([int]$request.virtualKey) -band 0x8000) -ne 0) }
      $result = @{ pressed = $pressed; left = (([BabjiNative]::GetAsyncKeyState(0x01) -band 0x8000) -ne 0); space = (([BabjiNative]::GetAsyncKeyState(0x20) -band 0x8000) -ne 0); control = (([BabjiNative]::GetAsyncKeyState(0x11) -band 0x8000) -ne 0); shift = (([BabjiNative]::GetAsyncKeyState(0x10) -band 0x8000) -ne 0); alt = (([BabjiNative]::GetAsyncKeyState(0x12) -band 0x8000) -ne 0) }
    } elseif ($request.action -eq 'restore-target') {
      [BabjiNative]::RestoreFromBabji([long]$request.handle,[uint32]$request.pid,[uint32]$request.babjiPid)
      $result = $true
    } elseif ($request.action -eq 'paste') {
      [BabjiNative]::Paste([long]$request.handle)
      $result = $true
    } elseif ($request.action -eq 'type') {
      [BabjiNative]::TypeText([long]$request.handle, [string]$request.text)
      $result = $true
    } else { throw 'Unknown native action' }
    @{ id = $request.id; result = $result } | ConvertTo-Json -Compress -Depth 5 | ForEach-Object { [Console]::WriteLine($_) }
  } catch {
    @{ id = $request.id; error = $_.Exception.Message } | ConvertTo-Json -Compress | ForEach-Object { [Console]::WriteLine($_) }
  }
}
