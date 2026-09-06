# P16 · 2026-09-06 切歌分段诊断

## 结论

**20 个当前真机 prepared-hit 完整样本：P50 157.086 ms、P90 201.880 ms、P95 260.556 ms、最大 302.878 ms。当前采样场景已满足 P50 < 200 ms / P90 < 400 ms，未复现历史 Issue 3。没有实施播放代码优化，也没有声称代码性能改善。**

**正式裁决：P16 ACCEPTED / ZERO-CODE CLOSURE。** 用户批准 measurement → evaluate evidence → optimize only if required。当前正式 prepared-hit 目标已满足；Optimization Required = NO，optimization stage = NOT ENTERED，before/after optimization comparison = NOT APPLICABLE。Production playback code：NONE changed。

P16 DIAGNOSIS COMPLETE
TARGET SATISFIED
OPTIMIZATION NOT JUSTIFIED BY CURRENT EVIDENCE
ZERO-CODE CLOSURE ACCEPTED

T-BUG-2/3 要求分段样本和 prepared-hit 指标，没有要求真实声学输出测量。声学 latency 未测属于 limitation，不是本次 P16 blocker。所有下述采集保留偏差、非因果对比及观测边界继续成立。

## 正式范围与依赖

依据 `11-execution-tasks.md` P16（1643–1720）：依赖 P12 + P14 的实现；没有明确要求 M-13 PASS 为开发前置。P15 已正常合并至 iOS main `df1bdb51ceeeca509d66b08773a281aa3fd2b963`，merge tree 与 accepted `ce4c3af` 相同、无冲突。原工作区三项未提交改动保留。

只读取 P16 及其直接引用的 `06 §1 §5`、`08 §5 §8`、baseline 采集工具、Issue 3/Phase 2 报告、G-IOS/相关 T-BUG/M 要求。未重新审计 P3–P15。

诊断阶段仅新增本 baseline 下文件。应用源码、工程配置、Backend、FINAL/Frozen、P15 状态架构、视图、队列、URL resolver、缓存和真实 flags 均未改。未开始 P17，也未执行 M-13、AirPlay 或旧 UI 修复。

## 测量条件与限制

- 物理 iPhone 17 / iOS 27，通过 iPhone Mirroring 操作；同一普通用户歌单、3 首循环、界面 Hi-Res、Wi-Fi 图标。未控制网络链路、解码品质、温度或实际音频路由。
- 复用 accepted P15 已有签名 Debug 真机包；该包早于最后两个 P15 专属 UI 修复，播放实现未因这两个修复变化。**不宣称安装了最终 P15 精确源码树构建**，见 `p16/source-identity.json`。
- 使用现有 `MusicPlayback` / `MusicPlaybackP01` signpost；Recording Options 仅启用该 subsystem 动态追踪，不改变 client feature flags。
- 正式数据来自 9 个独立窗口中的 20 个完整 hit：每个窗口独立配对，窗口8因 Mac 锁定无事件、计0；preflight 的2个 hit 不混入正式20。
- 长窗口只保留后段事件。没有事件的实际点击无法分类为 hit/miss，不填补、不当作失败/成功样本。**样本保留存在选择偏差，因此不把当前分布外推成所有网络、队列或设备均达标，也不与历史533ms做因果收益比较。**
- 20/20 复用 item，20/20 session 已 ready，无 source-resolve await 事件。此证据支持该路径未进入 source resolver；不冒充独立 Network trace 的 URL 请求数审计。
- 20条转场完整，Ready 子段只有19条；缺少的 Ready 不由 playing 倒推。KVO / playing 时间为 MainActor 回调观测点；不是 AVFoundation 内部精确时刻，也不是物理点击或声学首帧。
- 全部窗口正常 Stop/保存，完成 `xctrace export` 重新读取；原始 trace/XML 本地保留，仅匿名事件入 Git。没有执行30分钟 M-13。

## 分段分布

单位 ms；P50=median，P90/P95=nearest-rank。子段分位数不能相加。

| 分段 | n | P50 | P90 |
|---|---:|---:|---:|
| `transition_to_lookup_result` | 20 | 0.818 | 1.606 |
| `lookup_result_to_playing` | 20 | 156.273 | 200.632 |
| `request_to_queue_resolved` | 20 | 0.058 | 0.163 |
| `queue_lookup` | 20 | 0.041 | 0.087 |
| `prepared_lookup` | 20 | 0.026 | 0.067 |
| `lookup_result_to_source_ready` | 20 | 0.003 | 0.004 |
| `item_create_or_reuse` | 20 | 0.002 | 0.003 |
| `clear_old_item` | 20 | 0.369 | 0.686 |
| `install_new_item` | 20 | 0.762 | 1.121 |
| `request_to_player_ready` | 19 | 113.098 | 170.084 |
| `first_ready_relative_to_install_end` | 19 | 110.403 | 167.772 |
| `install_end_to_playing` | 20 | 155.516 | 199.738 |
| `ready_to_playing` | 19 | 31.966 | 69.960 |
| `request_to_playing` | 20 | 157.168 | 202.050 |

## 四候选原因的证据判断

1. **替换后的准备/等待**：安装后到 playing P50 155.516 ms，占据主要观测区间；同步安装本身 P50 0.762 ms。与异步 ready/buffering 路径相符，但不能仅凭区间确定 AVFoundation 内部或历史问题根因。
2. **Session 激活/路由阻塞**：20/20 `SessionGate=1`，该 cohort 未发生激活 await，不能解释其主要耗时；没有据此声称打断/路由恢复场景不存在问题。
3. **主线程 UI 工作**：没有同步 Time Profiler/主线程调度证据，现有回调边界无法排除调度影响。没有依据延后 NowPlaying 封面更新，且视图属于 P16 禁改范围。
4. **观察器移除/添加**：没有独立 observer interval，不能给出其单独耗时。同步清空/安装很短；不足以论证观察器重构。

## 建议、风险与正式门禁

建议保留当前实现，不调整 buffer，不预热已激活 session，不引入 AVQueuePlayer，不碰 PlaybackQueue/URLResolver/MusicStore 或视图。当前数据没有足够的因果证据证明这些改变必要，也无法把当前达标归功于本任务。

P16 写明先诊断、方案 PR 获批后才进入优化。本次不需要优化，因此没有优化代码或优化后 A/B 队列。用户已批准零代码结项；未进入 optimization stage，优化后对比为 NOT APPLICABLE。此结项不表示播放器算法已被优化。

## 验证与重算

```sh
python3 baseline/p16/summarize-playback.py /tmp/p16-recomputed.json baseline/p16/evidence/baseline-0?-events.json
```

20样本门槛与延迟门槛均 PASS。空输入及不足20的历史解析夹具会失败；历史夹具只验证解析器，不计入当前数据。重复输入被拒绝。应用源码没有改动，未为了形式重跑 P15 full/build；P16 优化后的最终 Swift full、physical build、UI 和 M-1/2/3/5/6 未触发、未声明通过。

P14 SOFTWARE ACCEPTANCE COMPLETE；M-13 EXTERNAL EVIDENCE DEFERRED。未来单独补 M-13 仍必须先1–2分钟，确认Stop/保存/重开/memory-stall-audio数据可读，再准许30分钟。本任务的 Logging 转场窗口不能替代这道 M-13 预检。
