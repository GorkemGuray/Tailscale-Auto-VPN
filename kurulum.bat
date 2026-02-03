@echo off
setlocal EnableDelayedExpansion
cls
title Otomatik PLC Ag ve VPN Kurulum Araci (Final v8)

:: ==========================================================
:: AYARLAR (Lutfen Auth Key kismini doldurun)
:: ==========================================================
set "AUTH_KEY=tskey-auth-k123456CNTRL-abcdefg123456"
set "TARGET_SUBNET=192.168.250"
:: Headscale kullaniyorsaniz asagiya yazin, yoksa bos birakin:
set "LOGIN_SERVER="
:: ==========================================================

:: 1. YONETICI IZNI KONTROLU
net session >nul 2>&1
if %errorLevel% neq 0 (
    echo.
    echo HATA: Yonetici izni gerekli!
    echo Lutfen dosyaya sag tiklayip "Yonetici Olarak Calistir" deyin.
    pause
    exit
)

echo.
echo ========================================================
echo   PLC ERISIM SISTEMI KURULUM SIHIRBAZI
echo ========================================================
echo.

:: 2. CIHAZ ISMI ALMA
:askName
set /p "DeviceName=1. Cihaza verilecek isim (Orn: Musteri-Fabrika): "
if "%DeviceName%"=="" goto askName
echo [OK] Cihaz ismi: %DeviceName%
echo.

:: 3. AG KARTI LISTELEME
echo --------------------------------------------------------
echo MEVCUT AG KARTLARI:
echo --------------------------------------------------------
set count=0
for /f "skip=3 tokens=3*" %%A in ('netsh interface show interface') do (
    set /a count+=1
    set "adapter[!count!]=%%B"
    echo [!count!] %%B
)

if %count%==0 (
    echo HATA: Ag karti bulunamadi!
    pause
    exit
)

echo.
echo DIKKAT: Yanlis kart secimi interneti kesebilir.
echo Lutfen sadece PLC'ye bagli olan karti secin.
echo.

:selectAdapter
set /p "selection=2. PLC'nin bagli oldugu kart numarasi (1-%count%): "
if "%selection%"=="" goto selectAdapter
if %selection% gtr %count% goto selectAdapter
if %selection% lss 1 goto selectAdapter

set "SelectedAdapter=!adapter[%selection%]!"
echo.
echo SECILEN KART: "%SelectedAdapter%"
echo IP Yapilandirmasi kontrol ediliyor...

:: 4. IP KONTROLU (GOTO YAPISI - COKMEZ)
netsh interface ip show address "%SelectedAdapter%" | findstr /C:"%TARGET_SUBNET%." >nul

if %errorLevel% EQU 0 goto :IPAlreadySet

:: --- IP YOKSA BURASI CALISIR ---
echo.
echo [ISLEM] Kart %TARGET_SUBNET% blogunda degil.
echo Rastgele IP ataniyor...

set /a "randNum=(%random% %% 224) + 31"
set "NewIP=%TARGET_SUBNET%.!randNum!"

netsh interface ip set address name="%SelectedAdapter%" source=static addr=!NewIP! mask=255.255.255.0 gateway=none

if !errorLevel! neq 0 (
    echo.
    echo HATA: IP Adresi degistirilemedi!
    pause
    exit
)
echo [BASARILI] Yeni IP: !NewIP!
timeout /t 2 >nul
goto :CheckVPN

:IPAlreadySet
echo.
echo [BILGI] Bu kartta zaten %TARGET_SUBNET%.x IP adresi var.
echo [BILGI] Mevcut ayarlar korundu.

:CheckVPN
:: 5. VPN KURULUM VE KONTROL
echo.
echo --------------------------------------------------------
echo 3. VPN Durumu Kontrol Ediliyor...
echo --------------------------------------------------------

if exist "C:\Program Files\Tailscale\tailscale.exe" (
    echo [BILGI] Tailscale zaten yuklu. Yapilandirmaya geciliyor...
    goto :RunTailscale
)

echo [BILGI] Tailscale yukleniyor...
if not exist "tailscale-setup.msi" (
    echo HATA: tailscale-setup.msi dosyasi ayni klasorde yok!
    pause
    exit
)

msiexec /i "tailscale-setup.msi" /quiet /qn /norestart
echo Kurulumun bitmesi bekleniyor (10 saniye)...
timeout /t 10 /nobreak >nul

:RunTailscale
:: 6. TAILSCALE YAPILANDIRMA
echo.
echo 4. Sunucuya baglaniliyor...

if defined LOGIN_SERVER (
    set "SRV_PARAM=%LOGIN_SERVER%"
) else (
    set "SRV_PARAM="
)

"C:\Program Files\Tailscale\tailscale.exe" up ^
--authkey=%AUTH_KEY% ^
--hostname="%DeviceName%" ^
--advertise-routes=%TARGET_SUBNET%.0/24 ^
%SRV_PARAM% ^
--unattended ^
--accept-routes ^
--force-reauth ^
--reset

echo.
echo ========================================================
echo   KURULUM TAMAMLANDI!
echo ========================================================
echo.
echo   Lutfen VPN panelinden Route onayini vermeyi unutmayin.
echo.
pause