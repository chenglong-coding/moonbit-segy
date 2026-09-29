# MoonSEGY：保留原始道位置的 SEG-Y 交换与质量检查

本地模块 `chenglong-coding/segy@0.2.0`，MIT；拟替换因应用范围过窄而停用的 IRC 选题。公开仓库：https://github.com/chenglong-coding/moonbit-segy。

## 任务与 MoonBit 交付

地震记录交换涉及不同样本码、字节序、头字段和采集缺失。需要定位问题道时，先导出再重编号容易丢失原文件位置；将非有限值静默过滤则使统计具有误导性。本库把扫描、样本解释、道集/子集QC和有损变换限制放在MoonBit核心，报告原始字节位置、不可分析整道、完整计数和有界详情，供MoonBit导入或预览流程复用。

## 同类工具与独立价值

segyio 等已有成熟 C/Python 实现；项目不声称文件格式、统计算法或生态空白的原创性。MoonBit 内可组合的扫描/QC 状态、原始道定位与有限报告是独立交付范围；同义词检索未找到同域包不等于穷尽生态。旧 IRC 的价值异议不能靠改名解决，故此为不同任务的换题候选，真实采用者仍未知。

同域 MoonBit 现有 [MoonSeis](https://github.com/hzc-666-ai/MoonSeis) 的 miniSEED3 波形/QC 和 [moonbit-seismic](https://github.com/wch6766/moonbit-seismic) 的 SAC/miniSEED 信号处理。统计与检查概念存在交集；本项目独立范围是 SEG-Y 道模型、原始位置及交换约束，不把整个地震处理生态称为空白。

## 公开测线验证

0.2.0 已消费 USGS DS259 一条完整测线：19158 道、14368500 样本，struct/NumPy 独立全局和三组统计一致，segyio 逐道读完；发现 2667 条零振幅道，问题明细上限 100 并显式标注截断。先前 300 道节选另有 225000 个 int32 逐值检查。非标准版本字仅经显式 `legacy_revision_one` 选择解释，严格默认不放宽。来源、公共领域署名、输入散列见 [FULL-USGS](docs/FULL-USGS.md)。

不推断故障原因、物理标定振幅、CRS或地质结论；不宣称全部调查或任意厂商rev2.1布局可用。没有生产性能或客户采用证明。交付包含离线公开节选、可运行任务、公共API、独立参考和当前源码日志，公开仓库与注册表已有版本，报名表一致性和换题结果仍待核实。

**公开状态（2026-09-29 核对）**：GitHub [公开仓库](https://github.com/chenglong-coding/moonbit-segy)、[Mooncakes 0.2.0](https://mooncakes.io/docs/chenglong-coding/segy@0.2.0) 已可访问；[CI 成功记录](https://github.com/chenglong-coding/moonbit-segy/actions/runs/36561890331) 对应 `b4dbe7a4322a`。本次材料更新尚未推送；该远端 CI 对应所列公开提交。报名表一致性及赛事审核结果尚未核实。
