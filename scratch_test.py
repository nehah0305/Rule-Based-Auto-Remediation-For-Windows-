import base64
import subprocess
import json

script = """
$since = (Get-Date).AddSeconds(-1000)
$events = Get-WinEvent -FilterHashtable @{
    LogName = 'Application'
    Id = 1000
    Level = 2
    StartTime = $since
} -MaxEvents 20 -ErrorAction SilentlyContinue |
Where-Object { $_.Message -match 'notepad' } |
Select-Object Id, LogName, ProviderName, Message, TimeCreated, Level
if ($events) { $events | ConvertTo-Json -Depth 3 -Compress }
else { '[]' }
"""
encoded = base64.b64encode(script.encode('utf-16le')).decode('ascii')
ps_path = r'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe'
result = subprocess.run([ps_path, '-NoProfile', '-ExecutionPolicy', 'Bypass', '-EncodedCommand', encoded], capture_output=True, text=True)
print("STDOUT:", result.stdout)
print("STDERR:", result.stderr)
