#!/usr/bin/env python3
"""Generate the Smartisan R2 app inventory report as a Kami long-doc HTML."""

from __future__ import annotations

import datetime as _dt
import html
import json
import re
from dataclasses import asdict, dataclass
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
KAMI = Path("/Users/siaovon/.skills/kami")
TEMPLATE = KAMI / "assets/templates/long-doc.html"

DATA_DIR = ROOT / "data/app-inventory"
OUT_DIR = ROOT / "reports/app-inventory"

PM_ALL = DATA_DIR / "pm-list-packages-f-U-version-after-apkextractor-uninstall.txt"
PM_SYSTEM = DATA_DIR / "pm-list-packages-f-s-U-version-after-apkextractor-uninstall.txt"
PM_THIRD = DATA_DIR / "pm-list-packages-f-3-U-version-after-apkextractor-uninstall.txt"
OVERLAYS = DATA_DIR / "cmd-overlay-list-after-apkextractor-uninstall.txt"

REPORT_HTML = OUT_DIR / "smartisan-r2-app-inventory.html"
REPORT_JSON = OUT_DIR / "smartisan-r2-app-inventory.json"


@dataclass
class AppRow:
    package: str
    path: str
    apk: str
    module: str
    partition: str
    install_scope: str
    version_code: str
    uid: str
    category: str
    purpose: str
    risk: str
    risk_label: str
    action: str
    evidence: str
    overlay_state: str = ""


RISK_LABELS = {
    "critical": "红 · 暂不触碰",
    "high": "橙 · 先调查",
    "medium": "蓝 · 中等风险",
    "low": "绿 · 低风险候选",
    "user": "灰 · 用户应用",
}

RISK_ORDER = {
    "critical": 0,
    "high": 1,
    "medium": 2,
    "low": 3,
    "user": 4,
}


EXACT_PURPOSE = {
    "android": "Android framework-res，全局系统资源、资源 ID 与基础 framework 资源入口。",
    "smartisanos": "Smartisan framework 资源包，提供锤子系统扩展资源与系统级样式。",
    "android.ext.services": "Android ExtServices APEX 模块，承载系统级文本分类、存储、通知等扩展服务。",
    "android.ext.shared": "Android 扩展共享库，供系统组件和应用复用。",
    "com.android.providers.settings": "SettingsProvider，保存系统设置、secure/global/system 设置项。",
    "com.android.settings": "系统设置主应用，承载设置 UI 与大量系统配置入口。",
    "com.android.systemui": "系统 UI，状态栏、通知、快捷设置、系统导航等核心界面。",
    "com.android.desktop.systemui": "Smartisan 桌面/TNT 相关 SystemUI 组件。",
    "com.smartisanos.launcher": "Smartisan 桌面启动器，主屏、图标、桌面数据库与入口管理。",
    "com.android.launcher3": "Android/Smartisan 原始 Launcher 兼容组件。",
    "com.smartisanos.keyguard": "Smartisan 锁屏与 keyguard 界面，开机解锁链路核心组件。",
    "com.smartisanos.desktop": "Smartisan 桌面模式/TNT 桌面组件。",
    "com.android.packageinstaller": "系统包安装器，处理 APK 安装、卸载与权限确认流程。",
    "com.android.permissioncontroller": "权限控制器，运行时权限、权限弹窗与权限策略核心组件。",
    "com.android.providers.downloads": "下载提供者，系统下载数据库与下载服务。",
    "com.android.providers.downloads.ui": "下载管理 UI，显示和管理系统下载任务。",
    "com.android.providers.media.module": "MediaProvider APEX 模块，Android 媒体库扫描与媒体数据库核心。",
    "com.android.providers.media": "Legacy MediaProvider，兼容旧媒体 provider 路径。",
    "com.android.externalstorage": "ExternalStorageProvider，文件选择器和存储访问框架的核心 provider。",
    "com.android.documentsui": "系统文件选择器/DocumentsUI，存储访问框架 UI。",
    "com.android.mtp": "MTP 服务，负责 USB 文件传输协议。",
    "com.android.shell": "ADB shell 包，调试、shell 权限和部分系统命令入口。",
    "com.android.webview": "Android System WebView，应用内网页渲染引擎。",
    "com.android.browser": "系统内置浏览器 BrowserChrome，Smartisan 自带浏览器入口。",
    "com.android.phone": "TeleService，蜂窝电话和 SIM 相关核心服务。",
    "com.android.server.telecom": "Telecom 服务，通话路由、电话账户、呼叫状态管理。",
    "com.android.incallui": "通话中界面，接听、挂断、通话 UI。",
    "com.android.providers.telephony": "TelephonyProvider，短信、彩信、APN 与电话相关数据库。",
    "com.android.mms": "Smartisan 短信/彩信应用。",
    "com.android.mms.service": "MMS 后台服务，彩信收发与相关 provider 支撑。",
    "org.codeaurora.ims": "Qualcomm IMS 服务，VoLTE/VoWiFi/RCS 等运营商通话能力。",
    "com.qualcomm.qcrilmsgtunnel": "Qualcomm RIL 消息隧道，基带/电话栈通信组件。",
    "com.android.carrierconfig": "运营商配置服务，读取和应用运营商网络/通话策略。",
    "com.android.emergency": "EmergencyInfo，紧急信息和紧急联系人相关系统组件。",
    "com.android.bluetooth": "蓝牙系统服务，蓝牙连接、配对、音频与外设支持。",
    "com.android.networkstack": "Android NetworkStack，网络验证、IP 配置、连接管理核心。",
    "com.android.networkstack.tethering": "Tethering APEX，热点/网络共享核心服务。",
    "com.android.wifi.resources": "Wi-Fi APEX 资源包，供 Wi-Fi 栈读取资源与配置。",
    "vendor.qti.iwlan": "Qualcomm IWLAN 服务，Wi-Fi calling / ePDG 等蜂窝-Wi-Fi 互通能力。",
    "com.qualcomm.qti.cne": "Qualcomm Connectivity Engine，网络选择、链路质量和连接优化服务。",
    "com.android.camera2": "Smartisan 相机应用。",
    "com.android.gallery3d": "Smartisan 图库应用。",
    "com.android.contacts": "Smartisan 联系人应用。",
    "com.android.providers.contacts": "联系人数据库 provider，联系人、通话相关数据核心。",
    "com.smartisanos.clock": "Smartisan 时钟、闹钟、计时器应用。",
    "com.smartisanos.updater": "SmartisanUpdater，系统更新检查、下载与 OTA 入口。",
    "me.bmax.apatch": "APatch 管理器，当前 root 路线的管理端应用。",
    "com.topjohnwu.magisk": "Magisk 管理器残留应用；当前 root 路线不是 Magisk，但可用于历史对照。",
    "org.cromite.cromite": "Cromite 浏览器，作为现代浏览器用户态补充。",
}

LOW_PURPOSE = {
    "com.android.cts.ctsshim": "CTS 兼容性 shim，主要服务兼容性测试，不面向日常用户。",
    "com.android.cts.priv.ctsshim": "Privileged CTS 兼容性 shim，主要服务系统兼容性测试。",
    "com.android.egg": "Android 彩蛋应用，非功能核心。",
    "com.android.protips": "旧版 Android tips 小组件/提示应用。",
    "com.android.traceur": "系统 tracing UI，用于开发者性能跟踪。",
    "com.smartisanos.bug2go": "Smartisan bugreport/反馈采集工具。",
    "com.goodix.fingerprint.producttest": "Goodix 指纹工厂/产测应用。",
    "com.android.dreams.basic": "Android 基础屏保/Dream 组件。",
    "com.android.dreams.phototable": "照片桌面屏保/Dream 组件。",
    "com.android.wallpaper.livepicker": "动态壁纸选择器。",
    "com.android.wallpaperbackup": "壁纸备份/恢复辅助组件。",
    "com.android.bips": "内置打印服务。",
    "com.android.printspooler": "Android 打印队列/打印后台服务。",
    "com.android.printservice.recommendation": "打印服务推荐组件。",
    "com.android.htmlviewer": "简单 HTML 查看器。",
    "com.android.exchange": "Exchange 邮件同步组件；Email 主体已移除后的残留候选。",
    "com.android.musicfx": "Android 音效控制面板。",
}

MEDIUM_PURPOSE = {
    "com.smartisanos.cloudsync": "Smartisan 云同步主应用/更新包，负责账号云同步体验。",
    "com.smartisanos.cloudagent": "Smartisan 云同步代理服务。",
    "com.smartisanos.cloudsyncshare": "Smartisan 云同步分享服务。",
    "com.smartisanos.wallet": "Smartisan 钱包应用。",
    "com.smartisanos.weather": "Smartisan 天气应用。",
    "com.android.providers.weather": "天气数据 provider。",
    "com.smartisanos.sara": "Smartisan 语音助手主应用。",
    "com.smartisanos.voice": "语音助手后台服务。",
    "com.iflytek.speechsuite": "讯飞语音套件，语音识别/合成能力。",
    "com.smartisanos.smartisanbrain": "Smartisan Brain 智能服务组件。",
    "com.smartisanos.ideapills": "闪念胶囊/IdeaPills 组件。",
    "com.smartisanos.textboom": "Big Bang/TextBoom 文本处理功能。",
    "com.smartisanos.textparticiple": "文本分词组件，支撑 Big Bang/搜索等文本能力。",
    "com.smartisanos.intelligenwords": "Smartisan 智能词语/文本辅助组件。",
    "com.smartisanos.quicksearch": "Smartisan 快速搜索组件。",
    "com.smartisanos.music": "Smartisan 音乐播放器。",
    "com.smartisanos.videoplayerproject": "Smartisan 视频播放器。",
    "com.smartisanos.screenrecorder": "Smartisan 屏幕录制。",
    "com.smartisanos.virtualremoter": "虚拟遥控器。",
    "com.smartisanos.boston.phone": "Boston/TNT 投屏相关手机端组件。",
    "com.bytedance.casthal": "Boston Cast HAL 服务，投屏底层服务。",
    "com.bytedance.wirelesscast": "Smartisan 无线投屏组件。",
    "com.smartisanos.smartfolder.aoa": "HandShaker/手机文件互传组件。",
    "com.smartisanos.share.browser": "Smartisan 分享浏览器/分享入口组件。",
    "com.smartisanos.manual": "Smartisan 分享/手册相关组件。",
    "com.smartisan.crashreport": "Smartisan crash report 崩溃日志上报组件。",
    "com.smartisanos.tracker": "Smartisan tracker 埋点/统计组件。",
    "com.smartisanos.teatracker": "Smartisan TeaTracker 埋点/统计组件。",
    "com.bytedance.os.slardar": "字节 Slardar OS 客户端，统计/崩溃/性能上报相关。",
    "com.smartisan.smpush": "Smartisan 推送服务。",
    "com.smartisan.unionpush.proxy": "统一推送代理服务。",
    "com.cmcc.csu": "中国移动 CSU 运营商组件。",
    "com.redteamobile.global.roaming": "Redtea 国际漫游/eSIM 相关应用。",
    "com.redteamobile.virtual.softsim": "Redtea 软 SIM/虚拟 SIM 系统组件。",
    "com.bytedance.deltammi": "字节/Smartisan 预置组件，需结合实际使用场景判断。",
    "com.google.android.marvin.talkback": "TalkBack 无障碍读屏服务。",
    "com.smartisanos.hearingaid": "Smartisan 助听/听力辅助组件。",
    "com.smartisan.facerecognition": "Smartisan 人脸识别组件。",
}

HIGH_PURPOSE = {
    "com.smartisanos.ime": "Smartisan 输入法。",
    "com.smartisanos.security.ime": "Smartisan 安全输入法，密码/隐私场景可能调用。",
    "com.android.inputmethod.latin": "AOSP LatinIME 输入法，至少应保留一个可用键盘。",
    "com.smartisanos.security": "Smartisan 权限管理/安全策略入口。",
    "com.smartisanos.securitycenter": "Smartisan 安全中心，权限、清理、安全策略相关。",
    "com.amap.android.location": "高德定位组件。",
    "com.android.location.fused": "Android 融合定位 provider。",
    "com.qualcomm.location": "Qualcomm 定位服务。",
    "com.smartisanos.filemanager": "Smartisan 文件管理器。",
    "com.smartisanos.filemanagerservice": "Smartisan 文件管理后台服务。",
    "com.smartisanos.filepreview": "Smartisan 文件预览组件。",
    "com.smartisanos.previewer": "Smartisan 文件预览器。",
    "com.android.nfc": "NFC 服务。",
    "com.android.se": "Secure Element 安全元件服务。",
    "com.android.stk": "SIM Toolkit 运营商菜单。",
    "com.android.apps.tag": "NFC Tag 应用。",
    "org.ifaa.android.service": "IFAA 生物识别/支付认证服务。",
    "com.tencent.soter.soterserver": "腾讯 Soter 安全认证服务。",
    "com.smartisanos.setupwizard": "Smartisan 初始设置向导。",
    "com.smartisan.table.setupwizard": "Smartisan 桌面/平板模式设置向导。",
    "com.android.managedprovisioning": "Android 企业/工作资料配置向导。",
}

CRITICAL_PACKAGES = {
    "android",
    "smartisanos",
    "android.ext.services",
    "android.ext.shared",
    "com.android.providers.settings",
    "com.android.settings",
    "com.android.systemui",
    "com.android.desktop.systemui",
    "com.smartisanos.launcher",
    "com.android.launcher3",
    "com.smartisanos.keyguard",
    "com.smartisanos.desktop",
    "com.android.desktop.recentspsp",
    "com.android.recentspsp",
    "com.android.packageinstaller",
    "com.android.permissioncontroller",
    "com.android.providers.downloads",
    "com.android.providers.downloads.ui",
    "com.android.providers.media.module",
    "com.android.providers.media",
    "com.android.externalstorage",
    "com.android.documentsui",
    "com.android.mtp",
    "com.android.shell",
    "com.android.webview",
    "com.android.browser",
    "com.android.phone",
    "com.android.server.telecom",
    "com.android.incallui",
    "com.android.providers.telephony",
    "com.android.mms",
    "com.android.mms.service",
    "org.codeaurora.ims",
    "com.qualcomm.qcrilmsgtunnel",
    "com.android.carrierconfig",
    "com.android.emergency",
    "com.android.bluetooth",
    "com.android.networkstack",
    "com.android.networkstack.permissionconfig",
    "com.android.networkstack.tethering",
    "com.android.wifi.resources",
    "vendor.qti.iwlan",
    "com.qualcomm.qti.cne",
    "com.android.camera2",
    "com.android.gallery3d",
    "com.android.contacts",
    "com.android.providers.contacts",
    "com.smartisanos.clock",
    "com.smartisanos.updater",
    "me.bmax.apatch",
}

USER_APP_PURPOSE = {
    "com.android.vending": "Google Play 商店，用户安装的 Google 应用商店。",
    "com.google.android.gms": "Google Play services，Google 服务框架核心。",
    "com.google.android.gsf": "Google Services Framework。",
    "com.google.android.gsf.login": "Google 账号登录服务。",
    "com.google.android.syncadapters.contacts": "Google 联系人同步适配器。",
    "com.google.android.syncadapters.calendar": "Google 日历同步适配器。",
    "com.google.android.contactkeys": "Google Contact Keys / 联系人密钥相关组件。",
    "com.google.android.safetycore": "Google SafetyCore 安全/隐私相关组件。",
    "cn.wps.moffice.lite.smartison_large": "WPS Office Smartisan 定制/轻量版。",
    "cn.cyberIdentity.certification": "网证/身份认证类用户应用。",
    "com.intsig.camscanner": "扫描全能王用户应用。",
    "org.cromite.cromite": "Cromite 浏览器用户应用。",
    "com.topjohnwu.magisk": "Magisk 管理器用户应用，当前 root 路线不是 Magisk。",
}


def parse_pm_line(line: str) -> tuple[str, str, str, str]:
    body = line.strip()[len("package:") :]
    before_uid, uid = body.rsplit(" uid:", 1)
    before_version, version = before_uid.rsplit(" versionCode:", 1)
    path, package = before_version.rsplit("=", 1)
    return path, package, version, uid


def parse_pm(path: Path) -> list[tuple[str, str, str, str]]:
    rows = []
    for line in path.read_text().splitlines():
        if line.startswith("package:"):
            rows.append(parse_pm_line(line))
    return rows


def parse_pkg_set(path: Path) -> set[str]:
    return {package for _, package, _, _ in parse_pm(path)}


def parse_overlays(path: Path) -> dict[str, str]:
    states: dict[str, str] = {}
    for raw in path.read_text().splitlines():
        line = raw.strip()
        if line.startswith("[x] "):
            states[line[4:]] = "enabled"
        elif line.startswith("[ ] "):
            states[line[4:]] = "disabled"
        elif line.startswith("--- "):
            states[line[4:]] = "static"
    return states


def partition_for(path: str) -> str:
    if path.startswith("/apex/"):
        return "apex"
    if path.startswith("/data/"):
        return "data"
    if path.startswith("/product/"):
        return "product"
    if path.startswith("/vendor/"):
        return "vendor"
    if path.startswith("/system_ext/"):
        return "system_ext"
    if path.startswith("/system/"):
        return "system"
    return "other"


def module_for(path: str) -> str:
    p = Path(path)
    if path.endswith(".apk"):
        return p.parent.name
    return p.name


def apk_for(path: str) -> str:
    return Path(path).name


def nice_from_module(module: str) -> str:
    text = re.sub(r"(?<!^)([A-Z])", r" \1", module).replace("_", " ").replace("-", " ")
    return " ".join(text.split())


def is_overlay(package: str, path: str) -> bool:
    return "/overlay/" in path or ".overlay." in package or package.startswith("com.android.theme.")


def overlay_purpose(package: str, path: str, state: str) -> str:
    suffix = "当前启用" if state == "enabled" else "当前禁用" if state == "disabled" else "静态/资源 overlay"
    if "display.cutout" in package:
        return f"屏幕挖孔/刘海模拟 overlay，{suffix}。"
    if "navbar" in package:
        return f"导航栏模式 overlay，{suffix}。"
    if ".theme.color." in package:
        return f"系统强调色主题 overlay，{suffix}。"
    if ".theme.icon_pack." in package:
        return f"图标包 overlay，{suffix}。"
    if ".theme.icon." in package:
        return f"图标形状 overlay，{suffix}。"
    if ".theme.font." in package:
        return f"字体主题 overlay，{suffix}。"
    return f"系统资源 overlay，目标包由 overlay 管理；{suffix}。"


def infer_category(package: str, path: str, install_scope: str, overlay_state: str) -> str:
    if is_overlay(package, path):
        return "资源 overlay"
    if path.startswith("/apex/"):
        return "APEX 模块"
    if package.startswith("com.android.providers"):
        return "系统数据 provider"
    if package.startswith("com.android.theme") or "overlay" in package:
        return "主题/资源"
    if package.startswith("com.qualcomm") or package.startswith("com.qti") or package.startswith("vendor.qti"):
        return "Qualcomm/供应商服务"
    if package.startswith("com.smartisanos") or package.startswith("smartisan"):
        return "Smartisan 系统组件"
    if package.startswith("com.google"):
        return "Google 用户/服务组件" if install_scope == "third-party" else "Google/Android 组件"
    if package.startswith("com.bytedance"):
        return "字节/Smartisan 预置组件"
    if install_scope == "third-party":
        return "用户应用"
    return "Android 系统组件"


def infer_purpose(package: str, path: str, overlay_state: str) -> tuple[str, str]:
    if package in EXACT_PURPOSE:
        return EXACT_PURPOSE[package], "精确规则"
    if package in LOW_PURPOSE:
        return LOW_PURPOSE[package], "v0.5 低风险候选"
    if package in MEDIUM_PURPOSE:
        return MEDIUM_PURPOSE[package], "v0.5 中风险组"
    if package in HIGH_PURPOSE:
        return HIGH_PURPOSE[package], "v0.5 调查组"
    if package in USER_APP_PURPOSE:
        return USER_APP_PURPOSE[package], "用户应用规则"
    if is_overlay(package, path):
        return overlay_purpose(package, path, overlay_state), "overlay 规则"
    module = nice_from_module(module_for(path))
    if package.startswith("com.android.providers."):
        name = package.rsplit(".", 1)[-1]
        return f"Android {name} 数据 provider，向系统或应用提供对应数据访问。", "provider 推断"
    if package.startswith("com.android."):
        name = package.rsplit(".", 1)[-1]
        return f"Android 系统组件 {module or name}，按包名/路径推断负责 {name} 相关系统能力。", "包名推断"
    if package.startswith("com.smartisanos."):
        name = package.split("com.smartisanos.", 1)[1]
        return f"Smartisan 系统组件 {module or name}，按包名/路径推断负责 {name} 相关功能。", "包名推断"
    if package.startswith("com.qualcomm") or package.startswith("com.qti") or package.startswith("vendor.qti"):
        return f"Qualcomm/供应商组件 {module}，按路径推断服务于硬件、通信、性能或安全能力。", "供应商路径推断"
    if package.startswith("com.bytedance."):
        return f"字节/Smartisan 预置组件 {module}，需结合反编译或运行日志确认精确职责。", "包名推断"
    if package.startswith("com.google."):
        return f"Google 组件 {module}，按包名/路径推断服务于 Google 框架、同步或安全能力。", "包名推断"
    return f"按包名/路径推断为 {module} 组件；精确行为需要进一步反编译或运行日志确认。", "保守推断"


def classify_risk(package: str, path: str, install_scope: str, overlay_state: str) -> tuple[str, str]:
    if package in CRITICAL_PACKAGES:
        return "critical", "保留；属于核心启动、UI、权限、包管理、电话、网络、WebView/root 或当前已知脆弱面。"
    if install_scope == "third-party":
        if package in {"com.google.android.gms", "com.google.android.gsf", "com.google.android.gsf.login"}:
            return "user", "用户应用；可卸载但会破坏 Google 服务生态，不纳入硬 ROM 删除。"
        if package == "org.cromite.cromite":
            return "user", "用户态现代浏览器，建议保留作为旧系统浏览器的补充。"
        if package == "com.topjohnwu.magisk":
            return "user", "用户应用；当前 root 不依赖 Magisk，可后续按需卸载。"
        return "user", "用户应用；优先用普通卸载处理，不作为 hard-ROM 精简目标。"
    if is_overlay(package, path):
        if overlay_state == "disabled":
            return "low", "低风险候选；当前 overlay 未启用，但删除 product overlay 需要 product_b 构建支持。"
        return "critical", "资源 overlay 当前启用或静态加载；先保留，除非验证目标包资源依赖。"
    if package in LOW_PURPOSE:
        return "low", "低风险候选；功能非核心，适合进入下一轮小步验证。"
    if package in MEDIUM_PURPOSE:
        return "medium", "中等风险；用户可见或厂商体验组件，删除前确认是否需要对应功能。"
    if package in HIGH_PURPOSE:
        return "high", "高风险；跨权限、输入、定位、文件、NFC/SIM/认证或初始化链路，先做依赖检查。"
    if path.startswith("/apex/"):
        return "critical", "APEX 模块；不要在当前 hard-ROM 阶段直接删除。"
    if path.startswith("/vendor/") or path.startswith("/system_ext/"):
        return "high", "供应商/扩展分区组件；可能牵涉 HAL、RIL、IMS、Wi-Fi 或硬件服务，先调查。"
    if "Provider" in path or package.startswith("com.android.providers"):
        return "critical", "系统 provider；删除会影响数据、权限或框架访问路径。"
    return "high", "未进入候选清单；先保守标记为需调查。"


def rows() -> list[AppRow]:
    system = parse_pkg_set(PM_SYSTEM)
    third = parse_pkg_set(PM_THIRD)
    overlays = parse_overlays(OVERLAYS)
    result = []
    for path, package, version_code, uid in parse_pm(PM_ALL):
        install_scope = "third-party" if package in third else "system" if package in system else "unknown"
        partition = partition_for(path)
        overlay_state = overlays.get(package, "")
        category = infer_category(package, path, install_scope, overlay_state)
        purpose, evidence = infer_purpose(package, path, overlay_state)
        risk, action = classify_risk(package, path, install_scope, overlay_state)
        result.append(
            AppRow(
                package=package,
                path=path,
                apk=apk_for(path),
                module=module_for(path),
                partition=partition,
                install_scope=install_scope,
                version_code=version_code,
                uid=uid,
                category=category,
                purpose=purpose,
                risk=risk,
                risk_label=RISK_LABELS[risk],
                action=action,
                evidence=evidence,
                overlay_state=overlay_state,
            )
        )
    return sorted(result, key=lambda r: (RISK_ORDER[r.risk], r.category, r.package))


def esc(value: object) -> str:
    return html.escape(str(value), quote=True)


def count_by(rows_: list[AppRow], attr: str) -> dict[str, int]:
    counts: dict[str, int] = {}
    for row in rows_:
        key = getattr(row, attr)
        counts[key] = counts.get(key, 0) + 1
    return counts


def table_rows(rows_: list[AppRow]) -> str:
    out = []
    for idx, row in enumerate(rows_, 1):
        overlay_note = f" · overlay:{row.overlay_state}" if row.overlay_state else ""
        out.append(
            f"""<tr class="app-row risk-row-{esc(row.risk)}">
  <td class="num">{idx}</td>
  <td><code class="pkg">{esc(row.package)}</code><div class="mini">{esc(row.apk)}</div></td>
  <td>{esc(row.category)}<div class="mini">{esc(row.partition)} · {esc(row.install_scope)}{esc(overlay_note)}</div></td>
  <td>{esc(row.purpose)}</td>
  <td><span class="risk-badge risk-{esc(row.risk)}">{esc(row.risk_label)}</span></td>
  <td>{esc(row.action)}<div class="mini">依据：{esc(row.evidence)} · versionCode {esc(row.version_code)} · uid {esc(row.uid)}</div></td>
  <td><code class="path">{esc(row.path)}</code></td>
</tr>"""
        )
    return "\n".join(out)


def summary_grid(rows_: list[AppRow]) -> str:
    risk_counts = count_by(rows_, "risk")
    partition_counts = count_by(rows_, "partition")
    return f"""
  <div class="glance-grid">
    <div class="glance-cell">
      <div class="glance-label">TOTAL PACKAGES</div>
      <div class="glance-value">{len(rows_)}</div>
      <div class="glance-note">卸载 APK Extractor 后的 PackageManager 全量清单</div>
    </div>
    <div class="glance-cell">
      <div class="glance-label">SYSTEM / USER</div>
      <div class="glance-value">{sum(1 for r in rows_ if r.install_scope == "system")} / {sum(1 for r in rows_ if r.install_scope == "third-party")}</div>
      <div class="glance-note">系统或系统更新包 / 第三方用户应用</div>
    </div>
    <div class="glance-cell">
      <div class="glance-label">LOW CANDIDATES</div>
      <div class="glance-value">{risk_counts.get("low", 0)}</div>
      <div class="glance-note">当前可作为下一轮低风险候选</div>
    </div>
    <div class="glance-cell">
      <div class="glance-label">CORE KEEP</div>
      <div class="glance-value">{risk_counts.get("critical", 0)}</div>
      <div class="glance-note">红色项先不进入硬精简</div>
    </div>
  </div>
  <table class="kami-table compact striped summary-table">
    <thead><tr><th>分区</th><th>数量</th><th>说明</th></tr></thead>
    <tbody>
      {''.join(f"<tr><td>{esc(k)}</td><td>{v}</td><td>{esc(partition_note(k))}</td></tr>" for k, v in sorted(partition_counts.items()))}
    </tbody>
  </table>
"""


def partition_note(partition: str) -> str:
    return {
        "apex": "模块化系统包，当前阶段保守保留。",
        "data": "用户空间或更新后的系统应用，优先普通卸载或数据清理。",
        "product": "product 分区，overlay 删除需要 product_b 构建能力。",
        "system": "system 分区，是当前 hard-ROM 主要修改目标。",
        "system_ext": "系统扩展分区，常与 Qualcomm/权限/硬件服务耦合。",
        "vendor": "供应商分区，常与 HAL、基带、硬件驱动耦合。",
    }.get(partition, "其它路径。")


REPORT_CSS = """
  .app-report {
    counter-reset: approw;
  }
  @media screen {
    body.app-report {
      max-width: 1380px;
    }
  }
  .glance-grid {
    display: grid;
    grid-template-columns: 1fr 1fr;
    gap: 14pt;
    margin: 18pt 0;
  }
  .glance-cell {
    padding: 12pt 0 10pt 14pt;
    border-left: 2pt solid var(--brand);
    border-radius: 1.5pt;
  }
  .glance-label {
    font-family: var(--mono, var(--serif));
    font-size: 8.5pt;
    color: var(--brand);
    letter-spacing: 1pt;
    text-transform: uppercase;
    font-weight: 500;
  }
  .glance-value {
    font-size: 18pt;
    font-weight: 500;
    color: var(--near-black);
    font-variant-numeric: tabular-nums;
    letter-spacing: 0.5pt;
  }
  .glance-note {
    font-size: 9pt;
    color: var(--olive);
    line-height: 1.4;
  }
  .risk-badge {
    display: inline-block;
    border-radius: 3pt;
    padding: 1pt 5pt;
    font-size: 8pt;
    line-height: 1.35;
    white-space: nowrap;
  }
  .risk-critical { background: #f0e0d8; color: #8b4513; }
  .risk-high { background: #efe6d5; color: #6a4a1f; }
  .risk-medium { background: #E4ECF5; color: var(--brand); }
  .risk-low { background: #e7ece0; color: #3f5f37; }
  .risk-user { background: var(--border); color: var(--dark-warm); }
  .risk-row-critical td:first-child { border-left: 2pt solid #8b4513; }
  .risk-row-high td:first-child { border-left: 2pt solid #6a4a1f; }
  .risk-row-medium td:first-child { border-left: 2pt solid var(--brand); }
  .risk-row-low td:first-child { border-left: 2pt solid #3f5f37; }
  .risk-row-user td:first-child { border-left: 2pt solid var(--stone); }
  .app-inventory {
    table-layout: fixed;
    font-size: 8pt;
  }
  .app-inventory th,
  .app-inventory td {
    vertical-align: top;
    line-height: 1.42;
  }
  .app-inventory th:nth-child(1), .app-inventory td:nth-child(1) { width: 24pt; }
  .app-inventory th:nth-child(2), .app-inventory td:nth-child(2) { width: 132pt; }
  .app-inventory th:nth-child(3), .app-inventory td:nth-child(3) { width: 82pt; }
  .app-inventory th:nth-child(4), .app-inventory td:nth-child(4) { width: 190pt; }
  .app-inventory th:nth-child(5), .app-inventory td:nth-child(5) { width: 66pt; }
  .app-inventory th:nth-child(6), .app-inventory td:nth-child(6) { width: 182pt; }
  .app-inventory th:nth-child(7), .app-inventory td:nth-child(7) { width: 178pt; }
  .num {
    color: var(--stone);
    font-variant-numeric: tabular-nums;
  }
  .mini {
    margin-top: 2pt;
    color: var(--stone);
    font-size: 7.2pt;
    line-height: 1.35;
  }
  code.pkg,
  code.path {
    font-size: 7.5pt;
    line-height: 1.35;
    background: transparent;
    padding: 0;
    word-break: break-all;
  }
  .legend-grid {
    display: grid;
    grid-template-columns: 1fr 1fr;
    gap: 8pt 14pt;
    margin: 12pt 0;
  }
  .legend-item {
    background: var(--ivory);
    border-radius: 4pt;
    padding: 8pt 10pt;
    break-inside: avoid;
  }
  .summary-table td:nth-child(2) {
    font-variant-numeric: tabular-nums;
  }
"""


def render(rows_: list[AppRow]) -> str:
    today = _dt.datetime.now().strftime("%Y.%m.%d")
    template = TEMPLATE.read_text()
    template = template.replace("{{文档标题}}", "Smartisan R2 应用清单与精简风险")
    template = template.replace("{{作者}}", "Smartisax")
    template = template.replace(
        "{{摘要}}",
        "卸载 APK Extractor 后的 Smartisan R2 全量应用清单，按用途和精简风险分级。",
    )
    template = template.replace("{{关键词}}", "Smartisan R2, 应用清单, 硬精简, APK, 风险分级")
    template = template.replace("<style>", "<style>")
    template = template.replace("</style>", REPORT_CSS + "\n</style>")

    body = f"""
<body class="app-report">

<section class="cover">
  <div>
    <div class="cover-eyebrow">Smartisax · Hard-ROM Inventory</div>
    <div class="cover-title">Smartisan R2<br>应用清单与精简风险</div>
    <div class="cover-sub">基于卸载 APK Extractor 后的 PackageManager 全量视图，逐项说明用途、来源分区与硬精简风险。</div>
  </div>
  <div class="cover-meta">
    <strong>Smartisax</strong><br>
    V1.0  ·  {today}<br>
    设备：Smartisan R2 · Smartisan OS 8.5.3 · 当前槽位 B
  </div>
</section>

<section class="toc">
  <h2>目录</h2>
  <div class="toc-item"><span class="toc-num">01</span><span class="toc-title">执行摘要</span><span class="toc-page">03</span></div>
  <div class="toc-item"><span class="toc-num">02</span><span class="toc-title">口径与风险颜色</span><span class="toc-page">04</span></div>
  <div class="toc-item"><span class="toc-num">03</span><span class="toc-title">完整应用清单</span><span class="toc-page">05</span></div>
  <div class="toc-item"><span class="toc-num">04</span><span class="toc-title">附录</span><span class="toc-page">末页</span></div>
</section>

<section class="chapter">
  <div class="chapter-num">01 · Executive Summary</div>
  <h1>执行摘要</h1>
  <p class="lead">
    APK Extractor 已卸载；当前设备 PackageManager 视图共有 <span class="hl">{len(rows_)}</span> 个已安装包，其中系统/系统更新包
    <span class="hl">{sum(1 for r in rows_ if r.install_scope == "system")}</span> 个，第三方用户应用
    <span class="hl">{sum(1 for r in rows_ if r.install_scope == "third-party")}</span> 个。风险颜色用于决定 hard-ROM 精简顺序，不等于立即刷写建议。
  </p>
  {summary_grid(rows_)}
  <h2>核心 Takeaways</h2>
  <ul>
    <li>APK Extractor 自身已经不在清单中；本报告以卸载后的实时状态为准。</li>
    <li>绿色项主要来自未启用 overlay、测试/彩蛋/打印/Dream 等低价值组件，适合下一轮小步验证。</li>
    <li>红色项覆盖启动、UI、权限、包管理、电话、网络、WebView、root 管理等核心链路，暂不进入精简候选。</li>
  </ul>
</section>

<section class="chapter">
  <div class="chapter-num">02 · Method</div>
  <h1>口径与风险颜色</h1>
  <p class="lead">这份清单复刻 APK Extractor 的核心口径：从 Android PackageManager 读取已安装应用，再结合路径和项目经验判断风险。</p>

  <h2>数据来源</h2>
  <table class="kami-table compact striped">
    <thead><tr><th>来源</th><th>用途</th><th>本次文件</th></tr></thead>
    <tbody>
      <tr><td>pm list packages -f -U --show-versioncode</td><td>全量包、APK 路径、versionCode、UID</td><td>data/app-inventory/pm-list-packages-f-U-version-after-apkextractor-uninstall.txt</td></tr>
      <tr><td>pm list packages -f -s / -3</td><td>区分系统包与第三方包</td><td>data/app-inventory/pm-list-packages-f-s/3-*.txt</td></tr>
      <tr><td>cmd overlay list</td><td>区分 overlay 当前启用、禁用或静态状态</td><td>data/app-inventory/cmd-overlay-list-after-apkextractor-uninstall.txt</td></tr>
      <tr><td>docs/v0.5-debloat-candidates.md</td><td>复用已经验证过的 v0.5 分层经验</td><td>项目级候选清单</td></tr>
    </tbody>
  </table>

  <h2>风险颜色</h2>
  <div class="legend-grid">
    <div class="legend-item"><span class="risk-badge risk-low">绿 · 低风险候选</span><p>当前看起来非核心，适合进入下一轮小批量 hard-ROM 验证。</p></div>
    <div class="legend-item"><span class="risk-badge risk-medium">蓝 · 中等风险</span><p>用户可见功能或厂商体验组件，删除前先确认是否使用。</p></div>
    <div class="legend-item"><span class="risk-badge risk-high">橙 · 先调查</span><p>可能跨权限、硬件、输入、定位、供应商服务或初始化流程。</p></div>
    <div class="legend-item"><span class="risk-badge risk-critical">红 · 暂不触碰</span><p>涉及启动、框架、UI、电话、网络、包管理、WebView 或 root 管理。</p></div>
    <div class="legend-item"><span class="risk-badge risk-user">灰 · 用户应用</span><p>位于 /data/app，优先普通卸载，不作为 hard-ROM 删除目标。</p></div>
  </div>

  <div class="callout">说明：用途列中「按包名/路径推断」表示当前未逐个反编译，只根据包名、APK 目录、已知 Android/Qualcomm/Smartisan 组件命名和本项目 v0.5 经验做保守判断。</div>
</section>

<section class="chapter">
  <div class="chapter-num">03 · Full Inventory</div>
  <h1>完整应用清单</h1>
  <p class="lead">共 {len(rows_)} 项。表格按风险从红到灰排序，便于先排除不该碰的核心项，再挑选绿色候选。</p>
  <table class="kami-table compact striped app-inventory">
    <thead>
      <tr>
        <th>#</th>
        <th>包名 / APK</th>
        <th>类别</th>
        <th>用途</th>
        <th>风险</th>
        <th>建议</th>
        <th>路径</th>
      </tr>
    </thead>
    <tbody>
      {table_rows(rows_)}
    </tbody>
  </table>
</section>

<section class="chapter">
  <div class="chapter-num">04 · Appendix</div>
  <h1>附录</h1>
  <h2>已执行的设备变更</h2>
  <p>已通过 <code>adb uninstall com.toralabs.apkextractor</code> 卸载 APK Extractor。卸载后未执行刷机、重启、清数据或分区修改。</p>
  <h2>如何复核</h2>
  <pre><code>adb -s bb12d264 shell 'pm list packages -f | wc -l'
adb -s bb12d264 shell 'pm list packages | grep -F com.toralabs.apkextractor || true'</code></pre>
  <h2>下一步用法</h2>
  <p>从绿色项里选择一小组 v0.5 候选，再按项目 hard-ROM 流程构建、刷入、验证。涉及 product overlay 的删除需要先让构建脚本支持 <code>product_b</code> exact-current 替换。</p>
</section>

</body>"""

    template = re.sub(r"<body>.*</body>", body, template, flags=re.S)
    return template


def main() -> None:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    font_dir = OUT_DIR.parent / "fonts"
    font_dir.mkdir(parents=True, exist_ok=True)
    for name in ("TsangerJinKai02-W04.ttf", "TsangerJinKai02-W05.ttf"):
        src = KAMI / "assets/fonts" / name
        dst = font_dir / name
        if src.exists() and not dst.exists():
            dst.write_bytes(src.read_bytes())

    data = rows()
    REPORT_JSON.write_text(
        json.dumps([asdict(row) for row in data], ensure_ascii=False, indent=2),
        encoding="utf-8",
    )
    REPORT_HTML.write_text(render(data), encoding="utf-8")
    print(REPORT_HTML)
    print(REPORT_JSON)
    print(f"rows={len(data)}")


if __name__ == "__main__":
    main()
