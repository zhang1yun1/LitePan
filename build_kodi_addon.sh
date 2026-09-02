#!/usr/bin/env bash
# ==============================================================================
# LitePan Kodi (CoreELEC / Linux ARMv7 & ARM64) 插件包一键构建脚本
# 作用: 自动应用 MountRoot 挂载根目录动态 Patch、交叉编译 Go 二进制并打成 ZIP 包
# ==============================================================================

set -e

# 项目根目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="${SCRIPT_DIR}"
BUILD_DIR="${ROOT_DIR}/dist/kodi_build"
DIST_DIR="${ROOT_DIR}/dist"
ADDON_ID="service.litepan"
ADDON_DIR="${BUILD_DIR}/${ADDON_ID}"



# 主程序版本信息（自动从代码中提取）
APP_VERSION="v0.5.3-Beta"
if [ -f "${ROOT_DIR}/internal/buildinfo/version.go" ]; then
    EXTRACTED_VER=$(grep 'Version =' "${ROOT_DIR}/internal/buildinfo/version.go" | cut -d '"' -f 2)
elif [ -f "${ROOT_DIR}/internal/httpx/user_agent.go" ]; then
    EXTRACTED_VER=$(grep 'AppVersion =' "${ROOT_DIR}/internal/httpx/user_agent.go" | cut -d '"' -f 2)
fi
if [ -n "${EXTRACTED_VER}" ]; then
    APP_VERSION="${EXTRACTED_VER}"
fi

# 插件独立发布版本号 (支持插件补丁版本，如 0.5.3.3)
KODI_VERSION="${KODI_ADDON_VERSION:-0.5.3.3}"
VERSION="v${KODI_VERSION}"

# 参数解析
ARCH_PARAM="${1:-all}"  # 默认打全架构通用包 (all, armv7, arm64 或 指定二进制文件路径)

echo "=================================================="
echo " LitePan Kodi 插件一键构建工具"
echo " LitePan 版本: ${VERSION} (Kodi Addon Version: ${KODI_VERSION})"
echo " 构建目标架构: ${ARCH_PARAM}"
echo "=================================================="

mkdir -p "${ADDON_DIR}/bin"
mkdir -p "${ADDON_DIR}/resources"
mkdir -p "${DIST_DIR}"

compile_go() {
    local goos="$1"
    local goarch="$2"
    local goarm="$3"
    local out_name="$4"
    local target_path="${ADDON_DIR}/bin/${out_name}"

    echo " -> 正在交叉编译 ${goos}/${goarch}${goarm:+ (GOARM=${goarm})} 二进制..."
    cd "${ROOT_DIR}"
    
    if [ -n "${goarm}" ]; then
        if ! CGO_ENABLED=0 GOOS="${goos}" GOARCH="${goarch}" GOARM="${goarm}" go build -tags fuse -ldflags="-s -w" -o "${target_path}" ./cmd/litepan; then
            return 1
        fi
    else
        if ! CGO_ENABLED=0 GOOS="${goos}" GOARCH="${goarch}" go build -tags fuse -ldflags="-s -w" -o "${target_path}" ./cmd/litepan; then
            return 1
        fi
    fi
    
    chmod +x "${target_path}"
    echo "    编译成功: ${out_name}"
}

# 1. 自动编译前端 Web 静态资源 (npm run build)
if [ -d "${ROOT_DIR}/web" ]; then
    if [ "${SKIP_BUILD_WEB}" = "1" ] || [ "${SKIP_WEB_BUILD}" = "1" ]; then
        echo "[1/5] 检测到 SKIP_BUILD_WEB=1，跳过前端 Web 界面重复构建..."
    else
        echo "[1/5] 正在构建前端 Web 界面静态资源 (npm run build)..."
        (cd "${ROOT_DIR}/web" && npm run build)
    fi
fi

# 2. 编译/复制二进制文件
if [ -f "${ARCH_PARAM}" ]; then
    echo "[2/5] 使用用户指定的预编译二进制文件: ${ARCH_PARAM}"
    cp "${ARCH_PARAM}" "${ADDON_DIR}/bin/litepan"
    chmod +x "${ADDON_DIR}/bin/litepan"
    ZIP_ARCH_TAG="custom"
elif [ "${ARCH_PARAM}" = "armv7" ] || [ "${ARCH_PARAM}" = "arm7" ] || [ "${ARCH_PARAM}" = "arm32" ]; then
    echo "[2/5] 开始编译 ARMv7 (32位 Linux ARM) 二进制..."
    compile_go "linux" "arm" "7" "litepan_armv7"
    ZIP_ARCH_TAG="armv7"
elif [ "${ARCH_PARAM}" = "arm64" ] || [ "${ARCH_PARAM}" = "aarch64" ]; then
    echo "[2/5] 开始编译 ARM64 (64位 Linux ARM) 二进制..."
    compile_go "linux" "arm64" "" "litepan_arm64"
    ZIP_ARCH_TAG="arm64"
else
    # 默认全架构打包 (同时打入 ARMv7 和 ARM64，实现 CoreELEC 双架构全兼容)
    echo "[2/5] 开始编译双架构 (ARMv7 32位 + ARM64 64位) 通用二进制..."
    compile_go "linux" "arm" "7" "litepan_armv7"
    compile_go "linux" "arm64" "" "litepan_arm64"
    ZIP_ARCH_TAG="universal"
fi

# 3. 生成 Kodi 插件描述文件 (addon.xml) 与 设置配置 (resources/settings.xml)
echo "[3/5] 生成 Kodi 插件描述文件 (addon.xml) 与 设置配置 (settings.xml)..."
cat <<EOF > "${ADDON_DIR}/addon.xml"
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<addon id="${ADDON_ID}" name="LitePan Background Service" version="${KODI_VERSION}" provider-name="LitePan">
  <requires>
    <import addon="xbmc.python" version="3.0.0"/>
  </requires>
  <extension point="xbmc.service" library="service.py" start="startup"/>
  <extension point="xbmc.addon.metadata">
    <summary lang="zh_CN">LitePan 网盘管理工具后台服务</summary>
    <description lang="zh_CN">在 CoreELEC (ARMv7 / ARM64) 后台静默启动 LitePan 守护进程，保留完整 Web 管理界面 (默认端口 5211)。</description>
    <platform>linux</platform>
    <license>PolyForm NC</license>
    <assets>
      <icon>icon.png</icon>
    </assets>
  </extension>
</addon>
EOF

cat <<EOF > "${ADDON_DIR}/resources/settings.xml"
<?xml version="1.0" encoding="utf-8" standalone="yes"?>
<settings>
    <category label="存储路径配置">
        <setting id="data_dir" type="folder" label="数据保存目录 (留空使用默认目录)" default="" />
        <setting id="mount_dir" type="folder" label="本地挂载根目录" default="/storage/videos/mount" />
        <setting id="strm_dir" type="folder" label="STRM 输出目录" default="/storage/videos/strm" />
    </category>
</settings>
EOF

# 4. 生成支持多架构自动判断、动态设置读取及自动热重启的 Kodi 服务守护脚本 (service.py)
echo "[4/5] 生成支持动态路径配置的 Kodi 服务守护脚本 (service.py)..."
cat <<'EOF' > "${ADDON_DIR}/service.py"
# -*- coding: utf-8 -*-
import os
import stat
import subprocess
import platform
import time
import xbmc
import xbmcaddon
import xbmcvfs

class LitePanService(xbmc.Monitor):
    def __init__(self):
        super().__init__()
        self.addon = xbmcaddon.Addon('service.litepan')
        self.addon_dir = xbmcvfs.translatePath(self.addon.getAddonInfo('path'))
        self.profile_dir = xbmcvfs.translatePath(self.addon.getAddonInfo('profile'))
        self.bin_path = self.detect_binary()
        self.process = None

    def detect_binary(self):
        bin_dir = os.path.join(self.addon_dir, 'bin')
        
        # 1. 优先使用单文件 litepan
        single_bin = os.path.join(bin_dir, 'litepan')
        if os.path.exists(single_bin):
            return single_bin

        # 2. 识别系统 CPU 架构选择 armv7 / arm64
        machine = platform.machine().lower()
        xbmc.log(f"[LitePan] 当前 CoreELEC 系统检测到的 CPU 架构为: {machine}", xbmc.LOGINFO)

        target_name = 'litepan_armv7'
        if 'aarch64' in machine or 'arm64' in machine:
            target_name = 'litepan_arm64'
        elif 'arm' in machine or 'armv7' in machine or 'armv6' in machine:
            target_name = 'litepan_armv7'

        target_bin = os.path.join(bin_dir, target_name)
        if os.path.exists(target_bin):
            return target_bin

        # 3. 兜底逻辑：若指定的架构缺失，取 bin/ 目录下现存的任何二进制
        if os.path.exists(bin_dir):
            files = [f for f in os.listdir(bin_dir) if not f.startswith('.')]
            if files:
                return os.path.join(bin_dir, files[0])

        return os.path.join(bin_dir, 'litepan')

    def get_configured_paths(self):
        # 1. 数据目录：优先读取用户自定义设置；若为空则默认使用 profile_dir/data
        custom_data_dir = self.addon.getSetting('data_dir').strip()
        if custom_data_dir:
            data_path = xbmcvfs.translatePath(custom_data_dir)
        else:
            data_path = os.path.join(self.profile_dir, 'data')

        # 2. 挂载根目录
        custom_mount_dir = self.addon.getSetting('mount_dir').strip()
        mount_path = xbmcvfs.translatePath(custom_mount_dir) if custom_mount_dir else '/storage/videos/mount'

        # 3. STRM 目录
        custom_strm_dir = self.addon.getSetting('strm_dir').strip()
        strm_path = xbmcvfs.translatePath(custom_strm_dir) if custom_strm_dir else '/storage/videos/strm'

        return data_path, mount_path, strm_path

    def onSettingsChanged(self):
        xbmc.log("[LitePan] 监听到插件设置发生变更，正在重启服务以应用新配置...", xbmc.LOGINFO)
        self.stop_process()
        self.start_process()

    def start_process(self):
        data_path, mount_path, strm_path = self.get_configured_paths()

        # 确保所有路径目录存在
        for p in [data_path, mount_path, strm_path, os.path.join(self.profile_dir, 'data')]:
            try:
                os.makedirs(p, exist_ok=True)
            except Exception as e:
                xbmc.log(f"[LitePan] 创建目录 {p} 警告: {str(e)}", xbmc.LOGWARNING)

        if not self.bin_path or not os.path.exists(self.bin_path):
            xbmc.log(f"[LitePan] 错误：找不到可执行的二进制文件 ({self.bin_path})", xbmc.LOGERROR)
            return

        # 设置二进制文件的可执行权限 (+x)
        try:
            st = os.stat(self.bin_path)
            os.chmod(self.bin_path, st.st_mode | stat.S_IEXEC | stat.S_IXGRP | stat.S_IXOTH)
        except Exception as e:
            xbmc.log(f"[LitePan] 设置可执行权限警告: {str(e)}", xbmc.LOGWARNING)

        # 注入环境变量 (上游原生支持)
        env = os.environ.copy()
        env['LITEPAN_MOUNT_ROOT'] = mount_path
        env['LITEPAN_STRM_DIR'] = strm_path
        env['LITEPAN_DATA_DIR'] = data_path

        xbmc.log(f"[LitePan] 正在启动后台服务 (Data: {data_path}, Mount: {mount_path}, STRM: {strm_path})，使用的二进制文件: {self.bin_path}", xbmc.LOGINFO)
        try:
            self.process = subprocess.Popen(
                [
                    self.bin_path,
                    "-data-dir", data_path,
                    "-strm-dir", strm_path
                ],
                cwd=data_path,
                env=env,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL
            )
            xbmc.log("[LitePan] 后台服务启动成功 (默认端口: 5211)", xbmc.LOGINFO)
        except Exception as e:
            xbmc.log(f"[LitePan] 进程启动失败: {str(e)}", xbmc.LOGERROR)

    def stop_process(self):
        if self.process and self.process.poll() is None:
            xbmc.log("[LitePan] 收到退出信号，终止后台服务...", xbmc.LOGINFO)
            self.process.terminate()
            try:
                self.process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                self.process.kill()
            xbmc.log("[LitePan] 后台服务已安全停止。", xbmc.LOGINFO)

if __name__ == '__main__':
    service = LitePanService()
    service.start_process()

    while not service.waitForAbort(1):
        if service.process and service.process.poll() is not None:
            xbmc.log("[LitePan] 监测到后台进程退出，重新拉起保活...", xbmc.LOGWARNING)
            service.start_process()

    service.stop_process()
EOF

# 4. 图标处理 (使用官方 LitePan app-icon.png)
ICON_URL="https://www.litepan.top/images/home/app-icon.png"
LOCAL_ICON="${ROOT_DIR}/docs/pictures/app-icon.png"

# 检查文件是否为有效的 PNG 图片
is_valid_png() {
    local file="$1"
    [ -f "$file" ] && [ "$(head -c 4 "$file" 2>/dev/null | xxd -p 2>/dev/null || head -c 4 "$file" 2>/dev/null)" != "" ] && [ $(wc -c <"$file") -gt 500 ]
}

if is_valid_png "${LOCAL_ICON}"; then
    echo " -> 使用本地官方图标: ${LOCAL_ICON}"
    cp "${LOCAL_ICON}" "${ADDON_DIR}/icon.png"
else
    echo " -> 尝试从官方下载图标 (${ICON_URL})..."
    TMP_ICON="/tmp/litepan_icon_$$.png"
    if curl -sSL -A "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)" --connect-timeout 8 "${ICON_URL}" -o "${TMP_ICON}" 2>/dev/null && is_valid_png "${TMP_ICON}"; then
        echo " -> 官方图标下载成功！"
        cp "${TMP_ICON}" "${ADDON_DIR}/icon.png"
        cp "${TMP_ICON}" "${LOCAL_ICON}" 2>/dev/null || true
        rm -f "${TMP_ICON}"
    elif [ -f "${ROOT_DIR}/docs/pictures/banner.png" ]; then
        echo " -> 下载失败或受限，回退使用本地横幅图标"
        cp "${ROOT_DIR}/docs/pictures/banner.png" "${ADDON_DIR}/icon.png"
    else
        touch "${ADDON_DIR}/icon.png"
    fi
fi

# 5. 打包为 ZIP 压缩包
ZIP_NAME="service.litepan-${VERSION}-${ZIP_ARCH_TAG}.zip"
OUTPUT_ZIP="${DIST_DIR}/${ZIP_NAME}"

echo "[5/5] 正在打包成 Kodi 插件包 (ZIP)..."
cd "${BUILD_DIR}"
rm -f "${OUTPUT_ZIP}"
zip -q -r "${OUTPUT_ZIP}" "${ADDON_ID}"

# 清理构建临时目录
rm -rf "${BUILD_DIR}"

echo "=================================================="
echo " 打包成功！"
echo " 插件包保存路径: ${OUTPUT_ZIP}"
echo "=================================================="
echo " 使用说明："
echo " 1. 将 ${ZIP_NAME} 传输到 CoreELEC / Kodi 设备上。"
echo " 2. 在 Kodi 中进入: 插件 -> 从 ZIP 文件安装。"
echo " 3. 插件会自动判断 32位(ARMv7) / 64位(ARM64) 架构并自动启动 LitePan 后台。"
echo " 4. 挂载根目录现已自动切换为: /storage/videos/mount 。"
echo " 5. STRM 输出路径现已自动切换为: /storage/videos/strm 。"
echo " 6. 在局域网浏览器打开 http://<CoreELEC_IP>:5211 进行管理。"
echo "=================================================="
