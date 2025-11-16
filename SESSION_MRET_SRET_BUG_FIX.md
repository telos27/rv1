# 会话总结：MRET/SRET 特权违规缺陷修复（进行中）

**日期**: 2025-10-23  
**状态**: 🔧 进行中  
**成果**: RTL 逻辑已实现，验证尚未完成

---

## 🎯 目标

修复在阶段 1 测试中发现的缺陷：MRET 和 SRET 指令在以不足特权模式执行时不会触发陷阱。

---

## 🐛 缺陷分析

### 根因
MRET 和 SRET 指令在译码阶段能正确识别，但从未进行特权违规检查。exception_unit 没有任何逻辑去判断这些指令是否在错误特权级下执行。

### 期望行为
- **MRET**：仅允许在 M 模式执行 → 在 S 模式或 U 模式执行时应触发非法指令异常  
- **SRET**：仅允许在 M 模式或 S 模式执行 → 在 U 模式执行时应触发非法指令异常  

### 修复前的实际行为
- MRET/SRET 在任意特权模式下都能执行成功  
- 不会产生非法指令异常  
- 安全问题：U 模式代码理论上可能操纵特权状态  

---

## 🔧 实现

### 修改文件（3 个）

#### 1. `rtl/core/exception_unit.v`
**变更**：
- 新增 `id_mret` 和 `id_sret` 输入端口  
- 新增特权检查逻辑：
  ```verilog
  wire id_mret_violation = id_valid && id_mret && (current_priv != 2'b11);
  wire id_sret_violation = id_valid && id_sret && (current_priv == 2'b00);
  wire id_illegal_combined = id_illegal || id_mret_violation || id_sret_violation;
  ```
- 更新异常优先级编码逻辑，使用 `id_illegal_combined`  
- 更新注释以反映 xRET 特权检查  

**修改行数**：约 15 行新增/修改  

#### 2. `rtl/core/rv32i_core_pipelined.v`
**变更**：
- 将 `id_mret` 和 `id_sret` 信号连接到 exception_unit：
  ```verilog
  .id_mret(idex_is_mret && idex_valid),
  .id_sret(idex_is_sret && idex_valid),
  ```
- 阻止非法 xRET 传播到 MEM 阶段：
  ```verilog
  .is_mret_in(idex_is_mret && !(exception && (exception_code == 5'd2))),
  .is_sret_in(idex_is_sret && !(exception && (exception_code == 5'd2))),
  ```
- 更新 mret_flush/sret_flush，避免异常发生时仍触发 flush：
  ```verilog
  assign mret_flush = exmem_is_mret && exmem_valid && !exception;
  assign sret_flush = exmem_is_sret && exmem_valid && !exception;
  ```

**修改行数**：约 10 行修改  

#### 3. `tests/asm/test_mret_trap_simple.s`（新）
**目的**：测试在 U 模式执行 MRET 会陷阱

**测试流程**：
1. 通过 MRET 进入 U 模式  
2. 在 U 模式再次执行 MRET  
3. 应触发异常，mcause=2（非法指令）  
4. 若陷阱发生则测试通过  

**状态**：⚠️ 测试已编写但会超时，需要调试  

---

## ✅ 验证结果

### 回归测试
```
make test-quick: 14/14 通过 ✅
```
- 未引入回归  
- 所有现有功能保持正常  

### 阶段 1 测试
```
test_umode_entry_from_mmode:    通过 ✅
test_umode_entry_from_smode:    通过 ✅
test_umode_ecall:               通过 ✅
test_umode_csr_violation:       通过 ✅
test_umode_illegal_instr:       通过 ✅
```
- 阶段 1 所有测试仍然通过  
- 合法的 MRET/SRET 用法仍工作正确  

### 新增特权测试
```
test_mret_trap_simple:      超时 ⚠️
test_xret_privilege_trap:   超时 ⚠️
```
- 测试超时而非通过  
- 表明测试或特权状态追踪存在问题  

---

## 🔍 当前问题

### 症状
测试 `test_mret_trap_simple` 超时，表现为：
- 执行 49,999 个周期  
- 执行 12,512 条指令（对简单测试来说过多）  
- 发生 12,496 次 flush（25% - 表明存在循环）  
- x28（t3）= 0x00000000（既未标记 PASS 也未标记 FAIL）  

### 可能原因
1. **特权模式未正确设置**：`current_priv` 可能在预期时并非 2'b00（U 模式）  
2. **异常未触发**：MRET 违规检查可能未激活  
3. **测试流程问题**：陷阱处理程序可能未被调用或未正确执行  
4. **信号时序问题**：异常信号的时序/传播可能存在问题  

### 下一次会话的调试思路
1. 使用波形分析检查 `current_priv` 信号  
2. 验证 `id_mret_violation` 信号是否拉高  
3. 检查 `exception` 与 `exception_code` 信号  
4. 追踪进入陷阱处理程序的执行路径  
5. 将测试简化为更加极简的场景  

---

## 📊 技术细节

### 特权检查逻辑
```verilog
// MRET：仅允许在 M 模式（priv == 2'b11）执行
wire id_mret_violation = id_valid && id_mret && (current_priv != 2'b11);

// SRET：仅允许在 M 或 S 模式执行（priv >= 2'b01）
wire id_sret_violation = id_valid && id_sret && (current_priv == 2'b00);
```

### 异常优先级
1. 指令地址未对齐（IF）  
2. EBREAK（ID）  
3. ECALL（ID）  
4. **非法指令（ID）- 包含 MRET/SRET 违规** ← 新增  
5. Load/Store 页故障（MEM）  
6. Load 地址未对齐（MEM）  
7. Store 地址未对齐（MEM）  

### xRET flush 控制
```verilog
// 仅在无异常时对 xRET 执行 flush
assign mret_flush = exmem_is_mret && exmem_valid && !exception;
assign sret_flush = exmem_is_sret && exmem_valid && !exception;

// 阻止非法 xRET 传播到 MEM 阶段
.is_mret_in(idex_is_mret && !(exception && (exception_code == 5'd2)))
.is_sret_in(idex_is_sret && !(exception && (exception_code == 5'd2)))
```

---

## 📝 已创建的测试基础设施

### 测试文件
- `tests/asm/test_mret_trap_simple.s` - 简单的 MRET U 模式陷阱测试  
- `tests/asm/test_xret_privilege_trap.s` - 综合 xRET 陷阱测试（3 个测试场景）  

### 计划覆盖的测试点
1. ✅ 在 U 模式执行 SRET → 非法指令  
2. ✅ 在 U 模式执行 MRET → 非法指令  
3. ✅ 在 S 模式执行 MRET → 非法指令  

---

## 🎯 下一次会话任务

### 高优先级
1. **调试测试超时问题**  
   - 使用波形工具（gtkwave）查看信号  
   - 检查特权模式切换  
   - 确认异常是否触发  

2. **修复并验证测试**  
   - 让 `test_mret_trap_simple` 通过  
   - 运行综合测试 `test_xret_privilege_trap`  

3. **完成验证**  
   - 运行完整一致性测试集  
   - 确认未对官方测试引入回归  

### 中优先级
4. **更新阶段 1 测试**  
   - 移除针对 MRET/SRET 缺陷的变通方案  
   - 增加直接验证 MRET/SRET 特权行为的测试  

5. **文档更新**  
   - 在所有相关文档中更新缺陷状态  
   - 增加对本次修复的技术说明  

---

## 💡 经验总结

### 做得好的方面
1. ✅ 通过系统分析较快定位根因  
2. ✅ 修复实现逻辑简洁清晰  
3. ✅ 未引入回归，所有现有测试仍然通过  
4. ✅ 职责分离良好（特权检查集中在 exception_unit）  

### 挑战
1. ⚠️ 测试验证耗时超出预期  
2. ⚠️ 特权模式状态追踪调试难度偏高  
3. ⚠️ 与流水线时序相关的交互较复杂  

### 关键认识
- 特权检查必须在流水线早期（EX 阶段）进行，以防错误指令继续传播  
- xRET 指令需要特殊处理——既会修改 PC，又可能触发异常  
- 异常优先级至关重要——异常必须阻止 xRET 的正常执行  
- 测试基础设施需要更好的调试支持（信号跟踪等）  

---

## 📈 进度指标

### 代码变更
- 修改 RTL 文件：2 个  
- 新增测试文件：2 个  
- 新增行数：约 30 行（RTL）  
- 新增行数：约 160 行（测试）  

### 测试
- 回归测试：14/14 通过 ✅  
- 阶段 1 测试：5/5 通过 ✅  
- 新增特权测试：0/2 通过 ⚠️  

### 时间投入
- 缺陷分析：~30 分钟  
- 实现：~45 分钟  
- 测试/调试：~45 分钟  
- **合计**：约 2 小时  

---

## 🔗 参考资料

- **RISC-V 特权规格**：3.3.2 节（特权模式）  
- **缺陷发现记录**：`SESSION_PHASE1_SUMMARY.md` - 缺陷 #1  
- **原始问题**：记录在阶段 1 测试 `test_umode_illegal_instr.s` 第 15–16 行  

---

## 🚀 下一次会话命令

### 快速开始
```bash
# 查看当前状态
make test-quick

# 运行阶段 1 测试
for test in test_umode_*; do
  env XLEN=32 ./tools/test_pipelined.sh $test
done

# 调试 MRET 陷阱测试
env XLEN=32 ./tools/test_pipelined.sh test_mret_trap_simple

# 查看波形进行调试
gtkwave sim/waves/core_pipelined.vcd

# 检查 git 状态
git status
```

### 调试检查清单
- [ ] 确认在 U 模式时 `current_priv` 为 2'b00  
- [ ] 检查 `id_mret_violation` 信号是否激活  
- [ ] 验证 `exception` 信号是否拉高  
- [ ] 确认 `exception_code` 是否为 5'd2  
- [ ] 追踪陷阱处理程序的执行过程  
- [ ] 检查 mepc/mcause CSR  

---

**状态**：已准备好进行下一次调试会话 🔧
