// atomic_unit.v - RISC-V A Extension Atomic Operations Unit
// Implements LR/SC and AMO instructions
// Part of RV1 RISC-V CPU Core

`include "rtl/config/rv_config.vh"

module atomic_unit #(
    parameter XLEN = `XLEN
) (
    input  wire clk,
    input  wire reset,

    // Control
    input  wire start,                  // Start atomic operation
    input  wire [4:0] funct5,           // Atomic operation type (funct5 field)
    input  wire [2:0] funct3,           // Size: 010=.W, 011=.D
    input  wire aq,                     // Acquire ordering bit
    input  wire rl,                     // Release ordering bit

    // Data inputs
    input  wire [XLEN-1:0] addr,        // Memory address (rs1)
    input  wire [XLEN-1:0] src_data,    // Source data (rs2)

    // Memory interface
    output reg  mem_req,                // Memory request
    output reg  mem_we,                 // Memory write enable
    output reg  [XLEN-1:0] mem_addr,    // Memory address
    output reg  [XLEN-1:0] mem_wdata,   // Memory write data
    output reg  [2:0] mem_size,         // Memory access size
    input  wire [XLEN-1:0] mem_rdata,   // Memory read data
    input  wire mem_ready,              // Memory ready

    // Reservation station interface (for LR/SC)
    output reg  lr_valid,               // LR operation valid
    output reg  [XLEN-1:0] lr_addr,     // LR address
    output reg  sc_valid,               // SC operation valid
    output reg  [XLEN-1:0] sc_addr,     // SC address
    input  wire sc_success,             // SC success flag from reservation station

    // Outputs
    output reg  [XLEN-1:0] result,      // Result to rd
    output reg  done,                   // Operation complete
    output reg  busy                    // Unit busy
);

    // Atomic operation types (funct5 encoding)
    localparam [4:0] ATOMIC_LR      = 5'b00010;
    localparam [4:0] ATOMIC_SC      = 5'b00011;
    localparam [4:0] ATOMIC_SWAP    = 5'b00001;
    localparam [4:0] ATOMIC_ADD     = 5'b00000;
    localparam [4:0] ATOMIC_XOR     = 5'b00100;
    localparam [4:0] ATOMIC_AND     = 5'b01100;
    localparam [4:0] ATOMIC_OR      = 5'b01000;
    localparam [4:0] ATOMIC_MIN     = 5'b10000;
    localparam [4:0] ATOMIC_MAX     = 5'b10100;
    localparam [4:0] ATOMIC_MINU    = 5'b11000;
    localparam [4:0] ATOMIC_MAXU    = 5'b11100;

    // State machine
    localparam STATE_IDLE    = 3'd0;
    localparam STATE_READ    = 3'd1;
    localparam STATE_WAIT_READ = 3'd2;
    localparam STATE_COMPUTE = 3'd3;
    localparam STATE_WRITE   = 3'd4;
    localparam STATE_WAIT_WRITE = 3'd5;
    localparam STATE_DONE    = 3'd6;

    reg [2:0] state, next_state;

    // Internal registers
    reg [XLEN-1:0] loaded_value;        // Value loaded from memory
    reg [XLEN-1:0] computed_value;      // Computed result for AMO
    reg [4:0] current_op;               // Current operation
    reg [XLEN-1:0] current_addr;        // Current address
    reg [XLEN-1:0] current_src;         // Current source data
    reg [2:0] current_size;             // Current size
    reg current_aq, current_rl;         // Current ordering bits

    // Decode operation type
    wire is_lr  = (current_op == ATOMIC_LR);
    wire is_sc  = (current_op == ATOMIC_SC);
    wire is_amo = !is_lr && !is_sc;

    // Size decoding (funct3: 010=word, 011=doubleword)
    wire is_word = (current_size == 3'b010);
    wire is_dword = (current_size == 3'b011);

    // State machine - sequential
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            state <= STATE_IDLE;
        end else begin
            state <= next_state;
        end
    end

    // State machine - combinational
    always @(*) begin
        next_state = state;

        case (state)
            STATE_IDLE: begin
                if (start) begin
                    next_state = STATE_READ;
                end
            end

            STATE_READ: begin
                next_state = STATE_WAIT_READ;
            end

            STATE_WAIT_READ: begin
                if (mem_ready) begin
                    if (is_lr) begin
                        // LR: Done after read + reservation
                        next_state = STATE_DONE;
                    end else if (is_sc) begin
                        // SC: Check reservation, then write if valid
                        if (sc_success) begin
                            next_state = STATE_WRITE;
                        end else begin
                            next_state = STATE_DONE;
                        end
                    end else begin
                        // AMO: Compute, then write
                        next_state = STATE_COMPUTE;
                    end
                end
            end

            STATE_COMPUTE: begin
                next_state = STATE_WRITE;
            end

            STATE_WRITE: begin
                next_state = STATE_WAIT_WRITE;
            end

            STATE_WAIT_WRITE: begin
                if (mem_ready) begin
                    next_state = STATE_DONE;
                end
            end

            STATE_DONE: begin
                next_state = STATE_IDLE;
            end

            default: begin
                next_state = STATE_IDLE;
            end
        endcase
    end

    // Capture inputs on start
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            current_op <= 5'b0;
            current_addr <= {XLEN{1'b0}};
            current_src <= {XLEN{1'b0}};
            current_size <= 3'b0;
            current_aq <= 1'b0;
            current_rl <= 1'b0;
        end else if (state == STATE_IDLE && start) begin
            current_op <= funct5;
            current_addr <= addr;
            current_src <= src_data;
            current_size <= funct3;
            current_aq <= aq;
            current_rl <= rl;
            `ifdef DEBUG_ATOMIC
            if (funct5 == ATOMIC_SC)
                $display("[ATOMIC] SC START: addr=0x%08h, src_data(rs2)=0x%08h", addr, src_data);
            else if (funct5 == ATOMIC_LR)
                $display("[ATOMIC] LR START: addr=0x%08h", addr);
            `endif
        end
    end

    // Memory request generation
    always @(*) begin
        mem_req = 1'b0;
        mem_we = 1'b0;
        mem_addr = current_addr;
        mem_wdata = {XLEN{1'b0}};
        mem_size = current_size;

        case (state)
            STATE_READ: begin
                mem_req = 1'b1;
                mem_we = 1'b0;
            end

            STATE_WAIT_READ: begin
                mem_req = 1'b1;
                mem_we = 1'b0;
            end

            STATE_WRITE: begin
                mem_req = 1'b1;
                mem_we = 1'b1;
                if (is_sc) begin
                    mem_wdata = current_src;  // SC writes rs2 value
                end else begin
                    mem_wdata = computed_value;  // AMO writes computed value
                end
            end

            STATE_WAIT_WRITE: begin
                mem_req = 1'b1;
                mem_we = 1'b1;
                if (is_sc) begin
                    mem_wdata = current_src;
                end else begin
                    mem_wdata = computed_value;
                end
            end
        endcase
    end

    // Load value from memory
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            loaded_value <= {XLEN{1'b0}};
        end else if (state == STATE_WAIT_READ && mem_ready) begin
            loaded_value <= mem_rdata;
        end
    end

    // AMO computation logic
    // Sign-extended operands for signed comparisons (declared as wires)
    wire signed [XLEN-1:0] loaded_signed;
    wire signed [XLEN-1:0] src_signed;
    assign loaded_signed = loaded_value;
    assign src_signed = current_src;

    always @(*) begin
        computed_value = loaded_value;  // Default: no change

        case (current_op)
            ATOMIC_SWAP: begin
                computed_value = current_src;
            end

            ATOMIC_ADD: begin
                computed_value = loaded_value + current_src;
            end

            ATOMIC_XOR: begin
                computed_value = loaded_value ^ current_src;
            end

            ATOMIC_AND: begin
                computed_value = loaded_value & current_src;
            end

            ATOMIC_OR: begin
                computed_value = loaded_value | current_src;
            end

            ATOMIC_MIN: begin
                computed_value = (loaded_signed < src_signed) ? loaded_value : current_src;
            end

            ATOMIC_MAX: begin
                computed_value = (loaded_signed > src_signed) ? loaded_value : current_src;
            end

            ATOMIC_MINU: begin
                computed_value = (loaded_value < current_src) ? loaded_value : current_src;
            end

            ATOMIC_MAXU: begin
                computed_value = (loaded_value > current_src) ? loaded_value : current_src;
            end

            default: begin
                computed_value = loaded_value;
            end
        endcase
    end

    // LR/SC reservation signals
    always @(*) begin
        lr_valid = (state == STATE_WAIT_READ && mem_ready && is_lr);
        lr_addr = current_addr;
        sc_valid = (state == STATE_WAIT_READ && is_sc);
        sc_addr = current_addr;
    end

    // Result output
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            result <= {XLEN{1'b0}};
        end else if (state == STATE_WAIT_READ && mem_ready) begin
            if (is_lr || is_amo) begin
                // LR and AMO return the loaded value
                result <= mem_rdata;
                `ifdef DEBUG_ATOMIC
                if (is_lr) $display("[ATOMIC] LR @ 0x%08h -> 0x%08h", current_addr, mem_rdata);
                if (is_amo) $display("[ATOMIC] AMO @ 0x%08h -> 0x%08h (op=%d)", current_addr, mem_rdata, current_op);
                `endif
            end else if (is_sc) begin
                // SC returns 0 on success, 1 on failure
                result <= sc_success ? {XLEN{1'b0}} : {{(XLEN-1){1'b0}}, 1'b1};
                `ifdef DEBUG_ATOMIC
                $display("[ATOMIC] SC @ 0x%08h %s (wdata=0x%08h)", current_addr, sc_success ? "SUCCESS" : "FAILED", current_src);
                `endif
            end
        end
    end

    // Control signals
    always @(*) begin
        busy = (state != STATE_IDLE);
        done = (state == STATE_DONE);
    end

endmodule
