# 坚果 R2 (Nut R2, DE106, darwin) 官方已签名 OTA 全量包 搜索结果

## 搜索结果总结

### 1. ONFIX.cn — 官方卡刷包 (需付费购买)

此网站提供坚果 R2 的官方卡刷包（update.zip格式，Smartisan官方签名），但下载链接需要购买后才能查看。

#### 8.5.3 版本 (最新)
- **页面**: https://onfix.cn/rom/563075
- **版本**: Smartisan OS 8.5.3-202207181710-user-drw (Android 11)
- **文件名**: 8.5.3-202207181710-user-drw-afb56dfbfc.zip
- **大小**: 2.75 GB
- **类型**: 卡刷包 (官方固件)
- **品牌**: 锤子 (smartisan)
- **型号**: 坚果R2
- **状态**: 需购买后查看下载地址

#### 8.1.4.1 版本 (早期)
- **页面**: https://onfix.cn/rom/563076
- **版本**: Smartisan OS 8.1.4.1-202108241114-user-drw (Android 10/11?)
- **文件名**: 8.1.4.1-202108241114-user-drw-d7ca294bcb.zip
- **大小**: 2.76 GB
- **类型**: 卡刷包 (官方固件)
- **品牌**: 锤子 (smartisan)
- **型号**: 坚果R2
- **状态**: 需购买后查看下载地址

### 2. 官方 OTA 服务器

- **ota2.smartisan.com** — 服务器仍然在线
  - 根路径 https://ota2.smartisan.com/ : 403 Forbidden
  - check.php 端点存在，返回 `{"result":null,"errMsg":"empty param"}`，说明需要特定参数（如 device=darwin 等）但未知完整的调用方式
  - 其他路径均返回 404

### 3. 新闻报道确认了 OTA 推送

| 版本 | 日期 | 大小 | 来源 |
|------|------|------|------|
| Smartisan OS 8.5.0 Beta 2 | 2021-09-08 | 92MB (增量) | IT之家 |
| Smartisan OS 8.5.0 Beta 3 | 2021-09-21 | - | IT之家 |
| Smartisan OS 8.5.0 Beta 4 | 2021-09-28 | 96MB (增量) | IT之家 |
| Smartisan OS 8.5.0 正式版 | 2021-11-08 | 1,345 MB (全量) | IT之家/泡泡网 |
| Smartisan OS 8.5.3 | 2022-08-02 | 2.75 GB (全量卡刷) | ONFIX |

### 4. 其他资源

- **CSDN**: 锤子坚果R2 基带分区备份 (105.19MB) — 不是 OTA 包
- **百度网盘**: 搜索结果有 AI 生成的"锤子手机系统rom包各版本合集"链接，但无法验证真实性
- **刷机之家/奇兔ROM**: 有坚果 Pro 系列 ROM，但未发现 R2

### 5. OTA 服务器 API 探测结果

```
https://ota2.smartisan.com/           → 403 Forbidden
https://ota2.smartisan.com/check.php  → 200 OK (需参数)
https://ota2.smartisan.com/check      → 404
https://ota2.smartisan.com/update/    → 404
https://ota2.smartisan.com/update/darwin/stable/ → 404
```

### 结论

官方已签名的 OTA 全量包存在于 **ONFIX.cn** 平台，需要购买会员/积分才能获取下载链接。目前未能找到免费的公开直链。

#### 建议的下一步行动
1. 在 ONFIX.cn 注册并购买积分以获取下载链接 (https://onfix.cn/rom/563075)
2. 尝试在百度网盘搜索 "坚果R2 8.5.3" 可能找到用户分享
3. 在酷安 (coolapk.com) 搜索用户备份的坚果R2 OTA 包
4. 尝试在 GitHub 搜索 "darwin" + "Smartisan" 相关仓库
