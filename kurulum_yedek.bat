@echo off
setlocal EnableDelayedExpansion
cls
title Otomatik PLC Ag ve VPN Kurulum Araci (Final v9)

:: ==========================================================
:: AYARLAR (Lutfen Auth Key kismini doldurun)
:: ==========================================================
set "AUTH_KEY=tskey-auth-k123456CNTRL-abcdefg123456"
set "TARGET_SUBNET=192.168.250"
set "IP_MIN=30"
set "IP_MAX=200"
:: Headscale kullaniyorsaniz asagiya yazin, yoksa bos birakin:
set "LOGIN_SERVER="
:: ==========================================================

:: RENK TANIMLARI (ANSI Escape)
for /f %%a in ('echo prompt $E ^| cmd') do set "ESC=%%a"
set "GREEN=%ESC%[92m"
set "RED=%ESC%[91m"
set "YELLOW=%ESC%[93m"
set "CYAN=%ESC%[96m"
set "RESET=%ESC%[0m"

:: LOG DOSYASI AYARLARI
set "LOGDIR=%~dp0logs"
if not exist "%LOGDIR%" mkdir "%LOGDIR%" 2>nul

:: Tarih/saat al (bolgesel ayarlardan bagimsiz)
for /f "tokens=2 delims==" %%a in ('wmic os get localdatetime /value 2^>nul') do set "dt=%%a"
set "LOGFILE=%LOGDIR%\kurulum_%dt:~0,8%_%dt:~8,6%.log"

:: Log dosyasi olusturulamazsa varsayilan kullan
if "%dt%"=="" set "LOGFILE=%LOGDIR%\kurulum.log"

:: LOG FONKSIYONU (ilk calisma)
echo [%date% %time%] ========================================== >> "%LOGFILE%" 2>nul
echo [%date% %time%] Kurulum Basladi >> "%LOGFILE%" 2>nul
echo [%date% %time%] ========================================== >> "%LOGFILE%" 2>nul

:: 1. YONETICI IZNI KONTROLU
net session >nul 2>&1
if %errorLevel% neq 0 (
    echo.
    echo %RED%[HATA] Yonetici izni gerekli!%RESET%
    echo Lutfen dosyaya sag tiklayip "Yonetici Olarak Calistir" deyin.
    call :Log "HATA: Yonetici izni yok"
    pause
    exit
)
call :Log "Yonetici izni dogrulandi"

echo.
echo %CYAN%========================================================%RESET%
echo %CYAN%   PLC ERISIM SISTEMI KURULUM SIHIRBAZI v9%RESET%
echo %CYAN%========================================================%RESET%
echo.

:: 2. CIHAZ ISMI ALMA
:askName
set /p "DeviceName=1. Cihaza verilecek isim (Orn: Musteri-Fabrika): "
if "%DeviceName%"=="" goto askName
echo %GREEN%[OK]%RESET% Cihaz ismi: %DeviceName%
call :Log "Cihaz ismi: %DeviceName%"
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
    echo %RED%[HATA] Ag karti bulunamadi!%RESET%
    call :Log "HATA: Ag karti bulunamadi"
    pause
    exit
)

echo.
echo %YELLOW%DIKKAT: Yanlis kart secimi interneti kesebilir.%RESET%
echo %YELLOW%Lutfen sadece PLC'ye bagli olan karti secin.%RESET%
echo.

:selectAdapter
set /p "selection=2. PLC'nin bagli oldugu kart numarasi (1-%count%): "
if "%selection%"=="" goto selectAdapter
if %selection% gtr %count% goto selectAdapter
if %selection% lss 1 goto selectAdapter

set "SelectedAdapter=!adapter[%selection%]!"
call :Log "Secilen ag karti: %SelectedAdapter%"

:: 4. ONAY ADIMI
echo.
echo --------------------------------------------------------
echo %YELLOW%ONAY ISTENYOR:%RESET%
echo --------------------------------------------------------
echo   Secilen Kart : %SelectedAdapter%
echo   Cihaz Ismi   : %DeviceName%
echo   Hedef Subnet : %TARGET_SUBNET%.0/24
echo --------------------------------------------------------
echo.
set /p "confirm=Bu ayarlarla devam etmek istiyor musunuz? [E/H]: "
if /i not "%confirm%"=="E" (
    echo %YELLOW%[IPTAL] Kullanici iptal etti.%RESET%
    call :Log "Kullanici kurulumu iptal etti"
    pause
    exit
)
call :Log "Kullanici onayladi, devam ediliyor"

echo.
echo SECILEN KART: "%SelectedAdapter%"
echo IP Yapilandirmasi kontrol ediliyor...

:: 5. IP KONTROLU
netsh interface ip show address "%SelectedAdapter%" | findstr /C:"%TARGET_SUBNET%." >nul
if %errorLevel% EQU 0 goto :IPAlreadySet

:: --- IP YOKSA BURASI CALISIR ---
echo.
echo %YELLOW%[ISLEM]%RESET% Kart %TARGET_SUBNET% blogunda degil.
echo IP atama islemi basliyor...
call :Log "Kart hedef subnetde degil, IP atanacak"

:: IP CAKISMA KONTROLU ILE RASTGELE IP ATAMA
set "maxAttempts=10"
set "attempt=0"

:FindFreeIP
set /a attempt+=1
if %attempt% gtr %maxAttempts% (
    echo %RED%[HATA] %maxAttempts% denemede bos IP bulunamadi!%RESET%
    call :Log "HATA: Bos IP bulunamadi"
    pause
    exit
)

set /a "randNum=(%random% %% 171) + %IP_MIN%"
set "NewIP=%TARGET_SUBNET%.!randNum!"

echo [%attempt%/%maxAttempts%] %NewIP% kontrol ediliyor...
ping -n 1 -w 500 !NewIP! >nul 2>&1
if %errorLevel% EQU 0 (
    echo %YELLOW%[UYARI]%RESET% !NewIP! kullanilmakta, baska deneniyor...
    call :Log "IP %NewIP% kullaniliyor, yeni deneme"
    goto :FindFreeIP
)

echo %GREEN%[OK]%RESET% !NewIP! musait.
call :Log "Musait IP bulundu: %NewIP%"

netsh interface ip set address name="%SelectedAdapter%" source=static addr=!NewIP! mask=255.255.255.0 gateway=none

if !errorLevel! neq 0 (
    echo.
    echo %RED%[HATA] IP Adresi degistirilemedi!%RESET%
    call :Log "HATA: IP degistirilemedi"
    pause
    exit
)
echo %GREEN%[BASARILI]%RESET% Yeni IP: !NewIP!
call :Log "IP basariyla atandi: %NewIP%"
timeout /t 2 >nul
goto :CheckVPN

:IPAlreadySet
echo.
echo %GREEN%[BILGI]%RESET% Bu kartta zaten %TARGET_SUBNET%.x IP adresi var.
echo [BILGI] Mevcut ayarlar korundu.
call :Log "IP zaten hedef subnetde, degisiklik yapilmadi"

:CheckVPN
:: 6. VPN KURULUM VE KONTROL
echo.
echo --------------------------------------------------------
echo 3. VPN Durumu Kontrol Ediliyor...
echo --------------------------------------------------------

if exist "C:\Program Files\Tailscale\tailscale.exe" (
    echo %GREEN%[BILGI]%RESET% Tailscale zaten yuklu. Yapilandirmaya geciliyor...
    call :Log "Tailscale onceden yuklu"
    goto :RunTailscale
)

echo %YELLOW%[BILGI]%RESET% Tailscale yukleniyor...
call :Log "Tailscale kurulumu basliyor"

if not exist "%~dp0tailscale-setup.msi" (
    echo %RED%[HATA] tailscale-setup.msi dosyasi ayni klasorde yok!%RESET%
    call :Log "HATA: MSI dosyasi bulunamadi"
    pause
    exit
)

msiexec /i "%~dp0tailscale-setup.msi" /quiet /qn /norestart
set "msiResult=%errorLevel%"

if %msiResult% neq 0 (
    echo %RED%[HATA] Tailscale kurulumu basarisiz! (Kod: %msiResult%)%RESET%
    call :Log "HATA: MSI kurulumu basarisiz, kod: %msiResult%"
    pause
    exit
)

echo Kurulumun bitmesi bekleniyor (15 saniye)...
call :Log "MSI kurulumu tamamlandi, bekleniyor"
timeout /t 15 /nobreak >nul

:RunTailscale
:: 7. TAILSCALE YAPILANDIRMA
echo.
echo 4. Sunucuya baglaniliyor...
call :Log "Tailscale baglantisi kuruluyor"

if defined LOGIN_SERVER (
    set "SRV_PARAM=--login-server=%LOGIN_SERVER%"
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

set "tsResult=%errorLevel%"

if %tsResult% neq 0 (
    echo.
    echo %RED%[HATA] Tailscale baglantisi kurulamadi! (Kod: %tsResult%)%RESET%
    call :Log "HATA: Tailscale baglantisi basarisiz, kod: %tsResult%"
    pause
    exit
)

call :Log "Tailscale baglantisi kuruldu"

:: 8. TAILSCALE DURUM KONTROLU
echo.
echo --------------------------------------------------------
echo 5. Baglanti Durumu Kontrol Ediliyor...
echo --------------------------------------------------------
timeout /t 3 >nul

"C:\Program Files\Tailscale\tailscale.exe" status
set "statusResult=%errorLevel%"

if %statusResult% neq 0 (
    echo.
    echo %YELLOW%[UYARI] Durum alinamadi, ancak baglanti kurulmus olabilir.%RESET%
    call :Log "UYARI: Tailscale status alinamadi"
) else (
    echo.
    echo %GREEN%[OK]%RESET% Baglanti durumu yukarida goruntuleniyor.
    call :Log "Tailscale status basarili"
)

echo.
echo %GREEN%========================================================%RESET%
echo %GREEN%   KURULUM BASARIYLA TAMAMLANDI!%RESET%
echo %GREEN%========================================================%RESET%
echo.
echo   %CYAN%Cihaz Ismi    :%RESET% %DeviceName%
echo   %CYAN%Ag Karti      :%RESET% %SelectedAdapter%
echo   %CYAN%Advertise     :%RESET% %TARGET_SUBNET%.0/24
echo   %CYAN%Log Dosyasi   :%RESET% %LOGFILE%
echo.
echo   %YELLOW%Lutfen VPN panelinden Route onayini vermeyi unutmayin.%RESET%
echo.
call :Log "Kurulum basariyla tamamlandi"
call :Log "=========================================="
pause
exit /b 0

:: ============================================
:: LOG FONKSIYONU
:: ============================================
:Log
echo [%date% %time%] %~1 >> "%LOGFILE%"
exit /b 0