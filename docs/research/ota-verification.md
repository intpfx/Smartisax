# Smartisax - OTA 劫持验证报告

## 验证成果 ✅

| 步骤 | 结果 | 说明 |
|------|------|------|
| 1. 自定义 URL 注入 | ✅ | 通过 `adb shell am start --es url` 传入 HTTP 地址 |
| 2. 假服务器返回 JSON | ✅ | 手机正常解析 `url`、`md5sum`、`size`、`changes` 等字段 |
| 3. UI 显示更新 | ✅ | 系统更新界面完整展示了 Smartisax 的版本信息 |
| 4. 下载 OTA 包 | ✅ | 从我们的服务器下载了 `213 bytes` 的 zip 文件 |
| 5. MD5 校验 | ✅ | `Calculated` = `Provided`，校验通过 |
| 6. 后续安装 | ❌ (预期内) | 文件被清除，返回初始状态 |

## 关键发现

1. **A/B 分区设备** (`ro.build.ab_update=true`) — 更新流程走 `update_engine`
2. **`update_engine` 签名校验** — 我们的 zip 没有 `payload.bin`，`update_engine` 拒绝安装，系统清理文件后回到初始界面
3. **没有直接漏洞** — MD5 校验是标准的，文件处理也没有发现明显的路径穿越或注入点
