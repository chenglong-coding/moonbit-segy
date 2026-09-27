# 完整 USGS 06c01 测线的本地验证

2026-09-27 后续验证已取得完整 `06c01.seg`，大小 62,075,520 字节，SHA-256 `50f298aa8d154895c6236d1f851228fe3cc6b590ad163c50835685243da61547`。它是 USGS Data Series 259 八条测线中的一条；先前300道节选、403及中断缓存的记录保留在 [PUBLIC-USGS](PUBLIC-USGS.md)，不将旧失败改写成成功。

来源：[USGS 原始文件](https://pubs.usgs.gov/ds/259/segy/06c01.seg)、[官方目录](https://pubs.usgs.gov/ds/259/segy/)、[调查元数据和使用条件](https://cmgds.marine.usgs.gov/catalog/whcmsc/segy/06015_segy.html)。元数据说明为美国政府公共领域数据，使用时保留 U.S. Geological Survey / Data Series 259 署名和来源。完整文件仅供本地下载验证，不随这个代码包分发。

## 复现

按 README 构建 JS release bridge 并安装 `tools/requirements.txt`。自行从上述原始链接取得文件，保持原字节，再执行：

```sh
python tools/verify-full-usgs.py /path/to/06c01.seg --output work/full-usgs-reference.json
```

脚本先检查固定散列与完整文件长度，再实际调用现有 QC 命令并比较独立参考；不执行网络下载。输出参考回执及同目录 `.qc.json`。QC 命令正常完成并发现问题时退出3，脚本确认这些发现符合预期后退出0。

## 实测范围

- 完整19,158道，每道750个有符号int32样本、间隔40微秒，共14,368,500样本；在已有256MiB/16M样本上限内。没有裁掉尾部或修改文件头。
- 独立 `struct`/NumPy 从所有原始样本计算全局和三组统计，与产品QC的最小/最大值、均值、RMS、总体标准差、零道计数一致。产品扫描到2,667条零振幅道，三个 `trace_in_record` 组各6,386道、889条零道。
- segyio 1.9.14读完全部19,158道；其该格式输出float32，故用作逐道布局/可读性参照，整数真值来自原始 `>i4` 解码。这里比较产品的统计汇总，不声称导出了每个MoonBit样本来做逐值比较；先前300道节选另有逐值验证。
- QC保留原始定位和显式旧版本字解释，报告只返回设定上限100条问题明细，并标记截断；完整扫描汇总不等于输出了全部问题行。

输入仍是非标准版本字 `00 01`，沿用 `examples/public/quality.json` 的显式兼容选择。默认严格解析未放宽；没有把结果称为标准合规。原始振幅不是物理标定结果，零道不是故障原因诊断。没有验证其余七条测线、任意厂商格式或生产地质应用。

当前回执 [full-usgs-20260927](../evidence/full-usgs-20260927/LOCAL-CHECKS.json) 绑定源文件、QC报告和已有release桥接。运行核心未修改，源码与前次标准检查散列逐项相同；本轮没有把历史 `moon test` 计为新运行。
