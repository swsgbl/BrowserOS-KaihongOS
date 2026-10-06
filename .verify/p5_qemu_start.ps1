$qemu = 'C:\Program Files\qemu\qemu-system-x86_64.exe'
$dir = 'D:\OHOS-QEMU\KaihongOS'
$args = @(
  '-bios', "$dir\OVMF.fd",
  '-boot', 'order=c',
  '-drive', "id=system,file=$dir\qemu.img,if=none,format=raw,cache=none",
  '-device', 'virtio-blk-pci,drive=system,bootindex=0',
  '-smp', '2',
  '-m', '16G',
  '-accel', 'whpx',
  '-chardev', "socket,id=serial0,host=127.0.0.1,port=22473,server=on,wait=off,logfile=$dir\kaihong-serial.log",
  '-serial', 'chardev:serial0',
  '-display', 'egl-headless',
  '-display', 'vnc=127.0.0.1:5',
  '-monitor', 'telnet:127.0.0.1:22471,server,nowait',
  '-qmp', 'telnet:127.0.0.1:22472,server,nowait',
  '-vga', 'none',
  '-device', 'virtio-vga-gl,xres=1280,yres=720',
  '-device', 'virtio-tablet-pci',
  '-netdev', 'user,id=net0,hostfwd=tcp:127.0.0.1:15565-:5555',
  '-device', 'virtio-net-pci,netdev=net0,bootindex=1'
)
$p = Start-Process -FilePath $qemu -ArgumentList $args -WindowStyle Hidden -RedirectStandardError "$dir\p5-stderr.log" -PassThru
Start-Sleep -Seconds 5
if ($p.HasExited) {
  Write-Output ("EXITED code=" + $p.ExitCode)
  Get-Content "$dir\p5-stderr.log" -Tail 10
} else {
  Write-Output ("RUNNING pid=" + $p.Id)
}
