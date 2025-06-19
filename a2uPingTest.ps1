# Nastavitve
$logPath = "C:\Logs\PingLogs" # Pot do mape, kjer bodo log datoteke
param(
[string]$ftpServer = "" # FTP strežnik
[string]$ftpUser = ""
[string]$ftpPass = ""
)

$computerName = $env:COMPUTERNAME

# Preveri, če mapa obstaja, sicer jo ustvari
if (!(Test-Path $logPath)) {
    New-Item -ItemType Directory -Path $logPath
}

# Pridobi privzeti gateway
$gateway = (Get-NetRoute -DestinationPrefix "0.0.0.0/0" | Select-Object -First 1).NextHop
$targets = @($gateway, "google.com", "192.168.1.1", "192.168.1.174")

# Nastavi začetni čas na začetku
$previousTime = Get-Date

while ($true) {
    # Ustvari ime datoteke z današnjim datumom in imenom računalnika
    $fileName = "PingLog_${computerName}_$(Get-Date -Format 'yyyy-MM-dd').txt"
    $filePath = Join-Path $logPath $fileName

    # Zaženi pinge asinhrono
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

    # Počakaj, da se vsi jobi zaključijo, nato shrani rezultate
    $jobs | Wait-Job | Receive-Job | ForEach-Object {
        "$($_.Timestamp) - Ping rezultat do $($_.Target): $($_.PingResult)" | Out-File -FilePath $filePath -Append
    }

    # Počisti zaključene jobe
    $jobs | Remove-Job

        # Trenutni čas
    $currentTime = Get-Date

    # Izračunaj časovno razliko od zadnjega dogodka
    $elapsedTime = $currentTime - $previousTime

    # Preveri, če je preteklo več kot 60 sekund (ali poljubna vrednost)
    if ($elapsedTime.TotalSeconds -ge 30) {
        Write-Output "Preteklo je $($elapsedTime.TotalSeconds) sekund od zadnjega dogodka."



        # Naloži datoteko na FTP
        Start-Job -ScriptBlock {
            param($ftpUri, $filePath, $ftpUser, $ftpPass)
            try {
                $webclient = New-Object System.Net.WebClient
                $webclient.Credentials = New-Object System.Net.NetworkCredential($ftpUser, $ftpPass)
                $webclient.UploadFile($ftpUri, $filePath)
                Write-Output "FTP upload uspešen."
            }
            catch {
                Write-Output "Napaka pri FTP uploadu: $_"
                Write-Output $ftpUri
            }
        } -ArgumentList "$ftpServer/web/pings/$fileName", $filePath, $ftpUser, $ftpPass | Out-Null
        $previousTime = $currentTime
    }

    # Brisanje datotek starejših kot 7 dni
    Get-ChildItem -Path $logPath -Filter "PingLog_*.txt" | 
        Where-Object { $_.CreationTime -lt (Get-Date).AddDays(-7) } |
        Remove-Item -Force

    # Počakaj 60 sekund
    Start-Sleep -Seconds 1
}
