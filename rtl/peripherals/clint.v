// clint.v - 核心本地中断控制器 (CLINT)
// 实现 RISC-V CLINT 规范中的定时器和软件中断
// 兼容 QEMU virt 机器和 SiFive 设备
// 作者: RV1 项目组
// 日期: 2025-10-26
//
// 内存映射 (基地址: 0x0200_0000):
//   0x0000 - 0x3FFF: MSIP (机器软件中断挂起寄存器) - 每个 hart 4 字节
//   0x4000 - 0xBFF7: MTIMECMP (机器定时器比较寄存器) - 每个 hart 8 字节
//   0xBFF8 - 0xBFFF: MTIME (机器时间计数器) - 共享 8 字节
//
// 特性:
// - 64 位实时时间计数器 (MTIME)
// - 每个 hart 的定时器比较寄存器 (MTIMECMP)
// - 每个 hart 的软件中断 (MSIP)
// - 当 MTIME >= MTIMECMP 时产生定时器中断
// - 小端序内存访问

`include "config/rv_config.vh"

module clint #(
  parameter NUM_HARTS = 1,                    // 硬件线程数量
  parameter BASE_ADDR = 32'h0200_0000         // 基地址（仅供参考）
) (
  input  wire                       clk,
  input  wire                       reset_n,

  // 内存映射接口
  input  wire                       req_valid,
  input  wire [15:0]                req_addr,    // 基地址的 16 位偏移（64KB 范围）
  input  wire [63:0]                req_wdata,
  input  wire                       req_we,
  input  wire [2:0]                 req_size,    // 0=字节, 1=半字, 2=字, 3=双字
  output wire                       req_ready,   // 组合逻辑 - 始终准备好
  output reg  [63:0]                req_rdata,

  // 中断输出（每个 hart 一个）
  output wire [NUM_HARTS-1:0]       mti_o,       // 机器定时器中断
  output wire [NUM_HARTS-1:0]       msi_o        // 机器软件中断
);

  //===========================================================================
  // 寄存器定义
  //===========================================================================

  // MTIME: 64 位实时时间计数器（所有 hart 共享）
  // 每个时钟周期递增
  reg [63:0] mtime;

  // MTIMECMP: 64 位定时器比较寄存器（每个 hart 一个）
  // 当 mtime >= mtimecmp[i] 时，断言 mti_o[i]
  reg [63:0] mtimecmp [0:NUM_HARTS-1];

  // MSIP: 机器软件中断挂起（每个 hart 一个）
  // 软件写 1 触发中断，写 0 清除
  reg [NUM_HARTS-1:0] msip;

  //===========================================================================
  // 地址解码
  //===========================================================================

  // CLINT 内存映射偏移:
  localparam MSIP_BASE     = 16'h0000;  // 0x0000 - 0x3FFF (每个 hart 4 字节)
  localparam MTIMECMP_BASE = 16'h4000;  // 0x4000 - 0xBFF7 (每个 hart 8 字节)
  localparam MTIME_ADDR    = 16'hBFF8;  // 0xBFF8 - 0xBFFF (8 字节，共享)

  wire is_msip;
  wire is_mtimecmp;
  wire is_mtime;
  wire [7:0] hart_id;          // 用于访问 MSIP/MTIMECMP 的硬件线程 ID
  wire [3:0] mtimecmp_offset;  // MTIMECMP 数组内部偏移量

  // 解码正在访问的是哪个寄存器
  // 优先匹配 MTIME（最具体），然后是 MTIMECMP，最后是 MSIP
  assign is_mtime    = (req_addr[15:3] == 13'h17FF);  // 0xBFF8-0xBFFF（检查高 13 位）
  assign is_mtimecmp = (req_addr >= 16'h4000) && (req_addr[15:3] != 13'h17FF);  // 0x4000-0xBFF7
  assign is_msip     = (req_addr < 16'h4000);  // 0x0000-0x3FFF

  // 从地址计算 hart ID
  // MSIP：从 0x0000 开始，每个 hart 占 4 字节
  // MTIMECMP：从 0x4000 开始，每个 hart 占 8 字节
  assign hart_id = is_msip ? (req_addr - MSIP_BASE) >> 2 :           // MSIP：按 4 字节对齐取 hart ID
                   is_mtimecmp ? (req_addr - MTIMECMP_BASE) >> 3 :   // MTIMECMP：按 8 字节对齐取 hart ID
                   8'h0;

  // 计算 MTIMECMP 访问的偏移（8 字节寄存器中的 0-7 字节）
  assign mtimecmp_offset = req_addr[2:0] - 4'h0;  // 在单个 8 字节 MTIMECMP 寄存器内的偏移

  //===========================================================================
  // MTIME 计数器 (自由运行)
  //===========================================================================

  // mtime 的预分频器 - 每 N 个时钟周期递增一次
  // 在真实系统中：mtime 以固定频率运行（1-10 MHz），而不是 CPU 频率
  // 对于 50 MHz 的 CPU 且 mtime 为 1 MHz：预分频值 = 50
  // FreeRTOS 期望 mtime 频率 = CPU 频率，因此预分频值 = 1
  localparam MTIME_PRESCALER = 1;
  reg [7:0] mtime_prescaler_count;

  always @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
      mtime <= 64'h0;
      mtime_prescaler_count <= 8'h0;
    end else begin
      // 每 MTIME_PRESCALER 个周期递增 MTIME
      // 软件也可以写入 MTIME（通常只在启动时）
      if (req_valid && req_we && is_mtime) begin
        // 允许写入 MTIME（用于初始化）
        case (req_size)
          3'h3: mtime <= req_wdata; // 64 位写入
          3'h2: begin               // 32 位写入
            if (req_addr[2] == 1'b0)
              mtime[31:0] <= req_wdata[31:0];   // 低 32 位
            else
              mtime[63:32] <= req_wdata[31:0];  // 高 32 位
          end
          default: begin
            // 字节/半字写入对 MTIME 不常见，但支持它们
            if (req_addr[2:0] == 3'h0) mtime[7:0]   <= req_wdata[7:0];
            if (req_addr[2:0] == 3'h1) mtime[15:8]  <= req_wdata[7:0];
            if (req_addr[2:0] == 3'h2) mtime[23:16] <= req_wdata[7:0];
            if (req_addr[2:0] == 3'h3) mtime[31:24] <= req_wdata[7:0];
            if (req_addr[2:0] == 3'h4) mtime[39:32] <= req_wdata[7:0];
            if (req_addr[2:0] == 3'h5) mtime[47:40] <= req_wdata[7:0];
            if (req_addr[2:0] == 3'h6) mtime[55:48] <= req_wdata[7:0];
            if (req_addr[2:0] == 3'h7) mtime[63:56] <= req_wdata[7:0];
          end
        endcase
        mtime_prescaler_count <= 8'h0;  // 写入时重置预分频器
      end else begin
        // 正常操作：每 MTIME_PRESCALER 个周期递增一次
        if (mtime_prescaler_count == MTIME_PRESCALER - 1) begin
          mtime <= mtime + 64'h1;
          mtime_prescaler_count <= 8'h0;
        end else begin
          mtime_prescaler_count <= mtime_prescaler_count + 8'h1;
        end
      end
    end
  end

  //===========================================================================
  // MTIMECMP 寄存器（每个 hart 一个）
  //===========================================================================

  integer i;

  always @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
      for (i = 0; i < NUM_HARTS; i = i + 1) begin
        mtimecmp[i] <= 64'hFFFF_FFFF_FFFF_FFFF;  // 初始化为最大值（无中断）
      end
    end else begin
      // 处理对 MTIMECMP 的写入
      if (req_valid && req_we && is_mtimecmp && (hart_id < NUM_HARTS)) begin
        `ifdef DEBUG_CLINT
        $display("MTIMECMP WRITE: hart_id=%0d data=0x%016h (addr=0x%04h)", hart_id, req_wdata, req_addr);
        `endif
        case (req_size)
          3'h3: begin  // 64 位写入
            mtimecmp[hart_id] <= req_wdata;
          end
          3'h2: begin  // 32 位写入
            if (req_addr[2] == 1'b0)
              mtimecmp[hart_id][31:0] <= req_wdata[31:0];    // 低 32 位
            else
              mtimecmp[hart_id][63:32] <= req_wdata[31:0];   // 高 32 位
          end
          3'h1: begin  // 16 位写入
            case (req_addr[2:1])
              2'h0: mtimecmp[hart_id][15:0]  <= req_wdata[15:0];
              2'h1: mtimecmp[hart_id][31:16] <= req_wdata[15:0];
              2'h2: mtimecmp[hart_id][47:32] <= req_wdata[15:0];
              2'h3: mtimecmp[hart_id][63:48] <= req_wdata[15:0];
            endcase
          end
          3'h0: begin  // 8 位写入
            case (req_addr[2:0])
              3'h0: mtimecmp[hart_id][7:0]   <= req_wdata[7:0];
              3'h1: mtimecmp[hart_id][15:8]  <= req_wdata[7:0];
              3'h2: mtimecmp[hart_id][23:16] <= req_wdata[7:0];
              3'h3: mtimecmp[hart_id][31:24] <= req_wdata[7:0];
              3'h4: mtimecmp[hart_id][39:32] <= req_wdata[7:0];
              3'h5: mtimecmp[hart_id][47:40] <= req_wdata[7:0];
              3'h6: mtimecmp[hart_id][55:48] <= req_wdata[7:0];
              3'h7: mtimecmp[hart_id][63:56] <= req_wdata[7:0];
            endcase
          end
        endcase
      end
    end
  end

  //===========================================================================
  // MSIP 寄存器（软件中断挂起）
  //===========================================================================

  always @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
      msip <= {NUM_HARTS{1'b0}};
    end else begin
      // 处理对 MSIP 的写入
      if (req_valid && req_we && is_msip && (hart_id < NUM_HARTS)) begin
        // 仅位 0 可写，其余为保留位
        msip[hart_id] <= req_wdata[0];
      end
    end
  end

  //===========================================================================
  // 内存读取逻辑
  //===========================================================================

  // CLINT 始终准备好处理请求（组合响应）
  assign req_ready = req_valid;

  always @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
      req_rdata <= 64'h0;
    end else begin
      if (req_valid && !req_we) begin
        // 处理读取
        if (is_mtime) begin
          // 读取 MTIME（64 位）
          req_rdata <= mtime;
        end else if (is_mtimecmp && (hart_id < NUM_HARTS)) begin
          // 读取特定 hart 的 MTIMECMP
          req_rdata <= mtimecmp[hart_id];
          `ifdef DEBUG_CLINT
          $display("MTIMECMP READ: hart_id=%0d data=0x%016h (addr=0x%04h)",  hart_id, mtimecmp[hart_id], req_addr);
          `endif
        end else if (is_msip && (hart_id < NUM_HARTS)) begin
          // 读取特定 hart 的 MSIP（仅位 0 有效）
          req_rdata <= {63'h0, msip[hart_id]};
        end else begin
          // 无效地址或超出范围的 hart ID
          req_rdata <= 64'h0;
        end
      end else if (req_valid && req_we) begin
        // 写操作不返回数据，但设置 ready
        req_rdata <= 64'h0;
      end else begin
        req_rdata <= 64'h0;
      end
    end
  end

  //===========================================================================
  // 中断生成逻辑
  //===========================================================================

  // 为每个 hart 生成定时器中断
  // 当 mtime >= mtimecmp[i] 时，MTI[i] 被断言
  genvar g;
  generate
    for (g = 0; g < NUM_HARTS; g = g + 1) begin : gen_interrupts
      assign mti_o[g] = (mtime >= mtimecmp[g]);
    end
  endgenerate

  // 软件中断由 MSIP 寄存器直接驱动
  assign msi_o = msip;

  // 调试中断生成
  `ifdef DEBUG_CLINT
  always @(posedge clk) begin
    if (mtime % 100 == 0 && mtime > 0 && mtime < 1000) begin
      $display("[CLINT] mtime=%0d mtimecmp[0]=%0d mti_o[0]=%b", mtime, mtimecmp[0], mti_o[0]);
    end
    if (mti_o[0] && mtime < 1000) begin
      $display("[CLINT] TIMER INTERRUPT ASSERTED: mtime=%0d >= mtimecmp[0]=%0d", mtime, mtimecmp[0]);
    end
    // 在 FreeRTOS 初始化期间定期调试 mtime 值
    if (mtime % 10000 == 0 && mtime >= 50000 && mtime <= 150000) begin
      $display("[CLINT_MTIME] cycle=%0d mtime=%0d (0x%h)", mtime, mtime, mtime);
    end
  end
  `endif

  //===========================================================================
  // 调试监控（可选）
  //===========================================================================

  `ifdef DEBUG_CLINT
  // 调试监控（Icarus Verilog 兼容）
  always @(posedge clk) begin
    if (req_valid) begin
      $display("[CLINT-REQ] Cycle %0d: req_valid=%b addr=0x%04h we=%b wdata=0x%016h size=%0d ready=%b | is_mtime=%b is_mtimecmp=%b is_msip=%b hart_id=%0d",
               $time/10, req_valid, req_addr, req_we, req_wdata, req_size, req_ready, is_mtime, is_mtimecmp, is_msip, hart_id);
    end
    if (req_valid && req_we && is_mtime) begin
      $display("  -> MTIME WRITE: 0x%016h (cycle %0d)", req_wdata, $time/10);
    end
    if (req_valid && req_we && is_mtimecmp) begin
      $display("  -> MTIMECMP[%0d] WRITE: 0x%016h size=%0d addr[2]=%b (cycle %0d) | mtime=%0d | mtimecmp_before=0x%016h", hart_id, req_wdata, req_size, req_addr[2], $time/10, mtime, mtimecmp[hart_id]);
    end
  end

  // 显示写入完成后的 MTIMECMP 值
  always @(posedge clk) begin
    if (req_valid && req_we && is_mtimecmp && req_ready) begin
      $display("  -> MTIMECMP[%0d] AFTER WRITE: 0x%016h (cycle %0d)", hart_id, mtimecmp[hart_id], $time/10);
    end
    // 监控定时器中断触发
    if (mtime >= 53800 && mtime <= 54000) begin
      $display("[CLINT-TIMER] mtime=%0d mtimecmp[0]=0x%016h mti_o[0]=%b (cycle %0d)", mtime, mtimecmp[0], mti_o[0], $time/10);
    end
    if (req_valid && req_we && is_msip) begin
      $display("  -> MSIP[%0d] WRITE: %b (cycle %0d)", hart_id, req_wdata[0], $time/10);
    end
  end
  `endif

endmodule
