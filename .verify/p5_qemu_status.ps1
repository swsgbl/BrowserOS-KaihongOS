$procs = Get-Process | Where-Object { $_.ProcessName -match 'qemu' }
if ($procs) {
  $procs | ForEach-Object { Write-Output ("PID=" + $_.Id + " name=" + $_.ProcessName) }
} else {
  Write-Output "NO-QEMU-PROCESS"
}
$listeners = netstat -ano | Select-String 'LISTENING' | Select-String '2247|1556|590'
if ($listeners) { $listeners | ForEach-Object { Write-Output $_.Line } } else { Write-Output "NO-LISTENERS" }
