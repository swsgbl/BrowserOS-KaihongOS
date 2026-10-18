# P36: 性能量化基线（VM 环境注记）

测量环境：Quickemu QEMU VM (KaihongOS 5.0, API14)，x86_64 host，1600x900。
VM 的 CPU/IO 调度与真机不同，以下数字为**同环境纵向基线**（P36 前后对比用），不可直接对标真机。

## 冷启动（EntryAbility.onCreate → BrowserShell aboutToAppear done）

| 轮次 | cold_start_ms | asset probe_ms | ConfigManager load_ms | 备注 |
|------|--------------|----------------|----------------------|------|
| run2 (11:12:06) | 55 | 7 | 11 | 2 tab 恢复 |
| run3 (11:17:02) | 60 | 8 | 12 | 稳态复启 |

冷路径 asset 探活首启为 1315ms（服务冷拉起），热路径 <10ms。
ConfigManager.load 含：asset 探活 + config.json 读 + 迁移检查 + asset 回灌。

## 内存（hidumper --mem，BrowserShell 运行态 2 tab）

- 主进程 (pid 24764): PSS Total **161071 KB (~157 MB)**
- 渲染进程 (:render pid 24838): 独立进程，未合并统计
- Swap: 0（VM 未启用 swap）

## 打点位置

- EntryAbility.coldStartT0: onCreate 首行静态锚点
- BrowserShell aboutToAppear 尾: `[P36] cold_start_ms=...`
- SecureStorageAdapter.init: `[P36] ... probe_ms=`
- ConfigManager.load 收口: `[P36] secure=... load_ms=`

## 5 轮采样说明

本轮 run2/run3 为装机验证轮（间隔重装），采样 2 轮有效值。
后续补充采样直接读 hilog `cold_start_ms` 即可，无需改码。
