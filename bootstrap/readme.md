# Розгортання SD LAB у локальній мережі

Домен системи — `sd.xenon.local`. У прикладах Ubuntu VM має адресу `192.168.10.50`, Windows DNS — `192.168.10.10`, а обліковий запис на VM — `ubuntu`. Підставте свої значення.

## 1. Підготуйте Ubuntu VM і TLS-файли

Розгорніть і запустіть Ubuntu Server 26.04 зі сталою IPv4-адресою, увімкніть SSH-сервер і підготуйте користувача з доступом до `sudo`. Дозвольте `22/tcp` із Windows Server, `80/tcp` і `443/tcp` із клієнтської мережі. VM потрібен вихід до GitHub, APT-репозиторіїв і реєстрів контейнерів.

На Windows Server із установленим OpenSSL 3.x виконайте в PowerShell із каталогу `bootstrap`:

```powershell
.\New-SdLabTls.ps1 -OutputDirectory 'C:\TLS'
```

Вкажіть новий каталог на NTFS під наявною батьківською текою. Якщо OpenSSL відсутній у `PATH`, додайте `-OpenSslPath` із повним шляхом до `openssl.exe`. Введіть пароль для ключа CA під час створення та повторно під час підпису. Сертифікат сервера діє 365 днів.

Скрипт створює три файли PEM:

| Файл | Вміст |
|---|---|
| `fullchain.pem` | Сертифікат сервера та проміжні сертифікати. Сертифікат має покривати `sd.xenon.local` і `*.sd.xenon.local` або всі DNS-імена окремо. |
| `privkey.pem` | Приватний ключ сертифіката сервера без парольної фрази, щоб Nginx запускався автоматично. |
| `root-ca.crt` | Публічний кореневий сертифікат внутрішнього CA. |

Створений CA підписує сертифікат сервера напряму, тому `fullchain.pem` містить лише сертифікат сервера. Збережіть зашифрований ключ `ca-private/root-ca.key.pem` і `root-ca.crt` у захищеній резервній копії для майбутнього перевипуску. На VM передавайте лише три файли з таблиці.

## 2. Налаштуйте DNS

На Windows Server 2019 відкрийте Windows PowerShell 5.1 від адміністратора й виконайте з каталогу `bootstrap`:

```powershell
.\Set-SdLabDnsServer.ps1 -ZoneName sd.xenon.local -VmAddress 192.168.10.50
```

Надайте клієнтам доступ до цієї зони через локальний DNS. У мережі з Active Directory створіть зону на чинному DNS або налаштуйте умовне пересилання. На Ubuntu з `systemd-resolved` задайте маршрут `~sd.xenon.local` для інтерфейсу з локальним DNS і перевірте його командою `resolvectl query sd.xenon.local`.

## 3. Передайте сертифікати з Windows Server на Ubuntu

Якщо `ssh.exe` і `scp.exe` відсутні, встановіть OpenSSH Client у PowerShell від адміністратора:

```powershell
Add-WindowsCapability -Online -Name OpenSSH.Client~~~~0.0.1.0
```

Під час першого підключення через `ssh ubuntu@192.168.10.50` звірте відбиток із результатом `ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub` у консолі VM, якщо SSH пропонує ключ ED25519. Підключіться від того самого користувача Windows, який запускатиме копіювання. Для автоматичного входу використовуйте SSH-ключ.

```powershell
.\Copy-SdLabTlsToVm.ps1 -VmHost 192.168.10.50 -SshUser ubuntu `
  -FullChain 'C:\TLS\fullchain.pem' -PrivateKey 'C:\TLS\privkey.pem' `
  -RootCA 'C:\TLS\root-ca.crt'
```

Скрипт копіює файли в окремий приватний каталог у домашній теці користувача Ubuntu й виводить рядок `TLS_DIR=...`. Для SSH на іншому порту додайте `-SshPort`.

## 4. Розгорніть SD LAB на Ubuntu

Увійдіть на VM тим самим користувачем SSH і вставте **точний рядок `TLS_DIR=...`**, який вивів скрипт. Після публікації файлів у гілці `feature/https` виконайте:

```bash
( installer=$(mktemp) && trap 'rm -f -- "$installer"' EXIT &&
  curl -fsSL https://raw.githubusercontent.com/plvnkv/spatial-data-lab/feature/https/bootstrap/deploy-ubuntu.sh -o "$installer" &&
  sudo bash "$installer" 192.168.10.50 "$TLS_DIR/fullchain.pem" "$TLS_DIR/privkey.pem" "$TLS_DIR/root-ca.crt" )
```

Інсталятор встановить Docker і Compose, клонує репозиторій у `/opt/spatial-data-lab`, згенерує `.env` та запустить HTTPS. Для приватного репозиторію завантажте інсталятор з авторизованого сеансу й забезпечте GitHub-доступ для `git` під `sudo`. Повторний запуск зберігає `.env`, томи й наявну версію коду.

Для наявного checkout з підготовленим `.env` використовуйте `sudo ./bootstrap/setup-ubuntu.sh sd.xenon.local IP FULLCHAIN KEY ROOT_CA`. Для поновлення TLS повторіть кроки 3–4 із новими файлами. Після успішного розгортання тимчасову копію TLS-файлів у домашній теці VM можна прибрати.

Якщо переносите наявні дані GeoNode, перед розгортанням зробіть резервну копію. Після переходу виконайте команду з фактичним старим origin:

```bash
sudo /opt/spatial-data-lab/bootstrap/compose-lan.sh exec -T django python manage.py migrate_baseurl --force \
  --source-address http://localhost:8088 --target-address https://sd.xenon.local
```

## 5. Налаштуйте клієнтів і перевірте доступ

Розгорніть кореневий CA на клієнтах через GPO або налаштуйте окрему машину з Windows 10, 11 чи Server 2019 у PowerShell від адміністратора:

```powershell
Get-NetAdapter
.\Set-SdLabDnsClient.ps1 -InterfaceIndex 12 -DnsServer 192.168.10.10 `
  -ZoneName sd.xenon.local -RootCA 'C:\TLS\root-ca.crt'
```

Підставте індекс активного адаптера. Відкрийте `https://sd.xenon.local/sd-lab/` і перевірте стан сервісів, сертифікат та вхід у GeoNode і GeoServer. Prometheus і Alertmanager відкриті для читання. Grafana потребує облікового запису з роллю Viewer, а консоль RustFS і приватні бакети — облікових даних RustFS.

Стан контейнерів перевіряйте через `sudo /opt/spatial-data-lab/bootstrap/compose-lan.sh ps`. Для тестових тайлів перейдіть у `/opt/spatial-data-lab` і виконайте `sudo sh scripts/seed-tiles.sh`.
