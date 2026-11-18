#!/usr/bin/env bash
set -euo pipefail
umask 077

if [[ $# -lt 4 || $# -gt 5 || ${EUID} -ne 0 ]]; then
    echo "Usage: sudo $0 DOMAIN VM_IPV4 FULLCHAIN_PEM PRIVATE_KEY_PEM [ROOT_CA_CRT]" >&2
    exit 2
fi

domain=$1
vm_ip=$2
fullchain=$(realpath -e -- "$3")
private_key=$(realpath -e -- "$4")
root_ca=
if [[ $# -eq 5 ]]; then root_ca=$(realpath -e -- "$5"); fi
cd -- "$(dirname -- "$0")/.."

if [[ ! $domain =~ ^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?(\.[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?)+$ ||
      ${#domain} -gt 240 ]]; then
    echo "Use a lowercase DNS name, for example sd.xenon.local." >&2
    exit 2
fi
if [[ ! $vm_ip =~ ^[0-9]+(\.[0-9]+){3}$ ]] ||
   ! ip -o -4 addr show scope global | awk '{sub(/\/.*/, "", $4); print $4}' | grep -Fx "$vm_ip" >/dev/null; then
    echo "VM_IPV4 must already be assigned to this Ubuntu VM." >&2
    exit 2
fi
if [[ ! -s .env ]] || ! docker compose version >/dev/null; then
    echo "Install Docker Engine and Compose, and prepare the project .env first." >&2
    exit 1
fi
case "$(docker info --format '{{.Architecture}}')" in
    x86_64|amd64) platform=linux/amd64 ;;
    aarch64|arm64) platform=linux/arm64 ;;
    *) echo "Unsupported Docker architecture." >&2; exit 1 ;;
esac

temp=$(mktemp -d)
trap 'rm -rf -- "$temp"' EXIT
for name in "$domain" {martin,titiler,rustfs,s3,grafana,prometheus,alertmanager}."$domain"; do
    if ! openssl x509 -in "$fullchain" -noout -checkhost "$name" | grep -F 'does match certificate' >/dev/null; then
        echo "The certificate must cover $name." >&2
        exit 1
    fi
done
openssl x509 -in "$fullchain" -noout -checkend 0
openssl x509 -in "$fullchain" -pubkey -noout > "$temp/cert-public"
openssl pkey -in "$private_key" -passin pass: -pubout > "$temp/key-public"
cmp "$temp/cert-public" "$temp/key-public"

printf 'SD_LAB_HOST=%s\nSD_LAB_ORIGIN=https://%s\nSD_LAB_POSTGIS_PLATFORM=%s\n' \
    "$domain" "$domain" "$platform" > "$temp/lan.env"
unset SD_LAB_HOST SD_LAB_ORIGIN SD_LAB_POSTGIS_PLATFORM
compose=(docker compose --env-file .env --env-file "$temp/lan.env" -f compose.yaml -f bootstrap/compose.https.yaml)
"${compose[@]}" config -q

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y nginx ca-certificates default-jre-headless ca-certificates-java
if [[ -n $root_ca ]]; then
    install -m 0644 "$root_ca" /usr/local/share/ca-certificates/sd-lab-root.crt
    update-ca-certificates
fi
test -s /etc/ssl/certs/java/cacerts
openssl verify -purpose sslserver -verify_hostname "$domain" -untrusted "$fullchain" "$fullchain"

sed -e "s/@DOMAIN@/$domain/g" -e "s/@IP@/$vm_ip/g" bootstrap/nginx.conf.in > "$temp/sd-lab.conf"
sed "s/@DOMAIN@/$domain/g" bootstrap/index.html.in > "$temp/index.html"
install -d -m 0700 /etc/nginx/sd-lab-tls /etc/sd-lab

# Keep the previous on-disk configuration if the Nginx configuration test or reload fails.
mkdir "$temp/previous"
nginx_files=(
    /etc/nginx/sd-lab-tls/fullchain.pem
    /etc/nginx/sd-lab-tls/privkey.pem
    /etc/nginx/snippets/sd-lab-proxy.conf
    /etc/nginx/sd-lab-index.html
    /etc/nginx/sites-available/sd-lab.conf
    /etc/nginx/sites-enabled/sd-lab.conf
)
for path in "${nginx_files[@]}"; do
    if [[ -e $path || -L $path ]]; then cp -a --parents -- "$path" "$temp/previous"; fi
done
restore_nginx() {
    for path in "${nginx_files[@]}"; do
        rm -f -- "$path"
        if [[ -e $temp/previous$path || -L $temp/previous$path ]]; then
            cp -a -- "$temp/previous$path" "$path"
        fi
    done
}

write_nginx() {
    install -m 0644 "$fullchain" /etc/nginx/sd-lab-tls/fullchain.pem &&
    install -m 0600 "$private_key" /etc/nginx/sd-lab-tls/privkey.pem &&
    install -m 0644 bootstrap/nginx-proxy.conf /etc/nginx/snippets/sd-lab-proxy.conf &&
    install -m 0644 "$temp/index.html" /etc/nginx/sd-lab-index.html &&
    install -m 0644 "$temp/sd-lab.conf" /etc/nginx/sites-available/sd-lab.conf &&
    ln -sfn /etc/nginx/sites-available/sd-lab.conf /etc/nginx/sites-enabled/sd-lab.conf
}
if ! write_nginx || ! nginx -t; then
    restore_nginx
    exit 1
fi
if ! "${compose[@]}" up -d --wait --wait-timeout 900; then
    restore_nginx
    exit 1
fi
if ! systemctl enable --now nginx || ! systemctl reload nginx; then
    restore_nginx
    exit 1
fi
install -m 0644 "$temp/lan.env" /etc/sd-lab/lan.env
printf 'https://%s/sd-lab/\n' "$domain"
