$WG = "C:\Program Files\WireGuard\wg.exe"
$SERVER_IP = "91.84.96.45"
$WG_PORT = 51820
$CONFIG_DIR = "C:\WireGuard"
$PEERS_DIR = "$CONFIG_DIR\peers"
$JSON_DIR = "$CONFIG_DIR\peers\json"
$NUM_PEERS = 30
$MTU = 1280

New-Item -ItemType Directory -Force -Path $CONFIG_DIR | Out-Null
New-Item -ItemType Directory -Force -Path $PEERS_DIR | Out-Null
New-Item -ItemType Directory -Force -Path $JSON_DIR | Out-Null

Write-Host "=== Generating server keys..." -ForegroundColor Cyan
$serverPriv = & $WG genkey
$serverPub  = $serverPriv | & $WG pubkey
Write-Host "  Server public key: $serverPub" -ForegroundColor Green

$serverConf = "[Interface]`r`nAddress = 10.0.0.1/24`r`nListenPort = $WG_PORT`r`nPrivateKey = $serverPriv`r`nMTU = $MTU`r`n"

Write-Host ""
Write-Host "=== Generating $NUM_PEERS peer configs..." -ForegroundColor Cyan

for ($i = 1; $i -le $NUM_PEERS; $i++) {
    $peerIP = "10.0.0.$($i + 1)"
    $peerName = "peer-" + ("{0:D2}" -f $i)

    $peerPriv = & $WG genkey
    $peerPub  = $peerPriv | & $WG pubkey
    $peerPsk  = & $WG genpsk

    $serverConf += "`r`n# $peerName ($peerIP)`r`n[Peer]`r`nPublicKey = $peerPub`r`nPresharedKey = $peerPsk`r`nAllowedIPs = $peerIP/32`r`n"

    $clientConf  = "[Interface]`r`n"
    $clientConf += "PrivateKey = $peerPriv`r`n"
    $clientConf += "Address = $peerIP/32`r`n"
    $clientConf += "DNS = 1.1.1.1, 1.0.0.1`r`n"
    $clientConf += "MTU = $MTU`r`n"
    $clientConf += "`r`n[Peer]`r`n"
    $clientConf += "PublicKey = $serverPub`r`n"
    $clientConf += "PresharedKey = $peerPsk`r`n"
    $clientConf += "Endpoint = " + $SERVER_IP + ":" + $WG_PORT + "`r`n"
    $clientConf += "AllowedIPs = 0.0.0.0/0, ::/0`r`n"
    $clientConf += "PersistentKeepalive = 25`r`n"
    Set-Content -Path "$PEERS_DIR\$peerName.conf" -Value $clientConf -Encoding UTF8

    $jsonText  = "{`n"
    $jsonText += "    ``"type``": ``"wireGuard``",`n"
    $jsonText += "    ``"wireGuard``": {`n"
    $jsonText += "        ``"interface``": {`n"
    $jsonText += "            ``"privateKey``": ``"$peerPriv``",`n"
    $jsonText += "            ``"addresses``": [``"$peerIP/32``"],`n"
    $jsonText += "            ``"dns``": [``"1.1.1.1``", ``"1.0.0.1``"],`n"
    $jsonText += "            ``"mtu``": $MTU`n"
    $jsonText += "        },`n"
    $jsonText += "        ``"peer``": {`n"
    $jsonText += "            ``"publicKey``": ``"$serverPub``",`n"
    $jsonText += "            ``"presharedKey``": ``"$peerPsk``",`n"
    $jsonText += "            ``"endpoint``": ``"" + $SERVER_IP + ":" + $WG_PORT + "``",`n"
    $jsonText += "            ``"allowedIPs``": [``"0.0.0.0/0``", ``"::/0``"],`n"
    $jsonText += "            ``"persistentKeepalive``": 25`n"
    $jsonText += "        }`n"
    $jsonText += "    }`n"
    $jsonText += "}"
    Set-Content -Path "$JSON_DIR\$peerName.json" -Value $jsonText -Encoding UTF8

    Write-Host "  ok $peerName ($peerIP)" -ForegroundColor Gray
}

Set-Content -Path "$CONFIG_DIR\wg0.conf" -Value $serverConf -Encoding UTF8

Write-Host ""
Write-Host "=== Installing WireGuard tunnel service..." -ForegroundColor Cyan
& "C:\Program Files\WireGuard\wireguard.exe" /installtunnelservice "$CONFIG_DIR\wg0.conf"
Start-Sleep 3

$svcName = 'WireGuardTunnel$wg0'
$svc = Get-Service -Name $svcName -ErrorAction SilentlyContinue
if ($svc) {
    if ($svc.Status -ne "Running") {
        Start-Service -Name $svcName -ErrorAction SilentlyContinue
        Start-Sleep 2
    }
    $status = (Get-Service -Name $svcName -ErrorAction SilentlyContinue).Status
    Write-Host "  Service status: $status" -ForegroundColor Green
} else {
    Write-Host "  Service starting in background..." -ForegroundColor Yellow
}

Write-Host ""
Write-Host "=============================================="
Write-Host "  DONE!"
Write-Host "  Peer configs: $PEERS_DIR"
Write-Host "  JSON files:   $JSON_DIR"
Write-Host "  First peer:   $JSON_DIR\peer-01.json"
Write-Host "=============================================="
Write-Host ""

Write-Host "=== peer-01.json content ===" -ForegroundColor Yellow
Get-Content "$JSON_DIR\peer-01.json"