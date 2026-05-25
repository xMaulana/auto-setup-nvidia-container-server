#!/bin/bash
set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

ok()   { echo -e "${GREEN}[ok]${NC} $1"; }
info() { echo -e "${BLUE}[..]${NC} $1"; }
warn() { echo -e "${YELLOW}[!!]${NC} $1"; }
die()  { echo -e "${RED}[!!]${NC} $1"; exit 1; }

[ "$EUID" -ne 0 ] && die "Run as root: sudo bash install.sh"

# read os info
[ -f /etc/os-release ] || die "Cannot read /etc/os-release"
. /etc/os-release
OS_ID=$ID
OS_VERSION=$VERSION_ID
OS_CODENAME=${VERSION_CODENAME:-$UBUNTU_CODENAME}

info "Detected: $PRETTY_NAME"

[[ "$OS_ID" != "debian" && "$OS_ID" != "ubuntu" ]] && \
  die "Only Debian 12/13 and Ubuntu are supported (got: $OS_ID)"

if [[ "$OS_ID" == "debian" ]]; then
  [[ "$OS_VERSION" == "12" ]] && CUDA_DISTRO="debian12"
  [[ "$OS_VERSION" == "13" ]] && CUDA_DISTRO="debian13"
  [ -z "$CUDA_DISTRO" ] && die "Debian $OS_VERSION is not supported"
  DOCKER_DISTRO="debian"
  DOCKER_CODENAME=$OS_CODENAME
else
  CUDA_DISTRO="ubuntu$(echo $OS_VERSION | tr -d '.')"
  DOCKER_DISTRO="ubuntu"
  DOCKER_CODENAME=${UBUNTU_CODENAME:-$OS_CODENAME}
fi

CUDA_VERSION="13-2"
CTK_VERSION="1.19.1-1"

echo ""
echo "  OS      : $PRETTY_NAME"
echo "  CUDA    : $CUDA_VERSION"
echo "  CTK     : $CTK_VERSION"
echo ""
read -p "Continue? (y/N): " CONFIRM
[[ "$CONFIRM" != "y" && "$CONFIRM" != "Y" ]] && { echo "Aborted."; exit 0; }

# -- cuda toolkit --

info "Installing CUDA Toolkit $CUDA_VERSION..."

KEYRING_FILE="cuda-keyring_1.1-1_all.deb"
KEYRING_URL="https://developer.download.nvidia.com/compute/cuda/repos/${CUDA_DISTRO}/x86_64/${KEYRING_FILE}"

wget -q --show-progress "$KEYRING_URL" -O "/tmp/${KEYRING_FILE}"
dpkg -i "/tmp/${KEYRING_FILE}"
apt-get update -q
apt-get install -y "cuda-toolkit-${CUDA_VERSION}"
rm -f "/tmp/${KEYRING_FILE}"

ok "CUDA Toolkit installed"

# -- docker --

info "Installing Docker..."

apt-get update -q
apt-get install -y ca-certificates curl
install -m 0755 -d /etc/apt/keyrings
curl -fsSL "https://download.docker.com/linux/${DOCKER_DISTRO}/gpg" -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc

tee /etc/apt/sources.list.d/docker.sources > /dev/null <<EOF
Types: deb
URIs: https://download.docker.com/linux/${DOCKER_DISTRO}
Suites: ${DOCKER_CODENAME}
Components: stable
Architectures: $(dpkg --print-architecture)
Signed-By: /etc/apt/keyrings/docker.asc
EOF

apt-get update -q
apt-get install -y \
  docker-ce \
  docker-ce-cli \
  containerd.io \
  docker-buildx-plugin \
  docker-compose-plugin

systemctl enable docker
systemctl start docker

ok "Docker installed: $(docker --version)"

# -- nvidia container toolkit --

info "Installing NVIDIA Container Toolkit $CTK_VERSION..."

apt-get install -y --no-install-recommends ca-certificates curl gnupg2

curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey \
  | gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg

curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list \
  | sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' \
  | tee /etc/apt/sources.list.d/nvidia-container-toolkit.list > /dev/null

# enable experimental packages
sed -i -e '/experimental/ s/^#//g' /etc/apt/sources.list.d/nvidia-container-toolkit.list

apt-get update -q
apt-get install -y \
  nvidia-container-toolkit=${CTK_VERSION} \
  nvidia-container-toolkit-base=${CTK_VERSION} \
  libnvidia-container-tools=${CTK_VERSION} \
  libnvidia-container1=${CTK_VERSION}

nvidia-ctk runtime configure --runtime=docker
systemctl restart docker

ok "NVIDIA Container Toolkit installed"

# done
echo ""
ok "All done."
echo ""
warn "Reboot or re-login to activate CUDA PATH"
echo ""
echo "  Test GPU in Docker:"
echo "  docker run --rm --gpus all nvidia/cuda:12.1.0-base-ubuntu22.04 nvidia-smi"
echo ""
