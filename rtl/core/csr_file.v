// CSR (控制与状态寄存器) 文件
// 实现 RISC-V 中的机器模式 CSR
// 支持 CSR 指令: CSRRW, CSRRS, CSRRC, CSRRWI, CSRRSI, CSRRCI
// 支持陷入处理: 异常进入与 MRET
// 为 RV32/RV64 参数化

`include "config/rv_config.vh"
`include "config/rv_csr_defines.vh"

module csr_file #(
  parameter XLEN = `XLEN
) (
  input  wire             clk,
  input  wire             reset_n,

  // CSR 读/写接口
  input  wire [11:0]      csr_addr,       // CSR 地址
  input  wire [XLEN-1:0]  csr_wdata,      // 写入数据（来自 rs1 或 uimm）
  input  wire [2:0]       csr_op,         // CSR 操作（funct3）
  input  wire             csr_we,         // CSR 写使能
  input  wire             csr_access,     // CSR 指令激活（读或写）
  output reg  [XLEN-1:0]  csr_rdata,      // 读出数据

  // 陷入处理接口
  input  wire             trap_entry,     // 发生陷入
  input  wire [XLEN-1:0]  trap_pc,        // 保存到 mepc 的 PC
  input  wire [4:0]       trap_cause,     // 异常/中断原因代码
  input  wire             trap_is_interrupt, // 1 表示陷入为中断，0 表示异常
  input  wire [XLEN-1:0]  trap_val,       // mtval 值（错误地址、指令等）
  output wire [XLEN-1:0]  trap_vector,    // mtvec 值（陷入处理程序地址）
  // MRET (陷入返回)
  input  wire             mret,           // MRET 指令
  output wire [XLEN-1:0]  mepc_out,       // mepc 返回值

  // SRET (监督模式陷入返回)
  input  wire             sret,           // SRET 指令
  output wire [XLEN-1:0]  sepc_out,       // sepc 返回值
  // Status outputs
  output wire             mstatus_mie,    // 全局中断使能
  output wire             mstatus_sie,    // 监督模式中断使能
  output wire             mstatus_mpie,   // 机器前一中断使能
  output wire             mstatus_spie,   // 监督前一中断使能
  output wire             illegal_csr,    // 非法 CSR 访问

  // 特权模式跟踪（阶段 1）
  input  wire [1:0]       current_priv,   // 当前特权模式（用于 CSR 访问检查）
  input  wire [1:0]       actual_priv,    // 实际特权模式（用于陷入委托）
  output wire [1:0]       trap_target_priv, // 陷入目标特权模式
  output wire [1:0]       mpp_out,        // 机器前一特权模式
  output wire             spp_out,        // 监督前一特权模式
  output wire [XLEN-1:0]  medeleg_out,    // 机器异常委托寄存器
  // MMU 相关状态输出
  output wire [XLEN-1:0]  satp_out,       // SATP 寄存器（用于 MMU）
  output wire             mstatus_sum,    // SUM 位（用于 MMU）
  output wire             mstatus_mxr,    // MXR 位（用于 MMU）
  // 浮点单元状态
  output wire [1:0]       mstatus_fs,     // FPU 状态 (00=关闭, 01=初始, 10=干净, 11=脏)

  // 浮点 CSR 输出
  output wire [2:0]       frm_out,        // 浮点舍入模式（用于 FPU）
  output wire [4:0]       fflags_out,     // 浮点异常标志（用于读取）

  // 浮点标志累积（来自 WB 阶段的 FPU）
  input  wire             fflags_we,      // 浮点标志累积写使能
  input  wire [4:0]       fflags_in,      // 来自 FPU 的异常标志
  // 外部中断输入（来自 CLINT/PLIC）
  input  wire             mtip_in,        // 机器定时器中断挂起
  input  wire             msip_in,        // 机器软件中断挂起
  input  wire             meip_in,        // 机器外部中断挂起（来自 PLIC）
  input  wire             seip_in,        // 监督外部中断挂起（来自 PLIC）

  // 中断状态输出（来自核心中的中断处理）
  output wire [XLEN-1:0]  mip_out,        // 机器中断挂起寄存器
  output wire [XLEN-1:0]  mie_out,        // 机器中断使能寄存器
  output wire [XLEN-1:0]  mideleg_out     // 机器中断委托寄存器
);

  // =========================================================================
  // CSR 寄存器
  // =========================================================================
  // 注意: CSR 地址和位位置定义在 rv_csr_defines.vh 中

  // 机器状态寄存器 - 单寄存器存储
  reg [XLEN-1:0] mstatus_r;

  // 机器 ISA 寄存器 (misa) - 只读
  // RV32: [31:30] = 2'b01 (MXL=1), [25:0] = 扩展位
  // RV64: [63:62] = 2'b10 (MXL=2), [25:0] = 扩展位
  // 扩展: I(8), M(12), A(0), F(5), D(3) = 0x1129
  generate
    if (XLEN == 32) begin : gen_misa_rv32
      wire [31:0] misa = {2'b01, 4'b0, 26'b00000000000001000100101001};
    end else begin : gen_misa_rv64
      wire [63:0] misa = {2'b10, 36'b0, 26'b00000000000001000100101001};
    end
  endgenerate

  // 机器中断使能寄存器 (mie) - 尚未完全实现
  reg [XLEN-1:0] mie_r;

  // 机器陷入基址 (mtvec)
  reg [XLEN-1:0] mtvec_r;

  // 机器暂存寄存器 (mscratch) - 供软件使用
  reg [XLEN-1:0] mscratch_r;

  // 机器异常程序计数器 (mepc)
  reg [XLEN-1:0] mepc_r;

  // 机器陷入原因 (mcause)
  // [XLEN-1] = 中断标志, [XLEN-2:0] = 异常码
  reg [XLEN-1:0] mcause_r;

  // 机器陷入值 (mtval)
  reg [XLEN-1:0] mtval_r;

  // 机器中断挂起寄存器 (mip)
  // 位 11 (MEIP), 9 (SEIP), 7 (MTIP), 3 (MSIP) 为只读, 由外部硬件 (CLINT/PLIC) 驱动
  // 其他位可由软件写
  reg [XLEN-1:0] mip_r;

  // 将硬件中断输入与软件可写位组合
  // 位布局: [XLEN-1:12] | MEIP(11) | [10] | SEIP(9) | [8] | MTIP(7) | [6:4] | MSIP(3) | [2:0]
  wire [XLEN-1:0] mip_value;
  assign mip_value = {mip_r[XLEN-1:12], meip_in, mip_r[10], seip_in, mip_r[8], mtip_in, mip_r[6:4], msip_in, mip_r[2:0]};


  // 浮点 CSR
  reg [4:0] fflags_r;  // 浮点异常标志: [4] NV, [3] DZ, [2] OF, [1] UF, [0] NX
  reg [2:0] frm_r;     // 浮点舍入模式

  // 监督级地址转换与保护 (SATP)
  reg [XLEN-1:0] satp_r;

  // 监督陷入处理寄存器
  reg [XLEN-1:0] stvec_r;      // 监督陷入向量
  reg [XLEN-1:0] sscratch_r;   // 监督暂存寄存器
  reg [XLEN-1:0] sepc_r;       // 监督异常程序计数器
  reg [XLEN-1:0] scause_r;     // 监督异常原因
  reg [XLEN-1:0] stval_r;      // 监督陷入值
  // 机器陷入委托寄存器
  reg [XLEN-1:0] medeleg_r;    // 机器异常委托寄存器
  reg [XLEN-1:0] mideleg_r;    // 机器中断委托寄存器

  // 陷入处理状态
  reg trap_taken_r;            // 标志位，用于防止在同一个周期内多次进入陷入

  // =========================================================================
  // 只读 CSR (硬连线)
  // =========================================================================

  // 供应商 ID: 0 = 未实现
  wire [XLEN-1:0] mvendorid = {XLEN{1'b0}};

  // 架构 ID: 0 = 未实现
  wire [XLEN-1:0] marchid = {XLEN{1'b0}};

  // 实现 ID: 1 = RV1 实现
  wire [XLEN-1:0] mimpid = {{(XLEN-1){1'b0}}, 1'b1};

  // 硬件线程 ID: 0 = 单线程
  wire [XLEN-1:0] mhartid = {XLEN{1'b0}};

  // =========================================================================
  // CSR 读逻辑
  // =========================================================================

  // 从 mstatus 中提取字段, 供内部使用
  wire mstatus_sie_w  = mstatus_r[MSTATUS_SIE_BIT];
  wire mstatus_mie_w  = mstatus_r[MSTATUS_MIE_BIT];
  wire mstatus_spie_w = mstatus_r[MSTATUS_SPIE_BIT];
  wire mstatus_mpie_w = mstatus_r[MSTATUS_MPIE_BIT];
  wire mstatus_spp_w  = mstatus_r[MSTATUS_SPP_BIT];
  wire [1:0] mstatus_mpp_w = mstatus_r[MSTATUS_MPP_MSB:MSTATUS_MPP_LSB];
  wire [1:0] mstatus_fs_w  = mstatus_r[MSTATUS_FS_MSB:MSTATUS_FS_LSB];
  wire mstatus_sum_w  = mstatus_r[MSTATUS_SUM_BIT];
  wire mstatus_mxr_w  = mstatus_r[MSTATUS_MXR_BIT];

  // 直接从寄存器读取 mstatus
  wire [XLEN-1:0] mstatus_value = mstatus_r;

  // 构造 sstatus 为 mstatus 的只读子集
  // SSTATUS 仅提供 S 模式相关字段
  // 屏蔽 M 模式字段 (MPP, MPIE, MIE)
  // 可见位: SIE(1), SPIE(5), UBE(6), SPP(8), SUM(18), MXR(19)
  wire [XLEN-1:0] sstatus_mask = {{(XLEN-20){1'b0}}, 2'b11, 9'b000000000, 1'b1, 1'b0, 2'b11, 3'b000, 1'b1, 1'b0};
  wire [XLEN-1:0] sstatus_value = mstatus_r & sstatus_mask;

  // SIE 和 SIP 是 MIE 和 MIP 的子集
  // 监督级中断使用位: SEIP(9), STIP(5), SSIP(1)
  wire [XLEN-1:0] sie_value = mie_r & {{(XLEN-10){1'b0}}, 1'b1, 3'b0, 1'b1, 3'b0, 1'b1, 1'b0};  // Mask bits [9,5,1]
  // SIP 是 MIP 的一个视图，仅显示监督级中断位 [9,5,1]
  wire [XLEN-1:0] sip_value = mip_value & {{(XLEN-10){1'b0}}, 1'b1, 3'b0, 1'b1, 3'b0, 1'b1, 1'b0};  // 掩码位 [9,5,1]

  // CSR 读多路选择
  // 注意: mstatus_value 与 sstatus_value 已在上面赋值
  // misa 仍需单独 wire
  wire [XLEN-1:0] misa_value;
  generate
    if (XLEN == 32) begin : gen_csr_access
      assign misa_value = gen_misa_rv32.misa;
    end else begin : gen_csr_access
      assign misa_value = gen_misa_rv64.misa;
    end
  endgenerate

  always @(*) begin
    case (csr_addr)
      // 机器模式 CSR
      CSR_MSTATUS: begin
        csr_rdata = mstatus_value;
      end
      CSR_MISA:      csr_rdata = misa_value;
      CSR_MEDELEG:   csr_rdata = medeleg_r;
      CSR_MIDELEG:   csr_rdata = mideleg_r;
      CSR_MIE:       csr_rdata = mie_r;
      CSR_MTVEC:     csr_rdata = mtvec_r;
      CSR_MSCRATCH:  csr_rdata = mscratch_r;
      CSR_MEPC:      csr_rdata = mepc_r;
      CSR_MCAUSE: begin
        csr_rdata = mcause_r;
        `ifdef DEBUG_EXCEPTION
        if (csr_access) $display("[CSR_READ] mcause = %0d", mcause_r);
        `endif
      end
      CSR_MTVAL:     csr_rdata = mtval_r;
      CSR_MIP:       csr_rdata = mip_value;  // 读取组合的软件 + 硬件中断位
      CSR_MVENDORID: csr_rdata = {{(XLEN-32){1'b0}}, mvendorid};  // 零扩展到 XLEN
      CSR_MARCHID:   csr_rdata = {{(XLEN-32){1'b0}}, marchid};    // 零扩展到 XLEN
      CSR_MIMPID:    csr_rdata = {{(XLEN-32){1'b0}}, mimpid};     // 零扩展到 XLEN
      CSR_MHARTID:   csr_rdata = {{(XLEN-32){1'b0}}, mhartid};    // 零扩展到 XLEN
      // 监督模式 CSRs
      CSR_SSTATUS:   csr_rdata = sstatus_value;
      CSR_SIE:       csr_rdata = sie_value;
      CSR_STVEC:     csr_rdata = stvec_r;
      CSR_SSCRATCH:  csr_rdata = sscratch_r;
      CSR_SEPC:      csr_rdata = sepc_r;
      CSR_SCAUSE:    csr_rdata = scause_r;
      CSR_STVAL:     csr_rdata = stval_r;
      CSR_SIP:       csr_rdata = sip_value;
      CSR_SATP:      csr_rdata = satp_r;
      // 浮点 CSRs
      CSR_FFLAGS:    begin
        // 若同周期在累加标志 (WB 阶段冒险), 则前推新标志
        csr_rdata = {{(XLEN-5){1'b0}}, (fflags_we ? (fflags_r | fflags_in) : fflags_r)};
        `ifdef DEBUG_FPU
        $display("[CSR] 读取 FFLAGS: fflags_r=%05b fflags_in=%05b fflags_we=%b, rdata=%h",
                 fflags_r, fflags_in, fflags_we, {{(XLEN-5){1'b0}}, (fflags_we ? (fflags_r | fflags_in) : fflags_r)});
        `endif
      end
      CSR_FRM:       csr_rdata = {{(XLEN-3){1'b0}}, frm_r};       // 零扩展到 XLEN
      CSR_FCSR:      begin
        // 若同周期在累加标志 (WB 阶段冒险), 则前推新标志
        csr_rdata = {{(XLEN-8){1'b0}}, frm_r, (fflags_we ? (fflags_r | fflags_in) : fflags_r)};
      end
      default:       csr_rdata = {XLEN{1'b0}};  // 未知 CSR 返回 0
    endcase
  end

  // =========================================================================
  // CSR 写逻辑
  // =========================================================================

  // =========================================================================
  // CSR 特权检查 (阶段 2)
  // =========================================================================
  // CSR 地址编码: [11:10] = 只读标志, [9:8] = 特权级
  // 00 = 用户, 01 = 监督, 10 = 保留, 11 = 机器

  wire [1:0] csr_priv_level = csr_addr[9:8];  // 从地址中提取特权级
  wire       csr_read_only_bit = (csr_addr[11:10] == 2'b11);  // 如果高2位是11，则只读

  // 检查当前特权级是否可访问该 CSR
  // 规则: 当前特权级 >= CSR 特权级
  wire csr_priv_ok = (current_priv >= csr_priv_level);

  // 判断 CSR 是否只读 (通过地址编码或特定 CSR)
  wire csr_read_only = csr_read_only_bit ||
                       (csr_addr == CSR_MISA) ||
                       (csr_addr == CSR_MVENDORID) ||
                       (csr_addr == CSR_MARCHID) ||
                       (csr_addr == CSR_MIMPID) ||
                       (csr_addr == CSR_MHARTID);

  // 测试/调试 CSR (部分测试框架用于输出)
  // 地址 0x700-0x7FF 有时用于测试输出
  wire csr_is_test = (csr_addr[11:8] == 4'b0111);  // 0x700-0x7FF 范围

  // 判断 CSR 是否存在 (有效)
  // 检查是否在已实现的 CSR 集中
  wire csr_exists = (csr_addr == CSR_MSTATUS) ||
                    (csr_addr == CSR_MISA) ||
                    (csr_addr == CSR_MEDELEG) ||
                    (csr_addr == CSR_MIDELEG) ||
                    (csr_addr == CSR_MIE) ||
                    (csr_addr == CSR_MTVEC) ||
                    (csr_addr == CSR_MSCRATCH) ||
                    (csr_addr == CSR_MEPC) ||
                    (csr_addr == CSR_MCAUSE) ||
                    (csr_addr == CSR_MTVAL) ||
                    (csr_addr == CSR_MIP) ||
                    (csr_addr == CSR_MVENDORID) ||
                    (csr_addr == CSR_MARCHID) ||
                    (csr_addr == CSR_MIMPID) ||
                    (csr_addr == CSR_MHARTID) ||
                    (csr_addr == CSR_SSTATUS) ||
                    (csr_addr == CSR_SIE) ||
                    (csr_addr == CSR_STVEC) ||
                    (csr_addr == CSR_SSCRATCH) ||
                    (csr_addr == CSR_SEPC) ||
                    (csr_addr == CSR_SCAUSE) ||
                    (csr_addr == CSR_STVAL) ||
                    (csr_addr == CSR_SIP) ||
                    (csr_addr == CSR_SATP) ||
                    (csr_addr == CSR_FFLAGS) ||
                    (csr_addr == CSR_FRM) ||
                    (csr_addr == CSR_FCSR) ||
                    csr_is_test;  // 接受测试 CSR

  // 非法 CSR 访问条件:
  // 1. CSR 不存在
  // 2. 特权级不足以访问该 CSR
  // 3. 写只读 CSR
  //
  // 注意: 特权与存在检查对读写都会检查 (csr_access)。
  // 只读检查仅对写操作 (csr_we) 生效。
  assign illegal_csr = csr_access && ((!csr_exists) || (!csr_priv_ok) || (csr_we && csr_read_only));

  `ifdef DEBUG_CSR
  always @(posedge clk) begin
    if (csr_access) begin
      $display("[CSR] 时间=%0t 地址=0x%03x 操作=%0d 访问=%b 写使能=%b 当前特权=%b CSR特权级=%b 特权检查=%b 存在=%b 只读=%b 非法=%b 写入数据=0x%08x mstatus_fs=%b",
               $time, csr_addr, csr_op, csr_access, csr_we, current_priv, csr_priv_level, csr_priv_ok, csr_exists, csr_read_only, illegal_csr, csr_wdata, mstatus_fs_w);
      if (csr_addr == CSR_MSTATUS && csr_we) begin
        $display("[CSR-MSTATUS-WRITE] 操作=%0d wdata=0x%08x rdata=0x%08x 写入值=0x%08x", csr_op, csr_wdata, csr_rdata, csr_write_value);
      end
      if (illegal_csr) begin
        $display("[CSR] *** 非法 CSR 访问检测 ***");
      end
    end
    // 调试 MSTATUS.FS 在复位时
    // 禁用 - 会导致过多的输出
    // if ($time < 100) begin
    //   $display("[CSR-INIT] 时间=%0t mstatus_r=0x%08x mstatus_fs=%b", $time, mstatus_r, mstatus_fs_w);
    // end
    if (sret) begin
      $display("[CSR] 时间=%0t SRET: SIE=%b->%b SPIE=%b->1 SPP=%b->0 mstatus_r=0x%08x",
               $time, mstatus_r[MSTATUS_SIE_BIT], mstatus_spie_w, mstatus_r[MSTATUS_SPIE_BIT],
               mstatus_r[MSTATUS_SPP_BIT], mstatus_r);
    end
  end
  `endif

  // 计算 CSR 写入值
  reg [XLEN-1:0] csr_write_value;
  always @(*) begin
    case (csr_op)
      CSR_RW, CSR_RWI: csr_write_value = csr_wdata;               // 写入新值
      CSR_RS, CSR_RSI: csr_write_value = csr_rdata | csr_wdata;   // 置位位
      CSR_RC, CSR_RCI: csr_write_value = csr_rdata & ~csr_wdata;  // 清除位
      default:         csr_write_value = csr_rdata;               // 无变化
    endcase
  end

  // CSR 写 (同步)
  always @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
      // 复位所有 CSR
      // 初始化 mstatus: MPP=11 (M 模式), FS=11 (FPU 已启用/脏), 其它字段为 0
      mstatus_r      <= {{(XLEN-15){1'b0}}, 2'b11, 2'b11, {11{1'b0}}}; // FS[14:13]=11, MPP[12:11]=11, rest=0
      mie_r          <= {XLEN{1'b0}};
      mtvec_r        <= {XLEN{1'b0}};   // 陷阱向量地址 0
      mscratch_r     <= {XLEN{1'b0}};
      mepc_r         <= {XLEN{1'b0}};
      mcause_r       <= {XLEN{1'b0}};
      mtval_r        <= {XLEN{1'b0}};
      mip_r          <= {XLEN{1'b0}};
      satp_r         <= {XLEN{1'b0}};   // 无地址转换 (裸模式)
      // 复位浮点 CSR
      fflags_r       <= 5'b0;            // 无异常
      frm_r          <= 3'b000;          // RNE (四舍六入)
      // 复位监督 CSR
      stvec_r        <= {XLEN{1'b0}};   // 监督陷阱向量地址 0
      sscratch_r     <= {XLEN{1'b0}};
      sepc_r         <= {XLEN{1'b0}};
      scause_r       <= {XLEN{1'b0}};
      stval_r        <= {XLEN{1'b0}};
      // 复位陷入委托寄存器
      medeleg_r      <= {XLEN{1'b0}};   // 默认无委托
      mideleg_r      <= {XLEN{1'b0}};   // 默认无委托
      trap_taken_r   <= 1'b0;            // 初始无陷入
    end else begin
      // 陷入进入优先于 CSR 写和 SRET/MRET
      // trap_entry 为顶层发出的单周期脉冲
      if (trap_entry) begin
        `ifdef DEBUG_EXCEPTION
        $display("[CSR_TRAP] 陷入进入: target_priv=%b cause=%0d PC=%h", trap_target_priv, trap_cause, trap_pc);
        `endif
        // 决定陷入目标特权级
        if (trap_target_priv == 2'b11) begin
          // 机器模式陷入
          mepc_r  <= trap_pc;
          // 设置 mcause: MSB = interrupt bit, lower bits = cause code
          mcause_r <= {trap_is_interrupt, {(XLEN-6){1'b0}}, trap_cause};
          mtval_r  <= trap_val;
          `ifdef DEBUG_EXCEPTION
          $display("[CSR_TRAP] 写入 mcause=%0d (interrupt=%b) mepc=%h", trap_cause, trap_is_interrupt, trap_pc);
          `endif
          `ifdef DEBUG_CSR
          $display("[CSR_TRAP_M] 禁用中断: MIE=%b -> MPIE, 设置 MIE=0, cause=%0d PC=%h",
                   mstatus_mie_w, trap_cause, trap_pc);
          `endif
          mstatus_r[MSTATUS_MPIE_BIT] <= mstatus_mie_w;         // 保存当前 MIE
          mstatus_r[MSTATUS_MIE_BIT]  <= 1'b0;                  // 禁用中断
          mstatus_r[MSTATUS_MPP_MSB:MSTATUS_MPP_LSB] <= current_priv; // 保存当前特权级
        end else if (trap_target_priv == 2'b01) begin
          // 监督模式陷入
          sepc_r  <= trap_pc;
          // 设置 scause: MSB = 中断位, 低位 = 原因代码
          scause_r <= {trap_is_interrupt, {(XLEN-6){1'b0}}, trap_cause};
          stval_r  <= trap_val;
          mstatus_r[MSTATUS_SPIE_BIT] <= mstatus_sie_w;         // 保存当前 SIE
          mstatus_r[MSTATUS_SIE_BIT]  <= 1'b0;                  // 禁用监督模式中断
          mstatus_r[MSTATUS_SPP_BIT]  <= current_priv[0];       // 保存当前特权级 (0=U, 1=S)
        end
      end else if (mret) begin
        // MRET: 从机器模式陷入返回
        `ifdef DEBUG_CSR_FORWARD
        $display("[CSR_MRET] 时间=%0t 执行 MRET: MPIE=%b -> MIE, mstatus_before=%h",
                 $time, mstatus_mpie_w, mstatus_r);
        `endif
        `ifdef DEBUG_CSR
        $display("[CSR_MRET] 恢复 MIE: MPIE=%b -> MIE, MPP=%b (was M-mode, now restoring)",
                 mstatus_mpie_w, mstatus_r[MSTATUS_MPP_MSB:MSTATUS_MPP_LSB]);
        `endif
        mstatus_r[MSTATUS_MIE_BIT]  <= mstatus_mpie_w;  // 恢复中断使能
        mstatus_r[MSTATUS_MPIE_BIT] <= 1'b1;            // 将 MPIE 置为 1
        // 根据 RISC-V 规范: MPP 需要被设置为最低特权级 (若实现 U 模式则为 U，否则为 M)
        // 当前实现支持 U 模式，因此将 MPP 置为 U 模式 (2'b00)
        mstatus_r[MSTATUS_MPP_MSB:MSTATUS_MPP_LSB] <= 2'b00; // 将 MPP 设置为 U 模式
            end else if (sret) begin
        // SRET: 从监督模式陷入返回
        mstatus_r[MSTATUS_SIE_BIT]  <= mstatus_spie_w;  // 恢复监督模式中断使能
        mstatus_r[MSTATUS_SPIE_BIT] <= 1'b1;            // 将 SPIE 置为 1
        mstatus_r[MSTATUS_SPP_BIT]  <= 1'b0;            // 将 SPP 设置为 U 模式
      end else if (csr_we && !csr_read_only) begin
        // 正常 CSR 写
        case (csr_addr)
          CSR_MSTATUS: begin
            // 写各个字段
            mstatus_r[MSTATUS_SIE_BIT]  <= csr_write_value[MSTATUS_SIE_BIT];
            mstatus_r[MSTATUS_MIE_BIT]  <= csr_write_value[MSTATUS_MIE_BIT];
            mstatus_r[MSTATUS_SPIE_BIT] <= csr_write_value[MSTATUS_SPIE_BIT];
            mstatus_r[MSTATUS_MPIE_BIT] <= csr_write_value[MSTATUS_MPIE_BIT];
            mstatus_r[MSTATUS_SPP_BIT]  <= csr_write_value[MSTATUS_SPP_BIT];
            mstatus_r[MSTATUS_MPP_MSB:MSTATUS_MPP_LSB] <= csr_write_value[MSTATUS_MPP_MSB:MSTATUS_MPP_LSB];
            mstatus_r[MSTATUS_FS_MSB:MSTATUS_FS_LSB]   <= csr_write_value[MSTATUS_FS_MSB:MSTATUS_FS_LSB];
            mstatus_r[MSTATUS_SUM_BIT]  <= csr_write_value[MSTATUS_SUM_BIT];
            mstatus_r[MSTATUS_MXR_BIT]  <= csr_write_value[MSTATUS_MXR_BIT];
          end
          CSR_MIE:      mie_r      <= csr_write_value;
          // MTVEC 对齐: 开启 C 扩展时 2 字节对齐, 否则 4 字节
          `ifdef ENABLE_C_EXT
          CSR_MTVEC:    mtvec_r    <= {csr_write_value[XLEN-1:1], 1'b0};   // 对齐到 2 字节 (C 扩展)
          `else
          CSR_MTVEC:    mtvec_r    <= {csr_write_value[XLEN-1:2], 2'b00};  // 对齐到 4 字节
          `endif
          CSR_MSCRATCH: mscratch_r <= csr_write_value;
          CSR_MEPC:     mepc_r     <= {csr_write_value[XLEN-1:1], 1'b0};   // 对齐到 2 字节 (C 扩展)
          CSR_MCAUSE:   mcause_r   <= csr_write_value;
          CSR_MTVAL:    mtval_r    <= csr_write_value;
          CSR_MIP: begin
            // MIP: 屏蔽只读位 (MEIP=11, SEIP=9, MTIP=7, MSIP=3) - 这些由硬件驱动
            // 掩码格式: 位 11, 9, 7, 3 = 1 (只读)
            mip_r      <= csr_write_value & ~({{(XLEN-12){1'b0}}, 1'b1, 1'b0, 1'b1, 1'b0, 1'b1, 3'b0, 1'b1, 3'b0});
          end
          CSR_SATP: begin
            satp_r <= csr_write_value;
            $display("[CSR] SATP 写入: 0x%h priv=%b at time %0t", csr_write_value, current_priv, $time);
          end
          CSR_MEDELEG:  medeleg_r  <= csr_write_value;
          CSR_MIDELEG:  mideleg_r  <= csr_write_value;
          // 监督模式 CSR
          CSR_SSTATUS: begin
            // SSTATUS 是 MSTATUS 的受限视图
            // 仅允许写 S 模式可见的字段
            mstatus_r[MSTATUS_SIE_BIT]  <= csr_write_value[MSTATUS_SIE_BIT];
            mstatus_r[MSTATUS_SPIE_BIT] <= csr_write_value[MSTATUS_SPIE_BIT];
            mstatus_r[MSTATUS_SPP_BIT]  <= csr_write_value[MSTATUS_SPP_BIT];
            mstatus_r[MSTATUS_SUM_BIT]  <= csr_write_value[MSTATUS_SUM_BIT];
            mstatus_r[MSTATUS_MXR_BIT]  <= csr_write_value[MSTATUS_MXR_BIT];
          end
          CSR_SIE: begin
            // SIE 是 MIE 的子集 - 仅写 S 模式中断位 [9,5,1]
            mie_r[9] <= csr_write_value[9];  // SEIE
            mie_r[5] <= csr_write_value[5];  // STIE
            mie_r[1] <= csr_write_value[1];  // SSIE
          end
          // STVEC 对齐: 2 字节对齐 (C 扩展), 4 字节对齐 (无 C 扩展)
          `ifdef ENABLE_C_EXT
          CSR_STVEC:    stvec_r    <= {csr_write_value[XLEN-1:1], 1'b0};   // 对齐到 2 字节 (C 扩展)
          `else
          CSR_STVEC:    stvec_r    <= {csr_write_value[XLEN-1:2], 2'b00};  // 对齐到 4 字节
          `endif
          CSR_SSCRATCH: sscratch_r <= csr_write_value;
          CSR_SEPC:     sepc_r     <= {csr_write_value[XLEN-1:1], 1'b0};   // 对齐到 2 字节 (C 扩展)
          CSR_SCAUSE:   scause_r   <= csr_write_value;
          CSR_STVAL:    stval_r    <= csr_write_value;
          CSR_SIP: begin
            // SIP 是 MIP 的子集 - 仅写 S 模式中断位 [9,5,1]
            // 注意: 通常只有 SSIP (bit 1) 允许被软件写
            mip_r[1] <= csr_write_value[1];  // SSIP (软件中断)
          end
          // 浮点 CSR
          CSR_FFLAGS: begin
            fflags_r   <= csr_write_value[4:0];  // 写异常标志
            `ifdef DEBUG_FPU
            $display("[CSR] 写入 FFLAGS: 值=%05b (清除标志)", csr_write_value[4:0]);
            `endif
          end
          CSR_FRM:      frm_r      <= csr_write_value[2:0];  // 写舍入模式
          CSR_FCSR: begin
            frm_r    <= csr_write_value[7:5];  // 高 3 位 = 舍入模式
            fflags_r <= csr_write_value[4:0];  // 低 5 位 = 异常标志
            `ifdef DEBUG_FPU
            $display("[CSR] 写入 FCSR: frm=%03b fflags=%05b", csr_write_value[7:5], csr_write_value[4:0]);
            `endif
          end
          default: begin
            // 未知或只读 CSR: 不写
          end
        endcase

        // CSR 中断相关写调试
        `ifdef DEBUG_CSR
        if (csr_addr == CSR_MSTATUS) begin
          $display("[CSR_WRITE] MSTATUS: op=%h wdata=%h rdata=%h -> write_val=%h MIE=%b->%b",
                   csr_op, csr_wdata, csr_rdata, csr_write_value,
                   csr_rdata[MSTATUS_MIE_BIT], csr_write_value[MSTATUS_MIE_BIT]);
        end
        if (csr_addr == CSR_MIE) begin
          $display("[CSR_WRITE] MIE: MEIE=%b MTIE=%b MSIE=%b SEIE=%b STIE=%b SSIE=%b (full=%h)",
                   csr_write_value[11], csr_write_value[7], csr_write_value[3],
                   csr_write_value[9], csr_write_value[5], csr_write_value[1],
                   csr_write_value);
        end
        if (csr_addr == CSR_MIP) begin
          $display("[CSR_WRITE] MIP: MEIP=%b MTIP=%b MSIP=%b SEIP=%b STIP=%b SSIP=%b (full=%h)",
                   csr_write_value[11], csr_write_value[7], csr_write_value[3],
                   csr_write_value[9], csr_write_value[5], csr_write_value[1],
                   csr_write_value);
        end
        `endif
      end

      // 浮点标志累加 (按位或)
      // 允许 FPU 在无 CSR 指令情况下累加异常标志
      // 标志为“黏性”: 一旦置位, 直到通过 CSR 写显式清除
      // 重要: 若本周期有对 FFLAGS/FCSR 的 CSR 写, 则 CSR 写优先于累加
      // 仅当本周期没有针对 fflags 的 CSR 写时才累加
      if (fflags_we && !(csr_we && (csr_addr == CSR_FFLAGS || csr_addr == CSR_FCSR))) begin
        fflags_r <= fflags_r | fflags_in;  // 累加 (按位或)
        `ifdef DEBUG_FPU
        $display("[CSR] FFlags 累加: old=%05b new=%05b result=%05b",
                 fflags_r, fflags_in, fflags_r | fflags_in);
        `endif
      end
    end
  end

  // =========================================================================
  // 陷入目标特权判断 (阶段 2)
  // =========================================================================
  // 根据委托寄存器与当前特权级确定陷入目标特权:
  // 逻辑:
  // 1. 若当前特权为 M, 陷入一定进入 M (不委托)
  // 2. 若异常被委托 (medeleg 对应 bit 置 1) 且特权 < M, 则进入 S
  // 3. 否则进入 M

  function [1:0] get_trap_target_priv;
    input [4:0] cause;
    input [1:0] curr_priv;
    input [XLEN-1:0] medeleg;
    begin
      `ifdef DEBUG_EXCEPTION
      $display("[CSR_DELEG] get_trap_target_priv: 原因=%0d curr_priv=%b medeleg=%h medeleg[cause]=%b",
               cause, curr_priv, medeleg, medeleg[cause]);
      `endif
      // M-mode 陷入永远不委托
      if (curr_priv == 2'b11) begin
        get_trap_target_priv = 2'b11;  // M-mode
        `ifdef DEBUG_EXCEPTION
        $display("[CSR_DELEG] -> M-mode (curr_priv==M)");
        `endif
      end
      // 检查异常是否委托给 监督模式
      else if (medeleg[cause] && (curr_priv <= 2'b01)) begin
        get_trap_target_priv = 2'b01;  // 监督模式
        `ifdef DEBUG_EXCEPTION
        $display("[CSR_DELEG] -> 监督模式 (delegated)");
        `endif
      end
      else begin
        get_trap_target_priv = 2'b11;  // M-mode (默认)
        `ifdef DEBUG_EXCEPTION
        $display("[CSR_DELEG] -> M-mode (无委托)");
        `endif
      end
    end
  endfunction

  // 使用 actual_priv 做陷入委托判断 (而非转发后的 effective_priv)
  // 陷入委托决策必须基于异常发生时的真实特权级,
  // 而不是来自待执行 xRET 的转发特权级。
  assign trap_target_priv = get_trap_target_priv(trap_cause, actual_priv, medeleg_r);

  // =========================================================================
  // 输出分配
  // =========================================================================

  // 选择陷入向量基于目标特权
  assign trap_vector = (trap_target_priv == 2'b01) ? stvec_r : mtvec_r;
  assign mepc_out    = mepc_r;
  assign sepc_out    = sepc_r;
  assign mstatus_mie = mstatus_mie_w;
  assign mstatus_sie = mstatus_sie_w;
  assign mstatus_mpie = mstatus_mpie_w;
  assign mstatus_spie = mstatus_spie_w;

  // 特权模式输出
  assign mpp_out     = mstatus_mpp_w;
  assign spp_out     = mstatus_spp_w;
  assign medeleg_out = medeleg_r;

  // 中断寄存器输出
  assign mip_out     = mip_value;     // 当前中断挂起 (包括硬件输入)
  assign mie_out     = mie_r;         // 中断使能寄存器
  assign mideleg_out = mideleg_r;     // 中断委托寄存器

  // MMU 相关输出
  assign satp_out    = satp_r;
  assign mstatus_sum = mstatus_sum_w;
  assign mstatus_mxr = mstatus_mxr_w;

  // FPU 状态输出
  assign mstatus_fs  = mstatus_fs_w;

  // 浮点 CSR 输出
  assign frm_out     = frm_r;
  assign fflags_out  = fflags_r;

endmodule
