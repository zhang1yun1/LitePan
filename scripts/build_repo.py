#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Kodi 插件库索引生成脚本 (build_repo.py)
功能：
1. 扫描 zips 目录下所有插件子目录 (如 zips/service.litepan, zips/plugin.video.xxx)
2. 自动支持多架构平台 (linux-aarch64, linux-x86_64, linux-armv7 等) 的细分打包
3. 提取最高版本的各平台包，并在 addons.xml 中注入 <platform> 与精确的 <path> 标签
4. 生成统一的 addons.xml 与 addons.xml.md5
"""

import os
import re
import sys
import zipfile
import hashlib
import xml.etree.ElementTree as ET
from pathlib import Path

STANDARD_PLATFORMS = (
    'android-aarch64', 'android-armv7', 'linux-aarch64', 'linux-armv7',
    'linux-i686', 'linux-x86_64', 'windows-i686', 'windows-x86_64',
    'osx-x86_64', 'osx-arm64', 'ios-arm64',
)

ARCH_ALIASES = {
    'arm64': 'linux-aarch64',
    'aarch64': 'linux-aarch64',
    'amd64': 'linux-x86_64',
    'x86_64': 'linux-x86_64',
    'armv7': 'linux-armv7',
    'arm7': 'linux-armv7',
}

def version_key(version_str: str):
    """
    解析版本号供排序：0.5.7.1 -> (0, 5, 7, 1)
    """
    cleaned = version_str.lstrip('v')
    match = re.match(r'(\d+(?:\.\d+)*)(.*)', cleaned)
    if not match:
        return ((0,), False, '')
    numbers = tuple(map(int, match.group(1).split('.')))
    suffix = match.group(2).lower()
    return (numbers + (0,) * max(0, 8 - len(numbers)), not bool(suffix), suffix)

def get_platform_from_filename(filename: str, fallback_platform: str = 'all') -> str:
    name_no_ext = filename[:-4] if filename.endswith('.zip') else filename
    # 优先匹配标准平台
    for p in STANDARD_PLATFORMS:
        if name_no_ext.endswith(f'-{p}'):
            return p
    # 匹配架构简写
    for alias, standard in ARCH_ALIASES.items():
        if name_no_ext.endswith(f'-{alias}'):
            return standard
    return fallback_platform

def extract_addon_xml_bytes(zip_path: Path):
    """从 ZIP 中提取 addon.xml 原始字节"""
    try:
        with zipfile.ZipFile(zip_path, 'r') as zf:
            for item in zf.infolist():
                if item.filename.endswith('addon.xml') and item.filename.count('/') <= 1:
                    return zf.read(item.filename)
    except Exception as e:
        print(f"[ERROR] 读取 {zip_path.name} 中的 addon.xml 失败: {e}")
    return None

def extract_assets(zip_path: Path, target_dir: Path):
    """从 ZIP 中提取 icon.png, fanart.jpg 等资源"""
    try:
        with zipfile.ZipFile(zip_path, 'r') as zf:
            for name in zf.namelist():
                base = os.path.basename(name)
                if base in ('icon.png', 'icon.jpg', 'fanart.jpg', 'fanart.png') and name.count('/') <= 1:
                    dest = target_dir / base
                    if not dest.exists():
                        dest.write_bytes(zf.read(name))
    except Exception as e:
        print(f"[WARN] 提取资产文件失败 {zip_path.name}: {e}")

def clean_xml_header(content: str) -> str:
    lines = [line for line in content.splitlines() if not line.strip().startswith('<?xml')]
    return "\n".join(lines).strip()

def process_addon_dir(addon_dir: Path):
    """
    处理单个插件目录，返回生成的 addon.xml 片段列表
    """
    if not addon_dir.is_dir():
        return []

    zip_files = list(addon_dir.glob("*.zip"))
    if not zip_files:
        # 没有 zip 文件，检查是否有现成的 addon.xml
        xml_path = addon_dir / "addon.xml"
        if xml_path.exists():
            return [clean_xml_header(xml_path.read_text(encoding='utf-8'))]
        return []

    # 解析所有 zip 包的元数据
    packages = []
    for zf in zip_files:
        raw_xml = extract_addon_xml_bytes(zf)
        if not raw_xml:
            continue
        try:
            root = ET.fromstring(raw_xml)
        except Exception as e:
            print(f"[ERROR] 解析 XML 失败 {zf.name}: {e}")
            continue

        addon_id = root.attrib.get('id')
        version = root.attrib.get('version')
        if not addon_id or not version:
            continue

        metadata = root.find("extension[@point='xbmc.addon.metadata']")
        xml_platform = 'all'
        if metadata is not None:
            p_elem = metadata.find('platform')
            if p_elem is not None and p_elem.text:
                xml_platform = p_elem.text.strip()

        # 根据文件名识别平台，若无后缀则使用 XML 内自带的平台
        detected_platform = get_platform_from_filename(zf.name, fallback_platform=xml_platform)
        packages.append({
            'path': zf,
            'root': root,
            'addon_id': addon_id,
            'version': version,
            'platform': detected_platform,
            'metadata': metadata,
        })

    if not packages:
        return []

    # 找到最高版本
    latest_ver_key = max(version_key(p['version']) for p in packages)
    latest_packages = [p for p in packages if version_key(p['version']) == latest_ver_key]

    # 按平台去重（相同平台保留修改时间最新的）
    platform_map = {}
    for p in sorted(latest_packages, key=lambda x: x['path'].stat().st_mtime):
        platform_map[p['platform']] = p

    results = []
    # 按照优先级排序：让精确平台 (如 linux-x86_64) 先输出，让带 linux 兜底的 linux-aarch64 后输出
    # 这样当 Kodi 遇到完全同版本条目时，优先匹配精确架构，未识别架构的 Linux 则自然落入 linux-aarch64 兜底
    ordered_platforms = sorted(platform_map.keys(), key=lambda p: (1 if p == 'linux-aarch64' else 0, p))
    for platform in ordered_platforms:
        pkg = platform_map[platform]
        root = pkg['root']
        metadata = pkg['metadata']
        if metadata is None:
            metadata = ET.SubElement(root, 'extension', point='xbmc.addon.metadata')

        # 平台值适配：让未识别架构的 Linux 统一兜底下载 ARM64 (linux-aarch64 linux)
        if platform == 'linux-aarch64':
            platform_str = 'linux-aarch64 linux'
        elif platform == 'linux-armv7':
            platform_str = 'linux-armv7'
        else:
            platform_str = platform

        # 更新/添加 platform 标签
        for p_old in metadata.findall('platform'):
            metadata.remove(p_old)
        ET.SubElement(metadata, 'platform').text = platform_str

        # 更新/添加 path 标签指向对应的 zip 包相对路径
        for path_old in metadata.findall('path'):
            metadata.remove(path_old)
        rel_path = f"{pkg['addon_id']}/{pkg['path'].name}"
        ET.SubElement(metadata, 'path').text = rel_path

        xml_str = ET.tostring(root, encoding='utf-8').decode('utf-8')
        results.append(clean_xml_header(xml_str))

        # 顺便提取 icon / fanart
        extract_assets(pkg['path'], addon_dir)

    print(f"[DEBUG] 插件 {addon_dir.name} 解析出 {len(results)} 个平台条目 (版本: {latest_packages[0]['version']})")
    return results

def process_dir(target_dir):
    zips_root = Path(target_dir) / "zips"
    if not zips_root.exists():
        print(f"[WARN] 目录 {zips_root} 不存在，跳过处理")
        return

    all_addon_xmls = []

    # 扫描 zips 目录下的各个插件目录 (如 zips/plugin.video.juku, zips/service.litepan)
    for item in sorted(zips_root.iterdir()):
        if item.is_dir():
            print(f"[DEBUG] 扫描到目录: {item.name}")
            xml_entries = process_addon_dir(item)
            all_addon_xmls.extend(xml_entries)

    # 生成 zips 根目录统一的 addons.xml 与 md5
    if all_addon_xmls:
        content = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n<addons>\n'
        content += "\n".join(all_addon_xmls) + "\n</addons>\n"

        out_xml = zips_root / "addons.xml"
        out_xml.write_text(content, encoding='utf-8')

        md5_str = hashlib.md5(content.encode('utf-8')).hexdigest()
        out_md5 = zips_root / "addons.xml.md5"
        out_md5.write_text(md5_str, encoding='utf-8')
        print(f"[SUCCESS] 生成插件库统一索引: {out_xml} (共 {len(all_addon_xmls)} 个条目, MD5: {md5_str})")
    else:
        print(f"[WARN] 未在 {zips_root} 下找到任何有效的插件目录")

if __name__ == "__main__":
    target = sys.argv[1] if len(sys.argv) > 1 else "."
    print(f"--- 开始构建 Kodi 插件库索引 ({target}) ---")
    process_dir(target)
    print("--- 插件库索引构建完成 ---")
