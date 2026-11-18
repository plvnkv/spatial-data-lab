#!/usr/bin/env bash
set -euo pipefail
umask 077

if [[ $# -ne 4 || $EUID -ne 0 ]]; then
    echo "Usage: sudo bash $0 VM_IPV4 FULLCHAIN_PEM PRIVATE_KEY_PEM ROOT_CA_CRT" >&2
    exit 2
fi

. /etc/os-release
if [[ $ID != ubuntu || $VERSION_ID != 26.04 ]]; then
    echo "This installer requires Ubuntu Server 26.04 LTS." >&2
    exit 2
fi

vm_ip=$1
fullchain=$(realpath -e -- "$2")
private_key=$(realpath -e -- "$3")
root_ca=$(realpath -e -- "$4")
for file in "$fullchain" "$private_key" "$root_ca"; do
    if [[ ! -f $file || ! -s $file ]]; then
        echo "Expected a nonempty certificate or key file: $file" >&2
        exit 2
    fi
done
if ! ip -o -4 addr show scope global | awk '{sub(/\/.*/, "", $4); print $4}' | grep -Fx -- "$vm_ip" >/dev/null; then
    echo "VM_IPV4 must already be assigned to this Ubuntu VM." >&2
    exit 2
fi

repo=https://github.com/plvnkv/spatial-data-lab.git
ref=${SD_LAB_GIT_REF:-feature/https}
target=/opt/spatial-data-lab
staging=$(mktemp -d /opt/.sd-lab-install.XXXXXX)
trap 'rm -rf -- "$staging"' EXIT

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y ca-certificates curl git openssl

if [[ ! -e $target && ! -L $target ]]; then
    git clone --branch "$ref" --single-branch -- "$repo" "$staging/repo"
    test -x "$staging/repo/bootstrap/setup-ubuntu.sh"
    mv -T -- "$staging/repo" "$target"
fi
if [[ -L $target || ! -d $target/.git ]] ||
   [[ $(git -C "$target" remote get-url origin) != "$repo" ]]; then
    echo "Expected $target to be a checkout of $repo." >&2
    exit 1
fi
cd -- "$target"
test -x bootstrap/setup-ubuntu.sh

if ! command -v docker >/dev/null || ! docker compose version >/dev/null; then
    # Preserve any Docker installation already provided by Ubuntu or another package source.
    for package in docker.io docker-compose docker-compose-v2 docker-doc podman-docker containerd runc; do
        status=$(dpkg-query -W -f='${Status}' "$package" 2>/dev/null || true)
        if [[ $status == 'install ok installed' ]]; then
            echo "Conflicting package $package is installed. Configure Docker and Compose before retrying." >&2
            exit 1
        fi
    done
    curl -fsSL --retry 3 https://download.docker.com/linux/ubuntu/gpg -o "$staging/docker.asc"
    install -d -m 0755 /etc/apt/keyrings
    install -m 0644 "$staging/docker.asc" /etc/apt/keyrings/docker.asc
    cat > "$staging/docker.sources" <<SOURCES
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: ${UBUNTU_CODENAME:-$VERSION_CODENAME}
Components: stable
Architectures: $(dpkg --print-architecture)
Signed-By: /etc/apt/keyrings/docker.asc
SOURCES
    install -m 0644 "$staging/docker.sources" /etc/apt/sources.list.d/docker.sources
    apt-get update
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
fi
systemctl enable --now docker
docker info >/dev/null
docker compose version >/dev/null

if [[ ! -e .env && ! -L .env ]]; then
    while IFS= read -r line || [[ -n $line ]]; do
        case "$line" in
            *=CHANGE_ME)
                secret=$(openssl rand -hex 24)
                printf '%s=%s\n' "${line%=*}" "$secret"
                ;;
            *) printf '%s\n' "$line" ;;
        esac
    done < .env.example > "$staging/project.env"
    # Creating the hard link fails if another invocation already supplied .env.
    ln -T -- "$staging/project.env" .env
fi
if [[ -L .env || ! -f .env || ! -s .env ]] || grep -Eq '=CHANGE_ME[[:space:]]*$' .env; then
    echo "Complete the existing $target/.env before retrying." >&2
    exit 1
fi

bootstrap/setup-ubuntu.sh sd.xenon.local "$vm_ip" "$fullchain" "$private_key" "$root_ca"
