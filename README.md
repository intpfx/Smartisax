# Smartisax

Smartisax 是一个面向 Smartisan R2 的实机改造工作区。目标设备运行
Smartisan OS 8.5.3 / Android 11。当前主路线是 hard-ROM 修改：编辑分区镜像、
重建 `super`、刷入当前使用的 B 槽、开机验证，并始终保留一份可回滚的已验证镜像。

## 当前路线

```text
设备: Smartisan R2, Snapdragon 865/kona
序列号: bb12d264
当前活动槽位: B
root: 成功 hard-ROM 构建中使用 APatch/kp
当前实机刷入状态: v0.portal5j.2-projection-binder-transact，已在精确确认后刷入 B 槽，正常启动，通过只读验证，Portal `/api/webrtc/capture/probe` 已验证，并完成 1080/30 与 1080/60 `projection-texture` WebRTC smoke。它从 /system/priv-app 提供 Smartisax v0.6.9/versionCode 26，保留只针对 `com.smartisax.browser` 的窄范围 `SmartisaxPackagePolicy` 签名权限授予：`READ_FRAME_BUFFER`、`CAPTURE_VIDEO_OUTPUT`、`MANAGE_MEDIA_PROJECTION`，并把隐藏 `IMediaProjectionManager$Stub.asInterface(IBinder)` 反射改成 raw Binder transact 调用来执行 `hasProjectionPermission` 与 `createProjection`；实机 probe 返回 `hasProjectionPermission=true`、`binderCreateProjection=available`、`tokenRoute=raw-binder-transact-media-projection`、`createProjection=ok`。`projection-texture` 当前可以连接和控制，但还不能持续达到 1080p30/60 目标：浏览器解码帧会在初始 burst 后停滞。
下一步 Portal: 优化 MediaProjection/VirtualDisplay/SurfaceTextureHelper 的 frame pump，使 `projection-texture` 先稳定达到 1080p30，再把 1080p60 作为默认目标；`projection-auto` fallback/regression 放在该修复之后。
上一条 Portal 基线: v0.portal5h-webrtc-bitrate-quality 仍是上一条完整通过 Portal smoke 的低负载线。它证明了 WebRTC-only UI、默认自动启动、H.264 ICE/DTLS/SRTP 播放、DataChannel ping/tap/swipe，以及显式 bitrate 参数生效；logcat 显示编码器使用了 600kbps minBitrateBps。
本地回滚: v0.4 hard debloat sparse image
当前 WebView 基线: v0.35.2 M150 system provider cleanup
已接受的 TextBoom/OCR 基线: v0.43e LocalPpOcrApi runtime adapter，删除 legacy CsOcr/Intsig 代码，保留 manifest ocr_key，使用 TextBoomArm32 codePath，修复 arm64 runtime，并已实机验证 BOOM_TEXT 和 BOOM_IMAGE。
下一步 TextBoom/OCR: 从 v0.43e 继续做 CamScanner 资源字符串清理，以及更广的 PP-OCR 质量/内存回归；真正强制 arm32 仍是单独的 PackageManager policy 调查。
下一步 PackageManager/Keyguard: v0.portal4b 保留来自 v0.portal2.3 的窄范围 PackageManager 签名权限授予，不做宽泛绕过；PackageInstallerSmartisan 暂停，TextBoom ABI policy 仍是 pm2，updated-system shadow repair 仍是 pm3。
USB 清理状态: v0.usb2 已实机证明；/vendor/etc/cdrom_install.iso 不存在，macOS 不再显示 Smartisan transfer-tool 卷。
HandShaker 替代状态: v0.mirror0 证明当前 ADB 传输上的 USB 和无线 scrcpy 镜像/控制；v0.portal1 到 v0.portal4c 逐步证明 direct-LAN Portal pairing、session hardening、screen PNG、tap/swipe input、H.264/MP4 playback、RTP diagnostics、media capabilities；v0.portal5a 到达真实浏览器 SDP offer 但 native library 加载失败；v0.portal5b 修复 native libwebrtc 加载并证明 ICE/DTLS/SRTP connected；v0.portal5c 证明 Canvas 不是有效的 HARDWARE bitmap 转换路线；v0.portal5d 证明 Bitmap.copy 可以喂给持续 native WebRTC screen video，包括浏览器偏好的 H.264；v0.portal5e 证明默认 H.264 negotiation 和显式 WebRTC session status/cleanup；v0.portal5f 移除 HTTP input，改用 smartisax-input WebRTC DataChannel 控制；v0.portal5g 实机证明真实 overlay 手势和第一次 quality/fps 提升；v0.portal5h 实机证明 WebRTC-only UI、默认自动启动、DataChannel 控制和显式 bitrate 参数；v0.portal5i 实机证明 Stable、Sharp、1080/30 profiles 的 token-gated WebRTC runtime tuning；v0.portal5j 证明 MediaProjection 需要 services.jar 签名权限 policy；v0.portal5j.1 证明该 policy 修复有效但暴露 token 创建处的 hidden-API 反射阻塞；v0.portal5j.2 证明 raw Binder token 修复，`createProjection=ok`，并证明 projection-texture 能在 1080x2340 H.264 下连接/控制，但 texture frame pump 远低于 1080p30/60；tools/r2-mirror.sh 是第一个 Mac 侧 mirror/portal helper。
```

完整状态账本见 `docs/index/current-state.md`。引用归档镜像前先看
`docs/rom-archive.md`。

## 从这里开始

- `AGENTS.md` - 面向 agent 的短操作规则和安全门禁。
- `.agents/skills/smartisan-r2-hardrom/SKILL.md` - 项目技能入口和任务路由。
- `.agents/skills/smartisan-r2-hardrom/references/` - 按主题拆分的长参考材料。
- `docs/README.md` - 文档索引。
- `docs/index/current-state.md` - 当前 ROM 与功能状态账本。
- `docs/index/hard-rom-log-toc.md` - 长证据日志的标题索引。
- `docs/index/knowledge-base.md` - 静态 ROM 源知识库地图。
- `docs/index/agent-memory-skill-map.md` - Codex memory、项目技能、文档和证据之间的边界。

## 工作区地图

- `docs/` - 文档索引、证据日志、研究笔记、归档地图和拆分索引。
- `tools/` - 构建、验证、审计、实机 preflight、OCR benchmark 和清理 helper。
- `apps/` - 小型 APK 项目，例如 Smartisax 和 OCR benchmark harness。
- `hard-rom/` - 生成镜像、manifest 和检查证据。本目录下的大型产物应保持本地/忽略。
- `reverse/smartisan-8.5.3-rom-static/` - 从 OTA 提取分区生成的静态 ROM 源知识库。
- `.agents/skills/smartisan-r2-hardrom/` - 项目级 agent 工作流知识。

更完整的目录地图见 `docs/index/workspace-layout.md`。当前任务指针见
`docs/index/next-work.md`。

## Agent 指南

Agent 应先阅读 `AGENTS.md`，再加载
`.agents/skills/smartisan-r2-hardrom/SKILL.md`。用 `docs/README.md` 查找支持性
笔记。规范证据链仍然是 `docs/hard-rom-ota-trust.md`；当可以直接检查实机或
生成镜像时，不要只依赖记忆。

## 许可证

Smartisax 的源代码、脚本和文档使用 Apache License 2.0。详见 `LICENSE`
和 `NOTICE`。

公开源码分发不应包含生成的 ROM 镜像、提取的 OTA payload、私钥、设备备份、
检查 dump，或包含私人状态的实机日志。
