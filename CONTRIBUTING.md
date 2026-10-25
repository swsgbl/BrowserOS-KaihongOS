# 贡献指南（Contributing Guide）

感谢关注 BrowserOS - KaihongOS！本指南说明如何参与贡献。

## 行为准则

参与本项目即表示你接受 [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md)。请保持尊重与建设性。

## 快速上手

```bash
git clone https://github.com/swsgbl/BrowserOS-KaihongOS.git
cd BrowserOS-KaihongOS

# 离线静态检查（提交前必须全绿）
python tools/static_checks.py

# 有设备时：设备在环回归（9 步）
python tools/smoke_reg.py --skip-install
```

## 开发约定

### 分支与提交

- 分支命名：`feat/<topic>`、`fix/<topic>`、`docs/<topic>`
- 提交信息：`<type>(<scope>): <subject>`，type 取 feat / fix / refactor / docs / test / chore

### 代码规范（ArkTS）

- 禁 `any` / `unknown`、禁解构、接口字段显式类型
- 图标必须用 `$rawfile('ic_*.svg')` 加载（禁止 `$r('app.media.ic_*')`——静态检查第 16 项会拦截）
- 日志统一 `console.info/warn/error`（禁 `console.log`）
- 图标-only 控件必须带 `accessibilityText`

### 设备/环境

- 目标平台：KaihongOS 5.0（API 14）与 6.x（API 23）双环境，改动需同时考虑
- **API 23 重打包铁律**：`tools/build_api23_hap.py` 产物必须 `ZIP_STORED` 且保持条目顺序（DEFLATE 会导致全部资源读取失败，见 DEVPLAN P40）
- 新增页面需注册 `main_pages.json`；涉及签名/装机的改动请同步更新 `docs/ARCHITECTURE.md`

### 提交前自查

1. `python tools/static_checks.py` 全绿
2. 有设备时 `python tools/smoke_reg.py` 全绿（或如实标注环境限制）
3. 新功能附设备证据（截图 / dump / hilog）到 `evidence/`，并在 `DEVPLAN.md` 追加小节

## PR 流程

1. Fork → 分支 → 提交（模板见 [.github/PULL_REQUEST_TEMPLATE.md](.github/PULL_REQUEST_TEMPLATE.md)）
2. CI（static checks）通过
3. 维护者评审，重点：功能证据、双环境兼容、合规件（若涉及第三方素材须在 [NOTICE](NOTICE) 登记）

## Issue

请使用仓库 Issue 模板（Bug Report / Feature Request），Bug 附设备型号、系统版本（API 级别）、复现步骤与日志。

## 许可

提交即表示你同意以 AGPL-3.0-or-later（与本项目一致）授权你的贡献。
