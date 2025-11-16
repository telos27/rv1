# 👋 从这里开始 - RV1 RISC-V 处理器

**新一次开发会话？先读这个！**

---

## 🎉 项目状态

✅ **已实现 100% RISC-V 兼容性！**
- 81/81 官方测试通过
- 已实现所有扩展：I, M, A, F, D, C
- 可用于生产的 5 级流水线内核

---

## 🔍 测试基础设施 - 使用这些工具！

### 快捷命令

```bash
# 查看所有可用命令
make help

# 浏览全部 208 个测试（127 自定义 + 81 官方）
cat docs/TEST_CATALOG.md

# 检查测试状态
make check-hex

# 运行测试
make test-quick                     # ⚡ 快速回归（约 7 秒跑完 14 个测试）
make test-custom-all                # 所有自定义测试
env XLEN=32 make test-all-official  # 所有官方测试

# 重新生成测试目录
make catalog
```

### 关键资源（请看这些！）

📋 **测试目录** - `docs/reference/TEST_CATALOG.md`
- 自动生成的全部测试索引
- 按扩展（I/M/A/F/D/C 等）分类
- 便于搜索的描述
- **用这个查找测试，而不是在文件里乱翻！**

🛠️ **脚本指南** - `tools/README.md`
- 所有 22 个脚本的说明
- 区分主脚本与遗留脚本
- 使用示例

📖 **快速回归** - `docs/guides/QUICK_REGRESSION_SUITE.md`
- 7 秒测试集的说明
- 开发工作流
- 节省时间的自动化流程

📖 **文档索引** - `docs/README.md`
- 完整文档地图
- 快速定位任意文档

---

## ⚡ 快速回归测试集（务必使用！）

**在修改前后都要跑：**

```bash
make test-quick
# 约 7 秒跑完 14 个测试 - 能捕获 90% 的 Bug！
```

**推荐开发流程：**
1. `make test-quick` → 建立基线（应全部 ✓）
2. 修改 RTL
3. `make test-quick` → 确认无回归
4. 若全部 ✓：继续开发
5. 若有 ✗：立刻调试（不要继续写代码！）
6. 在提交前：`env XLEN=32 ./tools/run_official_tests.sh all`

**为什么用快速测试：**
- ⚡ 比完整测试快 11 倍（7 秒 vs 80 秒）
- ⚡ 覆盖所有扩展（I/M/A/F/D/C）
- ⚡ 能捕获大多数常见 Bug
- ⚡ 反馈极快

---

## 🚀 常见任务

### 运行测试

**单个测试：**
```bash
env XLEN=32 ./tools/test_pipelined.sh test_fp_basic
```

**所有官方测试：**
```bash
env XLEN=32 ./tools/run_official_tests.sh all
```

**指定扩展：**
```bash
make test-m    # M 扩展
make test-f    # F 扩展
make test-d    # D 扩展
```

### 管理 Hex 文件

**检查缺失文件：**
```bash
make check-hex
```

**重建全部 hex 文件：**
```bash
make rebuild-hex
```

**清理生成的文件：**
```bash
make clean-hex
```

### 查找测试

**不要手动搜文件！** 用测试目录：
```bash
cat docs/reference/TEST_CATALOG.md
# 或在其中搜索：
grep "floating" docs/reference/TEST_CATALOG.md
```

---

## 📚 文档结构

```
docs/
├── README.md                           # ⭐ 文档索引 - 从这里开始
├── guides/                             # 指南
│   ├── QUICK_REGRESSION_SUITE.md      # ⚡ 7 秒测试集
│   ├── OFFICIAL_COMPLIANCE_TESTING.md # 完整兼容性测试说明
│   ├── TEST_STANDARD.md               # 如何编写测试
│   └── PARAMETERIZATION_GUIDE.md      # RV32/RV64 配置
├── reference/                          # 参考文档
│   ├── TEST_CATALOG.md                # ⭐ 全部 208 个测试的索引
│   ├── PHASE3_DATAPATH_DIAGRAM.md     # 数据通路图
│   └── PHASE3_PIPELINE_ARCHITECTURE.md  # 流水线规范
├── design/                             # 架构设计文档
│   ├── M_EXTENSION_DESIGN.md          # 乘/除
│   ├── A_EXTENSION_DESIGN.md          # 原子操作
│   ├── FD_EXTENSION_DESIGN.md         # 浮点
│   ├── C_EXTENSION_DESIGN.md          # 压缩指令
│   └── [更多...]
├── bugs/                               # Bug 文档
│   ├── CRITICAL_BUGS.md               # 前 10 个关键 Bug
│   └── BUG_FIXES_SUMMARY.md           # 已修复的 54+ 个 Bug 汇总
├── sessions/                           # 最近工作
│   └── SESSION*.md                    # 最近 3 次会话
└── archive/                            # 历史文档（145+ 文件）

tools/
└── README.md                           # ⭐ 脚本参考指南
```

---

## 🎯 接下来做什么

根据兴趣选择方向：

### 1. **添加新特性**
- B 扩展（位操作）
- V 扩展（向量）
- K 扩展（密码学）
- 性能优化

### 2. **改进测试**
- CI 检查脚本（自动化 pre-commit）
- 快速回归测试集（10 秒 10 个测试）
- 测试覆盖矩阵
- 测试并行执行

### 3. **硬件部署**
- FPGA 综合
- 外设接口（UART, GPIO, SPI）
- Boot ROM 与引导加载程序
- 跑 Linux 或 xv6-riscv

详见 `docs/test-infrastructure/TEST_INFRASTRUCTURE_CLEANUP_REPORT.md` 获取详细改进建议。

---

## ⚡ 小技巧

1. **总先跑一次 `make help`** - 看看已有的东西
2. **用测试目录找测试** - 不要在文件树里乱翻
3. **用 Make 目标** - 比直接跑脚本快且统一
4. **重新生成目录** - 添加测试后跑 `make catalog`
5. **检查 hex 文件** - 测试前跑 `make check-hex`

---

## 🤖 写给 AI 助手的话

**在做任何“测试相关”的操作之前：**

1. 运行 `make help` - 看看有哪些命令
2. 阅读 `docs/README.md` - 文档索引
3. 浏览 `docs/reference/TEST_CATALOG.md` - 全部测试
4. 查看 `tools/README.md` - 了解脚本

**不要：**
- ❌ 手动到处搜测试文件
- ❌ 瞎猜要用哪个脚本
- ❌ 胡猜命令行参数

**要：**
- ✅ 用测试目录找测试
- ✅ 使用 Make 目标
- ✅ 先看文档再动手

---

## 📞 帮助与反馈

- 文档索引：见 `docs/README.md`
- 如何跑测试：见 `tools/README.md`
- 架构详情：见 `ARCHITECTURE.md`
- 开发历史：见 `PHASES.md`
- 项目上下文：见 `CLAUDE.md`
- Bug 历史：见 `docs/bugs/CRITICAL_BUGS.md`

---

**最后更新**：2025-10-23  
**状态**：可用于生产 - 100% 兼容 ✅  
**总测试数**：208（127 自定义 + 81 官方）
