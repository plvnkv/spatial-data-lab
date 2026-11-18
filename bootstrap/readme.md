# Розгортання SD LAB у локальній мережі

Домен системи — `sd.xenon.local`. Перед початком запишіть свої значення й підставляйте їх у всіх командах.

| Що підготувати | Приклад | Де знайти |
|---|---|---|
| Назва VM | `sd-lab` | Команда `multipass list` на комп’ютері, де запущено Multipass |
| IP-адреса Ubuntu VM | `192.168.10.50` | Команда `multipass list` або `ip -br -4 addr` усередині VM. Виберіть адресу, доступну з Windows |
| IP-адреса локального DNS | `192.168.10.10` | Адреса Windows Server, що обслуговує вашу DNS-зону |
| Користувач Ubuntu | `ubuntu` | Обліковий запис із доступом до `sudo` |
| Каталог TLS-файлів на Windows | `C:\TLS` | Новий каталог, який створить скрипт |

Команди PowerShell запускайте на Windows, а Bash — усередині Ubuntu VM. Команди `multipass` запускайте на комп’ютері, де працює Multipass. Скрипти Windows запускайте з каталогу `bootstrap` вашої копії репозиторію. Якщо копії на Windows ще немає, відкрийте на GitHub гілку `feature/https`, виберіть **Code → Download ZIP** і розпакуйте архів.

## 1. Встановіть SSH-сервер на Ubuntu VM

Розгорніть і запустіть Ubuntu Server 26.04 зі сталою IPv4-адресою, доступною з Windows Server. Підготуйте користувача `ubuntu` з доступом до `sudo`. Дозвольте `22/tcp` із Windows Server, `80/tcp` і `443/tcp` із клієнтської мережі. VM потрібен вихід до GitHub, APT-репозиторіїв і реєстрів контейнерів.

На хості Multipass виконайте такі команди. Замініть `sd-lab` на назву своєї VM з `multipass list`.

```text
multipass exec sd-lab -- sudo apt-get update
multipass exec sd-lab -- sudo apt-get install -y openssh-server
multipass exec sd-lab -- sudo systemctl enable --now ssh
multipass exec sd-lab -- systemctl is-active ssh
```

Очікуваний результат останньої команди — `active`. [Документація Ubuntu щодо OpenSSH](https://ubuntu.com/server/docs/openssh-server/).

### Дозвольте вхідний трафік на Ubuntu VM

Виконайте команди на хості Multipass. Замініть `sd-lab` на назву вашої VM з `multipass list`. У правилах нижче замініть `192.168.10.10` на IP Windows Server, з якого підключатиметеся через SSH, а `192.168.10.0/24` — на підмережу клієнтів SD LAB.

```bash
multipass exec sd-lab -- sudo apt-get install -y ufw
multipass exec sd-lab -- sudo ufw allow from 192.168.10.10 to any port 22 proto tcp
multipass exec sd-lab -- sudo ufw allow from 192.168.10.0/24 to any port 80 proto tcp
multipass exec sd-lab -- sudo ufw allow from 192.168.10.0/24 to any port 443 proto tcp
multipass exec sd-lab -- sudo ufw show added
```

Якщо хост Multipass має іншу IP-адресу, яку бачить VM, додайте окреме правило на порт 22 для цієї адреси. Воно потрібне і для подальших викликів `multipass exec`, які використовують SSH. Щоб дізнатися IP хоста, яку бачить VM, виконайте `multipass exec sd-lab -- printenv SSH_CONNECTION`. Перше поле — адреса джерела з’єднання, якщо команда повернула значення. Перевірте, що потрібні правила SSH додано, перш ніж увімкнути UFW. Якщо UFW уже активний, правила діють одразу.

```bash
multipass exec sd-lab -- sudo ufw enable
multipass exec sd-lab -- sudo ufw status numbered
```

На Windows Server перевірте порт 22 командою `Test-NetConnection 192.168.10.50 -Port 22`. Порти 80 і 443 перевіряйте після запуску Nginx у кроці 6.5. [Документація Ubuntu щодо UFW](https://documentation.ubuntu.com/security/security-features/network/firewall/).

## 2. Встановіть OpenSSL і створіть TLS-сертифікати на Windows

На Windows Server 2019 встановіть OpenSSL 3.x зі схваленого джерела. Додайте каталог із `openssl.exe` до `PATH`, відкрийте нове вікно PowerShell і з каталогу `bootstrap` виконайте:

```powershell
openssl version
.\New-SdLabTls.ps1 -OutputDirectory 'C:\TLS'
```

Вкажіть новий каталог на NTFS під наявною батьківською текою. Якщо OpenSSL відсутній у `PATH`, додайте `-OpenSslPath` із повним шляхом до `openssl.exe`. Введіть пароль для ключа CA під час створення та повторно під час підпису. Обидва сертифікати мають `notBefore` о `00:00:00 UTC` у день генерації. Сертифікат сервера діє 365 днів від цього часу. Для VM і Windows Server потрібен правильний системний час.

Скрипт створює три файли PEM:

| Файл | Вміст |
|---|---|
| `fullchain.pem` | Сертифікат сервера та проміжні сертифікати. Сертифікат має покривати `sd.xenon.local` і `*.sd.xenon.local` або всі DNS-імена окремо. |
| `privkey.pem` | Приватний ключ сертифіката сервера без парольної фрази, щоб Nginx запускався автоматично. |
| `root-ca.crt` | Публічний кореневий сертифікат внутрішнього CA. |

Створений CA підписує сертифікат сервера напряму, тому `fullchain.pem` містить лише сертифікат сервера. Збережіть зашифрований ключ `ca-private/root-ca.key.pem` і `root-ca.crt` у захищеній резервній копії для майбутнього перевипуску. На VM передавайте лише три файли з таблиці.

## 3. Налаштуйте DNS

На Windows Server 2019 відкрийте Windows PowerShell 5.1 від адміністратора й виконайте з каталогу `bootstrap`:

```powershell
.\Set-SdLabDnsServer.ps1 -ZoneName sd.xenon.local -VmAddress 192.168.10.50
```

Надайте клієнтам доступ до цієї зони через локальний DNS. У мережі з Active Directory створіть зону на чинному DNS або налаштуйте умовне пересилання. На Windows перевірте, що DNS повертає адресу VM:

```powershell
Resolve-DnsName sd.xenon.local -Type A -Server 192.168.10.10
```

На Ubuntu з `systemd-resolved` виконайте `resolvectl query sd.xenon.local`. Якщо ім’я не знаходиться, налаштуйте на мережевому інтерфейсі локальний DNS і маршрут `~sd.xenon.local`. Для перевірки до наступного перезапуску мережі можна виконати команди нижче. Замініть `ens3` на ім’я інтерфейсу з `ip -br -4 addr`. Команди замінюють поточні DNS-сервери й домени на цьому інтерфейсі. У мережі з наявними DNS-маршрутами внесіть зміни через її адміністратора.

```bash
sudo resolvectl dns ens3 192.168.10.10
sudo resolvectl domain ens3 '~sd.xenon.local'
resolvectl query sd.xenon.local
```

Для постійної роботи після перезавантаження внесіть ці значення в наявну конфігурацію мережі VM або в налаштування, які надає адміністратор мережі.

## 4. Встановіть SSH-клієнт і налаштуйте вхід за ключем

На Windows Server 2019 у PowerShell від адміністратора встановіть OpenSSH Client, якщо його ще немає:

```powershell
Add-WindowsCapability -Online -Name OpenSSH.Client~~~~0.0.1.0
```

Далі працюйте під обліковим записом Windows, з якого підключатиметеся до VM. Створіть ключ і прийміть запропонований шлях до `id_ed25519`. Якщо ключ із таким іменем уже є, використайте його або збережіть новий під іншим іменем.

```powershell
ssh-keygen -t ed25519
```

На хості Multipass додайте публічний ключ до `authorized_keys` користувача `ubuntu`. Приклад нижче для випадку, коли Multipass працює на тому самому Windows Server:

```powershell
multipass exec sd-lab -- install -d -m 700 /home/ubuntu/.ssh
multipass exec sd-lab -- touch /home/ubuntu/.ssh/authorized_keys
multipass exec sd-lab -- chmod 600 /home/ubuntu/.ssh/authorized_keys
Get-Content -LiteralPath "$env:USERPROFILE\.ssh\id_ed25519.pub" |
  multipass exec sd-lab -- tee -a /home/ubuntu/.ssh/authorized_keys | Out-Null
```

Якщо Multipass працює на іншому хості, перенесіть на нього лише файл `id_ed25519.pub` і виконайте там ті самі команди підготовки каталогу. У Bash або zsh передайте ключ командою `cat ./id_ed25519.pub | multipass exec sd-lab -- tee -a /home/ubuntu/.ssh/authorized_keys >/dev/null`. Приватний ключ залишається на Windows Server.

На хості Multipass отримайте відбиток SSH-ключа сервера командою `multipass exec sd-lab -- ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub`. Потім підключіться з Windows і перед підтвердженням звірте відбиток ED25519:

```powershell
ssh ubuntu@192.168.10.50
```

Після входу команда `whoami` має показати `ubuntu`. Якщо SSH повідомляє про тайм-аут, перевірте з PowerShell доступ до порту командою `Test-NetConnection 192.168.10.50 -Port 22`. Якщо отримали `Permission denied (publickey)`, перевірте користувача, шлях до ключа і запис у `authorized_keys`. Якщо зберегли ключ під іншим іменем, вкажіть його через `ssh -i` або в SSH-конфігурації Windows. [Microsoft Learn про OpenSSH](https://learn.microsoft.com/en-us/windows-server/administration/openssh/openssh_install_firstuse) · [Документація multipass exec](https://canonical.com/multipass/docs/latest/reference/command-line-interface/exec/).

## 5. Передайте TLS-сертифікати на Ubuntu

Вийдіть із SSH-сеансу та виконайте в PowerShell із каталогу `bootstrap`:

```powershell
.\Copy-SdLabTlsToVm.ps1 -VmHost 192.168.10.50 -SshUser ubuntu `
  -FullChain 'C:\TLS\fullchain.pem' -PrivateKey 'C:\TLS\privkey.pem' `
  -RootCA 'C:\TLS\root-ca.crt'
```

Скрипт копіює файли в окремий приватний каталог у домашній теці користувача Ubuntu й виводить рядок `TLS_DIR=...`. Для SSH на іншому порту додайте `-SshPort`.

## 6. Розгорніть SD LAB на Ubuntu

### 6.1. Відкрийте термінал Ubuntu VM

З Windows підключіться по SSH. З хоста Multipass можна відкрити той самий термінал через `multipass shell sd-lab`:

```powershell
ssh ubuntu@192.168.10.50
```

Решту команд цього розділу виконуйте в Bash **всередині VM**. Копіюйте по одному рядку або блоку. Команди, що починаються з `if` або містять `<<APT`, вставляйте цілим блоком. Якщо команда завершується помилкою, зупиніться на цьому кроці. Вставте рядок `TLS_DIR=...` з кроку 5 і задайте IP, призначену мережевому інтерфейсу VM:

```bash
VM_IP=192.168.10.50
ip -br -4 addr
ls -l -- "$TLS_DIR"/{fullchain.pem,privkey.pem,root-ca.crt}
```

### 6.2. Встановіть Docker Engine і Compose

Спочатку встановіть інструменти, потрібні навіть за наявного Docker:

```bash
sudo apt-get update
sudo apt-get install -y ca-certificates curl git nano openssl python3
```

Якщо `sudo docker info` і `sudo docker compose version` уже працюють, перейдіть до клонування. Для чистої Ubuntu 26.04 підключіть офіційний APT-репозиторій Docker. Якщо APT повідомить про конфлікт із наявними пакетами Docker, перевірте їх за [інструкцією Docker](https://docs.docker.com/engine/install/ubuntu/) перед зміною пакетів чи зупинкою чинних контейнерів.

```bash
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc
. /etc/os-release

sudo tee /etc/apt/sources.list.d/docker.sources >/dev/null <<APT
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: ${UBUNTU_CODENAME:-$VERSION_CODENAME}
Components: stable
Architectures: $(dpkg --print-architecture)
Signed-By: /etc/apt/keyrings/docker.asc
APT
```

```bash
sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
sudo systemctl enable --now docker
sudo docker info
sudo docker compose version
```

Якщо Docker не стартує, перевірте журнал через `sudo journalctl -u docker -n 100 --no-pager`.

### 6.3. Клонуйте репозиторій і підготуйте `.env`

Клонуйте гілку `feature/https` під користувачем `ubuntu`. Для приватного репозиторію спочатку налаштуйте GitHub-доступ для цього користувача. Якщо каталог уже містить репозиторій, пропустіть перші дві команди й звірте адресу та гілку через `git remote -v` і `git branch --show-current`.

```bash
sudo install -d -o "$(id -un)" -g "$(id -gn)" -m 0750 /opt/spatial-data-lab
git clone --branch feature/https --single-branch https://github.com/plvnkv/spatial-data-lab.git /opt/spatial-data-lab
cd /opt/spatial-data-lab
git log -1 --oneline
```

Під час першого запуску створіть `.env` із шаблону. Блок генерує окреме випадкове значення для кожного `CHANGE_ME` та залишає наявний `.env` на місці:

```bash
if [ ! -e .env ]; then
  (umask 077
   while IFS= read -r line || [ -n "$line" ]; do
     case "$line" in
       *=CHANGE_ME)
         secret=$(openssl rand -hex 24) || exit 1
         printf '%s=%s\n' "${line%=*}" "$secret"
         ;;
       *) printf '%s\n' "$line" ;;
     esac
   done < .env.example > .env)
fi
chmod 600 .env
dpkg --print-architecture
nano .env
```

У редакторі Nano збережіть зміни через **Ctrl+O**, **Enter**, а потім вийдіть через **Ctrl+X**. Якщо наявний `.env` належить root, використайте `sudoedit .env` і виставте права командою `sudo chmod 600 .env`.

У `.env` додайте або оновіть три рядки. Нижче значення для VM з архітектурою `amd64`:

```dotenv
SD_LAB_HOST=sd.xenon.local
SD_LAB_ORIGIN=https://sd.xenon.local
SD_LAB_POSTGIS_PLATFORM=linux/amd64
```

Для `arm64` задайте `linux/arm64`. Поточні образи GeoNode й GeoServer у Compose вимагають `linux/amd64`, тому ARM64-VM потребує налаштованої емуляції AMD64. За наявних томів залиште чинні паролі та `SECRET_KEY`. Команда нижче має завершитися без виводу. Якщо вона показує ім’я змінної, вкажіть для неї значення в `.env`:

```bash
sudo awk -F= '$2 == "CHANGE_ME" {print $1}' .env
sudo docker compose -f compose.yaml -f bootstrap/compose.https.yaml config -q
```

### 6.4. Встановіть внутрішній CA та запустіть контейнери

```bash
sudo apt-get install -y nginx default-jre-headless ca-certificates-java
sudo install -m 0644 "$TLS_DIR/root-ca.crt" /usr/local/share/ca-certificates/sd-lab-root.crt
sudo update-ca-certificates
test -s /etc/ssl/certs/java/cacerts
openssl verify -purpose sslserver -verify_hostname sd.xenon.local \
  -untrusted "$TLS_DIR/fullchain.pem" "$TLS_DIR/fullchain.pem"
```

Перевірка сертифіката має повернути `OK`. Якщо OpenSSL показує `error 9 at 1 depth lookup: certificate is not yet valid`, дата початку дії сертифіката CA пізніша за поточний час Ubuntu VM. На Ubuntu порівняйте значення в UTC:

```bash
date -u
timedatectl status
openssl x509 -in "$TLS_DIR/root-ca.crt" -noout -subject -dates
openssl x509 -in "$TLS_DIR/fullchain.pem" -noout -subject -issuer -dates
```

Якщо годинник VM відстає, увімкніть синхронізацію часу командою `sudo timedatectl set-ntp true`. Якщо час не вирівнявся, перевірте також годинник хоста Multipass і доступ VM до сервера часу. Коли час VM буде правильним, повторіть `openssl verify`.

Якщо час VM правильний, а `notBefore` у майбутньому, перевірте годинник Windows Server командою `[DateTime]::UtcNow` у PowerShell. Якщо CA створили за неправильного часу Windows, синхронізуйте його та випустіть сертифікати заново в новий каталог. Передайте нові файли за кроком 5 і повторіть 6.4. Якщо старий CA вже розгорнуто на клієнтах, додайте довіру до нового CA до заміни сертифіката сервера.

Після успішної перевірки завантажте образи окремо від запуску, щоб бачити, на якому образі виникає помилка:

```bash
sudo docker compose -f compose.yaml -f bootstrap/compose.https.yaml pull
sudo docker compose -f compose.yaml -f bootstrap/compose.https.yaml up -d --wait --wait-timeout 900
sudo docker compose -f compose.yaml -f bootstrap/compose.https.yaml ps -a
```

Якщо запуск зупинився, перегляньте стан і останні повідомлення проблемного сервісу. Наприклад, для Django:

```bash
sudo docker compose -f compose.yaml -f bootstrap/compose.https.yaml logs --tail=100 django
```

Для інших компонентів підставте ім’я зі списку `ps -a`, наприклад `db`, `geoserver` або `init-postgis`. Одноразові сервіси `init-postgis`, `geoserver-data` й `init-buckets` мають завершитися зі статусом `Exited (0)`.

### 6.5. Увімкніть HTTPS у Nginx

З кореня репозиторію встановіть сертифікат і згенеруйте конфігурацію з наявних шаблонів. Для чинної інсталяції збережіть копію активної конфігурації та TLS-файлів перед їх заміною.

```bash
sudo install -d -m 0700 /etc/nginx/sd-lab-tls
sudo install -m 0644 "$TLS_DIR/fullchain.pem" /etc/nginx/sd-lab-tls/fullchain.pem
sudo install -m 0600 "$TLS_DIR/privkey.pem" /etc/nginx/sd-lab-tls/privkey.pem
sudo install -m 0644 bootstrap/nginx-proxy.conf /etc/nginx/snippets/sd-lab-proxy.conf
sed "s/@DOMAIN@/sd.xenon.local/g" bootstrap/index.html.in |
  sudo tee /etc/nginx/sd-lab-index.html >/dev/null
sed -e "s/@DOMAIN@/sd.xenon.local/g" -e "s/@IP@/$VM_IP/g" bootstrap/nginx.conf.in |
  sudo tee /etc/nginx/sites-available/sd-lab.conf >/dev/null
sudo ln -sfn /etc/nginx/sites-available/sd-lab.conf /etc/nginx/sites-enabled/sd-lab.conf
sudo nginx -t
```

Очікуваний результат — `syntax is ok` і `test is successful`. Якщо перевірка пройшла, застосуйте конфігурацію та перевірте HTTPS напряму за IP, зберігаючи перевірку домену й сертифіката:

```bash
sudo systemctl enable --now nginx
sudo systemctl reload nginx
curl -fsS --resolve "sd.xenon.local:443:$VM_IP" https://sd.xenon.local/sd-lab/ -o /dev/null
```

Якщо Nginx не стартує, перегляньте `sudo journalctl -u nginx -n 100 --no-pager`. Якщо перевірка через `--resolve` працює, а звичайний URL з клієнта ні, перевірте локальний DNS і довіру клієнта до CA. Для поновлення сертифіката передайте нові файли за кроком 5 і повторіть 6.5. Якщо змінився CA, спочатку оновіть довіру на VM за кроком 6.4 і на клієнтах за кроком 7.

Якщо переносите наявні дані GeoNode, зробіть резервну копію до запуску. Після переходу замініть старий origin, підставивши фактичну попередню адресу:

```bash
cd /opt/spatial-data-lab
sudo docker compose -f compose.yaml -f bootstrap/compose.https.yaml exec -T django \
  python manage.py migrate_baseurl --force \
  --source-address http://localhost:8088 --target-address https://sd.xenon.local
```

## 7. Налаштуйте клієнтів і перевірте доступ

Розгорніть кореневий CA на клієнтах через GPO або налаштуйте окрему машину з Windows 10, 11 чи Server 2019 у PowerShell від адміністратора:

```powershell
Get-NetAdapter
.\Set-SdLabDnsClient.ps1 -InterfaceIndex 12 -DnsServer 192.168.10.10 `
  -ZoneName sd.xenon.local -RootCA 'C:\TLS\root-ca.crt'
```

Підставте індекс активного адаптера зі стовпця `ifIndex`. На клієнтах, які вже використовують робочий локальний DNS, достатньо розгорнути довіру до CA через GPO. Відкрийте `https://sd.xenon.local/sd-lab/` і перевірте стан сервісів, сертифікат та вхід у GeoNode і GeoServer. Prometheus і Alertmanager відкриті для читання. Grafana потребує облікового запису з роллю Viewer, а консоль RustFS і приватні бакети — облікових даних RustFS.

Для перевірки контейнерів або створення тестових тайлів виконайте на Ubuntu:

```bash
cd /opt/spatial-data-lab
sudo docker compose -f compose.yaml -f bootstrap/compose.https.yaml ps
sudo sh scripts/seed-tiles.sh
```


### Які файли використовує інструкція

- `New-SdLabTls.ps1` готує TLS-файли. `Copy-SdLabTlsToVm.ps1` передає їх на Ubuntu.
- `Set-SdLabDnsServer.ps1` додає DNS-записи. `Set-SdLabDnsClient.ps1` налаштовує DNS і довіру до CA на окремому клієнті.
- `compose.https.yaml`, `django-https.py`, `geonode-nginx.conf`, `nginx-proxy.conf`, `nginx.conf.in` та `index.html.in` застосовуються командами з кроку 6.
- `setup-ubuntu.sh` і `compose-lan.sh` залишені для наявних інсталяцій, де використовується `/etc/sd-lab/lan.env`. Для ручного розгортання використовуйте команди цього README.
