# 官方 RISC-V 兼容性测试 - 快速上手指南

## TL;DR

```bash
# 1. 构建所有测试（一次性）
./tools/build_riscv_tests.sh

# 2. 运行测试
./tools/run_official_tests.sh i        # RV32I 测试
./tools/run_official_tests.sh m        # M 扩展
./tools/run_official_tests.sh a        # A 扩展
./tools/run_official_tests.sh f        # F 扩展
./tools/run_official_tests.sh d        # D 扩展
./tools/run_official_tests.sh c        # C 扩展
./tools/run_official_tests.sh all      # 所有扩展
```

## 可用内容

✅ **81 个官方 RISC-V 测试** 可直接运行：
- 42 个 RV32I（基础整数）
- 8 个 RV32M（乘除）
- 10 个 RV32A（原子）
- 11 个 RV32F（单精度浮点）
- 9 个 RV32D（双精度浮点）
- 1 个 RV32C（压缩）

## 快速示例

```bash
# 测试某一条具体指令
./tools/run_official_tests.sh i add

# 测试全部基础整数指令
./tools/run_official_tests.sh i

# 测试乘除扩展
./tools/run_official_tests.sh m

# 运行所有测试
./tools/run_official_tests.sh all
```

## 输出示例

### 测试成功
```
==========================================
RV1 Official RISC-V Compliance Tests
==========================================

Testing rv32ui...

  rv32ui-p-add...                PASSED

==========================================
Test Summary
==========================================
Total:  1
Passed: 1
Failed: 0
Pass rate: 100%
```

### 测试失败
```
  rv32ui-p-add...                FAILED (gp=6)
```
（gp 的值表示第几个子测试失败）

### 超时
```
  rv32ui-p-add...                TIMEOUT/ERROR
```
（查看 `sim/official-compliance/rv32ui-p-add.log` 获取详情）

## 文件位置

```
riscv-tests/isa/              # 测试二进制（ELF 格式）
tests/official-compliance/    # 转换后的 hex 文件
sim/official-compliance/      # 仿真日志与结果
tools/                        # 脚本
docs/OFFICIAL_COMPLIANCE_TESTING.md  # 完整文档
```

## 当前状态

**基础设施**：✅ 完成 (100%)  
**已构建测试**：✅ 81/81 个  
**通过测试数**：⚠️ 仍需调试

部分测试目前会超时，可能由于 CSR/陷入处理行为差异。调试步骤见完整文档。

## 获取帮助

- **完整文档**：`docs/OFFICIAL_COMPLIANCE_TESTING.md`
- **查看日志**：`sim/official-compliance/<test>.log`
- **启用调试**：编辑 `tb/integration/tb_core_pipelined.v` 第 88 行

## 接下来做什么

基础设施已经就绪！下一阶段是调试测试卡死的原因：

1. 启用详细 PC 跟踪
2. 检查 CSR 寄存器实现
3. 添加 PMP 占位寄存器
4. 验证陷入处理

详见 `docs/OFFICIAL_COMPLIANCE_TESTING.md` 中的详细调试指南。

---
**创建时间**：2025-10-12  
**状态**：基础设施完成，进入调试阶段
