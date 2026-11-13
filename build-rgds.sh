#!/bin/sh
# 编译 RGDS(aarch64 Linux)版本并部署到 RGDS-SORX/
# 依赖: Docker 容器 openbor-build(debian:bookworm arm64,源码挂载在 /src)
set -e
cd "$(dirname "$0")"

docker start openbor-build >/dev/null 2>&1 || \
  docker run -d --name openbor-build --platform linux/arm64 -v "$(pwd)":/src debian:bookworm sleep infinity

docker exec openbor-build bash -c "
  which gcc >/dev/null || (apt-get update -qq && apt-get install -y -qq --no-install-recommends build-essential cmake pkg-config libsdl2-dev libpng-dev libvorbis-dev libvpx-dev zlib1g-dev)
  cd /src && cmake -S . -B build-linux -DCMAKE_BUILD_TYPE=RelWithDebInfo -DBUILD_LINUX=ON -DTARGET_ARCH=aarch64 >/dev/null
  make -C build-linux -j4 2>&1 | tail -1
"

cp build-linux/OpenBOR RGDS-SORX/OpenBOR
echo ">> 完成: $(ls -la RGDS-SORX/OpenBOR | awk '{print $5, $9}')"
echo ">> 部署: scp -i ~/.ssh/id_ed25519 -r RGDS-SORX root@<掌机IP>:/mnt/mmc/Roms/APPS/"
