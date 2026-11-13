# SORX on RGDS — 版本对应、编译部署与踩坑记录

> 记录在 Anbernic RG DS(aarch64 Linux / Buildroot)上运行 SORX Beta 36 的完整链路。
> 日期:2026-11-13 · 分支:`sorx-engine` · 维护人:JXRow

---

## 一、版本对应关系(最重要,错一个都跑不起来)

### 游戏数据(SORX)

| 项目 | 值 |
|---|---|
| 版本 | **SoRX Beta 36.CC3**(Kratus,zip 内 Changelog 日期 2026-10-06) |
| 下载源 | itch.io `https://fgames9000.itch.io/streets-of-rage-x`,upload_id **19704437**(WINDOWS_LINUX.zip,432MB) |
| 校验 | SHA256 `90dac70c56e71f51618e4844aa3ff0c2720f5e4d2a28321dceafe18967256066` |
| 本地位置 | Mac: `openbor-launch/Paks/SORX.pak`(386,482,231 B);掌机: `/mnt/mmc/Roms/APPS/sorx/Paks/` |
| 安全检查 | 结构干净:无路径穿越/双扩展名/宏;启动脚本仅 chmod+cd+LD_LIBRARY_PATH;只运行自编译引擎,不执行包内 exe |

### 引擎(OpenBOR)——版本兼容矩阵

| 引擎版本 | 结果 | 原因 |
|---|---|---|
| 官方 4.0 Build **7735**(`f64d63c2`,2025-05-04) | ❌ 段错误 | 脚本解析时 `Player property name 'device_name' is not supported yet.`——SORX Beta 36 用了 7735 之后才有的引擎属性 |
| 官方 master `65a7f0b4`(Build 8027,2026-10-18) | ❌ pak 解析失败 | 新 pak 解析器严格校验 magic `"PACK"`,SORX.pak 用非标准魔数 `0x7F14111D` → `data/video.txt`、`data/levels.txt` 全部找不到 |
| **`new_controller_code` 分支 @ `16aae1a3`(2026-09-28)★正确答案** | ✅ | 分支含 Kratus 自己写的 `device_name` Player 属性(`openborscript.c` 注释 "Kratus (2026)"),日期与 Kratus 打包的引擎二进制(2026-09-28 编译)完全吻合 |

> **版本判断方法**(以后出新版 SORX 时照此排查):
> 1. `strings Kratus包内bin_x86_64 | grep -i "OpenBOR v"` → 得到版本横幅(本次为 `v4.0 Build 31 (commit hash: 526ebcb)`,该 hash 不在 DCurrent 仓库,系 Kratus 私有 fork/基线;但其编译日期 + `device_name` 作者注释足以锁定 `new_controller_code` 分支)
> 2. DCurrent 仓库 build 号 = `git rev-list --count HEAD`(master `65a7f0b4` = 8027)
> 3. pak 解析失败优先 diff `engine/source/gamelib/packfile.c` 的 magic 校验逻辑

### 掌机环境(RG DS)

- Linux 6.1.141 aarch64,Buildroot 根文件系统(glibc 2.41),4 核 / 3GB RAM
- 无 gcc/cmake/pkg-config/git——**不能在掌机上编译,必须交叉/容器构建**
- 显示:Wayland(`wayland-0`,`XDG_RUNTIME_DIR=/var/run`),GPU Mali-G52(libmali,无桌面 GL)
- 音频:ALSA card0(hw:0,0,44100Hz S16LE),前端 MUOS(`/mnt/vendor/bin/muos2.bin`)
- ssh:`root@192.168.1.11`(IP 随网络变动,`~/.ssh/config` 里 Host `rgds`/`rgds-ip` 需同步更新),密钥 `~/.ssh/id_ed25519`

---

## 二、本地补丁清单(全部在 `sorx-engine` 分支,提交 `a707c9dc` "run on rgds")

| 文件 | 补丁 | 原因 |
|---|---|---|
| `engine/source/gamelib/packfile.c` | `#define PACKMAGIC_ALT 0x7F14111DU`,`packfile_read_format_fd()` 接受两种魔数 | SORX.pak 魔数非标准;其目录结构完全符合 PAK32(record_size/offset/size/name,version 0 = `PAK_FORMAT_PAK32`),只差魔数 |
| `engine/sdl/control.c` | 默认键盘映射:A=攻击 S=跳 D=攻击2 F=攻击3 X=攻击4 Z=特殊技 | 用户键位偏好(Mac 键盘玩;掌机手柄走默认手柄映射,不受影响) |
| `CMakeLists.txt` | `cmake_minimum_required 3.22→3.21` | 本机 Homebrew cmake 3.21.3 |
| `cmake/macos.cmake` | SDKPATH 回退到 `/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk` | 本机无 Xcode.app,只有 Command Line Tools |

---

## 三、编译

### Mac 版(Apple Silicon,本地玩)

```sh
cd openbor
cmake -S . -B build -DCMAKE_BUILD_TYPE=Release -DBUILD_DARWIN=ON -DTARGET_ARCH=ARM64
cmake --build build -j 8
# 产物 build/OpenBOR;依赖 Homebrew dylib(/opt/homebrew:SDL2/vorbis/vpx/png/ogg)
# 编译警告(dylib built for newer macOS version)无害
```

### RGDS 版(aarch64 Linux,Docker arm64 原生构建)

```sh
./build-rgds.sh          # 一键:容器内 cmake + make,产物自动覆盖 RGDS-SORX/OpenBOR
```

等价手动流程:

```sh
docker run -d --name openbor-build --platform linux/arm64 -v "$(pwd)":/src debian:bookworm sleep infinity
docker exec openbor-build bash -c "apt-get update && apt-get install -y --no-install-recommends \
  build-essential cmake pkg-config libsdl2-dev libpng-dev libvorbis-dev libvpx-dev zlib1g-dev"
docker exec openbor-build bash -c "cd /src && \
  cmake -S . -B build-linux -DCMAKE_BUILD_TYPE=RelWithDebInfo -DBUILD_LINUX=ON -DTARGET_ARCH=aarch64 && \
  make -C build-linux -j4"
cp build-linux/OpenBOR RGDS-SORX/OpenBOR
```

要点:
- **用 `-DCMAKE_BUILD_TYPE=RelWithDebInfo`**,不要用 Release——项目在 CMakeLists 里给 Release 写死 `-Werror`,gcc12 报 `use-after-free` 告警直接编译失败(clang 不报,所以 Mac Release 没事)。RelWithDebInfo 类型项目没覆写 flags,绕开
- Apple Silicon 的 Docker 跑 `linux/arm64` 是**原生速度**,不是模拟
- 掌机自带运行库(SDL2 2.32 / libpng16 / libvorbis 0.4.9 / libogg / libFLAC)与 Debian bookworm 产物 soname 兼容,**唯独 libvpx**(掌机 .so.8,Debian .so.7)→ 从容器拷 `libvpx.so.7.1.0` 改名放入 `RGDS-SORX/lib/`,启动脚本 LD_LIBRARY_PATH 优先加载

### 编译产物验证

```sh
file build-linux/OpenBOR      # ELF 64-bit ... ARM aarch64
docker exec openbor-build readelf -d build-linux/OpenBOR | grep NEEDED
# 掌机侧检查:LD_LIBRARY_PATH=RGDS-SORX/lib ldd RGDS-SORX/OpenBOR 不得有 "not found"
```

---

## 四、部署与运行

### RGDS-SORX 自包含包(推荐)

```
RGDS-SORX/
├── OpenBOR          aarch64 引擎
├── Paks/SORX.pak    游戏数据
├── lib/libvpx.so.7  掌机缺的 so
├── RGDS-SORX.sh     启动器(基于 dirname 自定位,日志 → /tmp/RGDS-SORX.log)
├── install.sh       上传后运行一次:装菜单入口 APPS/RGDS-SORX.sh + Imgs/RGDS-SORX.png
├── icon.png         菜单图标
└── README.txt
```

```sh
# Mac 上部署(整个文件夹上传即可运行)
scp -i ~/.ssh/id_ed25519 -r openbor/RGDS-SORX root@<掌机IP>:/mnt/mmc/Roms/APPS/
ssh -i ~/.ssh/id_ed25519 root@<掌机IP> 'sh /mnt/mmc/Roms/APPS/RGDS-SORX/install.sh'
```

之后掌机菜单 APPS → **RGDS-SORX.sh**。

### pak 定位机制(排查"游戏找不到"时看这里)

- 引擎 `main()`:有第二个参数 → 直接当作 pak 路径(相对**当前目录**),存在则跳过选择菜单
- 无参数 → 列出 `./Paks/*.pak` 弹引擎自带选择菜单
- `Saves/ Logs/ ScreenShots/` 均相对当前目录生成 → 启动脚本必须先 `cd` 到应用目录
- 键位存档:`Saves/<pak名>.controls`(每 pak 独立)

### 掌机上的旧布局(已可用,后续可迁移)

`/mnt/mmc/Roms/APPS/sorx/{OpenBOR,Paks/SORX.pak,lib/}` + `APPS/sorx.sh`,与 RGDS-SORX 等价。

---

## 五、RGDS 需要做的修改(系统级)

### 1. ALSA dmix 混音(必须,否则游戏无声)

**问题**:MUOS 前端(`muos2.bin`)以独占模式常驻持有 `hw:0,0`(prepared 状态,2 个 snd fd),引擎打开音频报 `Device or resource busy` → 日志 `Warning: can't play sound!`,全程无声。

**修改(v1)**:重写 `/etc/asound.conf`,把 default 从直连 `hw:0,0` 改为 **dmix/dsnoop 混音**,保留 RK 编解码器的输出路径 hook(`Playback Path = SPK`)。改完**必须重启掌机**(MUOS 要按新配置重新打开声卡)。

**坑(v1 遗留,已修)**:hooks 里的 `lock true` 会在打开音频时**锁住 ctl 控件**——MUOS 先开声卡就永远持有 `Playback Path` 的锁,之后引擎再开报 `Cannot lock ctl elem → Operation not permitted`,音频照样无声(且 MUOS 侧实际已走 MMAP/dmix 模式,更具迷惑性)。**v2 修复**:playback 路径去掉 hooks(MUOS 每次开机已把 `Playback Path=SPK` 写入并 `preserve` 持久化,无需每次设置);capture 路径的 hooks 不影响游戏,保留。历史版本备份:`/etc/asound.conf.bak`(原始)、`/etc/asound.conf.v1`(带 hooks 的 dmix 版)。

**v2 当前配置结构**:
```
default → asym
  playback → plug → dmix(hw:0,0, 44100 S16LE, period 1024, buffer 8192)   # 无 hooks!
  capture  → hooks(Capture MIC Path=Main Mic) → plug → dsnoop(hw:0,0)
ctl.default → hw card 0
```

验证:
```sh
ssh 掌机 '/tmp/audiotest'    # 期待 "opened: freq=44100" 而非 busy/refused
# 游戏日志中 Initialize Sound 后不得出现 can't play sound
```
> 注意:audiotest 测试程序在 /tmp(重启即失);可随时从 Docker 容器 `docker cp openbor-build:/tmp/audiotest` 重新拷贝。

### 2. 存储空间

`/mnt/mmc`(TF 卡)需 ≥400MB 空闲(pak 386MB + 引擎 7MB + lib 2MB)。根分区 4.9GB 不建议放。

### 3. 无需修改的部分(自动适配)

- **输入**:掌机手柄被 SDL 自动识别为 `ANBERNIC-rk3568-keys (game controller)`,走引擎默认手柄映射,零配置
- **视频**:Wayland 正常,启动器设 `WAYLAND_DISPLAY=wayland-0`、`XDG_RUNTIME_DIR=/var/run`、`SDL_VIDEO_DOUBLE_BUFFER=1`
- **OpenGL**:Mali G52 无桌面 GL,EGL 创建兼容上下文失败(`EGL_BAD_ATTRIBUTE`)→ 引擎自动回退 SDL 软件渲染,**属预期行为,不是故障**

---

## 六、踩坑全记录(按影响排序)

| # | 坑 | 现象 | 解法 |
|---|---|---|---|
| 1 | 引擎版本不对 | 7735 段错误(`device_name`);master 8027 `video.txt/levels.txt not found` | 锁定 `new_controller_code@16aae1a3` + 魔数补丁,见第一节 |
| 2 | pak 魔数 | `0x7F14111D` ≠ `"PACK"`,新解析器直接拒绝 | `PACKMAGIC_ALT` 一行补丁 |
| 3 | MUOS 独占声卡 | `Warning: can't play sound!` | `/etc/asound.conf` dmix + **重启掌机**;v2 再去掉 playback hooks 的 `lock true`(ctl 锁冲突,见第五节) |
| 4 | libvpx soname | 掌机 .so.8 vs Debian .so.7 | 随包带 `lib/libvpx.so.7` |
| 5 | gcc12 + `-Werror` | `use-after-free` 告警编译失败 | 构建用 `RelWithDebInfo` 类型 |
| 6 | cmake 版本 | 本机 3.21 < 要求 3.22 | CMakeLists 改 3.21 |
| 7 | CLT SDK | macos.cmake 写死 Xcode.app SDK 路径 | SDKPATH 回退补丁 |
| 8 | Docker apt 拉 Debian 包大量 502 / HTTPS 证书缺失 | 依赖装不上 | 多重试 + 换镜像;或本地 curl 下载 deb 喂容器;最终 tcping 清华源不可达,deb.debian.org HTTP 间歇可用,反复 `--fix-missing` 装齐 |
| 9 | 首启模型缓存慢 | 引擎看起来"卡死"几分钟 | 386MB pak 首次缓存全模型;看 `Logs/OpenBorLog.txt` 确认在推进。Mac ~40s,掌机数分钟 |
| 10 | stdout 无输出 | `/tmp/*.log` 恒为 0 字节 | glibc 对非 tty 全缓冲;**看引擎自己的 `Logs/OpenBorLog.txt`**(脚本日志 ScriptLog.txt 同目录) |
| 11 | 32-bit PNG 报错刷屏 | `unsupported color type... loading/logo/title.png` | 非致命,引擎自动回退(`Loaded 32-bit background '...'`),不用管 |
| 12 | 掌机 IP 漂移 | ssh 连不上 | arp 扫描找 aarch64+Buildroot 主机;更新 `~/.ssh/config` |
| 13 | GitHub 大传输不稳 | ssh 22 超时、443 断流、tarball 是唯一稳定通道 | clone 用 codeload tarball + `--filter=blob:none` 部分克隆;SSH 走 `ssh.github.com:443`(已写进 `~/.ssh/config`) |
| 14 | git 大仓库 | 1.5GB 二十年历史 | 部分克隆瘦身到 147MB(考古去 GitHub 网页) |
| 15 | 版本号显示 `Build ,` | 引擎横幅空版本 | 容器内无 git,`version.sh` 取不到提交号,纯外观问题 |

---

## 七、快速排障

```sh
# 游戏没画面/闪退 → 看引擎日志(不是 stdout!)
ssh 掌机 'tail -30 /mnt/mmc/Roms/APPS/RGDS-SORX/Logs/OpenBorLog.txt'   # 新布局
# 无声 → 确认 dmix 配置 + 掌机是否重启过
ssh 掌机 'cat /etc/asound.conf | head -5; grep -c "can.t play" /mnt/mmc/Roms/APPS/RGDS-SORX/Logs/OpenBorLog.txt'
# 进程还活着吗
ssh 掌机 'pidof OpenBOR; ps -o pid,stat,etime,pcpu -p $(pidof OpenBOR)'
```

## 八、仓库与文件位置速查

| 内容 | 位置 |
|---|---|
| 引擎源码(本地) | `openbor/`(分支 `sorx-engine`,origin = `git@github.com:JXRow/openbor.git`,SSH 走 443) |
| Mac 运行环境 | `openbor-launch/`(OpenBOR.app + Paks/,双击即玩) |
| 掌机部署包 | `openbor/RGDS-SORX/`(自包含,scp 上传即用) |
| 一键构建 | `openbor/build-rgds.sh` |
| 官方源 | `https://github.com/DCurrent/openbor`(remotes/upstream) |
