param([int]$HoldMs = 0, [int]$VirtualKey = 32)
$ErrorActionPreference = 'Stop'
Add-Type -TypeDefinition @'
using System; using System.Runtime.InteropServices;
public static class ShortcutTest {
  [DllImport("user32.dll",SetLastError=true)] static extern uint SendInput(uint count,INPUT[] events,int size);
  [DllImport("user32.dll")] static extern short GetAsyncKeyState(int key);
  [StructLayout(LayoutKind.Sequential)] struct INPUT {public uint type;public UNION data;}
  [StructLayout(LayoutKind.Explicit)] struct UNION {[FieldOffset(0)]public KEY key;[FieldOffset(0)]public MOUSE mouse;}
  [StructLayout(LayoutKind.Sequential)] struct KEY {public ushort vk,scan;public uint flags,time;public UIntPtr extra;}
  [StructLayout(LayoutKind.Sequential)] struct MOUSE {public int x,y;public uint data,flags,time;public UIntPtr extra;}
  public static void Send(int holdMs, ushort virtualKey) {
    foreach(int k in new int[]{0x11,0x10,0x12,virtualKey})if((GetAsyncKeyState(k)&0x8000)!=0)throw new Exception("A key is held; shortcut test did not inject anything");
    INPUT[] events=new INPUT[6];ushort[] keys={0x11,0x10,virtualKey,virtualKey,0x10,0x11};
    for(int i=0;i<6;i++){events[i].type=1;events[i].data.key.vk=keys[i];events[i].data.key.flags=i>=3?2u:0u;}
    if(holdMs==0) { if(SendInput(6,events,Marshal.SizeOf(typeof(INPUT)))!=6)throw new Exception("Shortcut injection blocked"); }
    else { try { if(SendInput(3,new INPUT[]{events[0],events[1],events[2]},Marshal.SizeOf(typeof(INPUT)))!=3)throw new Exception("Shortcut injection blocked"); System.Threading.Thread.Sleep(holdMs); } finally { SendInput(3,new INPUT[]{events[3],events[4],events[5]},Marshal.SizeOf(typeof(INPUT))); } }
  }
}
'@
[ShortcutTest]::Send($HoldMs, $VirtualKey)
