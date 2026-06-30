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
当前实机刷入状态: v0.portal6g-rvfc-media-tail，已在精确确认后刷入 B 槽，正常启动并通过只读验证。它把 Smartisax 升到 v0.6.33/versionCode 50，在 live/read-only v0.portal6f presentation-tail cadence 基础上专打 Chrome/in-app browser 1080/60 RVFC/media callback tail clustering：显式保留 `inputRefreshHz=90`，1080p60 sender de-phase 到 59fps，60Hz sender 窗口收窄到 7Mbps，并把 continuity/marker tail forceFrame spacing 固定到 full media-frame interval。刷后验证：`sys.boot_completed=1`、slot `_b`、bootanim `stopped`、verified boot `orange`、root 可用、SELinux Enforcing、`isKeyguardShowing=false`、Smartisax Shell focused、device APK hash `442276dfaf1e70ecf0209818ed61b207bae72194fc490f8c601471b6a43f9f6a`、`WAKE_LOCK: granted=true`。6g system_b hash `941c660259f32270eaf4e3a8a5778b8518d4035e0f5efb73a8b704fd7d4b4241`，sparse hash `d3a938546f197e54ea1f7c08bf300b8d61bf91b9c389bca92a9ddfa018a038fb`，offline result `PASS_OFFLINE_IMAGE_V0PORTAL6G_RVFC_MEDIA_TAIL`，live result `PASS_READ_ONLY_V0PORTAL6G_RVFC_MEDIA_TAIL`，flash result `PASS_FLASH_V0PORTAL6G_RVFC_MEDIA_TAIL`，flash evidence `hard-rom/inspect/v0.portal6g-rvfc-media-tail/flash-v0.portal6g-rvfc-media-tail-20260629-203737.txt`。
Portal smoke: pairing code `666132` 已跑完 6e strict 1080/60 + 1080/90 diagnostic FAIL，但证明 1080/60 packetLossDelta 从 6b 的 560 降到 0。6f pairing code `176725` Safari fallback strict smoke 已 PASS，两档 H264 1080x2340 可视/反控/T2P gate 都通过；6f Chrome-side/in-app browser pairing code `998599` 则证明剩余瓶颈已收敛到 1080/60 RVFC/media callback tail：1080/60 H264 1080x2340 59.76fps、packetLossDelta 0、RVFC 51.2fps、T2P p95 124.42ms，但 RVFC >34ms gaps 123 超过 <=60 门限；1080/90 PASS，59.93fps、packetLossDelta 0、RVFC 53.79fps、T2P p95 129.26ms、RVFC gaps 63。当前 6g 已刷入并只读验证；pairing codes `829543` 和 `808364` 的 6g localhost receiver strict smoke 尝试都已消费 code，但只形成 `CONTROL_FAIL` 证据，不是 6g 性能失败。随后复用已配对的 `http://192.168.31.103:37601/` 内置浏览器 Portal tab 做 direct diagnostic：两档均 H264 1080x2340、packetLossDelta 0、反控 ack 完整，1080/60 decoded 55.66fps/RVFC gaps 61，1080/90 decoded 57.36fps/RVFC gaps 83；像素 T2P 因自动化节流暂未测。Safari fresh-code `223229` strict smoke 证明 6g 的 1080/60 已达门：H264 1080x2340、57.94fps、packetLossDelta 0、RVFC 56.18fps、RVFC gaps 6、T2P p95 149.2ms、move-stream PASS；1080/90 的 packetLoss/T2P/input 也通过，但页面在约 33s 后进入 hidden/blur，导致 RVFC 38.93fps、gaps 163，归类为 Safari visibility contaminated diagnostic FAIL。下一步优先把 direct-in-Portal 路径固化成 strict harness，并给 Safari/in-app-browser receiver 加 foreground/visibility guard 后重跑 1080/90；目标仍是把 1080/60 `frameGapsOver34ms` 稳定保持 <=60，同时保住 packetLossDelta 0、DataChannel ack 和 T2P p95。H264 仍是交互式默认，AV1 保留实验入口，H265/VP9 暂不默认优先。当前保留 v0.4 回滚 sparse、previous live 5z/6a/6b/6c/6d/6e/6f sparse、current live 6g sparse。
上一条 Portal 基线: v0.portal5h-webrtc-bitrate-quality 仍是上一条完整通过 Portal smoke 的低负载线。它证明了 WebRTC-only UI、默认自动启动、H.264 ICE/DTLS/SRTP 播放、DataChannel ping/tap/swipe，以及显式 bitrate 参数生效；logcat 显示编码器使用了 600kbps minBitrateBps。
本地回滚: v0.4 hard debloat sparse image
当前 WebView 基线: v0.35.2 M150 system provider cleanup
已接受的 TextBoom/OCR 基线: v0.43e LocalPpOcrApi runtime adapter，删除 legacy CsOcr/Intsig 代码，保留 manifest ocr_key，使用 TextBoomArm32 codePath，修复 arm64 runtime，并已实机验证 BOOM_TEXT 和 BOOM_IMAGE。
下一步 TextBoom/OCR: 从 v0.43e 继续做 CamScanner 资源字符串清理，以及更广的 PP-OCR 质量/内存回归；真正强制 arm32 仍是单独的 PackageManager policy 调查。
下一步 PackageManager/Keyguard: v0.portal4b 保留来自 v0.portal2.3 的窄范围 PackageManager 签名权限授予，不做宽泛绕过；PackageInstallerSmartisan 暂停，TextBoom ABI policy 仍是 pm2，updated-system shadow repair 仍是 pm3。
USB 清理状态: v0.usb2 已实机证明；/vendor/etc/cdrom_install.iso 不存在，macOS 不再显示 Smartisan transfer-tool 卷。
HandShaker 替代状态: v0.mirror0 证明当前 ADB 传输上的 USB 和无线 scrcpy 镜像/控制；v0.portal1 到 v0.portal4c 逐步证明 direct-LAN Portal pairing、session hardening、screen PNG、tap/swipe input、H.264/MP4 playback、RTP diagnostics、media capabilities；v0.portal5a 到达真实浏览器 SDP offer 但 native library 加载失败；v0.portal5b 修复 native libwebrtc 加载并证明 ICE/DTLS/SRTP connected；v0.portal5c 证明 Canvas 不是有效的 HARDWARE bitmap 转换路线；v0.portal5d 证明 Bitmap.copy 可以喂给持续 native WebRTC screen video，包括浏览器偏好的 H.264；v0.portal5e 证明默认 H.264 negotiation 和显式 WebRTC session status/cleanup；v0.portal5f 移除 HTTP input，改用 smartisax-input WebRTC DataChannel 控制；v0.portal5g 实机证明真实 overlay 手势和第一次 quality/fps 提升；v0.portal5h 实机证明 WebRTC-only UI、默认自动启动、DataChannel 控制和显式 bitrate 参数；v0.portal5i 实机证明 Stable、Sharp、1080/30 profiles 的 token-gated WebRTC runtime tuning；v0.portal5j 证明 MediaProjection 需要 services.jar 签名权限 policy；v0.portal5j.1 证明该 policy 修复有效但暴露 token 创建处的 hidden-API 反射阻塞；v0.portal5j.2 证明 raw Binder token 修复，`createProjection=ok`，并证明 projection-texture 能在 1080x2340 H.264 下连接/控制但初始 burst 后停滞；v0.portal5k 证明 forceFrame continuity counter 能持续跑，但 browser decode 仍停在 26 frames；v0.portal5k.1 已实机证明 fresh timestamp/retain 修复，让 1080/30 稳定到 29.7fps 并让 1080/60 达到 60.15fps；v0.portal5l 已实机证明 touch-to-photon marker 和 move-stream 反控；v0.portal5m 已实机证明 latency/follow-rate smoke，1080/30 为 29.81fps，1080/60 为 59.94fps，T2P p95 降到 158.1ms；v0.portal5n 已实机证明 latest-frame-only queue collapse 和 dual move-channel，其中 1080/60 gaps 改善但 T2P 回归到约 209ms；v0.portal5o 已实机刷入并只读验证 input-frame-boost，单独 1080/60 T2P p95 降到 138.51ms，但 1080/30 仍未达标；v0.portal5p 已实机刷入并只读验证双相 input boost；v0.portal5r 已离线/preflight 准备好 60/90Hz + boost-token-retain 对照候选；v0.portal5s 已实机刷入并只读验证 60/90Hz + event-time move-stream + input-priority frame，但 strict smoke 因 Chrome presentation/RVFC 和 T2P 尾延迟未接受；v0.portal5t 已离线/preflight 准备好 marker-visible burst presentation 对照候选；v0.portal5u 已实机刷入并只读验证 durable burst-reschedule presentation，strict smoke 证明 1080/90 T2P p95 已到 134.61ms 但 Chrome RVFC/presentation gap 仍未接受；v0.portal5v 已离线/preflight 准备好 receiver presentation cadence 对照候选；v0.portal5w 已实机刷入并只读验证 quiet presentation，strict smoke 进一步锁定 video presentation/RVFC 为瓶颈；v0.portal5x 已实机刷入并只读验证 presenter-mode，strict smoke 证明 canvas 可见反馈路径能把 T2P 收回到约 140-173ms，但 RVFC/media cadence 和 90Hz packet loss 仍未接受；v0.portal5y 已实机刷入并只读验证 presentation-transport pacing，证明 90Hz input + 60fps video transport 可以消掉 packet loss，但 Chrome presentation/RVFC freeze 和 T2P 尾延迟仍未接受；v0.portal5z 已实机刷入并只读验证 video-primary ROI probe，strict/anti-throttle smoke 证明 packet loss 和 RAF 已基本干净，剩余瓶颈是 video RVFC cadence 与 marker 入流尾延迟；v0.portal6a 已实机刷入并只读验证 marker draw-sync capture boost；v0.portal6b 已实机刷入并只读验证 draw-urgent marker boost，strict smoke 证明 urgent counters 生效但 T2P/RVFC/1080/60 packet loss 仍未接受；v0.portal6c 已实机刷入并只读验证真实 Portal screenBox 可见容器修复，真实 Chrome smoke 进一步把黑屏根因定位为设备显示睡眠；v0.portal6d 已实机刷入并只读验证 display wake guard，且真实 Portal Chrome 可视 smoke 已证明 H264 1080x2340 非黑视频和双 DataChannel open；v0.portal6e 已实机刷入并只读验证 1080/60 packet-loss/encoder-transport burst 候选，strict smoke 证明 1080/60 packet loss 已清零但 RVFC/T2P strict gate 仍未接受；v0.portal6f 已实机刷入并只读验证 RVFC/presentation cadence + marker-visible T2P tail 候选，Safari fallback strict smoke 已通过两档 H264 1080x2340 可视/反控/T2P gate，内置浏览器 Chrome-side cadence smoke 已证明 1080/90 PASS 且 1080/60 只剩 RVFC >34ms gaps 超门限；v0.portal6g 已实机刷入并只读验证 1080/60 RVFC/media callback tail repair 候选，下一步跑 1080/60 + 1080/90 strict smoke；tools/r2-mirror.sh 是第一个 Mac 侧 mirror/portal helper。
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
