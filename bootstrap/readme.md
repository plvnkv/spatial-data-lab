# SD LAB у локальній мережі

Домен SD LAB — `sd.xenon.local`. Замініть приклади IP-адрес на свої.

## 1. DNS на Windows Server 2019

У Windows PowerShell 5.1 від адміністратора запустіть:

```powershell
.\Set-SdLabDnsServer.ps1 -ZoneName sd.xenon.local -VmAddress 192.168.10.50
```

Скрипт встановлює роль DNS за потреби й додає в окрему зону записи для порталу та семи піддоменів. Додайте цей DNS у DHCP для клієнтів і налаштуйте Ubuntu VM користуватися DNS, який бачить цю зону. У мережі з Active Directory виконайте скрипт на чинному DNS або налаштуйте на ньому пересилання для цієї зони.

## 2. HTTPS на Ubuntu Server 26.04

Якщо VM використовує `systemd-resolved`, задайте `~sd.xenon.local` як DNS-маршрут на інтерфейсі з локальним DNS. Перевірте резолюцію командою `resolvectl query sd.xenon.local`.

Призначте VM сталу IP-адресу, дозвольте порти 80 і 443 із LAN та завантажте на VM сертифікат і ключ. Сертифікат внутрішнього CA має покривати `sd.xenon.local` і `*.sd.xenon.local` або всі імена окремо.

Після публікації скрипту в гілці `feature/https` виконайте на VM:

```bash
( installer=$(mktemp) && trap 'rm -f -- "$installer"' EXIT &&
  curl -fsSL https://raw.githubusercontent.com/plvnkv/spatial-data-lab/feature/https/bootstrap/deploy-ubuntu.sh -o "$installer" &&
  sudo bash "$installer" 192.168.10.50 /path/fullchain.pem /path/privkey.pem /path/root-ca.crt )
```

Скрипт встановить Docker і Compose, клонує репозиторій у `/opt/spatial-data-lab`, створить `.env` та запустить HTTPS. Для приватного GitHub-репозиторію потрібен попередньо налаштований доступ для завантаження скрипту й клонування від імені root. Повторний запуск зберігає `.env`, томи й версію локального коду.

Для готового checkout використовуйте `sudo ./bootstrap/setup-ubuntu.sh sd.xenon.local IP FULLCHAIN KEY ROOT_CA`. Після поновлення сертифіката повторіть запуск. Для керування стеком використовуйте `sudo /opt/spatial-data-lab/bootstrap/compose-lan.sh ps`.

Якщо переносите наявні дані, спершу зробіть резервну копію. Після переходу замініть попередній origin у GeoNode:

```bash
sudo ./bootstrap/compose-lan.sh exec -T django python manage.py migrate_baseurl --force \
  --source-address http://localhost:8088 --target-address https://sd.xenon.local
```

## 3. DNS на Windows 10, 11 і Server 2019

За потреби налаштуйте окремий клієнт у Windows PowerShell від адміністратора:

```powershell
Get-NetAdapter
.\Set-SdLabDnsClient.ps1 -InterfaceIndex 12 -DnsServer 192.168.10.10 -ZoneName sd.xenon.local
```

Замініть `12` на індекс активного адаптера. Для внутрішнього CA додайте `-RootCA C:\path\root-ca.crt` або розгорніть сертифікат через GPO. Параметр `-Reset` разом з `-InterfaceIndex` повертає DNS від DHCP.

## 4. Огляд

Відкрийте `https://sd.xenon.local/sd-lab/`. Сторінка показує результати внутрішніх перевірок і містить посилання на всі сервіси. Prometheus і Alertmanager доступні для читання. Для Grafana створіть користувачів із роллю Viewer. У RustFS перевірка стану доступна всім, а консоль і приватні бакети потребують облікових даних.

Для тестових тайлів виконайте `sh scripts/seed-tiles.sh` з кореня репозиторію від користувача з доступом до Docker. Щоб додати інші тайли для LAN, внесіть дозволені джерела в `nginx.conf.in` і повторіть запуск налаштування.
