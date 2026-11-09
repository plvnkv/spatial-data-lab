# Spatial Data Lab

Локальний ГІС-стенд для Mac з Apple Silicon і Docker Desktop. PostgreSQL 18.6 із PostGIS 3.7.0 працює в нативному ARM64-контейнері. Вибрані образи GeoNode та GeoServer запускаються як Linux AMD64. Опубліковані порти прив’язані до `127.0.0.1`.

## Запуск

Під час першого запуску Docker завантажує всі образи та ініціалізує бази GeoNode і бакети RustFS. Згенеруйте локальні облікові дані, якщо файл `.env` ще не створено.

```sh
if [ ! -e .env ]; then
  umask 077
  while IFS= read -r line; do
    case "$line" in
      *=CHANGE_ME) printf '%s=%s\n' "${line%=*}" "$(openssl rand -hex 24)" ;;
      *) printf '%s\n' "$line" ;;
    esac
  done < .env.example > .env
fi
docker compose config -q
docker compose up -d --wait
docker compose ps -a
```

`init-postgis`, `geoserver-data` і `init-buckets` виконують одноразову підготовку та завершуються з кодом 0. Зупинити стек зі збереженням томів можна через `docker compose stop`, а відновити через `docker compose up -d`.

## Локальні адреси

| Сервіс | URL | Вхід |
| --- | --- | --- |
| GeoNode | <http://localhost:8088> | `admin`, пароль `GEONODE_ADMIN_PASSWORD` |
| GeoServer | <http://localhost:8088/geoserver/web> | Вхід через GeoNode або локальний `admin` |
| Martin | <http://localhost:3001> | Каталог тайлів |
| TiTiler | <http://localhost:8001/api.html> | Swagger UI. Схема OpenAPI доступна на <http://localhost:8001/api> |
| RustFS | <http://localhost:9001> | `RUSTFS_ACCESS_KEY` і `RUSTFS_SECRET_KEY` |
| Grafana | <http://localhost:3000/d/local-gis/local-gis> | `admin`, пароль `GRAFANA_PASSWORD` |
| Prometheus | <http://localhost:9090/targets> | Цілі збору метрик |
| Alertmanager | <http://localhost:9093> | Локальні сповіщення |
| Loki | <http://localhost:3100/ready> | Готовність API |

Паролі містяться в локальному `.env`. PostgreSQL доступний сервісам як `db:5432`. Бази `geonode` і `geonode_data` мають окремі ролі. RabbitMQ обслуговує чергу Celery, а PostgreSQL зберігає результати її задач.

## Вхід через GeoNode

Увійдіть у GeoNode, потім відкрийте [вхід до GeoServer через GeoNode](http://localhost:8088/geoserver/web/j_spring_oauth2_geonode_login). GeoServer отримує ролі через OAuth2. Адміністративні функції потребують відповідної ролі. Для прямого входу до GeoServer пароль локального `admin` зберігається в `GEOSERVER_ADMIN_PASSWORD`.

## Локальний домен

Щоб користуватися `sd-lab.local` на цьому Mac, відкрийте `sudoedit /etc/hosts` і додайте рядок:

```text
127.0.0.1 sd-lab.local
```

Додайте до локального `.env`:

```dotenv
SD_LAB_HOST=sd-lab.local
SD_LAB_ORIGIN=http://sd-lab.local:8088
```

Застосуйте параметри й оновіть збережені URL шарів і OAuth2 callback:

```sh
docker compose up -d --wait django celery geoserver geonode
docker compose exec -T django python manage.py migrate_baseurl --force \
  --source-address http://localhost:8088 \
  --target-address http://sd-lab.local:8088
```

Після переходу відкривайте GeoNode і GeoServer за `http://sd-lab.local:8088/`. Інші вебсервіси використовують той самий хост і порти з таблиці, наприклад `http://sd-lab.local:8001/api.html` для TiTiler. Прив’язка до `127.0.0.1` залишає доступ локальним для цього Mac.

Якщо після оновлення GeoNode з’являється стара верстка MapStore, перезберіть згенеровані статичні файли й оновіть сторінку:

```sh
docker compose exec -T django python manage.py collectstatic --noinput --clear
```

## Дані й перевірки

У GeoNode увійдіть як адміністратор, завантажте GeoJSON через **Datasets → Upload dataset** і відкрийте опублікований шар на карті. GeoServer доступний через той самий локальний проксі.

Розміщуйте PMTiles у приватному бакеті `vector-tiles`, а COG у `raster-data`. Після додавання нового джерела перезапустіть Martin для оновлення каталогу. Для TiTiler передайте адресу на зразок `s3://raster-data/example.tif` у параметрі `url` API COG.

```sh
sh scripts/check-core.sh
sh scripts/seed-tiles.sh
sh scripts/check-tiles.sh
sh scripts/check-monitoring.sh
sh scripts/check-alert.sh
```

`seed-tiles.sh` створює тестову таблицю `public.gis_smoke` і завантажує два об’єкти з префіксом `gis_smoke`. `check-alert.sh` короткочасно зупиняє TiTiler, очікує сповіщення в Alertmanager та відновлює сервіс. Prometheus перевіряє HTTP і TCP, а Alloy використовує Docker-сокет для читання журналів контейнерів цього Compose-проєкту.

Для зовнішньої доставки додайте `webhook_configs` із `send_resolved: true` до отримувача у `config/monitoring/alertmanager.yaml` і перезапустіть Alertmanager. Зберігайте секрети каналу окремо від конфігурації проєкту.
