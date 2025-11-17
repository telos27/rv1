// 浮点运算单元 (FPU) - 顶层集成
// 集成 F/D 扩展的全部 10 个浮点算术单元
// 实现 IEEE 754-2008 单精度和双精度运算
// 作者: RV1 项目
// 日期: 2025-10-10
//
// FPU 支持的操作:
//   - 算术: FADD, FSUB, FMUL, FDIV, FSQRT (多周期)
//   - FMA: FMADD, FMSUB, FNMSUB, FNMADD (多周期，单次舍入)
//   - 符号注入: FSGNJ, FSGNJN, FSGNJX (1 周期)
//   - 最小/最大: FMIN, FMAX (1 周期)
//   - 比较: FEQ, FLT, FLE (1 周期，写入整数寄存器)
//   - 分类: FCLASS (1 周期，写入整数寄存器)
//   - 转换: 整数↔浮点，单精度↔双精度 (多周期)
//
// 多周期操作处理:
//   - 多周期操作期间 FPU 置位 busy 信号
//   - 当 FPU busy 时流水线必须暂停
//   - 操作完成时 FPU 产生 done 脉冲

`include "config/rv_config.vh"

module fpu #(
  parameter FLEN = `FLEN,  // 对于单精度 (F) 为 32，对于双精度 (D) 为 64
  parameter XLEN = `XLEN   // RV32 为 32，RV64 为 64
) (
  input  wire              clk,
  input  wire              reset_n,

  // 控制信号
  input  wire              start,          // 启动浮点操作
  input  wire [4:0]        fp_alu_op,      // 浮点操作码 (来自控制单元)
  input  wire [2:0]        funct3,         // funct3 字段 (比较操作: FEQ=010, FLT=001, FLE=000)
  input  wire [4:0]        rs2,            // rs2 字段 (FCVT: 00000=W, 00001=WU, 00010=L, 00011=LU)
  input  wire [6:0]        funct7,         // funct7 字段 (用于 FCVT 方向和格式)
  input  wire [2:0]        rounding_mode,  // IEEE 754 舍入模式 (来自 frm CSR 或指令)
  output wire              busy,           // FPU 忙 (多周期操作进行中)
  output wire              done,           // 操作完成 (1 周期脉冲)

  // 操作数 (来自浮点寄存器堆)
  input  wire [FLEN-1:0]   operand_a,      // rs1 (或 FMA 的被乘数)
  input  wire [FLEN-1:0]   operand_b,      // rs2 (或 FMA 的乘数)
  input  wire [FLEN-1:0]   operand_c,      // rs3 (仅 FMA 使用)

  // 整数操作数 (用于 INT→FP 转换)
  input  wire [XLEN-1:0]   int_operand,

  // 结果
  output reg  [FLEN-1:0]   fp_result,      // 浮点结果 (写回浮点寄存器堆)
  output reg  [XLEN-1:0]   int_result,     // 整数结果 (用于 FP→INT、比较、分类)

  // 异常标志 (累加到 fflags CSR)
  output reg               flag_nv,        // 无效操作
  output reg               flag_dz,        // 被零除
  output reg               flag_of,        // 上溢
  output reg               flag_uf,        // 下溢
  output reg               flag_nx         // 不精确
);

  // 浮点操作编码 (与 control.v 保持一致)
  localparam FP_ADD    = 5'b00000;
  localparam FP_SUB    = 5'b00001;
  localparam FP_MUL    = 5'b00010;
  localparam FP_DIV    = 5'b00011;
  localparam FP_SQRT   = 5'b00100;
  localparam FP_SGNJ   = 5'b00101;
  localparam FP_SGNJN  = 5'b00110;
  localparam FP_SGNJX  = 5'b00111;
  localparam FP_MIN    = 5'b01000;
  localparam FP_MAX    = 5'b01001;
  localparam FP_CVT    = 5'b01010;
  localparam FP_CMP    = 5'b01011;
  localparam FP_CLASS  = 5'b01100;
  localparam FP_FMA    = 5'b01101;
  localparam FP_FMSUB  = 5'b01110;
  localparam FP_FNMSUB = 5'b01111;
  localparam FP_FNMADD = 5'b10000;
  localparam FP_MV_XW  = 5'b10001;  // FMV.X.W (位解释 FP→INT，1 周期)
  localparam FP_MV_WX  = 5'b10010;  // FMV.W.X (位解释 INT→FP，1 周期)

  // 从 funct7[1:0] 提取格式: 00=单精度, 01=双精度
  // 对于单精度: fmt=0，对于双精度: fmt=1
  wire fmt = funct7[0];  // 第 0 位区分单精度 (0) 和双精度 (1)

  // ========================================
  // 浮点加/减单元
  // ========================================
  wire              adder_start;
  wire              adder_busy;
  wire              adder_done;
  wire [FLEN-1:0]   adder_result;
  wire              adder_flag_nv;
  wire              adder_flag_of;
  wire              adder_flag_uf;
  wire              adder_flag_nx;

  assign adder_start = start && (fp_alu_op == FP_ADD || fp_alu_op == FP_SUB);

  `ifdef DEBUG_FPU
  always @(posedge clk) begin
    if (adder_start) begin
      $display("[FPU] %s: operand_a=%h operand_b=%h",
               (fp_alu_op == FP_SUB) ? "FSUB" : "FADD", operand_a, operand_b);
    end
  end
  `endif

  fp_adder #(.FLEN(FLEN)) u_fp_adder (
    .clk            (clk),
    .reset_n        (reset_n),
    .start          (adder_start),
    .is_sub         (fp_alu_op == FP_SUB),
    .fmt            (fmt),
    .rounding_mode  (rounding_mode),
    .busy           (adder_busy),
    .done           (adder_done),
    .operand_a      (operand_a),
    .operand_b      (operand_b),
    .result         (adder_result),
    .flag_nv        (adder_flag_nv),
    .flag_of        (adder_flag_of),
    .flag_uf        (adder_flag_uf),
    .flag_nx        (adder_flag_nx)
  );

  // ========================================
  // 浮点乘法器
  // ========================================
  wire              mul_start;
  wire              mul_busy;
  wire              mul_done;
  wire [FLEN-1:0]   mul_result;
  wire              mul_flag_nv;
  wire              mul_flag_of;
  wire              mul_flag_uf;
  wire              mul_flag_nx;

  assign mul_start = start && (fp_alu_op == FP_MUL);

  fp_multiplier #(.FLEN(FLEN)) u_fp_multiplier (
    .clk            (clk),
    .reset_n        (reset_n),
    .start          (mul_start),
    .rounding_mode  (rounding_mode),
    .fmt            (fmt),
    .busy           (mul_busy),
    .done           (mul_done),
    .operand_a      (operand_a),
    .operand_b      (operand_b),
    .result         (mul_result),
    .flag_nv        (mul_flag_nv),
    .flag_of        (mul_flag_of),
    .flag_uf        (mul_flag_uf),
    .flag_nx        (mul_flag_nx)
  );

  // ========================================
  // 浮点除法器
  // ========================================
  wire              div_start;
  wire              div_busy;
  wire              div_done;
  wire [FLEN-1:0]   div_result;
  wire              div_flag_nv;
  wire              div_flag_dz;
  wire              div_flag_of;
  wire              div_flag_uf;
  wire              div_flag_nx;

  assign div_start = start && (fp_alu_op == FP_DIV);

  fp_divider #(.FLEN(FLEN)) u_fp_divider (
    .clk            (clk),
    .reset_n        (reset_n),
    .start          (div_start),
    .fmt            (fmt),
    .rounding_mode  (rounding_mode),
    .busy           (div_busy),
    .done           (div_done),
    .operand_a      (operand_a),
    .operand_b      (operand_b),
    .result         (div_result),
    .flag_nv        (div_flag_nv),
    .flag_dz        (div_flag_dz),
    .flag_of        (div_flag_of),
    .flag_uf        (div_flag_uf),
    .flag_nx        (div_flag_nx)
  );

  // ========================================
  // 浮点开方
  // ========================================
  wire              sqrt_start;
  wire              sqrt_busy;
  wire              sqrt_done;
  wire [FLEN-1:0]   sqrt_result;
  wire              sqrt_flag_nv;
  wire              sqrt_flag_nx;

  assign sqrt_start = start && (fp_alu_op == FP_SQRT);

  fp_sqrt #(.FLEN(FLEN)) u_fp_sqrt (
    .clk            (clk),
    .reset_n        (reset_n),
    .start          (sqrt_start),
    .fmt            (fmt),
    .rounding_mode  (rounding_mode),
    .busy           (sqrt_busy),
    .done           (sqrt_done),
    .operand        (operand_a),
    .result         (sqrt_result),
    .flag_nv        (sqrt_flag_nv),
    .flag_nx        (sqrt_flag_nx)
  );

  // ========================================
  // 浮点融合乘加 (FMA)
  // ========================================
  wire              fma_start;
  wire [1:0]        fma_op_type;
  wire              fma_busy;
  wire              fma_done;
  wire [FLEN-1:0]   fma_result;
  wire              fma_flag_nv;
  wire              fma_flag_of;
  wire              fma_flag_uf;
  wire              fma_flag_nx;

  assign fma_start = start && (fp_alu_op == FP_FMA || fp_alu_op == FP_FMSUB ||
                                fp_alu_op == FP_FNMSUB || fp_alu_op == FP_FNMADD);

  // 将 FP_ALU_OP 映射为 FMA 操作类型
  assign fma_op_type = (fp_alu_op == FP_FMA)    ? 2'b00 :
                       (fp_alu_op == FP_FMSUB)  ? 2'b01 :
                       (fp_alu_op == FP_FNMSUB) ? 2'b10 :
                       (fp_alu_op == FP_FNMADD) ? 2'b11 : 2'b00;

  fp_fma #(.FLEN(FLEN)) u_fp_fma (
    .clk            (clk),
    .reset_n        (reset_n),
    .start          (fma_start),
    .fmt            (fmt),
    .fma_op         (fma_op_type),
    .rounding_mode  (rounding_mode),
    .busy           (fma_busy),
    .done           (fma_done),
    .operand_a      (operand_a),  // rs1 (被乘数)
    .operand_b      (operand_b),  // rs2 (乘数)
    .operand_c      (operand_c),  // rs3 (加数)
    .result         (fma_result),
    .flag_nv        (fma_flag_nv),
    .flag_of        (fma_flag_of),
    .flag_uf        (fma_flag_uf),
    .flag_nx        (fma_flag_nx)
  );

  // ========================================
  // 浮点符号注入 (组合逻辑，1 周期)
  // ========================================
  wire [1:0]        sign_op;
  wire [FLEN-1:0]   sign_result;

  assign sign_op = (fp_alu_op == FP_SGNJ)  ? 2'b00 :
                   (fp_alu_op == FP_SGNJN) ? 2'b01 :
                   (fp_alu_op == FP_SGNJX) ? 2'b10 : 2'b00;

  fp_sign #(.FLEN(FLEN)) u_fp_sign (
    .operand_a      (operand_a),
    .operand_b      (operand_b),
    .operation      (sign_op),
    .fmt            (fmt),
    .result         (sign_result)
  );

  // ========================================
  // 浮点最小/最大 (组合逻辑，1 周期)
  // ========================================
  wire              minmax_is_max;
  wire [FLEN-1:0]   minmax_result;
  wire              minmax_flag_nv;

  assign minmax_is_max = (fp_alu_op == FP_MAX);

  fp_minmax #(.FLEN(FLEN)) u_fp_minmax (
    .operand_a      (operand_a),
    .operand_b      (operand_b),
    .is_max         (minmax_is_max),
    .fmt            (fmt),
    .result         (minmax_result),
    .flag_nv        (minmax_flag_nv)
  );

  // ========================================
  // 浮点比较 (组合逻辑，1 周期)
  // ========================================
  wire [1:0]        cmp_op;
  wire [31:0]       cmp_result;
  wire              cmp_flag_nv;

  // 按 funct3 解码比较操作
  // FEQ: funct3=010 (2) -> cmp_op=00
  // FLT: funct3=001 (1) -> cmp_op=01
  // FLE: funct3=000 (0) -> cmp_op=10
  assign cmp_op = (funct3 == 3'b010) ? 2'b00 :  // FEQ
                  (funct3 == 3'b001) ? 2'b01 :  // FLT
                  (funct3 == 3'b000) ? 2'b10 :  // FLE
                  2'b00;  // 默认: FEQ

  fp_compare #(.FLEN(FLEN)) u_fp_compare (
    .operand_a      (operand_a),
    .operand_b      (operand_b),
    .operation      (cmp_op),
    .fmt            (fmt),
    .result         (cmp_result),
    .flag_nv        (cmp_flag_nv)
  );

  // ========================================
  // 浮点分类 (组合逻辑，1 周期)
  // ========================================
  wire [31:0]       class_result;

  fp_classify #(.FLEN(FLEN)) u_fp_classify (
    .operand        (operand_a),
    .fmt            (fmt),
    .result         (class_result)
  );

  `ifdef DEBUG_FPU
  always @(posedge clk) begin
    if (start && fp_alu_op == FP_CLASS) begin
      $display("[FPU] FCLASS: operand_a=0x%h fmt=%d result=0x%03x", operand_a, fmt, class_result);
    end
  end
  `endif

  // ========================================
  // 浮点转换器 (多周期，2-3 周期)
  // ========================================
  wire              cvt_start;
  wire [3:0]        cvt_op;
  wire              cvt_busy;
  wire              cvt_done;
  wire [XLEN-1:0]   cvt_int_result;
  wire [FLEN-1:0]   cvt_fp_result;
  wire              cvt_flag_nv;
  wire              cvt_flag_of;
  wire              cvt_flag_uf;
  wire              cvt_flag_nx;

  assign cvt_start = start && (fp_alu_op == FP_CVT);

  `ifdef DEBUG_FPU_CONVERTER
  always @(posedge clk) begin
    if (start && fp_alu_op == FP_CVT) begin
      $display("[FPU] FCVT 操作开始:");
      $display("[FPU]   funct7=%b, rs2=%b, cvt_op=%b", funct7, rs2, cvt_op);
      $display("[FPU]   int_operand=0x%h, fp_operand=0x%h", int_operand, operand_a);
    end
  end
  `endif

  // 根据 funct7 和 rs2 解码转换操作
  // funct7[1:0]: 00=单精度, 01=双精度 (格式位)
  // funct7[3]: 方向 (0=FP→INT, 1=INT→FP) - BUG #17 修复: 之前错误使用 bit[6]
  // rs2[1:0]: 00=W(有符号 32 位整数), 01=WU(无符号 32 位整数), 10=L(有符号 64 位整数), 11=LU(无符号 64 位整数)
  // 对于 FP↔FP: funct7 决定方向，rs2 决定源格式
  // Bug #52 补充: 使用 funct7[6] 而不是 funct7[5] 区分 FP↔FP 与 FP↔INT
  assign cvt_op = funct7[6] ?
                    // INT↔FP 转换 (funct7 = 0x60-0x6F 有 bit 6 置位)
                    (funct7[3] ? {2'b01, rs2[1:0]} : {2'b00, rs2[1:0]}) :
                    // FP↔FP 转换 (FCVT.S.D = 1000, FCVT.D.S = 1001)
                    (funct7[0] ? 4'b1001 : 4'b1000);

  fp_converter #(.FLEN(FLEN), .XLEN(XLEN)) u_fp_converter (
    .clk            (clk),
    .reset_n        (reset_n),
    .start          (cvt_start),
    .operation      (cvt_op),
    .rounding_mode  (rounding_mode),
    .fmt            (fmt),
    .busy           (cvt_busy),
    .done           (cvt_done),
    .int_operand    (int_operand),
    .fp_operand     (operand_a),
    .int_result     (cvt_int_result),
    .fp_result      (cvt_fp_result),
    .flag_nv        (cvt_flag_nv),
    .flag_of        (cvt_flag_of),
    .flag_uf        (cvt_flag_uf),
    .flag_nx        (cvt_flag_nx)
  );

  // ========================================
  // 输出多路复用
  // ========================================

  // busy 信号: 所有多周期单元 busy 信号的或
  assign busy = adder_busy | mul_busy | div_busy | sqrt_busy | fma_busy | cvt_busy;

  // done 信号: 所有单元 done 信号的或
  assign done = adder_done | mul_done | div_done | sqrt_done | fma_done | cvt_done |
                (start && (fp_alu_op == FP_SGNJ || fp_alu_op == FP_SGNJN || fp_alu_op == FP_SGNJX ||
                           fp_alu_op == FP_MIN || fp_alu_op == FP_MAX ||
                           fp_alu_op == FP_CMP || fp_alu_op == FP_CLASS ||
                           fp_alu_op == FP_MV_XW || fp_alu_op == FP_MV_WX));

  `ifdef DEBUG_FPU_DIVIDER
  reg prev_busy;
  initial prev_busy = 0;

  always @(posedge clk) begin
    // 打印 FPU 接收到 start 信号
    if (start) begin
      $display("[FPU_START] t=%0t op=%d", $time, fp_alu_op);
    end

    // 打印 busy 变化
    if (busy != prev_busy) begin
      $display("[FPU_BUSY_CHANGE] t=%0t busy: %b->%b [add=%b mul=%b div=%b sqrt=%b fma=%b cvt=%b]",
               $time, prev_busy, busy, adder_busy, mul_busy, div_busy, sqrt_busy, fma_busy, cvt_busy);
      prev_busy <= busy;
    end

    // 打印长时间 busy 时的状态
    if (busy && ($time % 1000 == 0)) begin
      $display("[FPU_STUCK?] t=%0t busy=1 for extended time [add=%b mul=%b div=%b sqrt=%b fma=%b cvt=%b]",
               $time, adder_busy, mul_busy, div_busy, sqrt_busy, fma_busy, cvt_busy);
    end
  end
  `endif

  // 结果多路复用
  always @(*) begin
    // 默认值
    fp_result  = {FLEN{1'b0}};
    int_result = {XLEN{1'b0}};
    flag_nv = 1'b0;
    flag_dz = 1'b0;
    flag_of = 1'b0;
    flag_uf = 1'b0;
    flag_nx = 1'b0;

    case (fp_alu_op)
      FP_ADD, FP_SUB: begin
        fp_result = adder_result;
        flag_nv = adder_flag_nv;
        flag_of = adder_flag_of;
        flag_uf = adder_flag_uf;
        flag_nx = adder_flag_nx;
        `ifdef DEBUG_FPU
        if (done) $display("[FPU] FP_ADD/SUB result mux: adder_result=%h", adder_result);
        `endif
      end

      FP_MUL: begin
        fp_result = mul_result;
        flag_nv = mul_flag_nv;
        flag_of = mul_flag_of;
        flag_uf = mul_flag_uf;
        flag_nx = mul_flag_nx;
        `ifdef DEBUG_FPU
        if (done) $display("[FPU] FP_MUL result mux: mul_result=%h", mul_result);
        `endif
      end

      FP_DIV: begin
        fp_result = div_result;
        flag_nv = div_flag_nv;
        flag_dz = div_flag_dz;
        flag_of = div_flag_of;
        flag_uf = div_flag_uf;
        flag_nx = div_flag_nx;
      end

      FP_SQRT: begin
        fp_result = sqrt_result;
        flag_nv = sqrt_flag_nv;
        flag_nx = sqrt_flag_nx;
      end

      FP_FMA, FP_FMSUB, FP_FNMSUB, FP_FNMADD: begin
        fp_result = fma_result;
        flag_nv = fma_flag_nv;
        flag_of = fma_flag_of;
        flag_uf = fma_flag_uf;
        flag_nx = fma_flag_nx;
        `ifdef DEBUG_FPU
        if (done) $display("[FPU] FMA result mux: fma_result=%h op=%b", fma_result, fma_op_type);
        `endif
      end

      FP_SGNJ, FP_SGNJN, FP_SGNJX: begin
        fp_result = sign_result;
        // 符号注入不会产生异常
      end

      FP_MIN, FP_MAX: begin
        fp_result = minmax_result;
        flag_nv = minmax_flag_nv;
      end

      FP_CMP: begin
        int_result = {{(XLEN-32){1'b0}}, cmp_result};  // 零扩展到 XLEN
        flag_nv = cmp_flag_nv;
      end

      FP_CLASS: begin
        int_result = {{(XLEN-32){1'b0}}, class_result};  // 零扩展到 XLEN
        // FCLASS 从不引发异常
      end

      FP_CVT: begin
        fp_result = cvt_fp_result;
        int_result = cvt_int_result;
        flag_nv = cvt_flag_nv;
        flag_of = cvt_flag_of;
        flag_uf = cvt_flag_uf;
        flag_nx = cvt_flag_nx;
      end

      FP_MV_XW: begin
        // 位解释 FP→INT (不做数值转换，只重解释位)
        // fmt=0: FMV.X.W (移动 32 位单精度，符号扩展到 XLEN)
        // fmt=1: FMV.X.D (移动 64 位双精度，仅 RV64 有效)
        if (fmt == 0) begin
          // FMV.X.W: 符号扩展 32 位值
          int_result = {{(XLEN-32){operand_a[31]}}, operand_a[31:0]};
        end else begin
          // FMV.X.D: 复制全部 64 位（仅适用于 RV64）
          int_result = operand_a[XLEN-1:0];
        end
        // 无异常
      end

      FP_MV_WX: begin
        // 位解释 INT→FP (不做数值转换，只重解释位)
        // fmt=0: FMV.W.X (将低 32 位写入 FP 寄存器，高位 NaN-box)
        // fmt=1: FMV.D.X (将全部 64 位写入 FP 寄存器，仅 RV64 有效)
        if (fmt == 0) begin
          // FMV.W.X: Move lower 32 bits, NaN-box to FLEN
          fp_result = {{(FLEN-32){1'b1}}, int_operand[31:0]};
        end else begin
          // FMV.D.X: 复制全部 64 位（仅适用于 RV64 且 FLEN=64）
          fp_result = int_operand[FLEN-1:0];
        end
        // 无异常
      end

      default: begin
        // 非法操作 - 若控制单元正确则不应发生
        fp_result  = {FLEN{1'b0}};
        int_result = {XLEN{1'b0}};
      end
    endcase
  end

  // 调试输出
  `ifdef DEBUG_FPU
  always @(posedge clk) begin
    if (start) $display("[FPU] START: op=%0d a=%h b=%h c=%h", fp_alu_op, operand_a, operand_b, operand_c);
    if (done) $display("[FPU] DONE: op=%0d result=%h flags=%b%b%b%b%b",
                       fp_alu_op, fp_result, flag_nv, flag_dz, flag_of, flag_uf, flag_nx);
  end
  `endif

endmodule
