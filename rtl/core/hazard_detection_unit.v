// 冒险检测单元
// 检测相关冒险并产生暂停/插入气泡控制信号
// 当 EX 阶段中的加载指令（load）生成的数据
// 被 ID 阶段中的指令所需要时，就会发生加载-使用冒险（load-use hazard）
//
// ⚠️ 已知问题：原子操作转发暂停策略过于保守（约 6% 性能损失）
// 详细说明和正确修复方案（需要增加 clk/reset_n）见约第 126 行的注释

`include "config/rv_csr_defines.vh"

module hazard_detection_unit (
  input  wire        clk,              // 用于调试日志的时钟
  // 来自 ID/EX 寄存器的输入（EX 阶段中的指令）
  input  wire        idex_mem_read,    // EX 阶段中的加载指令
  input  wire [4:0]  idex_rd,          // 加载指令的目标寄存器（整数）
  input  wire [4:0]  idex_fp_rd,       // FP 加载指令的目标寄存器
  input  wire        idex_fp_mem_op,   // FP 存储器操作（FP 读/写）

  // 来自 IF/ID 寄存器的输入（ID 阶段中的指令）
  input  wire [4:0]  ifid_rs1,         // 源寄存器 1（整数）
  input  wire [4:0]  ifid_rs2,         // 源寄存器 2（整数）
  input  wire [4:0]  ifid_fp_rs1,      // 源寄存器 1（FP）
  input  wire [4:0]  ifid_fp_rs2,      // 源寄存器 2（FP）
  input  wire [4:0]  ifid_fp_rs3,      // 源寄存器 3（FP，用于 FMA）

  // M 扩展信号
  input  wire        mul_div_busy,     // M 单元忙
  input  wire        idex_is_mul_div,  // EX 阶段是 M 指令

  // A 扩展信号
  input  wire        atomic_busy,      // A 单元忙
  input  wire        atomic_done,      // A 单元操作完成
  input  wire        idex_is_atomic,   // EX 阶段是 A 指令
  input  wire        exmem_is_atomic,  // MEM 阶段是 A 指令
  input  wire [4:0]  exmem_rd,         // MEM 阶段目标寄存器

  // F/D 扩展信号
  input  wire        fpu_busy,         // FPU 忙（多周期操作进行中）
  input  wire        fpu_done,         // FPU 操作完成（1 个周期脉冲）
  input  wire        idex_fp_alu_en,   // EX 阶段是 FP 指令
  input  wire        exmem_fp_reg_write, // MEM 阶段有 FP 写寄存器
  input  wire        memwb_fp_reg_write, // WB 阶段有 FP 写寄存器

  // CSR 信号（用于 FFLAGS/FCSR 相关依赖和 RAW 冒险）
  input  wire [11:0] id_csr_addr,      // ID 阶段的 CSR 地址
  input  wire        id_csr_we,        // ID 阶段的 CSR 写使能
  input  wire        id_is_csr,        // ID 阶段是 CSR 指令
  input  wire        idex_csr_we,      // EX 阶段的 CSR 写使能
  input  wire        exmem_csr_we,     // MEM 阶段的 CSR 写使能
  input  wire        memwb_csr_we,     // WB 阶段的 CSR 写使能

  // xRET 信号（MRET/SRET 会修改 CSR）
  input  wire        exmem_is_mret,    // MEM 阶段的 MRET（修改 mstatus）
  input  wire        exmem_is_sret,    // MEM 阶段的 SRET（修改 mstatus）

  // MMU 信号
  input  wire        mmu_busy,         // MMU 忙（页表遍历进行中）

  // 总线信号（第 52 节 - 修复 CLINT/外设存储挂起问题）
  input  wire        bus_req_valid,    // 总线请求有效
  input  wire        bus_req_ready,    // 总线已准备好接收/完成请求

  // 冒险控制输出
  output wire        stall_pc,         // 暂停程序计数器
  output wire        stall_ifid,       // 暂停 IF/ID 寄存器
  output wire        bubble_idex       // 向 ID/EX 插入气泡（NOP）
);

  // 加载-使用冒险检测逻辑
  // 冒险存在的条件：
  //   1. EX 阶段的指令是加载指令（mem_read = 1）
  //   2. 加载指令的目标寄存器与 ID 阶段的任一源寄存器匹配
  //   3. 目标寄存器不是 x0（零寄存器）
  //
  // 当检测到冒险时：
  //   - 暂停程序计数器（不取下一条指令）
  //   - 暂停 IF/ID（保持当前指令在 ID 阶段）
  //   - 向 ID/EX 插入气泡（将 ID 阶段转换为 NOP）
  //
  // 这会产生一个周期的暂停，允许加载完成
  // 然后转发可以在下一个周期提供数据

  wire rs1_hazard;
  wire rs2_hazard;
  wire load_use_hazard;

  // 检查 rs1 是否存在冒险
  assign rs1_hazard = (idex_rd == ifid_rs1) && (idex_rd != 5'h0);

  // 检查 rs2 是否存在冒险
  assign rs2_hazard = (idex_rd == ifid_rs2) && (idex_rd != 5'h0);

  // 加载-使用冒险存在当有加载指令且任一源寄存器存在冒险
  assign load_use_hazard = idex_mem_read && (rs1_hazard || rs2_hazard);

  // FP 加载-使用冒险检测
  // 类似于整数加载-使用，但检查 FP 寄存器
  // 冒险存在的条件：
  //   1. EX 阶段的指令是 FP 加载（mem_read && fp_mem_op）
  //   2. FP 加载的目标寄存器与 ID 阶段的任一 FP 源寄存器匹配
  // 注意：FP 寄存器不像 x0 那样有硬连零寄存器
  wire fp_rs1_hazard;
  wire fp_rs2_hazard;
  wire fp_rs3_hazard;
  wire fp_load_use_hazard;

  assign fp_rs1_hazard = (idex_fp_rd == ifid_fp_rs1);
  assign fp_rs2_hazard = (idex_fp_rd == ifid_fp_rs2);
  assign fp_rs3_hazard = (idex_fp_rd == ifid_fp_rs3);

  // FP 加载-使用冒险：EX 阶段的 FP 加载写入 ID 阶段 FP 指令需要的寄存器
  assign fp_load_use_hazard = idex_mem_read && idex_fp_mem_op &&
                               (fp_rs1_hazard || fp_rs2_hazard || fp_rs3_hazard);

  // M 扩展冒险：当 M 单元忙或 M 指令刚进入 EX 阶段时暂停 IF/ID 阶段
  // M 指令通过 IDEX 和 EXMEM 寄存器上的保持信号保持在 EX 阶段。
  // 我们还需要暂停 IF/ID，以防止新指令进入流水线。
  // 我们检查 idex_is_mul_div 以捕获 M 指令进入 EX 的第一个周期，
  // 在忙信号有机会变高之前。
  wire m_extension_stall;
  assign m_extension_stall = mul_div_busy || idex_is_mul_div;

  // A 扩展冒险：当 A 单元忙或 A 指令刚进入 EX 阶段时暂停 IF/ID 阶段
  // 类似于 M 扩展，原子操作是多周期的并保持流水线。
  // 但是：当操作完成时不暂停 - 这允许原子指令离开 ID/EX
  // 并防止连续原子操作时的无限暂停循环。
  wire a_extension_stall;
  assign a_extension_stall = (atomic_busy || idex_is_atomic) && !atomic_done;

  // A 扩展转发冒险：当 ID 阶段对正在进行的原子操作有依赖时暂停
  // 这防止在原子结果准备好之前转发它们。
  // 类似于加载-使用冒险，直接检查寄存器依赖
  // 暂停条件：
  //   1. EX 阶段有原子操作且 (rd 匹配 rs1 或 rs2) 且未完成，或者
  //   2. MEM 阶段有原子操作且 (rd 匹配 rs1 或 rs2) 但 exmem_is_atomic 尚未设置
  wire atomic_rs1_hazard_ex;
  wire atomic_rs2_hazard_ex;
  wire atomic_rs1_hazard_mem;
  wire atomic_rs2_hazard_mem;
  wire atomic_forward_hazard;

  // 检查 EX 阶段依赖
  assign atomic_rs1_hazard_ex = (idex_rd == ifid_rs1) && (idex_rd != 5'h0);
  assign atomic_rs2_hazard_ex = (idex_rd == ifid_rs2) && (idex_rd != 5'h0);

  // 检查 MEM 阶段依赖（用于原子操作刚从 EX 转移到 MEM 的过渡周期）
  assign atomic_rs1_hazard_mem = (exmem_rd == ifid_rs1) && (exmem_rd != 5'h0);
  assign atomic_rs2_hazard_mem = (exmem_rd == ifid_rs2) && (exmem_rd != 5'h0);

  // ============================================================================
  // FIXME：性能问题 - 过于保守的暂停（约 6% 开销）
  // ============================================================================
  // 当前实现：在存在依赖时整段原子执行过程都暂停
  // 问题：即使原子操作尚未完成以及在完成那个周期也会暂停
  // 开销：大约多出 1,049 个周期（18,616 vs 17,567 期望值）≈ 6% 性能损失
  //
  // 根本原因：状态转换周期的 bug —— 当 atomic_done=1 时，相关指令
  // 会在结果传播到 EXMEM、从而可以使用 MEM→ID 转发之前溜过去。
  //
  // 更好的方案（TODO）：
  //   1. 保留原始逻辑：只在 (!atomic_done && 有冒险) 时暂停
  //   2. 当 (atomic_done && 有冒险) 时额外再暂停 1 个周期，用状态寄存器实现
  //   3. 这样可以覆盖状态转换周期，而不会在整个原子执行期间都暂停
  //
  // 示例修复：
  //   reg atomic_done_prev;
  //   always @(posedge clk) atomic_done_prev <= atomic_done && idex_is_atomic;
  //   assign atomic_forward_hazard =
  //     (idex_is_atomic && !atomic_done && hazard) ||  // 执行期间
  //     (atomic_done_prev && hazard);                   // 仅在转换周期
  //
  // 尚未实现的原因：需要 clk/reset_n 端口，并增加时序逻辑复杂度
  // 权衡：为了更简单的纯组合逻辑设计，接受 6% 的性能损失
  // ============================================================================

  // 如果 EX 阶段有原子指令且存在依赖（包括完成那个周期）则暂停
  // 这样可以确保相关指令会一直等待，直到结果进入 EXMEM 并且可以使用 MEM→ID 转发
  assign atomic_forward_hazard =
    (idex_is_atomic && (atomic_rs1_hazard_ex || atomic_rs2_hazard_ex));

  // FP 扩展冒险：当 FPU 正在执行多周期操作时暂停 IF/ID 阶段
  // FP 多周期操作（FDIV、FSQRT、FMA 等）会占用流水线。
  // 类似于 A 扩展，在 FPU 忙碌时暂停，但在操作完成那一拍不暂停。
  // 这允许单周期 FP 指令（FSGNJ、FMV.X.W 等）在不暂停的情况下完成。
  wire fp_extension_stall;
  assign fp_extension_stall = (fpu_busy || idex_fp_alu_en) && !fpu_done;

  // MMU 冒险：当 MMU 正在进行页表遍历时暂停 IF/ID 阶段
  // 页表遍历是多周期操作，必须完成后才能继续执行。
  // 这样可以防止在 EX/MEM 阶段因等待 MMU 而保持时，IF/ID 继续前进。
  wire mmu_stall;
  assign mmu_stall = mmu_busy;

  // Bus 等待暂停 (第 52 节)：当总线请求有效但未就绪时暂停
  // 处理带寄存器的 req_ready 信号的外设（CLINT、UART、PLIC）。
  // 如果没有这个暂停机制，当总线事务仍在进行时流水线会继续前进，
  // 在 store 指令访问慢速外设时会导致 PC 被破坏和出现无限循环。
  wire bus_wait_stall;
  assign bus_wait_stall = bus_req_valid && !bus_req_ready;

  // CSR-FPU 依赖冒险：当 CSR 指令访问 FFLAGS/FCSR 且 FPU 正在忙时暂停
  // Bug 修复 #6: FSFLAGS/FCSR 指令必须等待所有未完成的 FP 操作完成。
  // 问题: 如果 fsflags 在 FP 操作仍在流水线中时执行，它会读取过时的标志，
  //          然后 FP 操作完成并累积其标志，覆盖 CSR 写入。
  // 解决方案：当 FPU 有未完成的操作时，暂停对 FFLAGS/FRM/FCSR 的 CSR 读写。
  //
  // CSR 地址：
  //   0x001 = FFLAGS (异常标志)
  //   0x002 = FRM (舍入模式)
  //   0x003 = FCSR (完整的 FP CSR = FRM[7:5] | FFLAGS[4:0])
  //
  // 注意：我们对这些 CSR 的任何访问（读或写）都会暂停，并且我们检查 fpu_busy（操作进行中）和 idex_fp_alu_en（FP 操作刚开始）。
  //       fpu_busy（操作正在进行中）和 idex_fp_alu_en（FP 操作刚开始）。
  //       当 fpu_done=1 时我们不会暂停，因为这表示操作已经完成且标志位已准备就绪。
  // 注意: CSR 地址定义在 rv_csr_defines.vh

  wire csr_accesses_fp_flags;
  wire csr_fpu_dependency_stall;

  // 检查 ID 阶段的 CSR 指令是否访问了与 FP 相关的 CSR
  // 注意: FRM 技术上不依赖于 FPU 操作，但为了简单和避免复杂性，我们保守地对所有三个 CSR 进行暂停
  assign csr_accesses_fp_flags = (id_csr_addr == CSR_FFLAGS) ||
                                   (id_csr_addr == CSR_FRM) ||
                                   (id_csr_addr == CSR_FCSR);

  // 当 ID 阶段的 CSR 指令访问 FP 标志且流水线中有 FP 操作时暂停
  // 我们必须对 EX、MEM 或 WB 阶段的 FP 操作进行暂停，因为：
  // 1. EX 阶段：FPU 可能正在忙或刚开始操作
  // 2. MEM 阶段：FP 加载结果或 FPU 结果传播到 WB
  // 3. WB 阶段：标志正在累积 - 对 FFLAGS 写入至关重要！
  //
  // Bug #7 修复：如果不检查 MEM/WB 阶段，那么在清除 FFLAGS 之后完成的飞行中的 FP 操作会污染清除结果。
  assign csr_fpu_dependency_stall = csr_accesses_fp_flags &&
                                     (fpu_busy || idex_fp_alu_en || exmem_fp_reg_write || memwb_fp_reg_write);

  `ifdef DEBUG_FPU
  always @(posedge clk) begin
    if (csr_fpu_dependency_stall) begin
      $display("[HAZARD] CSR-FPU stall: fpu_busy=%b idex_fp=%b exmem_fp=%b memwb_fp=%b",
               fpu_busy, idex_fp_alu_en, exmem_fp_reg_write, memwb_fp_reg_write);
    end
  end
  `endif

  // ==============================================================================
  // CSR 读后写（RAW）冒险检测
  // ==============================================================================
  // Bug 修复：之前没有处理 CSR 读后写冒险，导致在 CSR 写之后紧接着读会得到过期值或 0。
  //
  // 问题：背靠背的 CSR 指令会产生 RAW 冒险：
  //   csrw mstatus, t0    # 周期 N：在 EX 阶段执行写
  //   csrr a1, mstatus    # 周期 N+1：在 EX 阶段执行读（写还未提交！）
  //
  // CSR 寄存器文件在时钟上升沿同步写入，但读是在同一个周期内组合完成的，会读到旧数据。
  //
  // 解决方案：在以下情况暂停流水线：
  //   - ID 阶段有任意 CSR 指令（读或写）
  //   - 并且在 EX、MEM 或 WB 阶段存在尚未提交的 CSR 写
  //
  // 注意：我们保守地对任意 CSR 写暂停，而不是仅对地址匹配的写暂停。
  // 这样实现更简单，并且可以避免漏掉 CSR 别名（例如 sstatus 是 mstatus 的子集视图）上的依赖。性能影响很小，因为 CSR 指令在典型代码中很少见。
  //
  // 保守策略的理由：
  //   1. CSR 指令使用频率很低（< 1% 的指令）
  //   2. 检查地址匹配比较复杂（别名、带副作用的寄存器等）
  //   3. 每条 CSR 指令多停 1–3 个周期是可接受的开销
  // ==============================================================================

  wire csr_raw_hazard;

  // 检测 ID 阶段是否有任何 CSR 指令（使用译码器产生的信号）
  // 只要存在挂起的 CSR 写操作，所有 CSR 指令（读或写）都必须暂停
  // 当 ID 阶段有 CSR 指令且 EX 或 MEM 阶段存在 CSR 写时产生暂停
  //
  // 重要说明：我们不检查 memwb_csr_we，因为：
  //   - CSR 写在进入 WB 阶段时会在时钟上升沿提交
  //   - CSR 读在 EX 阶段是组合完成的
  //   - 当写到达 WB 阶段时，它会在下一周期前提交
  //   - 对 WB 阶段的写进行暂停已经太晚了——读已经发生
  //   - 我们只需要对 EX 和 MEM 阶段的写进行暂停
  //   - MRET/SRET 也会修改 CSR（mstatus），因此将它们视作 CSR 写
  assign csr_raw_hazard = id_is_csr &&
                          (idex_csr_we || exmem_csr_we || exmem_is_mret || exmem_is_sret);

  // 调试: 打印 CSR 冒险信息
  `ifdef DEBUG_CSR_HAZARD
  always @(posedge clk) begin
    if (id_is_csr || idex_csr_we || exmem_csr_we || memwb_csr_we || exmem_is_mret || exmem_is_sret) begin
      $display("[CSR_HAZARD] Time=%0t id_is_csr=%b idex_we=%b exmem_we=%b exmem_mret=%b exmem_sret=%b hazard=%b",
               $time, id_is_csr, idex_csr_we, exmem_csr_we, exmem_is_mret, exmem_is_sret, csr_raw_hazard);
    end
  end
  `endif

  // 生成控制信号
  // 当出现以下情况之一时暂停：整数或 FP 加载-使用冒险、M 扩展相关冒险、A 扩展相关冒险、
  // A 扩展转发冒险、FP 扩展相关冒险、CSR-FPU 相关冒险、CSR 读后写冒险、MMU 相关冒险，或总线等待
  assign stall_pc    = load_use_hazard || fp_load_use_hazard || m_extension_stall || a_extension_stall || atomic_forward_hazard || fp_extension_stall || csr_fpu_dependency_stall || csr_raw_hazard || mmu_stall || bus_wait_stall;
  assign stall_ifid  = load_use_hazard || fp_load_use_hazard || m_extension_stall || a_extension_stall || atomic_forward_hazard || fp_extension_stall || csr_fpu_dependency_stall || csr_raw_hazard || mmu_stall || bus_wait_stall;
  // 注意：只对加载-使用冒险、原子转发冒险、CSR-FPU 相关暂停以及 CSR 读后写冒险插入气泡
  // （M/A/FP/MMU/bus_wait 的暂停通过 IDEX 和 EXMEM 上的保持信号让指令原地不动）
  // CSR-FPU 和 CSR 读后写暂停需要插入气泡，因为它们是 EX 阶段操作与 ID 阶段指令之间的 RAW 冒险
  assign bubble_idex = load_use_hazard || fp_load_use_hazard || atomic_forward_hazard || csr_fpu_dependency_stall || csr_raw_hazard;

endmodule
