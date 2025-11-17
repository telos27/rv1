// plic.v - 平台级中断控制器（PLIC）
// 实现 RISC-V PLIC 规范，用于外部设备中断
// 兼容 QEMU virt 机器和 SiFive 设备
// 作者: RV1 项目组
// 日期: 2025-10-27
//
// 内存映射（基地址: 0x0C00_0000）:
//   0x000000 - 0x000FFF: 中断源优先级（1-31，每个 4 字节）
//   0x001000 - 0x001FFF: 中断挂起位（只读）
//   0x002000 - 0x00207F: M 模式 hart 0 中断使能（32 个源，4 字节）
//   0x002080 - 0x0020FF: S 模式 hart 0 中断使能（32 个源，4 字节）
//   0x200000 - 0x200003: M 模式 hart 0 优先级阈值
//   0x200004 - 0x200007: M 模式 hart 0 申请/完成寄存器
//   0x201000 - 0x201003: S 模式 hart 0 优先级阈值
//   0x201004 - 0x201007: S 模式 hart 0 申请/完成寄存器
//
// 特性:
// - 32 个中断源（0 号保留，1-31 可用）
// - 基于优先级的仲裁（1-7，0 表示永不产生中断）
// - 按 hart、按模式配置的中断使能
// - 用于中断应答的申请/完成机制
// - 支持 M 模式和 S 模式上下文

`include "config/rv_config.vh"

module plic #(
  parameter NUM_SOURCES = 32,           // 中断源数量（包括 0）
  parameter NUM_HARTS = 1,              // 硬件线程数量
  parameter BASE_ADDR = 32'h0C00_0000   // 基地址（仅供参考）
) (
  input  wire                       clk,
  input  wire                       reset_n,

  // 内存映射接口
  input  wire                       req_valid,
  input  wire [23:0]                req_addr,    // 基地址的 24 位偏移（16MB 范围）
  input  wire [31:0]                req_wdata,
  input  wire                       req_we,
  output reg                        req_ready,
  output reg  [31:0]                req_rdata,

  // 中断源输入（1-31，源 0 保留）
  input  wire [NUM_SOURCES-1:0]     irq_sources,

  // 中断输出到核心（按 hart、按模式）
  output wire [NUM_HARTS-1:0]       mei_o,        // 机器外部中断
  output wire [NUM_HARTS-1:0]       sei_o         // 监督外部中断
);

  //===========================================================================
  // 寄存器定义
  //===========================================================================

  // 中断源优先级（0-7，0 表示永不产生中断）
  // priorities[0] 保留且始终为 0
  reg [2:0] priorities [0:NUM_SOURCES-1];

  // 中断挂起位（只读，由硬件设置）
  reg [NUM_SOURCES-1:0] pending;

  // 中断使能（按 hart、按模式）
  // 对于单个 hart：enables_m[0] = M 模式，enables_s[0] = S 模式
  reg [NUM_SOURCES-1:0] enables_m [0:NUM_HARTS-1];
  reg [NUM_SOURCES-1:0] enables_s [0:NUM_HARTS-1];

  // 优先级阈值（按 hart、按模式）
  // 优先级小于等于阈值的中断被屏蔽
  reg [2:0] threshold_m [0:NUM_HARTS-1];
  reg [2:0] threshold_s [0:NUM_HARTS-1];

  // 申请/完成跟踪（按 hart、按模式）
  // 存储当前申请的中断 ID（0 表示无申请）
  reg [4:0] claimed_m [0:NUM_HARTS-1];  // 5 位表示 0-31 范围
  reg [4:0] claimed_s [0:NUM_HARTS-1];

  //===========================================================================
  // 地址解码
  //===========================================================================

  // PLIC 内存映射区域
  localparam ADDR_PRIORITIES    = 24'h000000;  // 0x000000 - 0x00007F (32 sources × 4B)
  localparam ADDR_PENDING       = 24'h001000;  // 0x001000 - 0x001003 (1 word for 32 bits)
  localparam ADDR_ENABLE_M      = 24'h002000;  // 0x002000 - 0x002003 (1 word for hart 0 M-mode)
  localparam ADDR_ENABLE_S      = 24'h002080;  // 0x002080 - 0x002083 (1 word for hart 0 S-mode)
  localparam ADDR_THRESHOLD_M   = 24'h200000;  // 0x200000 - 0x200003 (hart 0 M-mode)
  localparam ADDR_CLAIM_M       = 24'h200004;  // 0x200004 - 0x200007 (hart 0 M-mode)
  localparam ADDR_THRESHOLD_S   = 24'h201000;  // 0x201000 - 0x201003 (hart 0 S-mode)
  localparam ADDR_CLAIM_S       = 24'h201004;  // 0x201004 - 0x201007 (hart 0 S-mode)

  wire is_priority;
  wire is_pending;
  wire is_enable_m;
  wire is_enable_s;
  wire is_threshold_m;
  wire is_claim_m;
  wire is_threshold_s;
  wire is_claim_s;

  wire [4:0] priority_id;  // 哪个中断源的优先级（0-31）

  // 解码地址
  assign is_priority    = (req_addr < 24'h001000);  // 0x000000 - 0x000FFF
  assign is_pending     = (req_addr == ADDR_PENDING);
  assign is_enable_m    = (req_addr == ADDR_ENABLE_M);
  assign is_enable_s    = (req_addr == ADDR_ENABLE_S);
  assign is_threshold_m = (req_addr == ADDR_THRESHOLD_M);
  assign is_claim_m     = (req_addr == ADDR_CLAIM_M);
  assign is_threshold_s = (req_addr == ADDR_THRESHOLD_S);
  assign is_claim_s     = (req_addr == ADDR_CLAIM_S);

  // 计算优先级访问的源 ID（地址 / 4）
  assign priority_id = req_addr[6:2];  // 地址右移 2 位得到源 ID

  //===========================================================================
  // 中断挂起逻辑
  //===========================================================================

  integer i;

  always @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
      pending <= {NUM_SOURCES{1'b0}};
    end else begin
      // 根据中断源更新挂起位
      // 源 0 始终为 0（保留）
      pending[0] <= 1'b0;
      for (i = 1; i < NUM_SOURCES; i = i + 1) begin
        // 如果源处于活动状态，则设置挂起
        if (irq_sources[i] && !pending[i]) begin
          pending[i] <= 1'b1;
        end
        // 如果中断被认领，则清除挂起（在认领逻辑中处理）
      end
    end
  end

  //===========================================================================
  // 优先级仲裁（查找最高优先级挂起中断）
  //===========================================================================

  // 对于 M 模式 hart 0
  reg [4:0] highest_id_m;
  reg [2:0] highest_pri_m;

  // 对于 S 模式 hart 0
  reg [4:0] highest_id_s;
  reg [2:0] highest_pri_s;

  always @(*) begin
    // M 模式仲裁
    highest_id_m = 5'd0;
    highest_pri_m = 3'd0;

    for (i = 1; i < NUM_SOURCES; i = i + 1) begin
      if (pending[i] && enables_m[0][i] && (priorities[i] > threshold_m[0])) begin
        if (priorities[i] > highest_pri_m) begin
          highest_id_m = i[4:0];
          highest_pri_m = priorities[i];
        end
      end
    end

    // S 模式仲裁
    highest_id_s = 5'd0;
    highest_pri_s = 3'd0;

    for (i = 1; i < NUM_SOURCES; i = i + 1) begin
      if (pending[i] && enables_s[0][i] && (priorities[i] > threshold_s[0])) begin
        if (priorities[i] > highest_pri_s) begin
          highest_id_s = i[4:0];
          highest_pri_s = priorities[i];
        end
      end
    end
  end

  //===========================================================================
  // 中断输出生成
  //===========================================================================

  // 如果有挂起的中断，断言 M 模式中断输出
  assign mei_o[0] = (highest_id_m != 5'd0);

  // 如果有挂起的中断，断言 S 模式中断输出
  assign sei_o[0] = (highest_id_s != 5'd0);

  //===========================================================================
  // 内存映射寄存器访问
  //===========================================================================

  always @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
      // 复位所有配置寄存器
      for (i = 0; i < NUM_SOURCES; i = i + 1) begin
        priorities[i] <= 3'd0;
      end
      for (i = 0; i < NUM_HARTS; i = i + 1) begin
        enables_m[i] <= {NUM_SOURCES{1'b0}};
        enables_s[i] <= {NUM_SOURCES{1'b0}};
        threshold_m[i] <= 3'd0;
        threshold_s[i] <= 3'd0;
        claimed_m[i] <= 5'd0;
        claimed_s[i] <= 5'd0;
      end
      req_rdata <= 32'h0;
      req_ready <= 1'b0;
    end else begin
      req_ready <= req_valid;  // 单周期响应

      if (req_valid && req_we) begin
        //=====================================================================
        // 写操作
        //=====================================================================

        if (is_priority && priority_id < NUM_SOURCES && priority_id != 0) begin
          // 写入中断源优先级（源 0 是只读的）
          priorities[priority_id] <= req_wdata[2:0];  // 3-bit priority
        end else if (is_enable_m) begin
          // 写入 M 模式中断使能（hart 0）
          enables_m[0] <= req_wdata[NUM_SOURCES-1:0];
        end else if (is_enable_s) begin
          // 写入 S 模式中断使能（hart 0）
          enables_s[0] <= req_wdata[NUM_SOURCES-1:0];
        end else if (is_threshold_m) begin
          // 写入 M 模式优先级阈值（hart 0）
          threshold_m[0] <= req_wdata[2:0];
        end else if (is_threshold_s) begin
          // 写入 S 模式优先级阈值（hart 0）
          threshold_s[0] <= req_wdata[2:0];
        end else if (is_claim_m) begin
          // 完成 M 模式中断（写回已声明的 ID）
          if (req_wdata[4:0] == claimed_m[0] && claimed_m[0] != 5'd0) begin
            pending[claimed_m[0]] <= 1'b0;  // 清除挂起位
            claimed_m[0] <= 5'd0;           // 清除已声明的 ID
          end
        end else if (is_claim_s) begin
          // 完成 S 模式中断（写回已声明的 ID）
          if (req_wdata[4:0] == claimed_s[0] && claimed_s[0] != 5'd0) begin
            pending[claimed_s[0]] <= 1'b0;  // 清除挂起位
            claimed_s[0] <= 5'd0;           // 清除已声明的 ID
          end
        end
        // 挂起寄存器是只读的，写操作被忽略

        req_rdata <= 32'h0;  // 写操作不返回数据

      end else if (req_valid && !req_we) begin
        //=====================================================================
        // 读操作
        //=====================================================================

        if (is_priority && priority_id < NUM_SOURCES) begin
          // 读取中断源优先级
          req_rdata <= {29'h0, priorities[priority_id]};
        end else if (is_pending) begin
          // 读取中断挂起位（所有 32 个源在 1 个字中）
          req_rdata <= pending;
        end else if (is_enable_m) begin
          // 读取 M 模式中断使能（hart 0）
          req_rdata <= enables_m[0];
        end else if (is_enable_s) begin
          // 读取 S 模式中断使能（hart 0）
          req_rdata <= enables_s[0];
        end else if (is_threshold_m) begin
          // 读取 M 模式优先级阈值（hart 0）
          req_rdata <= {29'h0, threshold_m[0]};
        end else if (is_threshold_s) begin
          // 读取 S 模式优先级阈值（hart 0）
          req_rdata <= {29'h0, threshold_s[0]};
        end else if (is_claim_m) begin
          // 申领 M 模式中断（返回最高优先级挂起 ID）
          req_rdata <= {27'h0, highest_id_m};
          if (highest_id_m != 5'd0) begin
            claimed_m[0] <= highest_id_m;  // 记录已申领的中断
            // 不要立即清除挂起位 - 等待完成写操作
          end
        end else if (is_claim_s) begin
          // 申领 S 模式中断（返回最高优先级挂起 ID）
          req_rdata <= {27'h0, highest_id_s};
          if (highest_id_s != 5'd0) begin
            claimed_s[0] <= highest_id_s;  // 记录已申领的中断
            // 不要立即清除挂起位 - 等待完成写操作
          end
        end else begin
          // 无效地址
          req_rdata <= 32'h0;
        end

      end else begin
        req_rdata <= 32'h0;
      end
    end
  end

  //===========================================================================
  // 调试监控（可选）
  //===========================================================================

  `ifdef DEBUG_PLIC
  always @(posedge clk) begin
    if (req_valid) begin
      if (req_we) begin
        if (is_priority)
          $display("PLIC[@%t]: WRITE Priority[%0d] = %0d", $time, priority_id, req_wdata[2:0]);
        if (is_enable_m)
          $display("PLIC[@%t]: WRITE Enable_M = 0x%08h", $time, req_wdata);
        if (is_enable_s)
          $display("PLIC[@%t]: WRITE Enable_S = 0x%08h", $time, req_wdata);
        if (is_threshold_m)
          $display("PLIC[@%t]: WRITE Threshold_M = %0d", $time, req_wdata[2:0]);
        if (is_threshold_s)
          $display("PLIC[@%t]: WRITE Threshold_S = %0d", $time, req_wdata[2:0]);
        if (is_claim_m)
          $display("PLIC[@%t]: COMPLETE M-mode IRQ %0d", $time, req_wdata[4:0]);
        if (is_claim_s)
          $display("PLIC[@%t]: COMPLETE S-mode IRQ %0d", $time, req_wdata[4:0]);
      end else begin
        if (is_claim_m && highest_id_m != 0)
          $display("PLIC[@%t]: CLAIM M-mode IRQ %0d", $time, highest_id_m);
        if (is_claim_s && highest_id_s != 0)
          $display("PLIC[@%t]: CLAIM S-mode IRQ %0d", $time, highest_id_s);
      end
    end
    if (mei_o[0])
      $display("PLIC[@%t]: MEI asserted (IRQ %0d, pri %0d)", $time, highest_id_m, highest_pri_m);
    if (sei_o[0])
      $display("PLIC[@%t]: SEI asserted (IRQ %0d, pri %0d)", $time, highest_id_s, highest_pri_s);
  end
  `endif

endmodule
