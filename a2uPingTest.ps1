# Nastavitve
#Path to the folder where the log files will be located
$logPath = "C:\Logs\PingLogs"

param(
[string]$ftpServer = "" # FTP strežnik
[string]$ftpUser = ""
[string]$ftpPass = ""
)

$computerName = $env:COMPUTERNAME

# Check if the folder exists, otherwise create it
if (!(Test-Path $logPath)) {
    New-Item -ItemType Directory -Path $logPath
}

# Get default gateway
$gateway = (Get-NetRoute -DestinationPrefix "0.0.0.0/0" | Select-Object -First 1).NextHop
$targets = @($gateway, "google.com", "192.168.1.1", "192.168.1.174")

# Set the start time at the beginning
$previousTime = Get-Date

while ($true) {
    # Create a file name with today's date and computer name
    $fileName = "PingLog_${computerName}_$(Get-Date -Format 'yyyy-MM-dd').txt"
    $filePath = Join-Path $logPath $fileName

    # Run pings asynchronously
    $jobs = @()
    foreach ($target in $targets) {
        $jobs += Start-Job -ScriptBlock {
            param($t)
            try {
                $ping = Test-Connection -ComputerName $t -Count 1 -ErrorAction Stop | Select-Object -ExpandProperty ResponseTime
                [PSCustomObject]@{
                    Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
                    Target = $t
                    PingResult = "$ping ms"
                }
            }
            catch {
                [PSCustomObject]@{
                    Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
                    Target = $t
                    PingResult = "Napaka: $_"
                }
            }
        } -ArgumentList $target
    }

    # Wait for all jobs to complete, then save the results
    $jobs | Wait-Job | Receive-Job | ForEach-Object {
        "$($_.Timestamp) - Ping rezultat do $($_.Target): $($_.PingResult)" | Out-File -FilePath $filePath -Append
    }

    # Clear completed jobs
    $jobs | Remove-Job

    # current time
    $currentTime = Get-Date

    # Calculate time since last upload 
    $elapsedTime = $currentTime - $previousTime

    # check if more then 30 second has gon bay
    if ($elapsedTime.TotalSeconds -ge 30) {
        Write-Output "Preteklo je $($elapsedTime.TotalSeconds) sekund od zadnjega dogodka."



        # upload to FTP
        Start-Job -ScriptBlock {
            param($ftpUri, $filePath, $ftpUser, $ftpPass)
            try {
                $webclient = New-Object System.Net.WebClient
                $webclient.Credentials = New-Object System.Net.NetworkCredential($ftpUser, $ftpPass)
                $webclient.UploadFile($ftpUri, $filePath)
                Write-Output "FTP transfer successful."
            }
            catch {
                Write-Output "FTP upload error: $_"
                Write-Output $ftpUri
            }
        } -ArgumentList "$ftpServer/web/pings/$fileName", $filePath, $ftpUser, $ftpPass | Out-Null
        $previousTime = $currentTime
    }

    # delete files older then 7 days
    Get-ChildItem -Path $logPath -Filter "PingLog_*.txt" | 
        Where-Object { $_.CreationTime -lt (Get-Date).AddDays(-7) } |
        Remove-Item -Force

    # wait x sec
    Start-Sleep -Seconds 1
}
