// atomic_unit.v - RISC-V A 扩展原子操作单元
// 实现 LR/SC 和 AMO 指令
// RV1 RISC-V CPU 内核的一部分

`include "config/rv_config.vh"

module atomic_unit #(
    parameter XLEN = `XLEN
) (
    input  wire clk,
    input  wire reset,

    // 控制
    input  wire start,                  // 开始原子操作
    input  wire [4:0] funct5,           // 原子操作类型 (funct5 字段)
    input  wire [2:0] funct3,           // 大小: 010=.W, 011=.D
    input  wire aq,                     // Acquire 顺序位
    input  wire rl,                     // Release 顺序位

    // 数据信号
    input  wire [XLEN-1:0] addr,        // 内存地址 (rs1)
    input  wire [XLEN-1:0] src_data,    // 源数据 (rs2)

    // 访存接口
    output reg  mem_req,                // 访存请求
    output reg  mem_we,                 // 访存写使能
    output reg  [XLEN-1:0] mem_addr,    // 访存地址
    output reg  [XLEN-1:0] mem_wdata,   // 写数据
    output reg  [2:0] mem_size,         // 访存大小
    input  wire [XLEN-1:0] mem_rdata,   // 读数据
    input  wire mem_ready,              // 访存就绪

    // LR/SC 保留站接口
    output reg  lr_valid,               // LR 操作有效
    output reg  [XLEN-1:0] lr_addr,     // LR 地址
    output reg  sc_valid,               // SC 操作有效
    output reg  [XLEN-1:0] sc_addr,     // SC 地址
    input  wire sc_success,             // 来自保留站的 SC 成功标志

    // 输出
    output reg  [XLEN-1:0] result,      // 写回 rd 的结果
    output reg  done,                   // 操作完成
    output reg  busy                    // 单元忙
);

    // 原子操作类型 (funct5 编码)
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

    // 状态机
    localparam STATE_IDLE    = 3'd0;
    localparam STATE_READ    = 3'd1;
    localparam STATE_WAIT_READ = 3'd2;
    localparam STATE_COMPUTE = 3'd3;
    localparam STATE_WRITE   = 3'd4;
    localparam STATE_WAIT_WRITE = 3'd5;
    localparam STATE_DONE    = 3'd6;

    reg [2:0] state, next_state;

    // 内部寄存器
    reg [XLEN-1:0] loaded_value;        // 从内存加载的值
    reg [XLEN-1:0] computed_value;      // AMO 指令计算结果
    reg [4:0] current_op;               // 当前操作
    reg [XLEN-1:0] current_addr;        // 当前地址
    reg [XLEN-1:0] current_src;         // 当前源数据
    reg [2:0] current_size;             // 当前大小
    reg current_aq, current_rl;         // 当前顺序位

    // 操作类型译码
    wire is_lr  = (current_op == ATOMIC_LR);
    wire is_sc  = (current_op == ATOMIC_SC);
    wire is_amo = !is_lr && !is_sc;

    // 大小译码 (funct3: 010=word, 011=doubleword)
    wire is_word = (current_size == 3'b010);
    wire is_dword = (current_size == 3'b011);

    // 状态机 - 时序部分
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            state <= STATE_IDLE;
        end else begin
            state <= next_state;
        end
    end

    // 状态机 - 组合部分
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
                        // LR: 读取 + 保留后完成
                        next_state = STATE_DONE;
                    end else if (is_sc) begin
                        // SC: 检查保留, 如果有效则写入
                        if (sc_success) begin
                            next_state = STATE_WRITE;
                        end else begin
                            next_state = STATE_DONE;
                        end
                    end else begin
                        // AMO: 计算后写入
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

    // 启动时捕获输入
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

    // 访存请求生成
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
                    mem_wdata = current_src;  // SC 写入 rs2 值
                end else begin
                    mem_wdata = computed_value;  // AMO 写入计算结果
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

    // 从内存加载值
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            loaded_value <= {XLEN{1'b0}};
        end else if (state == STATE_WAIT_READ && mem_ready) begin
            loaded_value <= mem_rdata;
        end
    end

    // AMO 计算逻辑
    // 对 RV64 的 word 操作, 适当掩码:
    // - 有符号比较 (MIN/MAX): 从 bit 31 符号扩展
    // - 无符号比较 (MINU/MAXU): 零扩展
    wire signed [XLEN-1:0] loaded_signed, src_signed;
    wire [XLEN-1:0] loaded_unsigned, src_unsigned;

    generate
        if (XLEN == 64) begin : gen_mask_64
            // 对有符号比较: word 操作符号扩展
            assign loaded_signed = is_word ? {{32{loaded_value[31]}}, loaded_value[31:0]} : $signed(loaded_value);
            assign src_signed = is_word ? {{32{current_src[31]}}, current_src[31:0]} : $signed(current_src);

            // 对无符号比较: word 操作零扩展
            assign loaded_unsigned = is_word ? {{32{1'b0}}, loaded_value[31:0]} : loaded_value;
            assign src_unsigned = is_word ? {{32{1'b0}}, current_src[31:0]} : current_src;
        end else begin : gen_mask_32
            assign loaded_signed = $signed(loaded_value);
            assign src_signed = $signed(current_src);
            assign loaded_unsigned = loaded_value;
            assign src_unsigned = current_src;
        end
    endgenerate

    always @(*) begin
        computed_value = loaded_value;  // 默认: 不变

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
                // 对无符号比较使用零扩展值 (处理 RV64 word 操作)
                computed_value = (loaded_unsigned < src_unsigned) ? loaded_value : current_src;
            end

            ATOMIC_MAXU: begin
                // 对无符号比较使用零扩展值 (处理 RV64 word 操作)
                computed_value = (loaded_unsigned > src_unsigned) ? loaded_value : current_src;
            end

            default: begin
                computed_value = loaded_value;
            end
        endcase
    end

    // LR/SC 保留信号
    always @(*) begin
        lr_valid = (state == STATE_WAIT_READ && mem_ready && is_lr);
        lr_addr = current_addr;
        sc_valid = (state == STATE_WAIT_READ && is_sc);
        sc_addr = current_addr;
    end

    // 结果输出
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            result <= {XLEN{1'b0}};
        end else if (state == STATE_WAIT_READ && mem_ready) begin
            if (is_lr || is_amo) begin
                // LR 和 AMO 返回加载的值
                // 对 RV64 的 word 操作, 从 bit 31 符号扩展
                if (XLEN == 64 && is_word) begin
                    result <= {{32{mem_rdata[31]}}, mem_rdata[31:0]};
                end else begin
                    result <= mem_rdata;
                end
                `ifdef DEBUG_ATOMIC
                if (is_lr) $display("[ATOMIC] LR @ 0x%08h -> 0x%08h", current_addr, mem_rdata);
                if (is_amo) $display("[ATOMIC] AMO @ 0x%08h -> 0x%08h (op=%d)", current_addr, mem_rdata, current_op);
                `endif
            end else if (is_sc) begin
                // SC 成功时返回 0, 失败时返回 1
                result <= sc_success ? {XLEN{1'b0}} : {{(XLEN-1){1'b0}}, 1'b1};
                `ifdef DEBUG_ATOMIC
                $display("[ATOMIC] SC @ 0x%08h %s (wdata=0x%08h)", current_addr, sc_success ? "SUCCESS" : "FAILED", current_src);
                `endif
            end
        end
    end

    // 控制信号
    always @(*) begin
        busy = (state != STATE_IDLE);
        done = (state == STATE_DONE);
    end

endmodule
