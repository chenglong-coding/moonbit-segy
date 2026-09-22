# MoonSEGY

正在实现的 MoonBit 原生 SEG-Y 数据交换与道检查库，固定范围见 docs/SCOPE.md。`localreview/segy` 是未发布的本地模块；不声称远程 CI 或正式验收完成。Node 宿主仅负责 IO，样本、头和领域计算在 MoonBit。

独立依据：[SEG-Y rev2.0 原始规范](https://seg.org/wp-content/uploads/2025/11/seg_y_rev2_0_mar2017.pdf)、[segyio](https://segyio.readthedocs.io/)。ASCII/EBCDIC 明确编码，不把文本识别启发式当作确定事实。MIT；AI 辅助开发并保留真实作者。

```sh
moon check --target all
moon test --target js
moon test --target wasm-gc
moon fmt
moon info
```

当前仍在 A/B 基础阶段；完整文件工作流与独立批量验收待完成。
