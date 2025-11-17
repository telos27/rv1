// csr_priv_coordinator.v - CSR 与特权模式协调模块
// 处理 CSR 转发 (MRET/SRET) 与特权模式跟踪
// 从 rv32i_core_pipelined.v 抽取以增强模块化
// 作者: RV1 Project
// 日期: 2025-10-26

`include "config/rv_config.vh"
`include "config/rv_csr_defines.vh"

module csr_priv_coordinator #(
  parameter XLEN = `XLEN
) (
  input  wire             clk,
  input  wire             reset_n,

  // 陷入/xRET 控制输入
  input  wire             trap_flush,
  input  wire [1:0]       trap_target_priv,
  input  wire             mret_flush,
  input  wire             sret_flush,

  // 来自 CSR 文件的 MSTATUS 位
  input  wire [1:0]       mpp,
  input  wire             spp,
  input  wire             mstatus_mie,
  input  wire             mstatus_sie,
  input  wire             mstatus_mpie,
  input  wire             mstatus_spie,
  input  wire             mstatus_mxr,
  input  wire             mstatus_sum,

  // 用于 CSR 转发的流水级信号
  input  wire             exmem_is_mret,
  input  wire             exmem_is_sret,
  input  wire             exmem_valid,
  input  wire             idex_is_csr,
  input  wire             idex_valid,
  input  wire [11:0]      idex_csr_addr,
  input  wire             exception,
  input  wire [XLEN-1:0]  ex_csr_rdata,

  // 输出
  output wire [1:0]       current_priv,       // 当前特权模式
  output wire [1:0]       effective_priv,     // 转发后的特权模式 (用于 CSR 检查)
  output wire [XLEN-1:0]  ex_csr_rdata_forwarded  // 转发后的 CSR 读数据
);

  //==========================================================================
  // 特权模式跟踪
  //==========================================================================
  // 特权模式状态机: 在陷入进入和 xRET 时更新
  reg [1:0] current_priv_r;

  always @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
      current_priv_r <= 2'b11;  // 复位时进入机器模式
    end else begin
      if (trap_flush) begin
        // 陷入时, 切换到目标特权级别
        current_priv_r <= trap_target_priv;
        `ifdef DEBUG_PRIV
        $display("[PRIV] 时间=%0t TRAP: priv %b -> %b", $time, current_priv_r, trap_target_priv);
        `endif
      end else if (mret_flush) begin
        // MRET 时, 从 MSTATUS.MPP 恢复特权
        current_priv_r <= mpp;
        `ifdef DEBUG_PRIV
        $display("[PRIV] 时间=%0t MRET: priv %b -> %b (from MPP)", $time, current_priv_r, mpp);
        `endif
      end else if (sret_flush) begin
        // SRET 时, 从 MSTATUS.SPP 恢复特权
        current_priv_r <= {1'b0, spp};  // SPP: 0=U, 1=S -> {1'b0, spp} = 00 或 01
        `ifdef DEBUG_PRIV
        $display("[PRIV] 时间=%0t SRET: priv %b -> %b (from SPP=%b)", $time, current_priv_r, {1'b0, spp}, spp);
        `endif
      end
    end
  end

  assign current_priv = current_priv_r;

  //==========================================================================
  // CSR MRET/SRET 转发
  //==========================================================================
  // 当 MRET/SRET 在 MEM 阶段时, 它会在周期末更新 mstatus。
  // 若此时 EX 阶段有对 mstatus/sstatus 的 CSR 读, 需要看到更新后的值。
  // 通过转发“下一周期”的 mstatus 值避免读到陈旧数据。

  // 计算 MRET 后的“下一周期”mstatus 值
  function [XLEN-1:0] compute_mstatus_after_mret;
    input [XLEN-1:0] current_mstatus;
    input mpie_val;
    reg [XLEN-1:0] next_mstatus;
    begin
      next_mstatus = current_mstatus;
      // MIE ← MPIE
      next_mstatus[MSTATUS_MIE_BIT] = mpie_val;
      // MPIE ← 1
      next_mstatus[MSTATUS_MPIE_BIT] = 1'b1;
      // MPP ← U (2'b00)
      next_mstatus[MSTATUS_MPP_MSB:MSTATUS_MPP_LSB] = 2'b00;
      compute_mstatus_after_mret = next_mstatus;
    end
  endfunction

  // 计算 SRET 后的“下一周期” mstatus 值
  function [XLEN-1:0] compute_mstatus_after_sret;
    input [XLEN-1:0] current_mstatus;
    input spie_val;
    reg [XLEN-1:0] next_mstatus;
    begin
      next_mstatus = current_mstatus;
      // SIE ← SPIE
      next_mstatus[MSTATUS_SIE_BIT] = spie_val;
      // SPIE ← 1
      next_mstatus[MSTATUS_SPIE_BIT] = 1'b1;
      // SPP ← U (1'b0)
      next_mstatus[MSTATUS_SPP_BIT] = 1'b0;
      compute_mstatus_after_sret = next_mstatus;
    end
  endfunction

  // 构造当前 mstatus (与 csr_file.v 的存储格式一致)
  wire [XLEN-1:0] current_mstatus_reconstructed;
  assign current_mstatus_reconstructed = {
    {(XLEN-32){1'b0}},           // 上位未使用位 (如果 XLEN > 32)
    12'b0,                        // 保留位 [31:20]
    mstatus_mxr,                  // MXR [19]
    mstatus_sum,                  // SUM [18]
    5'b0,                         // 保留位 [17:13]
    mpp,                          // MPP [12:11]
    2'b0,                         // 保留 [10:9]
    spp,                          // SPP [8]
    mstatus_mpie,                 // MPIE [7]
    1'b0,                         // 保留 [6]
    mstatus_spie,                 // SPIE [5]
    1'b0,                         // 保留 [4]
    mstatus_mie,                  // MIE [3]
    1'b0,                         // 保留 [2]
    mstatus_sie,                  // SIE [1]
    1'b0                          // 保留 [0]
  };

  // 记录上一周期的 MRET/SRET (为应对冒险停顿后的转发)
  // 这些标志需要保持为 1, 直到导致冒险的 CSR 读真正执行
  reg exmem_is_mret_r;
  reg exmem_is_sret_r;
  reg exmem_valid_r;

  // 检测 CSR 指令何时消耗该转发
  // 仅当 CSR 读真正完成(未被异常取消)才清除
  wire mret_forward_consumed = exmem_is_mret_r && idex_is_csr && idex_valid && !exception &&
                                ((idex_csr_addr == CSR_MSTATUS) || (idex_csr_addr == CSR_SSTATUS));
  wire sret_forward_consumed = exmem_is_sret_r && idex_is_csr && idex_valid && !exception &&
                                ((idex_csr_addr == CSR_MSTATUS) || (idex_csr_addr == CSR_SSTATUS));

  always @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
      exmem_is_mret_r <= 1'b0;
      exmem_is_sret_r <= 1'b0;
      exmem_valid_r <= 1'b0;
    end else begin
      // 当 MRET/SRET 在 MEM 中时设置, 当 CSR 读消耗转发时清除
      if (mret_forward_consumed) begin
        exmem_is_mret_r <= 1'b0;  // 当转发被消耗时清除
      end else if (exmem_is_mret && exmem_valid && !exception) begin
        exmem_is_mret_r <= 1'b1;  // 当 MRET 进入 MEM 时设置
      end
      // 否则: 保持当前值 (在停顿期间保持设置)

      if (sret_forward_consumed) begin
        exmem_is_sret_r <= 1'b0;  // 当转发被消耗时清除
      end else if (exmem_is_sret && exmem_valid && !exception) begin
        exmem_is_sret_r <= 1'b1;  // 当 SRET 进入 MEM 时设置
      end
      // 否则: 保持当前值 (在停顿期间保持设置)

      exmem_valid_r <= exmem_valid;

      `ifdef DEBUG_CSR_FORWARD
      if (exmem_is_mret && exmem_valid) begin
        $display("[CSR_FORWARD] MRET in MEM: 设置 mret_r");
      end
      if (mret_forward_consumed) begin
        $display("[CSR_FORWARD] CSR 读已消耗 MRET 转发: 清除 mret_r");
      end
      if (exmem_is_mret_r && !mret_forward_consumed) begin
        $display("[CSR_FORWARD] 保持 mret_r: 等待 EX 阶段的 CSR 读");
      end
      `endif
    end
  end

  // 转发 mstatus 如果:
  // 情况 1: MRET 当前在 MEM 阶段 (同一周期 - 未发生停顿)
  // 情况 2: MRET 在上一周期在 MEM 阶段 (CSR 停顿, 现已推进)
  // 正在被读的 CSR 必须是 mstatus 或 sstatus
  wire forward_mret_mstatus = ((exmem_is_mret && exmem_valid && !exception) || exmem_is_mret_r) &&
                              (idex_is_csr && idex_valid) &&
                              ((idex_csr_addr == CSR_MSTATUS) || (idex_csr_addr == CSR_SSTATUS));

  wire forward_sret_mstatus = ((exmem_is_sret && exmem_valid && !exception) || exmem_is_sret_r) &&
                              (idex_is_csr && idex_valid) &&
                              ((idex_csr_addr == CSR_MSTATUS) || (idex_csr_addr == CSR_SSTATUS));

  // 如果 MRET/SRET 是上一周期, mstatus 已更新 - 直接使用当前值
  // 如果 MRET/SRET 是本周期, 计算更新后的值
  wire [XLEN-1:0] mstatus_after_mret = exmem_is_mret_r ? current_mstatus_reconstructed :
                                        compute_mstatus_after_mret(current_mstatus_reconstructed, mstatus_mpie);
  wire [XLEN-1:0] mstatus_after_sret = exmem_is_sret_r ? current_mstatus_reconstructed :
                                        compute_mstatus_after_sret(current_mstatus_reconstructed, mstatus_spie);

  assign ex_csr_rdata_forwarded = forward_mret_mstatus ? mstatus_after_mret :
                                  forward_sret_mstatus ? mstatus_after_sret :
                                  ex_csr_rdata;  // 正常情况: 不需要转发

  `ifdef DEBUG_CSR_FORWARD
  always @(posedge clk) begin
    if (forward_mret_mstatus || forward_sret_mstatus) begin
      $display("[CSR_FORWARD] 时间=%0t forward_mret=%b forward_sret=%b", $time, forward_mret_mstatus, forward_sret_mstatus);
      $display("[CSR_FORWARD]   current_mstatus=%h forwarded_mstatus=%h", current_mstatus_reconstructed, ex_csr_rdata_forwarded);
      $display("[CSR_FORWARD]   exmem_is_mret=%b exmem_is_sret=%b exmem_valid=%b", exmem_is_mret, exmem_is_sret, exmem_valid);
      $display("[CSR_FORWARD]   idex_is_csr=%b idex_valid=%b idex_csr_addr=%h", idex_is_csr, idex_valid, idex_csr_addr);
    end
    if (idex_is_csr && idex_valid && ((idex_csr_addr == CSR_MSTATUS) || (idex_csr_addr == CSR_SSTATUS))) begin
      $display("[CSR_FORWARD] CSR 读取: addr=%h rdata=%h (forwarded=%h)", idex_csr_addr, ex_csr_rdata, ex_csr_rdata_forwarded);
      $display("[CSR_FORWARD]   条件: exmem_mret=%b exmem_mret_r=%b exmem_valid=%b exc=%b",
               exmem_is_mret, exmem_is_mret_r, exmem_valid, exception);
      $display("[CSR_FORWARD]   forward_mret=%b forward_sret=%b", forward_mret_mstatus, forward_sret_mstatus);
    end
  end
  `endif

  //==========================================================================
  // 特权模式转发
  //==========================================================================
  // 当 MRET/SRET 在 MEM 阶段时, 它会在周期末更新 current_priv。
  // 但此时已经在前级 (IF/ID/EX) 的指令仍使用旧的 current_priv 进行
  // CSR 特权检查和异常委托判断。
  //
  // 这会导致 MRET/SRET 后紧跟 CSR 访问时行为错误:
  // - 例: MRET 将 M→S, 下一条指令访问 CSR
  // - CSR 检查仍看到旧特权=M 而不是新特权=S
  // - 委托判断出错 (M 模式陷入永不委托)
  //
  // 解决: 从 MEM 阶段向前级转发新的特权模式。

  // 计算来自 MEM 阶段 MRET/SRET 的新特权模式
  wire [1:0] mret_new_priv = mpp;              // MRET 从 MPP 恢复
  wire [1:0] sret_new_priv = {1'b0, spp};      // SRET 从 SPP 恢复 (0=U, 1=S)

  // 当 MRET/SRET 在 MEM 阶段时转发特权模式
  wire forward_priv_mode = (exmem_is_mret || exmem_is_sret) && exmem_valid && !exception;

  // EX 阶段的有效特权模式 (用于 CSR 检查和委托)
  assign effective_priv = forward_priv_mode ?
                          (exmem_is_mret ? mret_new_priv : sret_new_priv) :
                          current_priv_r;

  `ifdef DEBUG_PRIV
  always @(posedge clk) begin
    if (forward_priv_mode) begin
      $display("[PRIV_FORWARD] 时间=%0t 转发特权: %s in MEM, current_priv=%b -> effective_priv=%b",
               $time, exmem_is_mret ? "MRET" : "SRET", current_priv_r, effective_priv);
      if (idex_is_csr && idex_valid) begin
        $display("[PRIV_FORWARD]   CSR 访问在 EX: addr=0x%03x 将使用 effective_priv=%b",
                 idex_csr_addr, effective_priv);
      end
    end
  end
  `endif

endmodule
