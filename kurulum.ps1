<#
.SYNOPSIS
    Mekatronik Otomasyon - Otomatik VPN Kurulum Scripti
    
.DESCRIPTION
    Tailscale VPN kurulumu ve ag yapilandirmasi icin otomatik script.
    Uzaktan calistirilabilir: irm https://gorkem.co/vpn | iex
    
.PARAMETER AuthKey
    Tailscale Auth Key (zorunlu - interaktif modda sorulur)
    
.PARAMETER DeviceName
    Cihaza verilecek isim (zorunlu - interaktif modda sorulur)
    
.PARAMETER Subnet
    Hedef subnet (varsayilan: 192.168.250)
    
.PARAMETER IpMin
    IP araliginin alt siniri (varsayilan: 30)
    
.PARAMETER IpMax
    IP araliginin ust siniri (varsayilan: 200)
    
.PARAMETER LoginServer
    Headscale kullaniliyorsa sunucu adresi
    
.PARAMETER Silent
    Sessiz mod - onay istemez

.EXAMPLE
    irm https://gorkem.co/vpn | iex
    
.EXAMPLE
    .\kurulum.ps1 -AuthKey "tskey-xxx" -DeviceName "Musteri-PLC" -Silent
#>

param(
    [string]$AuthKey = "",
    [string]$DeviceName = "",
    [string]$Subnet = "192.168.250",
    [int]$IpMin = 30,
    [int]$IpMax = 200,
    [string]$LoginServer = "",
    [switch]$Silent
)

# ============================================
# YAPILANDIRMA
# ============================================
$Script:Version = "10.0"
$Script:TailscaleUrl = "https://pkgs.tailscale.com/stable/tailscale-setup-latest.exe"
$Script:TailscalePath = "C:\Program Files\Tailscale\tailscale.exe"

# ============================================
# YARDIMCI FONKSIYONLAR
# ============================================

function Write-ColorText {
    param(
        [string]$Text,
        [string]$Type = "Info"
    )
    
    switch ($Type) {
        "Success" { Write-Host $Text -ForegroundColor Green }
        "Error" { Write-Host $Text -ForegroundColor Red }
        "Warning" { Write-Host $Text -ForegroundColor Yellow }
        "Info" { Write-Host $Text -ForegroundColor Cyan }
        "Header" { Write-Host $Text -ForegroundColor Magenta }
        default { Write-Host $Text }
    }
}

function Write-Log {
    param([string]$Message)
    
    $LogDir = Join-Path $env:TEMP "TailscaleSetup"
    if (-not (Test-Path $LogDir)) {
        New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
    }
    
    $LogFile = Join-Path $LogDir "kurulum_$(Get-Date -Format 'yyyyMMdd').log"
    $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Add-Content -Path $LogFile -Value "[$Timestamp] $Message" -ErrorAction SilentlyContinue
}

function Test-Administrator {
    $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($currentUser)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-NetworkAdapters {
    # Tum fiziksel ag kartlarini listele (bagli olmasa bile)
    # Sanal adaptorler (Tailscale, VPN, Hyper-V vb.) haric tutulur
    Get-NetAdapter | Where-Object { 
        $_.Virtual -eq $false -and 
        $_.Name -notlike "*Tailscale*" -and
        $_.Name -notlike "*VPN*" -and
        $_.InterfaceDescription -notlike "*Tailscale*" -and
        $_.InterfaceDescription -notlike "*Virtual*" -and
        $_.InterfaceDescription -notlike "*Hyper-V*"
    } | Select-Object -Property Name, InterfaceDescription, Status, ifIndex
}

function Test-IpAvailable {
    param([string]$IpAddress)
    
    $ping = Test-Connection -ComputerName $IpAddress -Count 1 -Quiet -TimeoutSeconds 1 -ErrorAction SilentlyContinue
    return -not $ping
}

function Get-AdapterCurrentIp {
    param([string]$AdapterName)
    
    $config = Get-NetIPAddress -InterfaceAlias $AdapterName -AddressFamily IPv4 -ErrorAction SilentlyContinue
    return $config.IPAddress
}

function Find-FreeIp {
    param(
        [string]$SubnetBase,
        [int]$Min,
        [int]$Max,
        [int]$MaxAttempts = 10
    )
    
    for ($i = 1; $i -le $MaxAttempts; $i++) {
        $randNum = Get-Random -Minimum $Min -Maximum ($Max + 1)
        $testIp = "$SubnetBase.$randNum"
        
        Write-Host "[$i/$MaxAttempts] $testIp kontrol ediliyor..." -NoNewline
        
        if (Test-IpAvailable -IpAddress $testIp) {
            Write-ColorText " Musait!" "Success"
            return $testIp
        }
        else {
            Write-ColorText " Kullaniliyor." "Warning"
        }
    }
    
    return $null
}

function Install-Tailscale {
    Write-ColorText "`n[ISLEM] Tailscale indiriliyor..." "Info"
    Write-Log "Tailscale indirme basladi"
    
    $installerPath = Join-Path $env:TEMP "tailscale-setup.exe"
    
    try {
        # Progress bar'i gizle (hizlandirir)
        $ProgressPreference = 'SilentlyContinue'
        
        Invoke-WebRequest -Uri $Script:TailscaleUrl -OutFile $installerPath -UseBasicParsing
        
        Write-ColorText "[OK] Tailscale indirildi." "Success"
        Write-Log "Tailscale indirildi: $installerPath"
        
        Write-ColorText "[ISLEM] Tailscale kuruluyor..." "Info"
        
        $process = Start-Process -FilePath $installerPath -ArgumentList "/S" -Wait -PassThru
        
        if ($process.ExitCode -eq 0) {
            Write-ColorText "[OK] Tailscale kuruldu." "Success"
            Write-Log "Tailscale kurulum basarili"
            
            # Servisin baslamasini bekle
            Write-Host "Servis baslatiliyor..."
            Start-Sleep -Seconds 5
            return $true
        }
        else {
            Write-ColorText "[HATA] Kurulum basarisiz! Kod: $($process.ExitCode)" "Error"
            Write-Log "Tailscale kurulum hatasi: $($process.ExitCode)"
            return $false
        }
    }
    catch {
        Write-ColorText "[HATA] Tailscale indirilemedi: $_" "Error"
        Write-Log "Tailscale indirme hatasi: $_"
        return $false
    }
}

# ============================================
# ANA PROGRAM
# ============================================

Clear-Host
Write-ColorText "========================================================" "Header"
Write-ColorText "   PLC ERISIM SISTEMI KURULUM SIHIRBAZI v$($Script:Version)" "Header"
Write-ColorText "   Uzaktan Calistirma: irm https://gorkem.co/vpn | iex" "Header"
Write-ColorText "========================================================" "Header"
Write-Host ""

Write-Log "========================================"
Write-Log "Kurulum basladi - v$($Script:Version)"
Write-Log "========================================"

# 1. YONETICI KONTROLU
if (-not (Test-Administrator)) {
    Write-ColorText "[HATA] Yonetici izni gerekli!" "Error"
    Write-Host "Lutfen PowerShell'i 'Yonetici Olarak Calistir' ile acin."
    Write-Log "HATA: Yonetici izni yok"
    
    if (-not $Silent) {
        Write-Host "`nDevam etmek icin bir tusa basin..."
        $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    }
    exit 1
}

Write-ColorText "[OK] Yonetici izni dogrulandi." "Success"
Write-Log "Yonetici izni dogrulandi"

# 2. CIHAZ ISMI
if ([string]::IsNullOrEmpty($DeviceName)) {
    do {
        $DeviceName = Read-Host "`n1. Cihaza verilecek isim (Orn: Musteri-Fabrika)"
    } while ([string]::IsNullOrEmpty($DeviceName))
}

Write-ColorText "[OK] Cihaz ismi: $DeviceName" "Success"
Write-Log "Cihaz ismi: $DeviceName"

# 3. AUTH KEY
if ([string]::IsNullOrEmpty($AuthKey)) {
    do {
        $AuthKey = Read-Host "`n2. Tailscale Auth Key (tskey-auth-...)"
    } while ([string]::IsNullOrEmpty($AuthKey))
}

Write-ColorText "[OK] Auth Key alindi." "Success"
Write-Log "Auth Key alindi"

# 4. AG KARTI SECIMI
Write-Host "`n--------------------------------------------------------"
Write-Host "MEVCUT AG KARTLARI:"
Write-Host "--------------------------------------------------------"

$adapters = Get-NetworkAdapters
$adapterList = @()
$i = 1

foreach ($adapter in $adapters) {
    $adapterList += $adapter
    $statusText = if ($adapter.Status -eq "Up") { "(Bagli)" } else { "(Bagli Degil)" }
    Write-Host "[$i] $($adapter.Name) - $($adapter.InterfaceDescription) $statusText"
    $i++
}

if ($adapterList.Count -eq 0) {
    Write-ColorText "[HATA] Aktif ag karti bulunamadi!" "Error"
    Write-Log "HATA: Ag karti bulunamadi"
    exit 1
}

Write-Host ""
Write-ColorText "DIKKAT: Yanlis kart secimi interneti kesebilir." "Warning"
Write-ColorText "Lutfen sadece PLC'ye bagli olan karti secin." "Warning"

do {
    $selection = Read-Host "`n3. PLC'nin bagli oldugu kart numarasi (1-$($adapterList.Count))"
    $selIndex = [int]$selection - 1
} while ($selIndex -lt 0 -or $selIndex -ge $adapterList.Count)

$SelectedAdapter = $adapterList[$selIndex].Name
Write-ColorText "[OK] Secilen kart: $SelectedAdapter" "Success"
Write-Log "Secilen kart: $SelectedAdapter"

# 5. ONAY
if (-not $Silent) {
    Write-Host "`n--------------------------------------------------------"
    Write-ColorText "ONAY ISTENYOR:" "Warning"
    Write-Host "--------------------------------------------------------"
    Write-Host "  Secilen Kart : $SelectedAdapter"
    Write-Host "  Cihaz Ismi   : $DeviceName"
    Write-Host "  Hedef Subnet : $Subnet.0/24"
    Write-Host "--------------------------------------------------------"
    
    $confirm = Read-Host "`nBu ayarlarla devam etmek istiyor musunuz? [E/H]"
    if ($confirm -ne "E" -and $confirm -ne "e") {
        Write-ColorText "[IPTAL] Kullanici iptal etti." "Warning"
        Write-Log "Kullanici kurulumu iptal etti"
        exit 0
    }
}

Write-Log "Kullanici onayladi"

# 6. IP KONTROLU
Write-Host "`n--------------------------------------------------------"
Write-Host "4. IP Yapilandirmasi Kontrol Ediliyor..."
Write-Host "--------------------------------------------------------"

$currentIp = Get-AdapterCurrentIp -AdapterName $SelectedAdapter

if ($currentIp -and $currentIp -like "$Subnet.*") {
    Write-ColorText "[BILGI] Bu kartta zaten $Subnet.x IP adresi var: $currentIp" "Success"
    Write-ColorText "[BILGI] Mevcut ayarlar korundu." "Info"
    Write-Log "IP zaten dogru subnetde: $currentIp"
}
else {
    Write-ColorText "[ISLEM] Kart $Subnet blogunda degil. IP ataniyor..." "Warning"
    Write-Log "IP atama gerekiyor"
    
    $newIp = Find-FreeIp -SubnetBase $Subnet -Min $IpMin -Max $IpMax
    
    if ($null -eq $newIp) {
        Write-ColorText "[HATA] Musait IP bulunamadi!" "Error"
        Write-Log "HATA: Musait IP bulunamadi"
        exit 1
    }
    
    Write-Log "Musait IP bulundu: $newIp"
    
    try {
        # Mevcut IP'leri kaldir
        Remove-NetIPAddress -InterfaceAlias $SelectedAdapter -AddressFamily IPv4 -Confirm:$false -ErrorAction SilentlyContinue
        
        # Yeni IP ata
        New-NetIPAddress -InterfaceAlias $SelectedAdapter -IPAddress $newIp -PrefixLength 24 -ErrorAction Stop | Out-Null
        
        Write-ColorText "[BASARILI] Yeni IP: $newIp" "Success"
        Write-Log "IP atandi: $newIp"
        
        Start-Sleep -Seconds 2
    }
    catch {
        Write-ColorText "[HATA] IP atanamadi: $_" "Error"
        Write-Log "HATA: IP atama hatasi: $_"
        exit 1
    }
}

# 7. TAILSCALE KURULUM
Write-Host "`n--------------------------------------------------------"
Write-Host "5. VPN Durumu Kontrol Ediliyor..."
Write-Host "--------------------------------------------------------"

if (Test-Path $Script:TailscalePath) {
    Write-ColorText "[BILGI] Tailscale zaten yuklu." "Success"
    Write-Log "Tailscale onceden yuklu"
}
else {
    $installResult = Install-Tailscale
    if (-not $installResult) {
        Write-ColorText "[HATA] Tailscale kurulamadi!" "Error"
        exit 1
    }
}

# 8. TAILSCALE BAGLANTI
Write-Host "`n--------------------------------------------------------"
Write-Host "6. Sunucuya Baglaniliyor..."
Write-Host "--------------------------------------------------------"

Write-Log "Tailscale baglantisi kuruluyor"

$tailscaleArgs = @(
    "up",
    "--authkey=$AuthKey",
    "--hostname=$DeviceName",
    "--advertise-routes=$Subnet.0/24",
    "--unattended",
    "--accept-routes",
    "--force-reauth",
    "--reset"
)

if (-not [string]::IsNullOrEmpty($LoginServer)) {
    $tailscaleArgs += "--login-server=$LoginServer"
}

try {
    $result = & $Script:TailscalePath $tailscaleArgs 2>&1
    
    if ($LASTEXITCODE -ne 0) {
        Write-ColorText "[HATA] Tailscale baglantisi kurulamadi!" "Error"
        Write-Host $result
        Write-Log "HATA: Tailscale baglanti hatasi"
        exit 1
    }
    
    Write-ColorText "[OK] Tailscale baglantisi kuruldu." "Success"
    Write-Log "Tailscale baglantisi basarili"
}
catch {
    Write-ColorText "[HATA] Tailscale baglanti hatasi: $_" "Error"
    Write-Log "HATA: $_"
    exit 1
}

# 9. DURUM KONTROLU
Write-Host "`n--------------------------------------------------------"
Write-Host "7. Baglanti Durumu:"
Write-Host "--------------------------------------------------------"

Start-Sleep -Seconds 3
& $Script:TailscalePath status

# 10. TAMAMLANDI
Write-Host ""
Write-ColorText "========================================================" "Success"
Write-ColorText "   KURULUM BASARIYLA TAMAMLANDI!" "Success"
Write-ColorText "========================================================" "Success"
Write-Host ""
Write-Host "  Cihaz Ismi    : $DeviceName"
Write-Host "  Ag Karti      : $SelectedAdapter"
Write-Host "  Advertise     : $Subnet.0/24"
Write-Host ""
Write-ColorText "  Lutfen VPN panelinden Route onayini vermeyi unutmayin." "Warning"
Write-Host ""

Write-Log "Kurulum basariyla tamamlandi"
Write-Log "========================================"

if (-not $Silent) {
    Write-Host "Devam etmek icin bir tusa basin..."
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
}
