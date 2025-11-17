// reservation_station.v - LR/SC 保留跟踪单元
// 跟踪 load-reserved 地址以用于 store-conditional 成功性检查
// 属于 RV1 RISC-V CPU 核心 A 扩展

`include "rtl/config/rv_config.vh"

module reservation_station #(
    parameter XLEN = `XLEN
) (
    input  wire clk,
    input  wire reset,

    // LR 操作
    input  wire lr_valid,               // 正在执行 LR 操作
    input  wire [XLEN-1:0] lr_addr,     // 要被保留的地址

    // SC 操作
    input  wire sc_valid,               // 正在执行 SC 操作
    input  wire [XLEN-1:0] sc_addr,     // SC 目标地址
    output reg  sc_success,             // SC 成功标志

    // 失效/清除信号
    input  wire invalidate,             // 清除保留
    input  wire [XLEN-1:0] inv_addr,    // 被失效的地址
    input  wire exception,              // 发生异常
    input  wire interrupt               // 发生中断
);

    // 保留状态
    reg reserved;                       // 当前是否存在有效保留
    reg [XLEN-1:0] reserved_addr;       // 已保留的地址

    // 地址粒度：RISC-V 允许按 cache 行粒度保留
    // 为简化起见，使用按字对齐的地址（RV32 忽略最低 2 位）
    // 对于 RV64，使用双字对齐（忽略最低 3 位）
    localparam ADDR_MASK_BITS = (XLEN == 32) ? 2 : 3;

    wire [XLEN-1:0] lr_addr_masked  = lr_addr  & ~((1 << ADDR_MASK_BITS) - 1);
    wire [XLEN-1:0] sc_addr_masked  = sc_addr  & ~((1 << ADDR_MASK_BITS) - 1);
    wire [XLEN-1:0] inv_addr_masked = inv_addr & ~((1 << ADDR_MASK_BITS) - 1);

    // 保留逻辑
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            reserved      <= 1'b0;
            reserved_addr <= {XLEN{1'b0}};
        end else begin
            // 优先级：失效/异常/中断 > SC > LR

            // 异常或中断时清除保留
            if (exception || interrupt) begin
                reserved <= 1'b0;
                `ifdef DEBUG_ATOMIC
                $display("[RESERVATION] Cleared by exception/interrupt");
                `endif
            end
            // 外部写导致的保留失效
            else if (invalidate && reserved && (reserved_addr == inv_addr_masked)) begin
                reserved <= 1'b0;
                `ifdef DEBUG_ATOMIC
                $display("[RESERVATION] Invalidated by write to 0x%08h", inv_addr);
                `endif
            end
            // SC 消耗或清除保留
            else if (sc_valid) begin
                reserved <= 1'b0;  // 无论 SC 成功或失败，均清除当前保留
                `ifdef DEBUG_ATOMIC
                $display("[RESERVATION] SC at 0x%08h, reserved=%b, match=%b -> %s",
                         sc_addr, reserved, (reserved_addr == sc_addr_masked),
                         (reserved && (reserved_addr == sc_addr_masked)) ? "SUCCESS" : "FAIL");
                `endif
            end
            // LR 设置保留
            else if (lr_valid) begin
                reserved      <= 1'b1;
                reserved_addr <= lr_addr_masked;
                `ifdef DEBUG_ATOMIC
                $display("[RESERVATION] LR at 0x%08h (masked: 0x%08h)", lr_addr, lr_addr_masked);
                `endif
            end
        end
    end

    // SC 成功判定逻辑
    always @(*) begin
        sc_success = 1'b0;
        if (sc_valid && reserved && (reserved_addr == sc_addr_masked)) begin
            sc_success = 1'b1;
        end
    end

endmodule
