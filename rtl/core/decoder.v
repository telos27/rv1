// decoder.v - RISC-V 指令译码器
// 解析指令字段并生成立即数
// 作者: RV1 Project
// 日期: 2025-10-09
// 更新: 2025-10-10 - 增加 CSR 和陷入指令支持
// 更新: 2025-10-10 - 参数化 XLEN (支持 32/64 位)

`include "config/rv_config.vh"

module decoder #(
  parameter XLEN = `XLEN  // 数据宽度: 32 或 64 位
) (
  input  wire [31:0]     instruction,   // 32 位指令 (基础 ISA 始终为 32 位)
  output wire [6:0]      opcode,        // 操作码字段
  output wire [4:0]      rd,            // 目的寄存器
  output wire [4:0]      rs1,           // 源寄存器 1
  output wire [4:0]      rs2,           // 源寄存器 2
  output wire [2:0]      funct3,        // 3 位功能字段
  output wire [6:0]      funct7,        // 7 位功能字段
  output wire [XLEN-1:0] imm_i,         // I 型立即数
  output wire [XLEN-1:0] imm_s,         // S 型立即数
  output wire [XLEN-1:0] imm_b,         // B 型立即数
  output wire [XLEN-1:0] imm_u,         // U 型立即数
  output wire [XLEN-1:0] imm_j,         // J 型立即数

  // CSR 相关输出
  output wire [11:0]     csr_addr,      // CSR 地址 (12 位)
  output wire [4:0]      csr_uimm,      // CSR 无符号立即数 (zimm[4:0])
  output wire            is_csr,        // CSR 指令
  output wire            is_ecall,      // ECALL 指令
  output wire            is_ebreak,     // EBREAK 指令
  output wire            is_mret,       // MRET 指令
  output wire            is_sret,       // SRET 指令
  output wire            is_sfence_vma, // SFENCE.VMA 指令

  // M 扩展输出
  output wire            is_mul_div,    // M 扩展指令
  output wire [3:0]      mul_div_op,    // M 扩展操作 (funct3 + 类型)
  output wire            is_word_op,    // RV64M: W 后缀指令

  // A 扩展输出
  output wire            is_atomic,     // A 扩展指令
  output wire [4:0]      funct5,        // 原子操作类型 (funct5 字段)
  output wire            aq,            // Acquire 顺序位
  output wire            rl,            // Release 顺序位

  // F/D 扩展输出
  output wire            is_fp,         // 浮点指令
  output wire            is_fp_load,    // FLW/FLD
  output wire            is_fp_store,   // FSW/FSD
  output wire            is_fp_op,      // 浮点计算指令
  output wire            is_fp_fma,     // 浮点 FMA 指令
  output wire [4:0]      rs3,           // 第三个源寄存器 (FMA 用)
  output wire [2:0]      fp_rm,         // 浮点舍入模式 (来自指令)
  output wire            fp_fmt         // 浮点格式: 0=单精度, 1=双精度
);

  // 解析指令字段
  assign opcode = instruction[6:0];
  assign rd     = instruction[11:7];
  assign funct3 = instruction[14:12];
  assign rs1    = instruction[19:15];
  assign rs2    = instruction[24:20];
  assign funct7 = instruction[31:25];

  // I 型立即数: inst[31:20]
  // 从 bit 11 符号扩展到 XLEN 位
  assign imm_i = {{(XLEN-12){instruction[31]}}, instruction[31:20]};

  // S 型立即数: {inst[31:25], inst[11:7]}
  // 从 bit 11 符号扩展到 XLEN 位
  assign imm_s = {{(XLEN-12){instruction[31]}}, instruction[31:25], instruction[11:7]};

  // B 型立即数: {inst[31], inst[7], inst[30:25], inst[11:8], 1'b0}
  // 从 bit 12 符号扩展到 XLEN 位
  // 注意: 最低位总为 0 (2 字节对齐)
  assign imm_b = {{(XLEN-13){instruction[31]}}, instruction[31], instruction[7],
                  instruction[30:25], instruction[11:8], 1'b0};

  // U 型立即数: {inst[31:12], 12'b0}
  // 高 20 位, 低 12 位为 0, 符号扩展到 XLEN 位
  assign imm_u = {{(XLEN-32){instruction[31]}}, instruction[31:12], 12'b0};

  // J 型立即数: {inst[31], inst[19:12], inst[20], inst[30:21], 1'b0}
  // 从 bit 20 符号扩展到 XLEN 位
  // 注意: 最低位总为 0 (2 字节对齐)
  assign imm_j = {{(XLEN-21){instruction[31]}}, instruction[31], instruction[19:12],
                  instruction[20], instruction[30:21], 1'b0};

  // =========================================================================
  // CSR 和系统指令检测
  // =========================================================================

  // SYSTEM 操作码 = 7'b1110011
  localparam OPCODE_SYSTEM = 7'b1110011;

  // CSR 地址位于 CSR 指令的立即数字段
  assign csr_addr = instruction[31:20];

  // CSR 无符号立即数 (zimm) 位于立即数 CSR 指令的 rs1 字段
  assign csr_uimm = instruction[19:15];

  // CSR 指令检测
  // CSR 指令具有 SYSTEM 操作码且 funct3 != 0
  // funct3 编码:
  //   001: CSRRW
  //   010: CSRRS
  //   011: CSRRC
  //   101: CSRRWI
  //   110: CSRRSI
  //   111: CSRRCI
  assign is_csr = (opcode == OPCODE_SYSTEM) && (funct3 != 3'b000);

  // ECALL 检测
  // ECALL: opcode=SYSTEM, funct3=0, funct7=0, rs1=0, rd=0, imm[11:0]=0
  assign is_ecall = (opcode == OPCODE_SYSTEM) &&
                    (funct3 == 3'b000) &&
                    (instruction[31:20] == 12'h000);

  // EBREAK 检测
  // EBREAK: opcode=SYSTEM, funct3=0, funct7=0, rs1=0, rd=0, imm[11:0]=1
  assign is_ebreak = (opcode == OPCODE_SYSTEM) &&
                     (funct3 == 3'b000) &&
                     (instruction[31:20] == 12'h001);

  // MRET 检测
  // MRET: opcode=SYSTEM, funct3=0, funct7=0x18, rs1=0, rd=0, imm[11:0]=0x302
  // 完整编码: 0011000_00010_00000_000_00000_1110011
  assign is_mret = (opcode == OPCODE_SYSTEM) &&
                   (funct3 == 3'b000) &&
                   (instruction[31:20] == 12'h302);

  // SRET 检测
  // SRET: opcode=SYSTEM, funct3=0, imm[11:0]=0x102
  // 完整编码: 0001000_00010_00000_000_00000_1110011
  assign is_sret = (opcode == OPCODE_SYSTEM) &&
                   (funct3 == 3'b000) &&
                   (instruction[31:20] == 12'h102);

  // SFENCE.VMA 检测 (TLB 刷新指令)
  // SFENCE.VMA: opcode=SYSTEM, funct3=0, funct7=0x09
  // 完整编码: 0001001_rs2_rs1_000_00000_1110011
  // rs1 和 rs2 可指定 vaddr 与 asid 进行选择性刷新
  // 全局刷新: rs1=x0, rs2=x0
  assign is_sfence_vma = (opcode == OPCODE_SYSTEM) &&
                         (funct3 == 3'b000) &&
                         (funct7 == 7'b0001001);

  // =========================================================================
  // M 扩展检测 (RV32M / RV64M)
  // =========================================================================

  // M 扩展操作码
  localparam OPCODE_OP     = 7'b0110011;  // R 型指令
  localparam OPCODE_OP_32  = 7'b0111011;  // RV64: W 后缀指令

  // M 扩展使用 OP 操作码且 funct7 = 0000001
  // RV32M: MUL, MULH, MULHSU, MULHU, DIV, DIVU, REM, REMU
  // RV64M 增加: MULW, DIVW, DIVUW, REMW, REMUW
  assign is_mul_div = ((opcode == OPCODE_OP) || (opcode == OPCODE_OP_32)) &&
                      (funct7 == 7'b0000001);

  // M 扩展操作编码在 funct3 中
  // funct3[2:0]:
  //   000: MUL/MULW
  //   001: MULH
  //   010: MULHSU
  //   011: MULHU
  //   100: DIV/DIVW
  //   101: DIVU/DIVUW
  //   110: REM/REMW
  //   111: REMU/REMUW
  assign mul_div_op = {1'b0, funct3};

  // RV64M 字操作 (带符号扩展的 32 位操作)
  // OP_32操作码表示 W 后缀指令 (MULW, DIVW, 等等)
  assign is_word_op = (opcode == OPCODE_OP_32);

  // =========================================================================
  // A 扩展检测 (RV32A / RV64A)
  // =========================================================================

  // A 扩展操作码
  localparam OPCODE_AMO = 7'b0101111;  // 原子操作

  // A 扩展检测
  assign is_atomic = (opcode == OPCODE_AMO);

  // 提取 A 扩展特定字段
  // funct5: bits [31:27] - 原子操作类型
  // aq: bit [26] - acquire 顺序
  // rl: bit [25] - release 顺序
  assign funct5 = instruction[31:27];
  assign aq = instruction[26];
  assign rl = instruction[25];

  // 注意: rs2 字段用法不同:
  // - 对 LR: rs2 必须为 0 (保留)
  // - 对 SC 和 AMO: rs2 为源数据寄存器

  // =========================================================================
  // F/D 扩展检测 (RV32F/D / RV64F/D)
  // =========================================================================

  // 浮点扩展操作码
  localparam OPCODE_LOAD_FP  = 7'b0000111;  // FLW, FLD
  localparam OPCODE_STORE_FP = 7'b0100111;  // FSW, FSD
  localparam OPCODE_MADD     = 7'b1000011;  // FMADD.S/D
  localparam OPCODE_MSUB     = 7'b1000111;  // FMSUB.S/D
  localparam OPCODE_NMSUB    = 7'b1001011;  // FNMSUB.S/D
  localparam OPCODE_NMADD    = 7'b1001111;  // FNMADD.S/D
  localparam OPCODE_OP_FP    = 7'b1010011;  // 其他所有 FP 操作

  // FP 指令检测
  assign is_fp_load  = (opcode == OPCODE_LOAD_FP);
  assign is_fp_store = (opcode == OPCODE_STORE_FP);
  assign is_fp_fma   = (opcode == OPCODE_MADD)  ||
                       (opcode == OPCODE_MSUB)  ||
                       (opcode == OPCODE_NMSUB) ||
                       (opcode == OPCODE_NMADD);
  assign is_fp_op    = (opcode == OPCODE_OP_FP);

  // 任意浮点指令
  assign is_fp = is_fp_load || is_fp_store || is_fp_fma || is_fp_op;

  // R4 格式 (FMA 指令)
  // rs3 在 [31:27]
  // funct2 (fmt) 在 [26:25]
  assign rs3 = instruction[31:27];

  // 浮点格式
  // 对 FP load/store (FLW/FLD/FSW/FSD): 格式在 funct3[1:0]
  //   - FLW/FSW: funct3=010 (bit 0=0) → 单精度
  //   - FLD/FSD: funct3=011 (bit 0=1) → 双精度
  // 对 OP-FP: 格式在 funct7[1:0] (instruction[26:25])
  // 对 FMA: 格式在 funct2 (instruction[26:25])
  // 00 = 单精度 (S)
  // 01 = 双精度 (D)
  // 10 = 保留 (H - 半精度, Zfh)
  // 11 = 保留 (Q - 四倍精度)
  wire [1:0] fmt_field = (is_fp_load || is_fp_store) ? funct3[1:0] : instruction[26:25];
  assign fp_fmt = fmt_field[0];  // 0=单精度, 1=双精度 (简化处理 F/D)

  // 浮点舍入模式
  // 对大多数 FP 指令, rm 位于 [14:12] (与 funct3 相同位置)
  // rm 编码:
  //   000: RNE (就近, 偶数舍入)
  //   001: RTZ (向零舍入)
  //   010: RDN (向下舍入)
  //   011: RUP (向上舍入)
  //   100: RMM (向最大幅值就近舍入)
  //   111: DYN (动态 - 使用 fcsr.frm)
  assign fp_rm = funct3;

  // 浮点指令格式说明
  // - R4 格式 (FMA): rs3[31:27] | fmt[26:25] | rs2[24:20] | rs1[19:15] | rm[14:12] | rd[11:7] | opcode[6:0]
  // - R 型 (FP):   funct7[31:25] (包括 fmt) | rs2[24:20] | rs1[19:15] | rm[14:12] | rd[11:7] | opcode[6:0]
  // - I 型 (FP Load): imm[31:20] | rs1[19:15] | width[14:12] | rd[11:7] | opcode[6:0]
  // - S 型 (FP Store): imm[31:25] | rs2[24:20] | rs1[19:15] | width[14:12] | imm[11:7] | opcode[6:0]

endmodule
