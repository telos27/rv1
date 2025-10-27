// reservation_station.v - LR/SC Reservation Tracking
// Tracks load-reserved addresses for store-conditional validation
// Part of RV1 RISC-V CPU Core A Extension

`include "rtl/config/rv_config.vh"

module reservation_station #(
    parameter XLEN = `XLEN
) (
    input  wire clk,
    input  wire reset,

    // LR operation
    input  wire lr_valid,               // LR operation occurring
    input  wire [XLEN-1:0] lr_addr,     // Address being reserved

    // SC operation
    input  wire sc_valid,               // SC operation occurring
    input  wire [XLEN-1:0] sc_addr,     // Address for SC
    output reg  sc_success,             // SC success flag

    // Invalidation signals
    input  wire invalidate,             // Clear reservation
    input  wire [XLEN-1:0] inv_addr,    // Address being invalidated
    input  wire exception,              // Exception occurred
    input  wire interrupt               // Interrupt occurred
);

    // Reservation state
    reg reserved;                       // Reservation valid
    reg [XLEN-1:0] reserved_addr;       // Reserved address

    // Address granularity: RISC-V spec allows reservations on cache-line granularity
    // For simplicity, we use word-aligned addresses (ignore bottom 2 bits for RV32)
    // For RV64, ignore bottom 3 bits for doubleword alignment
    localparam ADDR_MASK_BITS = (XLEN == 32) ? 2 : 3;

    wire [XLEN-1:0] lr_addr_masked = lr_addr & ~((1 << ADDR_MASK_BITS) - 1);
    wire [XLEN-1:0] sc_addr_masked = sc_addr & ~((1 << ADDR_MASK_BITS) - 1);
    wire [XLEN-1:0] inv_addr_masked = inv_addr & ~((1 << ADDR_MASK_BITS) - 1);

    // Reservation logic
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            reserved <= 1'b0;
            reserved_addr <= {XLEN{1'b0}};
        end else begin
            // Priority: Invalidation > SC > LR

            // Clear reservation on exception or interrupt
            if (exception || interrupt) begin
                reserved <= 1'b0;
                `ifdef DEBUG_ATOMIC
                $display("[RESERVATION] Cleared by exception/interrupt");
                `endif
            end
            // Clear reservation on external invalidation
            else if (invalidate && reserved && (reserved_addr == inv_addr_masked)) begin
                reserved <= 1'b0;
                `ifdef DEBUG_ATOMIC
                $display("[RESERVATION] Invalidated by write to 0x%08h", inv_addr);
                `endif
            end
            // SC consumes or invalidates reservation
            else if (sc_valid) begin
                reserved <= 1'b0;  // Always clear on SC (success or fail)
                `ifdef DEBUG_ATOMIC
                $display("[RESERVATION] SC at 0x%08h, reserved=%b, match=%b -> %s",
                         sc_addr, reserved, (reserved_addr == sc_addr_masked),
                         (reserved && (reserved_addr == sc_addr_masked)) ? "SUCCESS" : "FAIL");
                `endif
            end
            // LR sets reservation
            else if (lr_valid) begin
                reserved <= 1'b1;
                reserved_addr <= lr_addr_masked;
                `ifdef DEBUG_ATOMIC
                $display("[RESERVATION] LR at 0x%08h (masked: 0x%08h)", lr_addr, lr_addr_masked);
                `endif
            end
        end
    end

    // SC success determination
    always @(*) begin
        sc_success = 1'b0;
        if (sc_valid && reserved && (reserved_addr == sc_addr_masked)) begin
            sc_success = 1'b1;
        end
    end

endmodule
