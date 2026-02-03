# Tailscale Auto VPN Kurulum Scripti

PLC sistemleri için otomatik Tailscale VPN kurulum aracı.

## 🚀 Hızlı Kurulum

PowerShell'i **Yönetici olarak** açın ve aşağıdaki komutu çalıştırın:

```powershell
irm https://raw.githubusercontent.com/GorkemGuray/Tailscale-Auto-VPN/main/kurulum.ps1 | iex
```

## 📋 Ne Yapar?

1. **Ağ Kartı Yapılandırması**: Seçilen ağ kartına `192.168.250.x` IP atar
2. **Tailscale Kurulumu**: Tailscale'i otomatik indirir ve kurar
3. **VPN Bağlantısı**: Cihazı Tailscale ağına bağlar ve route advertise eder

## ⚙️ Parametreli Kullanım

Sessiz/otomatik kurulum için parametreler kullanabilirsiniz:

```powershell
.\kurulum.ps1 -AuthKey "tskey-auth-xxx" -DeviceName "Musteri-PLC" -Silent
```

### Tüm Parametreler

| Parametre | Açıklama | Varsayılan |
|-----------|----------|------------|
| `-AuthKey` | Tailscale Auth Key | (interaktif sorulur) |
| `-DeviceName` | Cihaz ismi | (interaktif sorulur) |
| `-Subnet` | Hedef subnet | `192.168.250` |
| `-IpMin` | IP aralığı alt sınır | `30` |
| `-IpMax` | IP aralığı üst sınır | `200` |
| `-LoginServer` | Headscale sunucu adresi | (boş) |
| `-Silent` | Onay istemeden çalıştır | `false` |

## 📝 Gereksinimler

- Windows 10/11
- PowerShell 5.1+
- Yönetici izinleri
- İnternet bağlantısı (Tailscale indirmek için)

## 🔧 Özellikler

- ✅ Tailscale otomatik indirme ve kurulum
- ✅ IP çakışma kontrolü (ping testi)
- ✅ Tüm fiziksel ağ kartlarını listeleme
- ✅ Renkli terminal çıktısı
- ✅ Log dosyası oluşturma
- ✅ Uzaktan tek satırda kurulum

## 📄 Lisans

MIT License
