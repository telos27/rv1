// rv_core_pipelined.v - 五级流水线 RISC-V 处理器内核
// 实现经典 RISC 流水线：IF -> ID -> EX -> MEM -> WB
// 包含数据前递与冒险检测
// 参数化以支持 RV32/RV64
// 作者：RV1 项目
// 日期：2025-10-10

`include "config/rv_config.vh"
`include "config/rv_csr_defines.vh"

module rv_core_pipelined #(
  parameter XLEN = `XLEN,
  parameter RESET_VECTOR = {XLEN{1'b0}},
  parameter IMEM_SIZE = 4096,
  parameter DMEM_SIZE = 16384,
  parameter MEM_FILE = ""
) (
  input  wire             clk,
  input  wire             reset_n,

  // 外部中断输入（来自 CLINT/PLIC）
  input  wire             mtip_in,       // 机器定时器中断挂起
  input  wire             msip_in,       // 机器软件中断挂起
  input  wire             meip_in,       // 机器外部中断挂起（来自 PLIC）
  input  wire             seip_in,       // 监管级外部中断挂起（来自 PLIC）

  // 总线主机接口（连接到存储器互连）
  output wire             bus_req_valid,
  output wire [XLEN-1:0]  bus_req_addr,
  output wire [63:0]      bus_req_wdata,
  output wire             bus_req_we,
  output wire [2:0]       bus_req_size,
  input  wire             bus_req_ready,
  input  wire [63:0]      bus_req_rdata,

  output wire [XLEN-1:0]  pc_out,        // 调试用当前 PC
  output wire [31:0]      instr_out      // 调试用当前指令（始终为 32 位）
);

  //==========================================================================
  // 流水线控制信号
  //==========================================================================
  wire stall_pc;           // PC 停顿信号（来自冒险检测）
  wire stall_ifid;         // IF/ID 寄存器停顿信号
  wire flush_ifid;         // IF/ID 寄存器刷新信号（分支错误预测）
  wire flush_idex;         // ID/EX 寄存器刷新信号（气泡插入或分支）
  wire flush_idex_hazard;  // 来自冒险检测的刷新信号（加载-使用）
  // ID 阶段前递控制信号
  wire [2:0] id_forward_a;       // ID 阶段 rs1 的前递选择（3'b100=EX，3'b010=MEM，3'b001=WB，3'b000=NONE）
  wire [2:0] id_forward_b;       // ID 阶段 rs2 的前递选择
  wire [2:0] id_fp_forward_a;    // ID 阶段浮点 rs1 的前递选择
  wire [2:0] id_fp_forward_b;    // ID 阶段浮点 rs2 的前递选择
  wire [2:0] id_fp_forward_c;    // ID 阶段浮点 rs3 的前递选择

  // EX 阶段前递控制信号
  wire [1:0] forward_a;          // EX 阶段 ALU 操作数 A 的前递选择（2'b10=来自 MEM，2'b01=来自 WB，2'b00=无前递）
  wire [1:0] forward_b;          // EX 阶段 ALU 操作数 B 的前递选择

  // 陷阱/异常控制
  wire trap_flush;         // 流水线刷新信号（陷阱）
  wire mret_flush;         // 流水线刷新信号（MRET）
  wire sret_flush;         // 流水线刷新信号（SRET）

  // 特权模式跟踪
  reg  [1:0] current_priv; // 当前特权模式: 00=U, 01=S, 11=M
  wire [1:0] trap_target_priv;  // 陷阱的目标特权级
  wire [1:0] mpp;          // 来自 MSTATUS 的机器先前特权级 (Machine Previous Privilege)
  wire       spp;          // 来自 MSTATUS 的监管先前特权级 (Supervisor Previous Privilege)

  //==========================================================================
  // IF 阶段信号
  //==========================================================================
  wire [XLEN-1:0] pc_current;
  wire [XLEN-1:0] pc_next;
  wire [XLEN-1:0] pc_plus_4;
  wire [XLEN-1:0] pc_plus_2;
  wire [XLEN-1:0] pc_increment;       // +2 对于压缩指令，+4 对于普通指令
  wire [31:0]     if_instruction_raw; // 来自存储器的原始指令
  wire [31:0]     if_instruction;     // 最终指令（如果需要则解压缩）
  wire            if_is_compressed;   // 指令是否为压缩指令
  wire            if_illegal_c_instr; // 非法的压缩指令
  //==========================================================================
  // IF/ID 流水线寄存器输出
  //==========================================================================
  wire [XLEN-1:0] ifid_pc;
  wire [31:0]     ifid_instruction;  // 指令始终为 32 位
  wire            ifid_valid;
  wire            ifid_is_compressed; // 指令最初是否为压缩指令
  wire            ifid_page_fault;    // Session 117: 指令页错误
  wire [XLEN-1:0] ifid_fault_vaddr;   // Session 117: 发生错误的虚拟地址
  //==========================================================================
  // ID 阶段信号
  //==========================================================================
  // 解码器输出
  wire [6:0]      id_opcode;
  wire [4:0]      id_rd, id_rs1, id_rs2;
  wire [2:0]      id_funct3;
  wire [6:0]      id_funct7;
  wire [XLEN-1:0] id_imm_i, id_imm_s, id_imm_b, id_imm_u, id_imm_j;
  wire            id_is_csr_dec;   // 来自解码器的 CSR 指令
  wire            id_is_ecall_dec; // 来自解码器的 ECALL
  wire            id_is_ebreak_dec; // 来自解码器的 EBREAK
  wire            id_is_mret_dec;   // 来自解码器的 MRET
  wire            id_is_sret_dec;   // 来自解码器的 SRET
  wire            id_is_sfence_vma_dec; // 来自解码器的 SFENCE.VMA
  wire            id_is_mul_div_dec; // 来自解码器的 M 扩展指令
  wire [3:0]      id_mul_div_op_dec; // 来自解码器的 M 扩展操作
  wire            id_is_word_op_dec; // 来自解码器的 RV64M 字操作
  wire            id_is_atomic_dec;  // 来自解码器的 A 扩展指令
  wire [4:0]      id_funct5_dec;     // 来自解码器的 funct5 字段（原子操作）
  wire            id_aq_dec;         // 来自解码器的 Acquire 位
  wire            id_rl_dec;         // 来自解码器的 Release 位
  wire [4:0]      id_rs3;            // 第三个源寄存器（FMA）
  wire            id_is_fp;          // 来自解码器的 F/D 扩展指令
  wire            id_is_fp_load;     // 来自解码器的 FP 载入指令
  wire            id_is_fp_store;    // 来自解码器的 FP 存储指令
  wire            id_is_fp_op;       // 来自解码器的 FP 计算操作
  wire            id_is_fp_fma;      // 来自解码器的 FP FMA 指令
  wire [2:0]      id_fp_rm;          // 来自指令的 FP 舍入模式
  wire            id_fp_fmt;         // FP 格式：0=单精度，1=双精度

  // 控制信号
  wire        id_reg_write;
  wire        id_mem_read;
  wire        id_mem_write;
  wire        id_branch;
  wire        id_jump;
  wire [3:0]  id_alu_control;
  wire        id_alu_src;
  wire [2:0]  id_wb_sel;
  wire [2:0]  id_imm_sel;

  // CSR 信号
  wire [11:0]     id_csr_addr;
  wire [4:0]      id_csr_uimm;
  wire            id_csr_we;
  wire            id_csr_src;
  wire [XLEN-1:0] id_csr_wdata;

  // 异常信号
  wire            id_is_ecall;
  wire            id_is_ebreak;
  wire            id_is_mret;
  wire            id_is_sret;
  wire            id_is_sfence_vma;
  wire            id_illegal_inst_from_control; // 仅来自控制单元的非法指令标志
  wire            id_illegal_inst;               // 综合非法指令标志（控制单元 + RVC）

  // 寄存器文件输出
  wire [XLEN-1:0] id_rs1_data;
  wire [XLEN-1:0] id_rs2_data;

  // 来自控制单元的 FP 控制信号
  wire            id_fp_reg_write;    // FP 寄存器写使能
  wire            id_int_reg_write_fp;// 来自控制单元的整数寄存器写使能（FP 比较/分类/FMV.X.W）
  wire            id_fp_mem_op;       // FP 存储器操作
  wire            id_fp_alu_en;       // FP ALU 使能
  wire [4:0]      id_fp_alu_op;       // FP ALU 操作
  wire            id_fp_use_dynamic_rm; // 使用来自 frm CSR 的动态舍入模式

  // FP 寄存器文件输出
  wire [`FLEN-1:0] id_fp_rs1_data;
  wire [`FLEN-1:0] id_fp_rs2_data;
  wire [`FLEN-1:0] id_fp_rs3_data;
  wire [`FLEN-1:0] id_fp_rs1_data_raw; // 原始 FP 寄存器文件输出
  wire [`FLEN-1:0] id_fp_rs2_data_raw;
  wire [`FLEN-1:0] id_fp_rs3_data_raw;

  // 立即数选择
  wire [XLEN-1:0] id_immediate;

  //==========================================================================
  // ID/EX 流水线寄存器输出
  //==========================================================================
  wire [XLEN-1:0] idex_pc;
  wire [XLEN-1:0] idex_rs1_data;
  wire [XLEN-1:0] idex_rs2_data;
  wire [4:0]      idex_rs1_addr;
  wire [4:0]      idex_rs2_addr;
  wire [4:0]      idex_rd_addr;
  wire [XLEN-1:0] idex_imm;
  wire [6:0]      idex_opcode;
  wire [2:0]      idex_funct3;
  wire [6:0]      idex_funct7;
  wire [3:0]      idex_alu_control;
  wire            idex_alu_src;
  wire            idex_branch;
  wire            idex_jump;
  wire            idex_mem_read;
  wire            idex_mem_write;
  wire            idex_reg_write;
  wire [2:0]      idex_wb_sel;
  wire            idex_valid;
  wire            idex_is_mul_div;
  wire [3:0]      idex_mul_div_op;
  wire            idex_is_word_op;
  wire            idex_is_atomic;
  wire [4:0]      idex_funct5;
  wire            idex_aq;
  wire            idex_rl;
  wire [`FLEN-1:0] idex_fp_rs1_data;
  wire [`FLEN-1:0] idex_fp_rs2_data;
  wire [`FLEN-1:0] idex_fp_rs3_data;
  wire [4:0]      idex_fp_rs1_addr;
  wire [4:0]      idex_fp_rs2_addr;
  wire [4:0]      idex_fp_rs3_addr;
  wire [4:0]      idex_fp_rd_addr;
  wire            idex_fp_reg_write;
  wire            idex_int_reg_write_fp;
  wire            idex_fp_mem_op;
  wire            idex_fp_alu_en;
  wire [4:0]      idex_fp_alu_op;
  wire [2:0]      idex_fp_rm;
  wire            idex_fp_use_dynamic_rm;
  wire            idex_fp_fmt;
  wire [11:0]     idex_csr_addr;
  wire            idex_csr_we;
  wire            idex_csr_src;
  wire [XLEN-1:0] idex_csr_wdata;
  wire            idex_is_csr;
  wire            idex_is_ecall;
  wire            idex_is_ebreak;
  wire            idex_is_mret;
  wire            idex_is_sret;
  wire            idex_is_sfence_vma;
  wire            idex_illegal_inst;
  wire [31:0]     idex_instruction;
  wire            idex_is_compressed;  // Bug #42: 跟踪指令是否为压缩指令  // 指令始终为 32 位

  //==========================================================================
  // EX 阶段信号
  //==========================================================================
  wire [XLEN-1:0] ex_alu_operand_a;
  wire [XLEN-1:0] ex_alu_operand_b;
  wire [XLEN-1:0] ex_alu_operand_a_forwarded;
  wire [XLEN-1:0] ex_alu_operand_b_forwarded;
  wire [XLEN-1:0] ex_alu_result;
  wire            ex_alu_zero;
  wire            ex_alu_lt;
  wire            ex_alu_ltu;
  wire            ex_take_branch;
  wire [XLEN-1:0] ex_branch_target;
  wire [XLEN-1:0] ex_jump_target;
  wire [XLEN-1:0] ex_pc_plus_4;
  wire [XLEN-1:0] ex_csr_rdata;       // CSR 读取数据
  wire            ex_illegal_csr;     // 非法 CSR 访问

  // M 扩展信号
  wire [XLEN-1:0] ex_mul_div_result;
  wire            ex_mul_div_busy;
  wire            ex_mul_div_ready;

  // F/D 扩展信号
  wire [`FLEN-1:0] ex_fp_operand_a;        // FP 操作数 A（可能转发）
  wire [`FLEN-1:0] ex_fp_operand_b;        // FP 操作数 B（可能转发）
  wire [`FLEN-1:0] ex_fp_operand_c;        // FP 操作数 C（可能转发，用于 FMA）
  wire [`FLEN-1:0] ex_fp_result;           // 来自 FPU 的 FP 结果
  wire [XLEN-1:0] ex_int_result_fp;       // 来自 FP 操作的整数结果（比较/分类/FMV.X.W）
  wire            ex_fpu_busy;             // FPU 忙信号
  wire            ex_fpu_done;             // FPU 完成信号
  wire [2:0]      ex_fp_rounding_mode;     // 最终舍入模式（来自指令或 frm CSR）
  wire            ex_fp_flag_nv;           // FP 异常标志
  wire            ex_fp_flag_dz;
  wire            ex_fp_flag_of;
  wire            ex_fp_flag_uf;
  wire            ex_fp_flag_nx;
  wire [1:0]      fp_forward_a;            // FP 转发控制信号
  wire [1:0]      fp_forward_b;
  wire [1:0]      fp_forward_c;

  // 保持 EX/MEM 寄存器，当 M 指令、A 指令、FP 指令或 MMU 正在执行时
  // Session 53: 当总线等待时也保持（外设带有注册的 req_ready）
  // 否则，在总线等待期间 EX/MEM 寄存器会前进，导致存储写数据丢失
  wire            hold_exmem;
  wire            bus_wait_stall;  // 总线等待条件（也在 hazard 单元中计算）

  assign bus_wait_stall = bus_req_valid && !bus_req_ready;
  assign hold_exmem = (idex_is_mul_div && idex_valid && !ex_mul_div_ready) ||
                      (idex_is_atomic && idex_valid && !ex_atomic_done) ||
                      (idex_fp_alu_en && idex_valid && !ex_fpu_done) ||
                      mmu_busy ||     // 第三阶段：在 MMU 页表遍历时暂停
                      bus_wait_stall; // Session 53: 当总线等待时保持

  // M 单元启动信号：在 M 指令第一次进入 EX 阶段时产生一个脉冲
  // 仅在当前未忙且未完成时启动（防止重新启动）
  wire            m_unit_start;
  assign m_unit_start = idex_is_mul_div && idex_valid && !ex_mul_div_busy && !ex_mul_div_ready;

  // FPU 启动信号：在 FP 指令第一次进入 EX 阶段时产生一个脉冲
  // 启动 FPU 条件：（1）FP ALU 操作使能，（2）指令有效，（3）FPU 未忙
  // 注意：这里不检查 !ex_fpu_done - done 是完成标志，不是忙标志
  wire            fpu_start;
  assign fpu_start = idex_fp_alu_en && idex_valid && !ex_fpu_busy;

  `ifdef DEBUG_JALR_TRACE
  // 跟踪 JALR 指令通过所有流水线阶段
  integer jalr_cycle_count;
  always @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
      jalr_cycle_count <= 0;
    end else begin
      jalr_cycle_count <= jalr_cycle_count + 1;

      // ID 阶段：检查是否正在解码 JALR
      if (ifid_valid && id_opcode == 7'b1100111) begin
        $display("[CYCLE %0d] JALR in ID stage:", jalr_cycle_count);
        $display("  ifid_pc=%08h ifid_instr=%08h is_compressed=%b", ifid_pc, ifid_instruction, ifid_is_compressed);
        $display("  id_jump=%b id_branch=%b stall_ifid=%b flush_ifid=%b", id_jump, id_branch, stall_ifid, flush_ifid);
      end
      // IDEX 锁存器: 检查是否正在锁存 JALR 进入 EX 阶段
      if (flush_idex && !hold_exmem) begin
        if (id_opcode == 7'b1100111 && ifid_valid) begin
          $display("[CYCLE %0d] JALR FLUSHED before entering EX:", jalr_cycle_count);
          $display("  flush_idex=%b hold_exmem=%b", flush_idex, hold_exmem);
          $display("  flush sources: trap=%b mret=%b sret=%b hazard=%b ex_take_branch=%b",
                   trap_flush, mret_flush, sret_flush, flush_idex_hazard, ex_take_branch);
        end
      end else if (!hold_exmem && ifid_valid && id_opcode == 7'b1100111) begin
        $display("[CYCLE %0d] JALR latching into IDEX:", jalr_cycle_count);
        $display("  jump_in=%b branch_in=%b", id_jump, id_branch);
      end
      // EX 阶段：检查是否正在执行 JALR
      if (idex_valid && idex_opcode == 7'b1100111) begin
        $display("[CYCLE %0d] JALR in EX stage:", jalr_cycle_count);
        $display("  idex_pc=%08h idex_instr=%08h idex_is_compressed=%b", idex_pc, idex_instruction, idex_is_compressed);
        $display("  idex_jump=%b idex_branch=%b ex_take_branch=%b", idex_jump, idex_branch, ex_take_branch);
        $display("  rs1_addr=x%0d rs1_data=%08h target=%08h", idex_rs1_addr, ex_alu_operand_a_forwarded, ex_jump_target);
        $display("  Branch unit inputs: rs1_data=%08h rs2_data=%08h funct3=%03b branch=%b jump=%b",
                 ex_alu_operand_a_forwarded, ex_rs2_data_forwarded, idex_funct3, idex_branch, idex_jump);
      end
    end
  end
  `endif

  `ifdef DEBUG_FPU
  always @(posedge clk) begin
    if (fpu_start) begin
      $display("[CORE] FPU START: PC=%h fp_alu_op=%0d rs1=%0d rs2=%0d rs3=%0d rd=%0d",
               idex_pc, idex_fp_alu_op, idex_rs1_addr, idex_rs2_addr, idex_fp_rs3_addr, idex_rd_addr);
      $display("       FP operands: a=%h b=%h c=%h", ex_fp_operand_a, ex_fp_operand_b, ex_fp_operand_c);
      $display("       INT operand: int_operand=%h (ex_alu_operand_a_forwarded)", ex_alu_operand_a_forwarded);
      $display("       INT rs1 data: idex_rs1_data=%h, forward_a=%b", idex_rs1_data, forward_a);
    end
    if (idex_valid && (idex_opcode == 7'b1010011)) begin  // FP opcode
      $display("[FP_DECODE] PC=%h instr=%h opcode=%b funct7=%b rs2=%d fp_alu_en=%b fpu_busy=%b",
               idex_pc, idex_instruction, idex_opcode, idex_funct7, idex_rs2_addr, idex_fp_alu_en, ex_fpu_busy);
    end
    // 跟踪所有分支以理解控制流
    if (idex_valid && (idex_branch || idex_jump)) begin
      $display("[BRANCH] PC=%h instr=%h branch=%b jump=%b take=%b target=%h",
               idex_pc, idex_instruction, idex_branch, idex_jump, ex_take_branch,
               idex_branch ? ex_branch_target : ex_jump_target);
      if (idex_branch) begin
        $display("         rs1_data=%h (x%0d fwd=%b) rs2_data=%h (x%0d fwd=%b)",
                 ex_alu_operand_a_forwarded, idex_rs1_addr, forward_a,
                 ex_rs2_data_forwarded, idex_rs2_addr, forward_b);
        $display("         exmem: rd=x%0d reg_wr=%b int_wr_fp=%b alu_res=%h int_res_fp=%h fwd_data=%h",
                 exmem_rd_addr, exmem_reg_write, exmem_int_reg_write_fp, exmem_alu_result, exmem_int_result_fp, exmem_forward_data);
        $display("         memwb: rd=x%0d reg_wr=%b int_wr_fp=%b wb_data=%h",
                 memwb_rd_addr, memwb_reg_write, memwb_int_reg_write_fp, wb_data);
      end
    end
    // 跟踪 gp 写入以跟踪测试进度
    if (memwb_reg_write && (memwb_rd_addr == 3)) begin
      $display("[GP_WRITE] GP <= %h (test number)", wb_data);
    end
    // 跟踪 FP 到 INT 的写回
    if (memwb_int_reg_write_fp && memwb_reg_write) begin
      $display("[WB_FP2INT] x%0d <= %h (wb_sel=%b int_result_fp=%h wb_data=%h)",
               memwb_rd_addr, wb_data, memwb_wb_sel, memwb_int_result_fp, wb_data);
    end
  end
  `endif

  // 调试：FPU 执行（特别是针对 FCVT 调试）
  `ifdef DEBUG_FPU_EXEC
  always @(posedge clk) begin
    if (fpu_start) begin
      $display("[%0t] [FPU] START: op=%0d, rs1=f%0d, rs2=%0d, rd=f%0d, pc=%h",
               $time, idex_fp_alu_op, idex_fp_rs1_addr, idex_fp_rs2_addr, idex_fp_rd_addr, idex_pc);
      if (idex_fp_alu_op == 5'b01010) begin  // FP_CVT
        $display("[%0t] [FPU] FCVT START: fp_operand_a=%h, int_operand=%h",
                 $time, ex_fp_operand_a, ex_alu_operand_a_forwarded);
      end
    end
    if (ex_fpu_done) begin
      $display("[%0t] [FPU] DONE: result=%h, busy=%b, pc=%h",
               $time, ex_fp_result, ex_fpu_busy, idex_pc);
    end
  end
  `endif

  //==========================================================================
  // EX/MEM 流水线寄存器输出
  //==========================================================================
  wire [XLEN-1:0] exmem_alu_result;
  wire [XLEN-1:0] exmem_mem_write_data;      // 整数存储写数据
  wire [`FLEN-1:0] exmem_fp_mem_write_data;  // 浮点存储写数据
  wire [4:0]      exmem_rd_addr;
  wire [XLEN-1:0] exmem_pc_plus_4;
  wire [2:0]      exmem_funct3;
  wire            exmem_mem_read;
  wire            exmem_mem_write;
  wire            exmem_reg_write;
  wire [2:0]      exmem_wb_sel;
  wire            exmem_valid;
  wire [XLEN-1:0] exmem_mul_div_result;
  wire [XLEN-1:0] exmem_atomic_result;
  wire            exmem_is_atomic;
  wire [`FLEN-1:0] exmem_fp_result;
  wire [XLEN-1:0] exmem_int_result_fp;
  wire [4:0]      exmem_fp_rd_addr;
  wire            exmem_fp_reg_write;
  wire            exmem_int_reg_write_fp;
  wire            exmem_fp_mem_op;
  wire            exmem_fp_fmt;
  wire            exmem_fp_flag_nv;
  wire            exmem_fp_flag_dz;
  wire            exmem_fp_flag_of;
  wire            exmem_fp_flag_uf;
  wire            exmem_fp_flag_nx;
  wire [11:0]     exmem_csr_addr;
  wire            exmem_csr_we;
  wire [XLEN-1:0] exmem_csr_rdata;
  wire            exmem_is_mret;
  wire            exmem_is_sret;
  wire            exmem_is_sfence_vma;
  wire [4:0]      exmem_rs1_addr;
  wire [4:0]      exmem_rs2_addr;
  wire [XLEN-1:0] exmem_rs1_data;
  wire [31:0]     exmem_instruction;  // 指令始终为 32 位
  wire [XLEN-1:0] exmem_pc;
  wire [XLEN-1:0] exmem_paddr;         // MMU 翻译后的物理地址
  wire            exmem_translation_ready;  // MMU 翻译完成
  wire            exmem_page_fault;    // MMU 检测到页错误
  wire [XLEN-1:0] exmem_fault_vaddr;   // MMU 发生错误的虚拟地址

  //==========================================================================
  // MEM 阶段信号
  //==========================================================================
  wire [XLEN-1:0] mem_read_data;      // 整数加载数据（低位）
  wire [`FLEN-1:0] fp_mem_read_data;  // 浮点加载数据（RV32D 为完整 64 位）

  //==========================================================================
  // MMU 信号 (Phase 3)
  //==========================================================================
  // 指令取值 MMU 信号（Session 117）
  wire            if_mmu_req_valid;
  wire [XLEN-1:0] if_mmu_req_vaddr;
  wire            if_mmu_req_ready;
  wire [XLEN-1:0] if_mmu_req_paddr;
  wire            if_mmu_req_page_fault;
  wire [XLEN-1:0] if_mmu_req_fault_vaddr;

  // 数据访问 MMU 信号（Session 117：为清晰起见更名）
  wire            ex_mmu_req_valid;
  wire [XLEN-1:0] ex_mmu_req_vaddr;
  wire            ex_mmu_req_is_store;
  wire            ex_mmu_req_ready;
  wire [XLEN-1:0] ex_mmu_req_paddr;
  wire            ex_mmu_req_page_fault;
  wire [XLEN-1:0] ex_mmu_req_fault_vaddr;

  // 共享 MMU 信号（连接到 MMU 模块）
  wire            mmu_req_valid;
  wire [XLEN-1:0] mmu_req_vaddr;
  wire            mmu_req_is_store;
  wire            mmu_req_is_fetch;
  wire [2:0]      mmu_req_size;
  wire            mmu_req_ready;
  wire [XLEN-1:0] mmu_req_paddr;
  wire            mmu_req_page_fault;
  wire [XLEN-1:0] mmu_req_fault_vaddr;

  // MMU 页表遍历的存储器接口
  wire            mmu_ptw_req_valid;
  wire [XLEN-1:0] mmu_ptw_req_addr;
  wire            mmu_ptw_req_ready;
  wire [XLEN-1:0] mmu_ptw_resp_data;
  wire            mmu_ptw_resp_valid;

  // TLB 刷新控制
  wire            tlb_flush_all;
  wire            tlb_flush_vaddr;
  wire [XLEN-1:0] tlb_flush_addr;
  wire            mmu_busy;  // MMU 忙（正在进行页表遍历）

  //==========================================================================
  // MEM/WB 流水线寄存器输出
  //==========================================================================
  wire [XLEN-1:0] memwb_alu_result;
  wire [XLEN-1:0] memwb_mem_read_data;       // 整数加载数据
  wire [`FLEN-1:0] memwb_fp_mem_read_data;   // 浮点加载数据
  wire [4:0]      memwb_rd_addr;
  wire [XLEN-1:0] memwb_pc_plus_4;
  wire            memwb_reg_write;
  wire [2:0]      memwb_wb_sel;
  wire            memwb_valid;
  wire [XLEN-1:0] memwb_mul_div_result;
  wire [XLEN-1:0] memwb_atomic_result;
  wire [`FLEN-1:0] memwb_fp_result;
  wire [XLEN-1:0] memwb_int_result_fp;
  wire [4:0]      memwb_fp_rd_addr;
  wire            memwb_fp_reg_write;
  wire            memwb_int_reg_write_fp;
  wire            memwb_fp_fmt;
  wire            memwb_fp_flag_nv;
  wire            memwb_fp_flag_dz;
  wire            memwb_fp_flag_of;
  wire            memwb_fp_flag_uf;
  wire            memwb_fp_flag_nx;
  wire [XLEN-1:0] memwb_csr_rdata;
  wire            memwb_csr_we;

  //==========================================================================
  // CSR 和异常信号
  //==========================================================================
  wire            exception;
  wire [4:0]      exception_code;     // 5 位异常代码，用于 mcause
  wire [XLEN-1:0] exception_pc;
  wire [XLEN-1:0] exception_val;

  // 注册异常信号以防止陷阱处理期间的毛刺
  // 异常单元输出是组合逻辑，可能在时钟周期内产生毛刺。
  // 我们对它们进行寄存，以确保 CSR 文件采样时值稳定。
  reg             exception_r;
  reg [4:0]       exception_code_r;
  reg [XLEN-1:0]  exception_pc_r;
  reg [XLEN-1:0]  exception_val_r;
  reg             exception_r_hold;  // 保持 exception_r 一个额外周期
  reg [1:0]       exception_priv_r;  // 异常发生时的特权模式
  reg [1:0]       exception_target_priv_r;  // 陷阱的目标特权（已锁存）

  // 门异常信号以防止传播到后续指令
  // 一旦 exception_r 被锁存，在其完全处理完成之前忽略新的异常
  // 当 MRET/SRET 位于 MEM 阶段时也阻塞新的异常，防止同时发生流水线刷新
  wire exception_gated = exception && !exception_r && !exception_taken_r && !mret_flush && !sret_flush;

  // 调试异常门控
  always @(posedge clk) begin
    if (exception && !exception_gated) begin
      $display("[EXCEPTION_GATED] Exception detected but gated: exception_r=%b exception_taken_r=%b mret=%b sret=%b",
               exception_r, exception_taken_r, mret_flush, sret_flush);
    end
  end

  // 计算当前异常的陷阱目标特权（未锁存）
  // 必须使用未锁存的 exception_code 和 current_priv 以获得正确的委托
  function [1:0] compute_trap_target;
    input [4:0] cause;
    input [1:0] curr_priv;
    input [XLEN-1:0] medeleg;
    begin
      `ifdef DEBUG_EXCEPTION
      $display("[CORE_DELEG] compute_trap_target: cause=%0d curr_priv=%b medeleg=%h medeleg[cause]=%b",
               cause, curr_priv, medeleg, medeleg[cause]);
      `endif
      // M 模式陷阱从不委托
      if (curr_priv == 2'b11) begin
        compute_trap_target = 2'b11;  // M-mode
        `ifdef DEBUG_EXCEPTION
        $display("[CORE_DELEG] -> M-mode (curr_priv==M)");
        `endif
      end
      // 检查异常是否委托给 S 模式
      else if (medeleg[cause] && (curr_priv <= 2'b01)) begin
        compute_trap_target = 2'b01;  // S-mode
        `ifdef DEBUG_EXCEPTION
        $display("[CORE_DELEG] -> S-mode (delegated)");
        `endif
      end
      else begin
        compute_trap_target = 2'b11;  // M-mode (默认)
        `ifdef DEBUG_EXCEPTION
        $display("[CORE_DELEG] -> M-mode (no delegation)");
        `endif
      end
    end
  endfunction

  // 计算当前异常的陷阱目标特权（未锁存）
  wire [1:0] current_trap_target = compute_trap_target(exception_code, current_priv, medeleg);

  // 异常信号寄存
  // 锁存异常信号，当异常首次发生时保持一个周期
  always @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
      exception_r            <= 1'b0;
      exception_code_r       <= 5'd0;
      exception_pc_r         <= {XLEN{1'b0}};
      exception_val_r        <= {XLEN{1'b0}};
      exception_r_hold       <= 1'b0;
      exception_priv_r       <= 2'b11;  // 默认 M 模式
      exception_target_priv_r <= 2'b11;  // 默认 M 模式
    end else begin
      // 当异常第一次出现时锁存异常信息（使用门控后的信号）
      if (exception_gated) begin
        exception_r            <= 1'b1;  // 将保持一个时钟周期的脉冲
        exception_code_r       <= exception_code;
        exception_pc_r         <= exception_pc;
        exception_val_r        <= exception_val;
        exception_priv_r       <= current_priv;  // 锁存异常发生时的当前特权级
        exception_target_priv_r <= current_trap_target;  // 使用计算得到的目标特权级（而不是 CSR 中的 trap_target_priv）
        exception_r_hold       <= 1'b0;
        `ifdef DEBUG_EXCEPTION
        $display("[EXC_LATCH] Latching exception code=%0d PC=%h priv=%b target=%b (exception=%b taken=%b)",
             exception_code, exception_pc, current_priv, current_trap_target, exception, exception_taken_r);
        `endif
      end else begin
        // 一个周期之后清除 exception_r
        exception_r      <= 1'b0;
        exception_r_hold <= exception_r;  // 记录前一拍的值，用于清除 exception_taken_r
      end
    end
  end

  wire [XLEN-1:0] trap_vector;
  wire [XLEN-1:0] mepc;
  wire [XLEN-1:0] sepc;
  wire            mstatus_sum;  // MSTATUS.SUM 位 (用于 MMU)
  wire            mstatus_mxr;  // MSTATUS.MXR 位 (用于 MMU)
  wire [1:0]      mstatus_fs;   // MSTATUS.FS 字段 (FPU 状态)
  wire [XLEN-1:0] satp;         // SATP 寄存器 (用于 MMU)
  wire [XLEN-1:0] csr_satp;     // MMU 的别名
  wire            mstatus_mie;
  wire            mstatus_sie;
  wire            mstatus_mpie;
  wire            mstatus_spie;
  wire [2:0]      csr_frm;            // FP 舍入模式，来自 frm CSR
  wire [4:0]      csr_fflags;         // FP 异常标志，来自 fflags CSR
  wire [XLEN-1:0] medeleg;            // 机器异常委托寄存器
  wire [XLEN-1:0] mip;                // 机器中断挂起寄存器
  wire [XLEN-1:0] mie;                // 机器中断使能寄存器
  wire [XLEN-1:0] mideleg;            // 机器中断委托寄存器
  // 注意: csr_frm 和 csr_fflags 现在连接到 CSR 文件输出

  //==========================================================================
  // WB 阶段信号
  //==========================================================================
  wire [XLEN-1:0] wb_data;
  wire [`FLEN-1:0] wb_fp_data;         // FP 写回数据

  //==========================================================================
  // 调试输出
  //==========================================================================
  assign pc_out = pc_current;
  assign instr_out = if_instruction;

  //==========================================================================
  // IF 阶段: 指令获取
  //==========================================================================

  // PC 计算 (支持 C 扩展的 2 字节和 4 字节递增)
  assign pc_plus_2 = pc_current + 32'd2;
  assign pc_plus_4 = pc_current + 32'd4;
  assign pc_increment = if_is_compressed ? pc_plus_2 : pc_plus_4;

  // 调试: PC 增加逻辑跟踪
  `ifdef DEBUG_JAL_RET
  always @(posedge clk) begin
    if (reset_n && !stall_pc) begin
      $display("[PC_INC] PC=%h → %h | instr=%h [1:0]=%b is_comp=%b | inc=%h (+%0d)",
               pc_current, pc_next, if_instruction_raw, if_instruction_raw[1:0],
               if_is_compressed, pc_increment, if_is_compressed ? 2 : 4);
      // 显示控制 pc_next 的信号
      if (trap_flush) $display("  → TRAP (vec=%h)", trap_vector);
      else if (mret_flush) $display("  → MRET (mepc=%h)", mepc);
      else if (sret_flush) $display("  → SRET (sepc=%h)", sepc);
      else if (ex_take_branch) $display("  → BR/JMP (idex_pc=%h + imm=%h → tgt=%h, is_jump=%b, idex_is_comp=%b)",
                                        idex_pc, idex_imm, idex_jump ? ex_jump_target : ex_branch_target, idex_jump, idex_is_compressed);
      else $display("  → INC");

      // 健全性检查
      if (if_instruction_raw[1:0] == 2'b11 && if_is_compressed) begin
        $display("  *** BUG: Non-compressed instr marked as compressed!");
      end
      if (pc_next != pc_increment && !trap_flush && !mret_flush && !sret_flush && !ex_take_branch) begin
        $display("  *** BUG: PC_NEXT mismatch! Expected %h, got %h", pc_increment, pc_next);
      end
    end
  end
  `endif

  // Trap 和 xRET 处理
  // 使用 GATED 异常信号实现立即刷新，防止下一条指令执行
  // exception_gated 信号防止异常传播到后续指令
  // 注意: 我们使用 exception_gated（而非 exception_r）以实现 0 周期陷阱延迟

  // xRET 在 MEM 阶段无条件刷新 - 优先于异常
  // 这防止了在 xRET 之后获取的指令产生虚假异常
  assign mret_flush = exmem_is_mret && exmem_valid;  // MEM 阶段的 MRET
  assign sret_flush = exmem_is_sret && exmem_valid;  // MEM 阶段的 SRET

  // 仅当不执行 xRET 时才进行陷阱刷新（xRET 优先级更高）
  assign trap_flush = exception_gated && !mret_flush && !sret_flush;

  // 记录异常以防止重复触发
  // 在异常首次发生时置位，在陷阱刷新后一拍清零
  reg exception_taken_r;
  reg trap_flush_r;  // 将 trap_flush 寄存以用于清除 exception_taken_r
  always @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
      exception_taken_r <= 1'b0;
      trap_flush_r <= 1'b0;
    end else begin
      trap_flush_r <= trap_flush;  // 锁存 trap_flush
      if (exception_gated)
        exception_taken_r <= 1'b1;  // 在第一次异常时置位（使用门控后的信号）
      else if (trap_flush_r)
        exception_taken_r <= 1'b0;  // 在陷阱刷新后一拍清零
    end
  end

  //==========================================================================
  // 特权模式跟踪
  //==========================================================================
  // 特权模式状态机：在陷阱进入和 xRET 时更新
  always @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
      current_priv <= 2'b11;  // 复位后从机器模式启动
    end else begin
      if (trap_flush) begin
        // 进入陷阱时，切换到目标特权级
        // 采用 0 周期陷阱延迟，因此使用当前（未锁存）的目标特权级
        current_priv <= current_trap_target;
        $display("[TRAP] Taking trap to priv=%b, cause=%0d, PC=0x%h saved to %cEPC, trap_vector=0x%h",
                 current_trap_target, exception_code, exception_pc,
                 (current_trap_target == 2'b01) ? "S" : "M", trap_vector);
        `ifdef DEBUG_PRIV
        $display("[PRIV] Time=%0t TRAP: priv %b -> %b (current)", $time, current_priv, current_trap_target);
        `endif
      end else if (mret_flush) begin
        // 在 MRET 时，从 MSTATUS.MPP 恢复特权级
        current_priv <= mpp;
        `ifdef DEBUG_PRIV
        $display("[PRIV] Time=%0t MRET: priv %b -> %b (from MPP) mepc=0x%08x", $time, current_priv, mpp, mepc);
        `endif
      end else if (sret_flush) begin
        // 在 SRET 时，从 MSTATUS.SPP 恢复特权级
        current_priv <= {1'b0, spp};  // SPP: 0=U, 1=S -> {1'b0, spp} = 00 或 01
        `ifdef DEBUG_PRIV
        $display("[PRIV] Time=%0t SRET: priv %b -> %b (from SPP=%b)", $time, current_priv, {1'b0, spp}, spp);
        `endif
      end
    end
  end

  // PC 选择：优先级顺序 - 陷阱 > mret > sret > 分支/跳转 > PC+增量
  // 注意：分支/跳转可以目标为2字节对齐地址（用于C扩展）
  assign pc_next = trap_flush ? trap_vector :
                   mret_flush ? mepc :
                   sret_flush ? sepc :
                   ex_take_branch ? (idex_jump ? ex_jump_target : ex_branch_target) :
                   pc_increment;

  // 调试 PC 更新
  always @(posedge clk) begin
    if (trap_flush) begin
      $display("[PC_UPDATE] TRAP: pc_current=0x%h -> pc_next=0x%h (trap_vector)", pc_current, trap_vector);
    end
    if (sret_flush) begin
      $display("[PC_UPDATE] SRET: pc_current=0x%h -> pc_next=0x%h (sepc)", pc_current, sepc);
    end
    if (mret_flush) begin
      $display("[PC_UPDATE] MRET: pc_current=0x%h -> pc_next=0x%h (mepc)", pc_current, mepc);
    end
  end

  // 流水线刷新：trap/xRET 刷新所有阶段，分支刷新 IF/ID 和 ID/EX
  assign flush_ifid = trap_flush | mret_flush | sret_flush | ex_take_branch;
  assign flush_idex = trap_flush | mret_flush | sret_flush | flush_idex_hazard | ex_take_branch;

  // PC 停顿控制：在刷新时覆盖停顿（trap/xRET/分支）
  // 当发生控制流变化时，无论是否有冒险，PC 都必须更新
  // Session 125：在 I‑TLB 未命中（等待指令翻译）时也要暂停 PC
  wire pc_stall_gated;
  assign pc_stall_gated = (stall_pc || if_mmu_busy) && !(trap_flush | mret_flush | sret_flush | ex_take_branch);

  // 程序计数器
  pc #(
    .XLEN(XLEN),
    .RESET_VECTOR(RESET_VECTOR)
  ) pc_inst (
    .clk(clk),
    .reset_n(reset_n),
    .stall(pc_stall_gated),
    .pc_next(pc_next),
    .pc_current(pc_current)
  );

  // 指令存储器（可写，用于支持 FENCE.I）
  // IMEM 写使能——仅对 IMEM 范围内的地址有效（0x0–0xFFFF 对应 64KB IMEM）
  // 这样可以防止 DMEM 写入（例如 0x80000000）破坏 IMEM
  wire imem_write_enable = exmem_mem_write && exmem_valid && !exception &&
                           (exmem_alu_result < IMEM_SIZE);

  // Session 117：在启用分页时，取指使用翻译后的地址
  // 当需要翻译且 MMU 就绪：使用翻译后的地址
  // 否则：直接使用 PC（裸机模式、M 模式或 TLB 未命中挂起时）
  wire [XLEN-1:0] if_fetch_addr = (if_needs_translation && if_mmu_req_ready) ?
                                   if_mmu_req_paddr :
                                   pc_current;

  instruction_memory #(
    .XLEN(XLEN),
    .MEM_SIZE(IMEM_SIZE),
    .MEM_FILE(MEM_FILE)
  ) imem (
    .clk(clk),
    .addr(if_fetch_addr),  // 使用翻译后的地址！
    .instruction(if_instruction_raw),
    // 写接口，用于自修改代码（FENCE.I）
    .mem_write(imem_write_enable),
    .write_addr(exmem_alu_result),
    .write_data(exmem_mem_write_data),
    .funct3(exmem_funct3)
  );

  // RVC 解码器（C 扩展 - 压缩指令解压器）
  // 检测并将 16 位压缩指令扩展为 32 位等效指令
  // 对于 C 扩展，我们需要根据 PC 对齐选择正确的 16 位
  wire [15:0] if_compressed_instr_candidate;
  wire [31:0] if_instruction_decompressed;

  // RISC-V C 扩展：压缩指令通过位 [1:0] != 11 来识别
  // 指令存储器从半字对齐地址开始获取 32 位。
  // 由于 halfword_addr = {PC[XLEN-1:1], 1'b0}，取指总是从偶数地址开始。
  // PC 处的指令总是位于获取字的低 16 位！
  // - 当 PC 是 2 字节对齐时（PC = 0, 2, 4, 6, 8, a, c, e, ...）：位 [15:0]
  // - 高 16 位 [31:16] 包含下一个潜在的 16 位指令
  //
  // BUG 修复：总是使用低 16 位并检查位 [1:0] 以检测压缩指令
  assign if_compressed_instr_candidate = if_instruction_raw[15:0];

  // 通过检查低 16 位的位 [1:0] 来检测指令是否为压缩指令
  wire if_instr_is_compressed = (if_instruction_raw[1:0] != 2'b11);

  rvc_decoder #(
    .XLEN(XLEN)
  ) rvc_dec (
    .compressed_instr(if_compressed_instr_candidate),
    .is_rv64(XLEN == 64),
    .decompressed_instr(if_instruction_decompressed),
    .illegal_instr(if_illegal_c_instr),
    .is_compressed_out() // 未使用，该核自行计算压缩标志
  );

  // 使用修正后的压缩指令检测结果
  assign if_is_compressed = if_instr_is_compressed;

  // 选择最终指令：如果是压缩指令则使用解压后的指令，否则使用来自存储器的完整 32 位指令
  assign if_instruction = if_is_compressed ? if_instruction_decompressed : if_instruction_raw;

  // IF/ID 流水线寄存器
  ifid_register #(
    .XLEN(XLEN)
  ) ifid_reg (
    .clk(clk),
    .reset_n(reset_n),
    .stall(stall_ifid),
    .flush(flush_ifid),
    .pc_in(pc_current),
    .instruction_in(if_instruction),    // 如果是压缩指令，此时已经解压
    .is_compressed_in(if_is_compressed),
    .page_fault_in(if_mmu_req_page_fault),   // Session 117
    .fault_vaddr_in(if_mmu_req_fault_vaddr), // Session 117
    .pc_out(ifid_pc),
    .instruction_out(ifid_instruction),
    .valid_out(ifid_valid),
    .is_compressed_out(ifid_is_compressed),
    .page_fault_out(ifid_page_fault),        // Session 117
    .fault_vaddr_out(ifid_fault_vaddr)       // Session 117
  );

  //==========================================================================
  // ID 阶段：指令解码
  //==========================================================================

  // 指令解码器
  decoder #(
    .XLEN(XLEN)
  ) decoder_inst (
    .instruction(ifid_instruction),
    .opcode(id_opcode),
    .rd(id_rd),
    .rs1(id_rs1),
    .rs2(id_rs2),
    .funct3(id_funct3),
    .funct7(id_funct7),
    .imm_i(id_imm_i),
    .imm_s(id_imm_s),
    .imm_b(id_imm_b),
    .imm_u(id_imm_u),
    .imm_j(id_imm_j),
    .csr_addr(id_csr_addr),
    .csr_uimm(id_csr_uimm),
    .is_csr(id_is_csr_dec),
    .is_ecall(id_is_ecall_dec),
    .is_ebreak(id_is_ebreak_dec),
    .is_mret(id_is_mret_dec),
    .is_sret(id_is_sret_dec),
    .is_sfence_vma(id_is_sfence_vma_dec),
    .is_mul_div(id_is_mul_div_dec),
    .mul_div_op(id_mul_div_op_dec),
    .is_word_op(id_is_word_op_dec),
    // A 扩展输出
    .is_atomic(id_is_atomic_dec),
    .funct5(id_funct5_dec),
    .aq(id_aq_dec),
    .rl(id_rl_dec),
    // F/D 扩展输出
    .rs3(id_rs3),
    .is_fp(id_is_fp),
    .is_fp_load(id_is_fp_load),
    .is_fp_store(id_is_fp_store),
    .is_fp_op(id_is_fp_op),
    .is_fp_fma(id_is_fp_fma),
    .fp_rm(id_fp_rm),
    .fp_fmt(id_fp_fmt)
  );

  // M 扩展控制信号来自控制单元（不直接使用，但可用）
  wire        id_mul_div_en;       // M 单元使能来自控制
  wire [3:0]  id_mul_div_op_ctrl;  // M 操作来自控制（直通）
  wire        id_is_word_op_ctrl;  // 字操作来自控制（直通）

  // A 扩展控制信号来自控制单元
  wire        id_atomic_en;        // A 单元使能来自控制
  wire [4:0]  id_atomic_funct5;    // 原子操作来自控制（直通）
  // 控制单元
  control #(
    .XLEN(XLEN)
  ) control_inst (
    .opcode(id_opcode),
    .funct3(id_funct3),
    .funct7(id_funct7),
    // 解码器特殊指令标志
    .is_csr(id_is_csr_dec),
    .is_ecall(id_is_ecall_dec),
    .is_ebreak(id_is_ebreak_dec),
    .is_mret(id_is_mret_dec),
    .is_sret(id_is_sret_dec),
    .is_sfence_vma(id_is_sfence_vma_dec),
    .is_mul_div(id_is_mul_div_dec),
    .mul_div_op(id_mul_div_op_dec),
    .is_word_op(id_is_word_op_dec),
    .is_atomic(id_is_atomic_dec),
    .funct5(id_funct5_dec),
    // F/D 扩展输入
    .is_fp(id_is_fp),
    .is_fp_load(id_is_fp_load),
    .is_fp_store(id_is_fp_store),
    .is_fp_op(id_is_fp_op),
    .is_fp_fma(id_is_fp_fma),
    // FPU 状态输入（来自 MSTATUS.FS）
    .mstatus_fs(mstatus_fs),
    // 注意：fp_rm 来自解码器，而非控制单元
    // 标准输出
    .reg_write(id_reg_write),
    .mem_read(id_mem_read),
    .mem_write(id_mem_write),
    .branch(id_branch),
    .jump(id_jump),
    .alu_control(id_alu_control),
    .alu_src(id_alu_src),
    .wb_sel(id_wb_sel),
    .imm_sel(id_imm_sel),
    .csr_we(id_csr_we),
    .csr_src(id_csr_src),
    // M 扩展输出
    .mul_div_en(id_mul_div_en),
    .mul_div_op_out(id_mul_div_op_ctrl),
    .is_word_op_out(id_is_word_op_ctrl),
    // A 扩展输出
    .atomic_en(id_atomic_en),
    .atomic_funct5(id_atomic_funct5),
    // F/D 扩展输出
    .fp_reg_write(id_fp_reg_write),
    .int_reg_write_fp(id_int_reg_write_fp),
    .fp_mem_op(id_fp_mem_op),
    .fp_alu_en(id_fp_alu_en),
    .fp_alu_op(id_fp_alu_op),
    .fp_use_dynamic_rm(id_fp_use_dynamic_rm),
    .illegal_inst(id_illegal_inst_from_control)
  );

  // 组合来自控制单元和 RVC 解码器的非法指令信号
  // Bug #29: 未捕获非法压缩指令，导致 PC 损坏
  // 仅在指令实际为压缩指令时检查 RVC 非法标志（经过 IFID 流水线寄存器）
  // 注意：需要对非法标志进行一周期缓冲以匹配流水线阶段
  reg if_illegal_c_instr_buffered;
  always @(posedge clk or negedge reset_n) begin
    if (!reset_n)
      if_illegal_c_instr_buffered <= 1'b0;
    else if (!stall_ifid && !flush_ifid)
      if_illegal_c_instr_buffered <= if_illegal_c_instr;
    else if (flush_ifid)
      if_illegal_c_instr_buffered <= 1'b0;  // 冲刷清除非法标志
  end

  assign id_illegal_inst = id_illegal_inst_from_control | (ifid_is_compressed & if_illegal_c_instr_buffered);

  // 传递解码器标志以供流水线使用
  assign id_is_ecall = id_is_ecall_dec;
  assign id_is_ebreak = id_is_ebreak_dec;
  assign id_is_mret = id_is_mret_dec;
  assign id_is_sret = id_is_sret_dec;
  assign id_is_sfence_vma = id_is_sfence_vma_dec;

  // 寄存器文件
  wire [XLEN-1:0] id_rs1_data_raw;  // 原始寄存器文件输出
  wire [XLEN-1:0] id_rs2_data_raw;  // 原始寄存器文件输出

  // 写回门控：防止被冲刷的指令写寄存器
  // 导致异常的指令可能在被无效化前进入 EXMEM/MEMWB
  // 使用 memwb_valid 门控寄存器写，确保只有有效指令提交
  wire int_reg_write_enable = (memwb_reg_write | memwb_int_reg_write_fp) && memwb_valid;

  register_file #(
    .XLEN(XLEN)
  ) regfile (
    .clk(clk),
    .reset_n(reset_n),
    .rs1_addr(id_rs1),
    .rs2_addr(id_rs2),
    .rd_addr(memwb_rd_addr),          // 来自 WB 阶段的写地址
    .rd_data(wb_data),                // 来自 WB 阶段的写数据
    .rd_wen(int_reg_write_enable),    // 门控写使能：防止被冲刷的指令写寄存器
    .rs1_data(id_rs1_data_raw),
    .rs2_data(id_rs2_data_raw)
  );

  // ID 阶段整数寄存器转发多路复用器
  // 由集中转发单元输出驱动
  // 优先级：EX > MEM > WB > 寄存器文件

  // 转发来自 EX 阶段的数据：对原子指令使用 atomic_result，否则使用 alu_result
  // 对于原子指令，总是转发 atomic_result（即使初始为 0）
  // 对于字操作（RV64I），使用符号扩展结果
  wire [XLEN-1:0] ex_forward_data;
  assign ex_forward_data = idex_is_atomic ? ex_atomic_result : ex_alu_result_sext;

  assign id_rs1_data = (id_forward_a == 3'b100) ? ex_forward_data :     // 来自 EX 阶段的转发（原子或 ALU）
                       (id_forward_a == 3'b010) ? exmem_forward_data :  // 来自 MEM 阶段的转发（原子或 ALU）
                       (id_forward_a == 3'b001) ? wb_data :             // 来自 WB 阶段的转发
                       id_rs1_data_raw;                                  // 使用寄存器文件值

  assign id_rs2_data = (id_forward_b == 3'b100) ? ex_forward_data :     // 来自 EX 阶段的转发（原子或 ALU）
                       (id_forward_b == 3'b010) ? exmem_forward_data :  // 来自 MEM 阶段的转发（原子或 ALU）
                       (id_forward_b == 3'b001) ? wb_data :             // 来自 WB 阶段的转发
                       id_rs2_data_raw;                                  // 使用寄存器文件值

  `ifdef DEBUG_EXCEPTION
  always @(posedge clk) begin
    // 调试分支在 PC=0x60（mcause 比较）
    if (ifid_pc == 32'h60 && id_branch) begin
      $display("[BRANCH_0x60] rs1=x%0d rs2=x%0d rs1_data=%h rs2_data=%h fwd_a=%b fwd_b=%b",
               id_rs1, id_rs2, id_rs1_data, id_rs2_data, id_forward_a, id_forward_b);
      $display("[BRANCH_0x60] exmem_rd=x%0d exmem_reg_write=%b exmem_data=%h",
               exmem_rd_addr, exmem_reg_write, exmem_forward_data);
      $display("[BRANCH_0x60] idex_rd=x%0d idex_reg_write=%b idex_data=%h",
               idex_rd_addr, idex_reg_write, ex_forward_data);
    end
  end
  `endif

  `ifdef DEBUG_ATOMIC
  always @(posedge clk) begin
    if (id_opcode == 7'b0110011 && id_rd == 5'd14 && id_rs1 == 5'd14) begin // ADD 到 x14 从 x14
      $display("[ID_ADD] @%0t ADD x14, x%0d, x%0d: rs1_data=%h (fwd_a=%b), rs2_data=%h (fwd_b=%b), PC=%h",
               $time, id_rs1, id_rs2, id_rs1_data, id_forward_a, id_rs2_data, id_forward_b, ifid_pc);
      $display("[ID_ADD_DBG] regfile_x14=%h, idex_is_atomic=%b, idex_rd=%d, exmem_rd=%d, memwb_rd=%d",
               id_rs1_data_raw, idex_is_atomic, idex_rd_addr, exmem_rd_addr, memwb_rd_addr);
      $display("[ID_ADD_FWD] idex_is_atomic=%b, exmem_is_atomic=%b, exmem_rd=%d, id_forward_a=%b",
               idex_is_atomic, exmem_is_atomic, exmem_rd_addr, id_forward_a);
      $display("[ID_ADD_FWD2] exmem_alu=%h, exmem_atomic=%h, exmem_fwd=%h, hold_exmem=%b",
               exmem_alu_result, exmem_atomic_result, exmem_forward_data, hold_exmem);
    end
    // 跟踪写回到 x14
    if (memwb_reg_write && memwb_rd_addr == 5'd14) begin
      $display("[WB_X14] @%0t Writing x14 <= %h (wb_sel=%b, alu_result=%h, atomic_result=%h)",
               $time, wb_data, memwb_wb_sel, memwb_alu_result, memwb_atomic_result);
    end
  end
  `endif

  // 调试：WB 阶段 FP 寄存器写入
  `ifdef DEBUG_FPU_CONVERTER
  always @(posedge clk) begin
    if (memwb_fp_reg_write) begin
      $display("[%0t] [WB] FP write: f%0d <= 0x%h (wb_sel=%b, from %s)",
               $time, memwb_fp_rd_addr, wb_fp_data, memwb_wb_sel,
               (memwb_wb_sel == 3'b001) ? "MEM" : "FPU");
    end
  end
  `endif

  // FP 寄存器文件
  // 门控 FP 寄存器写入，使用 memwb_valid 以保持与整数寄存器文件的一致性
  wire fp_reg_write_enable = memwb_fp_reg_write && memwb_valid;

  fp_register_file #(
    .FLEN(`FLEN)  // 32 for F-only, 64 for F+D extensions
  ) fp_regfile (
    .clk(clk),
    .reset_n(reset_n),
    .rs1_addr(id_rs1),
    .rs2_addr(id_rs2),
    .rs3_addr(id_rs3),
    .rs1_data(id_fp_rs1_data_raw),
    .rs2_data(id_fp_rs2_data_raw),
    .rs3_data(id_fp_rs3_data_raw),
    .wr_en(fp_reg_write_enable),  // 门控写使能：防止被冲刷的指令写入
    .rd_addr(memwb_fp_rd_addr),
    .rd_data(wb_fp_data),
    .write_single(~memwb_fp_fmt)  // 1 表示单精度（fmt=0），0 表示双精度（fmt=1）
  );

  // ID 阶段 FP 寄存器转发多路复用器
  // 由集中转发单元输出驱动
  // 优先级：EX > MEM > WB > FP 寄存器文件

  assign id_fp_rs1_data = (id_fp_forward_a == 3'b100) ? ex_fp_result :      // 来自 EX 阶段的转发
                          (id_fp_forward_a == 3'b010) ? exmem_fp_result :   // 来自 MEM 阶段的转发
                          (id_fp_forward_a == 3'b001) ? wb_fp_data :        // 来自 WB 阶段的转发
                          id_fp_rs1_data_raw;                                // 使用 FP 寄存器文件值

  assign id_fp_rs2_data = (id_fp_forward_b == 3'b100) ? ex_fp_result :      // 来自 EX 阶段的转发
                          (id_fp_forward_b == 3'b010) ? exmem_fp_result :   // 来自 MEM 阶段的转发
                          (id_fp_forward_b == 3'b001) ? wb_fp_data :        // 来自 WB 阶段的转发
                          id_fp_rs2_data_raw;                                // 使用 FP 寄存器文件值

  assign id_fp_rs3_data = (id_fp_forward_c == 3'b100) ? ex_fp_result :      // 来自 EX 阶段的转发
                          (id_fp_forward_c == 3'b010) ? exmem_fp_result :   // 来自 MEM 阶段的转发
                          (id_fp_forward_c == 3'b001) ? wb_fp_data :        // 来自 WB 阶段的转发
                          id_fp_rs3_data_raw;                                // 使用 FP 寄存器文件值

  // 立即数选择
  // 对于原子操作，强制立即数为 0（地址为 rs1 + 0）
  assign id_immediate = id_is_atomic_dec ? {XLEN{1'b0}} :
                        (id_imm_sel == 3'b000) ? id_imm_i :
                        (id_imm_sel == 3'b001) ? id_imm_s :
                        (id_imm_sel == 3'b010) ? id_imm_b :
                        (id_imm_sel == 3'b011) ? id_imm_u :
                        (id_imm_sel == 3'b100) ? id_imm_j :
                        {XLEN{1'b0}};

  // CSR 地址提取（来自立即数字段 bits[31:20]）
  assign id_csr_addr = ifid_instruction[31:20];

  // CSR 写入数据（来自 rs1 数据或零扩展的 uimm，取决于 rs1 字段）
  assign id_csr_wdata = id_csr_src ? {{(XLEN-5){1'b0}}, id_rs1} : id_rs1_data;

  // CSR 写使能抑制（RISC-V 规范要求）
  // 对于 CSRRS/CSRRC（funct3[1]=1）：如果 rs1=x0，则不写入（只读操作）
  // 对于 CSRRSI/CSRRCI（funct3[1]=1）：如果 uimm=0，则不写入（只读操作）
  // 这允许读取只读 CSR 而不会触发非法指令异常
  // 抑制条件：（funct3[1] == 1）且（rs1 字段 == 0）
  wire id_csr_write_suppress = id_funct3[1] && (id_rs1 == 5'h0);
  wire id_csr_we_actual = id_csr_we && !id_csr_write_suppress;

  // 冒险检测单元
  hazard_detection_unit hazard_unit (
    .clk(clk),
    // 整数 加载-使用 冒险输入
    .idex_mem_read(idex_mem_read),
    .idex_rd(idex_rd_addr),
    .ifid_rs1(id_rs1),
    .ifid_rs2(id_rs2),
    // FP 加载-使用 冒险输入
    .idex_fp_rd(idex_fp_rd_addr),
    .idex_fp_mem_op(idex_fp_mem_op),
    .ifid_fp_rs1(id_rs1),           // FP 寄存器地址使用相同的 rs1/rs2/rs3 字段
    .ifid_fp_rs2(id_rs2),
    .ifid_fp_rs3(id_rs3),
    // M 扩展
    .mul_div_busy(ex_mul_div_busy),
    .idex_is_mul_div(idex_is_mul_div),
    // A 扩展
    .atomic_busy(ex_atomic_busy),
    .atomic_done(ex_atomic_done),
    .idex_is_atomic(idex_is_atomic),
    .exmem_is_atomic(exmem_is_atomic),
    .exmem_rd(exmem_rd_addr),
    // F/D 扩展
    .fpu_busy(ex_fpu_busy),
    .fpu_done(ex_fpu_done),
    .idex_fp_alu_en(idex_fp_alu_en),
    .exmem_fp_reg_write(exmem_fp_reg_write),
    .memwb_fp_reg_write(memwb_fp_reg_write),
    // CSR 信号（用于 FFLAGS/FCSR 依赖检查和 RAW 冒险）
    .id_csr_addr(id_csr_addr),
    .id_csr_we(id_csr_we),
    .id_is_csr(id_is_csr_dec),
    .idex_csr_we(idex_csr_we),
    .exmem_csr_we(exmem_csr_we),
    .memwb_csr_we(memwb_csr_we),
    // xRET 信号（MRET/SRET 修改 CSR）
    .exmem_is_mret(exmem_is_mret),
    .exmem_is_sret(exmem_is_sret),
    // MMU
    .mmu_busy(mmu_busy),
    // 总线信号（第 52 课 - 修复 CLINT/外设存储挂起）
    .bus_req_valid(bus_req_valid),
    .bus_req_ready(bus_req_ready),
    // 输出
    .stall_pc(stall_pc),
    .stall_ifid(stall_ifid),
    .bubble_idex(flush_idex_hazard)
  );

  // ID/EX 流水线寄存器
  idex_register #(
    .XLEN(XLEN),
    .FLEN(`FLEN)
  ) idex_reg (
    .clk(clk),
    .reset_n(reset_n),
    .hold(hold_exmem),
    .flush(flush_idex),
    // 数据输入
    .pc_in(ifid_pc),
    .rs1_data_in(id_rs1_data),
    .rs2_data_in(id_rs2_data),
    .rs1_addr_in(id_rs1),
    .rs2_addr_in(id_rs2),
    .rd_addr_in(id_rd),
    .imm_in(id_immediate),
    .opcode_in(id_opcode),
    .funct3_in(id_funct3),
    .funct7_in(id_funct7),
    // 控制输入
    .alu_control_in(id_alu_control),
    .alu_src_in(id_alu_src),
    .branch_in(id_branch),
    .jump_in(id_jump),
    .mem_read_in(id_mem_read),
    .mem_write_in(id_mem_write),
    .reg_write_in(id_reg_write),
    .wb_sel_in(id_wb_sel),
    .valid_in(ifid_valid),
    // M 扩展输入
    .is_mul_div_in(id_is_mul_div_dec),
    .mul_div_op_in(id_mul_div_op_dec),
    .is_word_op_in(id_is_word_op_dec),
    // A 扩展输入
    .is_atomic_in(id_is_atomic_dec),
    .funct5_in(id_funct5_dec),
    .aq_in(id_aq_dec),
    .rl_in(id_rl_dec),
    // F/D 扩展输入
    .fp_rs1_data_in(id_fp_rs1_data),
    .fp_rs2_data_in(id_fp_rs2_data),
    .fp_rs3_data_in(id_fp_rs3_data),
    .fp_rs1_addr_in(id_rs1),
    .fp_rs2_addr_in(id_rs2),
    .fp_rs3_addr_in(id_rs3),
    .fp_rd_addr_in(id_rd),
    .fp_reg_write_in(id_fp_reg_write),
    .int_reg_write_fp_in(id_int_reg_write_fp),
    .fp_mem_op_in(id_fp_mem_op),
    .fp_alu_en_in(id_fp_alu_en),
    .fp_alu_op_in(id_fp_alu_op),
    .fp_rm_in(id_fp_rm),
    .fp_use_dynamic_rm_in(id_fp_use_dynamic_rm),
    .fp_fmt_in(id_fp_fmt),
    // CSR 输入
    .csr_addr_in(id_csr_addr),
    .csr_we_in(id_csr_we_actual),
    .csr_src_in(id_csr_src),
    .csr_wdata_in(id_csr_wdata),
    .is_csr_in(id_is_csr_dec),
    // 异常输入
    .is_ecall_in(id_is_ecall),
    .is_ebreak_in(id_is_ebreak),
    .is_mret_in(id_is_mret),
    .is_sret_in(id_is_sret),
    .is_sfence_vma_in(id_is_sfence_vma),
    .illegal_inst_in(id_illegal_inst),
    .instruction_in(ifid_instruction),
    // C 扩展输入
    .is_compressed_in(ifid_is_compressed),
    // 数据输出
    .pc_out(idex_pc),
    .rs1_data_out(idex_rs1_data),
    .rs2_data_out(idex_rs2_data),
    .rs1_addr_out(idex_rs1_addr),
    .rs2_addr_out(idex_rs2_addr),
    .rd_addr_out(idex_rd_addr),
    .imm_out(idex_imm),
    .opcode_out(idex_opcode),
    .funct3_out(idex_funct3),
    .funct7_out(idex_funct7),
    // 控制输出
    .alu_control_out(idex_alu_control),
    .alu_src_out(idex_alu_src),
    .branch_out(idex_branch),
    .jump_out(idex_jump),
    .mem_read_out(idex_mem_read),
    .mem_write_out(idex_mem_write),
    .reg_write_out(idex_reg_write),
    .wb_sel_out(idex_wb_sel),
    .valid_out(idex_valid),
    // M 扩展输出
    .is_mul_div_out(idex_is_mul_div),
    .mul_div_op_out(idex_mul_div_op),
    .is_word_op_out(idex_is_word_op),
    // A 扩展输出
    .is_atomic_out(idex_is_atomic),
    .funct5_out(idex_funct5),
    .aq_out(idex_aq),
    .rl_out(idex_rl),
    // F/D 扩展输出
    .fp_rs1_data_out(idex_fp_rs1_data),
    .fp_rs2_data_out(idex_fp_rs2_data),
    .fp_rs3_data_out(idex_fp_rs3_data),
    .fp_rs1_addr_out(idex_fp_rs1_addr),
    .fp_rs2_addr_out(idex_fp_rs2_addr),
    .fp_rs3_addr_out(idex_fp_rs3_addr),
    .fp_rd_addr_out(idex_fp_rd_addr),
    .fp_reg_write_out(idex_fp_reg_write),
    .int_reg_write_fp_out(idex_int_reg_write_fp),
    .fp_mem_op_out(idex_fp_mem_op),
    .fp_alu_en_out(idex_fp_alu_en),
    .fp_alu_op_out(idex_fp_alu_op),
    .fp_rm_out(idex_fp_rm),
    .fp_use_dynamic_rm_out(idex_fp_use_dynamic_rm),
    .fp_fmt_out(idex_fp_fmt),
    // CSR 输出
    .csr_addr_out(idex_csr_addr),
    .csr_we_out(idex_csr_we),
    .csr_src_out(idex_csr_src),
    .csr_wdata_out(idex_csr_wdata),
    .is_csr_out(idex_is_csr),
    // 异常输出
    .is_ecall_out(idex_is_ecall),
    .is_ebreak_out(idex_is_ebreak),
    .is_mret_out(idex_is_mret),
    .is_sret_out(idex_is_sret),
    .is_sfence_vma_out(idex_is_sfence_vma),
    .illegal_inst_out(idex_illegal_inst),
    .instruction_out(idex_instruction),
    // C 扩展输出
    .is_compressed_out(idex_is_compressed)
  );

  //==========================================================================
  // EX 阶段：执行
  //==========================================================================

  // Bug #42: C.JAL 和 C.JALR 必须保存 PC+2，而不是 PC+4
  assign ex_pc_plus_4 = idex_is_compressed ? (idex_pc + {{(XLEN-2){1'b0}}, 2'b10}) :
                                              (idex_pc + {{(XLEN-3){1'b0}}, 3'b100});

  // 转发单元（所有阶段的集中转发逻辑）
  forwarding_unit forward_unit (
    // ID 阶段整数转发（用于分支）
    .id_rs1(id_rs1),
    .id_rs2(id_rs2),
    .id_forward_a(id_forward_a),
    .id_forward_b(id_forward_b),

    // EX 阶段整数转发（用于 ALU 操作）
    .idex_rs1(idex_rs1_addr),
    .idex_rs2(idex_rs2_addr),
    .forward_a(forward_a),
    .forward_b(forward_b),

    // 流水线阶段写端口
    .idex_rd(idex_rd_addr),
    .idex_reg_write(idex_reg_write),
    .idex_is_atomic(idex_is_atomic),
    .exmem_rd(exmem_rd_addr),
    .exmem_reg_write(exmem_reg_write),
    .exmem_int_reg_write_fp(exmem_int_reg_write_fp),
    .memwb_rd(memwb_rd_addr),
    .memwb_reg_write(memwb_reg_write),
    .memwb_int_reg_write_fp(memwb_int_reg_write_fp),
    .memwb_valid(memwb_valid),

    // ID 阶段 FP 转发
    .id_fp_rs1(id_rs1),
    .id_fp_rs2(id_rs2),
    .id_fp_rs3(id_rs3),
    .id_fp_forward_a(id_fp_forward_a),
    .id_fp_forward_b(id_fp_forward_b),
    .id_fp_forward_c(id_fp_forward_c),

    // EX 阶段 FP 转发
    .idex_fp_rs1(idex_fp_rs1_addr),
    .idex_fp_rs2(idex_fp_rs2_addr),
    .idex_fp_rs3(idex_fp_rs3_addr),
    .fp_forward_a(fp_forward_a),
    .fp_forward_b(fp_forward_b),
    .fp_forward_c(fp_forward_c),

    // FP 流水线阶段写端口
    .idex_fp_rd(idex_fp_rd_addr),
    .idex_fp_reg_write(idex_fp_reg_write),
    .exmem_fp_rd(exmem_fp_rd_addr),
    .exmem_fp_reg_write(exmem_fp_reg_write),
    .memwb_fp_rd(memwb_fp_rd_addr),
    .memwb_fp_reg_write(memwb_fp_reg_write)
  );

  // ALU 操作数 A 选择（带转发）
  // AUIPC 使用 PC，LUI 使用 0，其他使用 rs1
  assign ex_alu_operand_a = (idex_opcode == 7'b0010111) ? idex_pc :          // AUIPC
                            (idex_opcode == 7'b0110111) ? {XLEN{1'b0}} :   // LUI
                            idex_rs1_data;                                    // Others

  // 禁用 LUI 和 AUIPC 的转发（它们不使用 rs1，解码器提取的是垃圾）
  wire disable_forward_a = (idex_opcode == 7'b0110111) || (idex_opcode == 7'b0010111);  // LUI 或 AUIPC

  assign ex_alu_operand_a_forwarded = disable_forward_a ? ex_alu_operand_a :            // 不对 LUI/AUIPC 转发
                                      (forward_a == 2'b10) ? exmem_forward_data : // EX 冒险 (包括 FP 到整数)
                                      (forward_a == 2'b01) ? wb_data :  // MEM 冒险
                                      ex_alu_operand_a; // 无冒险

  `ifdef DEBUG_M_OPERANDS
  always @(*) begin
    if (idex_is_mul_div) begin
      $display("[M_OPERANDS] @%0t operand_a: idex_rs1_data=%h fwd_a=%b exmem=%h wb=%h → result=%h",
               $time, idex_rs1_data, forward_a, exmem_alu_result, wb_data, ex_alu_operand_a_forwarded);
    end
  end
  `endif

  // 转发数据选择：对原子指令使用 atomic_result，对 FP 到整数使用 int_result_fp，对 M 扩展使用 mul_div_result，否则使用 alu_result
  wire [XLEN-1:0] exmem_forward_data;
  assign exmem_forward_data = exmem_is_atomic ? exmem_atomic_result :
                              exmem_int_reg_write_fp ? exmem_int_result_fp :
                              (exmem_wb_sel == 3'b011) ? exmem_csr_rdata :  // CSR 读取结果
                              (exmem_wb_sel == 3'b100) ? exmem_mul_div_result :  // M 扩展结果
                              exmem_alu_result;

  // rs1 数据转发 (用于 SFENCE.VMA 以及其他直接使用 rs1 数据的指令)
  wire [XLEN-1:0] ex_rs1_data_forwarded;
  assign ex_rs1_data_forwarded = (forward_a == 2'b10) ? exmem_forward_data :       // EX 冒险
                                  (forward_a == 2'b01) ? wb_data :  // MEM 冒险
                                  idex_rs1_data;  // 无冒险
  // ALU Operand B selection (with forwarding)
  wire [XLEN-1:0] ex_rs2_data_forwarded;
  assign ex_rs2_data_forwarded = (forward_b == 2'b10) ? exmem_forward_data :       // EX 冒险
                                  (forward_b == 2'b01) ? wb_data :  // MEM 冒险
                                  idex_rs2_data;  // 无冒险

  `ifdef DEBUG_ATOMIC
  always @(*) begin
    if (idex_is_atomic && a_unit_start) begin
      $display("[FORWARD_ATOMIC] @%0t SC/LR start: rs2=x%0d, forward_b=%b, idex_rs2=%h, exmem_fwd=%h, wb=%h → result=%h",
               $time, idex_rs2_addr, forward_b, idex_rs2_data, exmem_forward_data, wb_data, ex_rs2_data_forwarded);
      $display("[FORWARD_ATOMIC] exmem_is_atomic=%b, exmem_atomic_result=%h, exmem_alu_result=%h, exmem_rd=x%0d",
               exmem_is_atomic, exmem_atomic_result, exmem_alu_result, exmem_rd_addr);
    end
  end
  `endif

  `ifdef DEBUG_M_OPERANDS
  always @(*) begin
    if (idex_is_mul_div) begin
      $display("[M_OPERANDS] @%0t operand_b: idex_rs2_data=%h fwd_b=%b exmem=%h wb=%h → result=%h",
               $time, idex_rs2_data, forward_b, exmem_alu_result, wb_data, ex_rs2_data_forwarded);
    end
  end
  `endif

  assign ex_alu_operand_b = idex_alu_src ? idex_imm : ex_rs2_data_forwarded;

  // RV64I: 检测字操作（在 32 位上运算，并对结果进行符号扩展）
  // OP_IMM_32 (0x1B): ADDIW, SLLIW, SRLIW, SRAIW
  // OP_OP_32  (0x3B): ADDW, SUBW, SLLW, SRLW, SRAW
  wire is_word_alu_op = (XLEN == 64) &&
                        ((idex_opcode == 7'b0011011) ||  // OP_IMM_32
                         (idex_opcode == 7'b0111011));   // OP_OP_32

  // 对于字操作，根据操作类型准备操作数：
  // - 算术右移（SRAIW/SRAW）：对操作数 A 做符号扩展以保留符号位
  // - 其他所有操作：对低 32 位做零扩展
  // 最终结果会在运算后根据第 31 位做符号扩展
  wire is_arith_shift_word = is_word_alu_op && (idex_funct3 == 3'b101) && idex_funct7[5];

  wire [XLEN-1:0] ex_alu_operand_a_final = is_arith_shift_word ?
                                            {{32{ex_alu_operand_a_forwarded[31]}}, ex_alu_operand_a_forwarded[31:0]} :
                                            is_word_alu_op ?
                                            {{32{1'b0}}, ex_alu_operand_a_forwarded[31:0]} :
                                            ex_alu_operand_a_forwarded;

  // 对于字移位操作（SLLW、SRLW、SRAW），将移位量限制为 5 位
  // 移位操作的 funct3 为 001（SLL）或 101（SRL/SRA）
  wire is_shift_op = (idex_funct3 == 3'b001) || (idex_funct3 == 3'b101);
  wire [XLEN-1:0] ex_alu_operand_b_final = (is_word_alu_op && is_shift_op) ?
                                            {{(XLEN-5){1'b0}}, ex_alu_operand_b[4:0]} :  // 对于字移位操作，将移位量限制为 5 位
                                            is_word_alu_op ?
                                            {{32{1'b0}}, ex_alu_operand_b[31:0]} :
                                            ex_alu_operand_b;

  // ALU
  alu #(
    .XLEN(XLEN)
  ) alu_inst (
    .operand_a(ex_alu_operand_a_final),
    .operand_b(ex_alu_operand_b_final),
    .alu_control(idex_alu_control),
    .result(ex_alu_result),
    .zero(ex_alu_zero),
    .less_than(ex_alu_lt),
    .less_than_unsigned(ex_alu_ltu)
  );

  // RV64I: 符号扩展字操作结果到 64 位
  // ALU 对符号扩展的 32 位输入进行运算，产生 64 位结果
  // 需要对结果的低 32 位进行符号扩展
  wire [XLEN-1:0] ex_alu_result_sext = is_word_alu_op ?
                                       {{32{ex_alu_result[31]}}, ex_alu_result[31:0]} :
                                       ex_alu_result;

  // 调试：ALU 输出
  `ifdef DEBUG_ALU
  always @(posedge clk) begin
    if (idex_valid && !idex_is_mul_div && !idex_fp_alu_en) begin
      $display("[ALU] @%0t pc=%h result=%h (opcode=%b rd=x%0d)",
               $time, idex_pc, ex_alu_result, idex_opcode, idex_rd_addr);
    end
  end
  `endif

  // 调试：字操作（RV64I）
  `ifdef DEBUG_WORD_OPS
  integer cycle_num = 0;

  always @(posedge clk) begin
    if (reset_n) cycle_num <= cycle_num + 1;
    else cycle_num <= 0;
  end

  always @(posedge clk) begin
    if (reset_n && ifid_valid) begin
      $display("[C%04d] IF: PC=%h instr=%h", cycle_num, ifid_pc, ifid_instruction);
    end
  end

  always @(posedge clk) begin
    if (idex_valid && is_word_alu_op) begin
      $display("[C%04d] WORD_OP_EX: pc=%h opcode=%b funct3=%b rd=x%0d",
               cycle_num, idex_pc, idex_opcode, idex_funct3, idex_rd_addr);
      $display("       Operand A: raw=%h zero-ext=%h", ex_alu_operand_a_forwarded, ex_alu_operand_a_final);
      $display("       Operand B: raw=%h zero-ext=%h", ex_alu_operand_b, ex_alu_operand_b_final);
      $display("       ALU result: raw=%h sign-ext=%h", ex_alu_result, ex_alu_result_sext);
    end
  end

  always @(posedge clk) begin
    if (int_reg_write_enable && memwb_rd_addr != 0) begin
      $display("[C%04d] WB: x%0d <= %h", cycle_num, memwb_rd_addr, wb_data);
    end
  end
  `endif

  // M 扩展：当指令首次进入 EX 阶段时锁存操作数
  // 这防止了在长时间的 M 操作中转发路径变化导致的数据损坏
  // 重要：锁存转发的值，而不是原始的 IDEX 值，因为当 M 指令依赖于最近的指令时需要转发
  reg [XLEN-1:0] m_operand_a_latched;
  reg [XLEN-1:0] m_operand_b_latched;
  reg m_operands_valid;

  always @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
      m_operand_a_latched <= {XLEN{1'b0}};
      m_operand_b_latched <= {XLEN{1'b0}};
      m_operands_valid <= 1'b0;
    end else if (idex_is_mul_div && !ex_mul_div_busy && !m_operands_valid) begin
      // 锁存转发的操作数，当 M 指令首次进入 EX（在开始执行之前）
      // 这捕获了正确的转发值，防止后续指令污染
      m_operand_a_latched <= ex_alu_operand_a_forwarded;
      m_operand_b_latched <= ex_rs2_data_forwarded;
      m_operands_valid <= 1'b1;
    end else if (ex_mul_div_ready || !idex_is_mul_div) begin
      // 清除有效标志，当 M 指令完成或非 M 指令进入 EX
      // 这确保连续的 M 指令获得新的操作数（第 60 课）
      m_operands_valid <= 1'b0;
    end
  end

  // 选择锁存的操作数（用于 M 单元）和转发的操作数（用于其他单元）
  wire [XLEN-1:0] m_final_operand_a = m_operands_valid ? m_operand_a_latched : ex_alu_operand_a_forwarded;
  wire [XLEN-1:0] m_final_operand_b = m_operands_valid ? m_operand_b_latched : ex_rs2_data_forwarded;

  // M 扩展单元
  mul_div_unit #(
    .XLEN(XLEN)
  ) m_unit (
    .clk(clk),
    .reset_n(reset_n),
    .start(m_unit_start),
    .operation(idex_mul_div_op),
    .is_word_op(idex_is_word_op),
    .operand_a(m_final_operand_a),
    .operand_b(m_final_operand_b),
    .result(ex_mul_div_result),
    .busy(ex_mul_div_busy),
    .ready(ex_mul_div_ready)
  );

  // A 扩展 - 原子操作单元
  wire [XLEN-1:0] ex_atomic_result;
  wire            ex_atomic_done;
  wire            ex_atomic_busy;
  wire            ex_atomic_mem_req;
  wire            ex_atomic_mem_we;
  wire [XLEN-1:0] ex_atomic_mem_addr;
  wire [XLEN-1:0] ex_atomic_mem_wdata;
  wire [2:0]      ex_atomic_mem_size;
  wire            ex_atomic_mem_ready;

  // A 扩展单元启动信号：当 A 指令首次进入 EX 时产生脉冲
  // 跟踪当前 IDEX 中的原子指令是否已经执行过
  reg atomic_already_started;

  always @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
      atomic_already_started <= 1'b0;
    end else if (flush_idex) begin
      // 清除 IDEX，重置标志
      atomic_already_started <= 1'b0;
    end else if (!hold_exmem && idex_valid) begin
      // 指令从 IDEX 移动到 EXMEM（下一周期新指令将进入 IDEX）
      atomic_already_started <= 1'b0;
    end else if (ex_atomic_done) begin
      // 原子操作完成，设置标志以防止重新启动
      atomic_already_started <= 1'b1;
    end
  end

  wire            a_unit_start;
  assign a_unit_start = idex_is_atomic && idex_valid && !ex_atomic_busy && !ex_atomic_done && !atomic_already_started;

  // 预留站信号
  wire            ex_lr_valid;
  wire [XLEN-1:0] ex_lr_addr;
  wire            ex_sc_valid;
  wire [XLEN-1:0] ex_sc_addr;
  wire            ex_sc_success;

  atomic_unit #(
    .XLEN(XLEN)
  ) atomic_unit_inst (
    .clk(clk),
    .reset(!reset_n),
    .start(a_unit_start),
    .funct5(idex_funct5),
    .funct3(idex_funct3),
    .aq(idex_aq),
    .rl(idex_rl),
    .addr(ex_alu_operand_a_forwarded),
    .src_data(ex_rs2_data_forwarded),
    // 内存接口（通过多路复用器连接到数据内存）
    .mem_req(ex_atomic_mem_req),
    .mem_we(ex_atomic_mem_we),
    .mem_addr(ex_atomic_mem_addr),
    .mem_wdata(ex_atomic_mem_wdata),
    .mem_size(ex_atomic_mem_size),
    .mem_rdata(mem_read_data),
    .mem_ready(ex_atomic_mem_ready),
    // 预留站接口
    .lr_valid(ex_lr_valid),
    .lr_addr(ex_lr_addr),
    .sc_valid(ex_sc_valid),
    .sc_addr(ex_sc_addr),
    .sc_success(ex_sc_success),
    // 输出
    .result(ex_atomic_result),
    .done(ex_atomic_done),
    .busy(ex_atomic_busy)
  );

  // 原子保留站在存储操作上的失效
  // 当任何存储操作在 MEM 阶段写入内存时，失效 LR 保留
  wire reservation_invalidate;
  wire [XLEN-1:0] reservation_inv_addr;

  // 仅当带有存储的新指令进入 MEM 阶段时失效保留
  // 跟踪上周期 EXMEM 是否被保持 - 如果保持，则释放意味着
  // EX 中的指令现在首次进入 MEM
  reg hold_exmem_prev;
  always @(posedge clk or negedge reset_n) begin
    if (!reset_n)
      hold_exmem_prev <= 1'b0;
    else
      hold_exmem_prev <= hold_exmem;
  end

  // 失效条件：（1）上周期 EXMEM 被保持且现在释放（指令进入 MEM）
  //           或（2）上周期 EXMEM 未被保持（正常流水线流动 - 指令刚进入 MEM）
  // 基本上：在指令进入 MEM 阶段的第一周期失效
  assign reservation_invalidate = exmem_mem_write && !exmem_is_atomic && !hold_exmem_prev && exmem_valid;
  assign reservation_inv_addr = exmem_alu_result;

  `ifdef DEBUG_ATOMIC
  always @(posedge clk) begin
    if (reservation_invalidate) begin
      $display("[CORE] Reservation invalidate: PC=0x%08h, mem_wr=%b, is_atomic=%b, hold=%b, valid=%b, addr=0x%08h",
               exmem_pc, exmem_mem_write, exmem_is_atomic, hold_exmem, exmem_valid, exmem_alu_result);
    end
    if (idex_is_atomic && idex_valid) begin
      $display("[CORE] Atomic in IDEX: PC=0x%08h, is_atomic=%b, hold_exmem=%b, done=%b, result=0x%08h",
               idex_pc, idex_is_atomic, hold_exmem, ex_atomic_done, ex_atomic_result);
    end
    if (exmem_is_atomic && exmem_valid) begin
      $display("[CORE] Atomic in EXMEM: PC=0x%08h, is_atomic=%b, mem_wr=%b, result=0x%08h",
               exmem_pc, exmem_is_atomic, exmem_mem_write, exmem_atomic_result);
    end
    if (idex_pc == 32'h20 && idex_valid) begin
      $display("[CORE] BNEZ in IDEX: PC=0x%08h, rs1(t3)=x%0d, rs1_data=0x%08h, id_forward_a=%b",
               idex_pc, idex_rs1_addr, idex_rs1_data, id_forward_a);
      $display("      exmem: rd=x%0d, reg_wr=%b, valid=%b, is_atomic=%b",
               exmem_rd_addr, exmem_reg_write, exmem_valid, exmem_is_atomic);
    end
  end
  `endif

  reservation_station #(
    .XLEN(XLEN)
  ) reservation_station_inst (
    .clk(clk),
    .reset(!reset_n),
    .lr_valid(ex_lr_valid),
    .lr_addr(ex_lr_addr),
    .sc_valid(ex_sc_valid),
    .sc_addr(ex_sc_addr),
    .sc_success(ex_sc_success),
    .invalidate(reservation_invalidate),
    .inv_addr(reservation_inv_addr),
    .exception(exception),
    .interrupt(1'b0)                // TODO: 连接到中断信号，当实现时
  );

  // 分支单元
  branch_unit #(
    .XLEN(XLEN)
  ) branch_inst (
    .rs1_data(ex_alu_operand_a_forwarded),
    .rs2_data(ex_rs2_data_forwarded),
    .funct3(idex_funct3),
    .branch(idex_branch),
    .jump(idex_jump),
    .take_branch(ex_take_branch)
  );

  // 分支/跳转目标计算
  assign ex_branch_target = idex_pc + idex_imm;

  // JALR 使用 rs1 + imm, JAL 使用 PC + imm
  // 清除 JALR 的最低有效位（始终对齐到 2 字节）
  assign ex_jump_target = (idex_opcode == 7'b1100111) ?
                          (ex_alu_operand_a_forwarded + idex_imm) & ~{{(XLEN-1){1'b0}}, 1'b1} :
                          idex_pc + idex_imm;

  //==========================================================================
  // CSR 文件（在 EX 阶段进行读/写）
  //==========================================================================

  // CSR 写数据前递
  // CSR 写数据来自 rs1（对于寄存器形式的 CSR 指令）
  // 需要从 EX/MEM 或 MEM/WB 阶段前递以处理 RAW 冒险
  // 仅对寄存器形式的 CSR 指令进行前递（funct3[2] = 0）
  wire ex_csr_uses_rs1;
  assign ex_csr_uses_rs1 = (idex_wb_sel == 3'b011) && !idex_csr_src;  // 使用 rs1 的 CSR 指令

  wire [XLEN-1:0] ex_csr_wdata_forwarded;
  assign ex_csr_wdata_forwarded = (ex_csr_uses_rs1 && forward_a == 2'b10) ? exmem_alu_result :  // EX 到 EX 转发
                                  (ex_csr_uses_rs1 && forward_a == 2'b01) ? wb_data :           // MEM 到 EX 转发
                                  idex_csr_wdata;                                                 // 无冒险或立即数形式

  `ifdef DEBUG_PRIV
  reg [31:0] debug_cycle;
  always @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
      debug_cycle <= 0;
    end else begin
      debug_cycle <= debug_cycle + 1;
      if (mret_flush || sret_flush) begin
        $display("[PIPE] Cycle %0d: xRET flush - PC=0x%08x->0x%08x ifid_valid=%b idex_valid=%b stall_pc=%b",
                 debug_cycle, pc_current, pc_next, ifid_valid, idex_valid, stall_pc);
      end
      if (debug_cycle > 0 && pc_current >= 32'h4c && pc_current <= 32'h60) begin
        $display("[PIPE] Cycle %0d: PC=0x%08x ifid_PC=0x%08x ifid_valid=%b idex_PC=0x%08x idex_valid=%b idex_is_csr=%b stall=%b",
                 debug_cycle, pc_current, ifid_pc, ifid_valid, idex_pc, idex_valid, idex_is_csr, stall_pc);
      end
    end
  end
  `endif

  `ifdef DEBUG_CSR
  reg [31:0] debug_cycle_csr;
  always @(posedge clk or negedge reset_n) begin
    if (!reset_n)
      debug_cycle_csr <= 0;
    else
      debug_cycle_csr <= debug_cycle_csr + 1;
  end

  always @(posedge clk) begin
    if (idex_is_csr) begin
      $display("[CORE_CSR] Cycle %0d: CSR in EX: addr=0x%03x is_csr=%b valid=%b access=%b PC=0x%08x priv=%b",
               debug_cycle_csr, idex_csr_addr, idex_is_csr, idex_valid, idex_is_csr && idex_valid, idex_pc, current_priv);
    end
  end
  `endif

  csr_file #(
    .XLEN(XLEN)
  ) csr_file_inst (
    .clk(clk),
    .reset_n(reset_n),
    .csr_addr(idex_csr_addr),
    .csr_wdata(ex_csr_wdata_forwarded),  // 使用前递值
    .csr_op(idex_funct3),           // funct3 编码 CSR 操作
    .csr_we(idex_csr_we && idex_valid && !exception),  // 异常时不提交 CSR 写入
    .csr_access(idex_is_csr && idex_valid),
    .csr_rdata(ex_csr_rdata),
    .trap_entry(trap_flush),       // 使用 trap_flush（已在 xRET 期间抑制异常）
    .trap_pc(exception_pc),        // 使用当前异常 PC（未注册）
    .trap_cause(exception_code),   // 使用当前异常代码（未注册）
    .trap_is_interrupt(combined_is_interrupt), // 指示这是中断还是异常
    .trap_val(exception_val),      // 使用当前异常值（未注册）
    .trap_vector(trap_vector),
    .mret(exmem_is_mret && exmem_valid && !exception),
    .mepc_out(mepc),
    .sret(exmem_is_sret && exmem_valid && !exception),
    .sepc_out(sepc),
    .mstatus_mie(mstatus_mie),
    .mstatus_sie(mstatus_sie),
    .mstatus_mpie(mstatus_mpie),
    .mstatus_spie(mstatus_spie),
    .illegal_csr(ex_illegal_csr),
    // 特权模式跟踪 (阶段 1)
    // Bug 修复：使用 effective_priv（带转发）进行 CSR 访问检查。
    // 对于陷阱委托，使用 current_priv（不带转发）以确保委托
    // 决策基于陷阱指令的实际特权模式。
    .current_priv(effective_priv),      // 对于 CSR 特权检查（带 xRET 转发）
    .actual_priv(current_priv),         // 对于陷阱委托（不带 xRET 转发）
    .trap_target_priv(trap_target_priv),
    .mpp_out(mpp),
    .spp_out(spp),
    .medeleg_out(medeleg),              // 用于核心中早期陷阱目标计算
    // 与 MMU 相关的输出（阶段 3）
    .satp_out(satp),
    .mstatus_sum(mstatus_sum),
    .mstatus_mxr(mstatus_mxr),
    // FPU 状态输出
    .mstatus_fs(mstatus_fs),
    // 浮点 CSR 连接
    .frm_out(csr_frm),
    .fflags_out(csr_fflags),
    // Bug #7b 修复：仅在 FP ALU 操作时累积标志，而不是在 FP 加载时
    // FP 加载的 wb_sel=001（来自内存的数据），FP ALU 使用其他 wb_sel 值
    // Bug #14 修复：包含 FP→INT 操作（fcvt.w.s, fclass 等）
    .fflags_we((memwb_fp_reg_write || memwb_int_reg_write_fp) && memwb_valid && (memwb_wb_sel != 3'b001)),
    .fflags_in({memwb_fp_flag_nv, memwb_fp_flag_dz, memwb_fp_flag_of, memwb_fp_flag_uf, memwb_fp_flag_nx}),
    // 外部中断输入（阶段 1.3：CLINT + PLIC 集成）
    .mtip_in(mtip_in),
    .msip_in(msip_in),
    .meip_in(meip_in),
    .seip_in(seip_in),
    // 中断寄存器输出（阶段 1.5：中断处理）
    .mip_out(mip),
    .mie_out(mie),
    .mideleg_out(mideleg)
    );

    // 用于 MMU 集成的别名
  assign csr_satp = satp;

  //==========================================================================
  // 中断处理（阶段 1.5）
  //==========================================================================
  // 中断被视为可在任何时间发生的异步异常
  // 优先级顺序（从高到低，符合 RISC-V 规范）:
  //   MEI (11) > MSI (3) > MTI (7) > SEI (9) > SSI (1) > STI (5)

  // 计算挂起且已使能的中断
  wire [XLEN-1:0] pending_interrupts = mip & mie;

  // 检查全局中断使能，基于当前特权模式
  wire interrupts_globally_enabled =
    (current_priv == 2'b11) ? mstatus_mie :  // M 模式：检查 MIE
    (current_priv == 2'b01) ? mstatus_sie :  // S 模式：检查 SIE
    1'b1;                                     // U 模式：始终使能

  // 中断优先级编码（符合 RISC-V 规范的优先级顺序）
  wire interrupt_pending;
  wire [4:0] interrupt_cause;
  wire interrupt_is_s_mode;  // 如果中断应捕获到 S 模式，则为真

  // 按优先级顺序检查每个中断
  wire mei_pending = pending_interrupts[11];  // 机器外部中断
  wire msi_pending = pending_interrupts[3];   // 机器软件中断
  wire mti_pending = pending_interrupts[7];   // 机器定时器中断
  wire sei_pending = pending_interrupts[9];   // 监督外部中断
  wire ssi_pending = pending_interrupts[1];   // 监督软件中断
  wire sti_pending = pending_interrupts[5];   // 监督定时器中断

  // 在 xRET 执行期间屏蔽中断以防止竞争条件
  // 当 MRET/SRET 在流水线中时，我们需要防止新的中断触发
  // 直到 xRET 完成并更新特权模式。否则，中断
  // 将使用旧的特权模式，可能导致错误的委托。
  wire xret_in_pipeline = (idex_is_mret || idex_is_sret) && idex_valid ||
                          (exmem_is_mret || exmem_is_sret) && exmem_valid;

  reg xret_completing;
  always @(posedge clk or negedge reset_n) begin
    if (!reset_n)
      xret_completing <= 1'b0;
    else
      xret_completing <= xret_in_pipeline;
  end

  // 优先级编码器（最高优先级获胜）
  // 在 xRET 在流水线中或正在完成时屏蔽中断
  assign interrupt_pending = interrupts_globally_enabled && |pending_interrupts &&
                             !xret_in_pipeline && !xret_completing;
  assign interrupt_cause =
    mei_pending ? 5'd11 :  // MEI
    msi_pending ? 5'd3  :  // MSI
    mti_pending ? 5'd7  :  // MTI
    sei_pending ? 5'd9  :  // SEI
    ssi_pending ? 5'd1  :  // SSI
    sti_pending ? 5'd5  :  // STI
    5'd0;                   // 无中断

  // 检查中断是否应委托给 S 模式
  // 仅当满足以下条件时委托：(1) 中断通过 mideleg 委托，且 (2) 当前处于 S 或 U 模式
  assign interrupt_is_s_mode = mideleg[interrupt_cause] && (current_priv <= 2'b01);

  // 调试中断处理
  `ifdef DEBUG_INTERRUPT
  reg [31:0] debug_cycle_intr;
  always @(posedge clk or negedge reset_n) begin
    if (!reset_n)
      debug_cycle_intr <= 0;
    else
      debug_cycle_intr <= debug_cycle_intr + 1;
  end

  always @(posedge clk) begin
    // 每 100 个周期调试一次以显示中断状态
    if (debug_cycle_intr % 100 == 50) begin
      $display("[CORE_INTR] cycle=%0d mtip_in=%b msip_in=%b meip_in=%b seip_in=%b",
               debug_cycle_intr, mtip_in, msip_in, meip_in, seip_in);
    end
    if (mtip_in || msip_in) begin
      $display("[INTR_IN] cycle=%0d mtip_in=%b msip_in=%b meip_in=%b seip_in=%b",
               debug_cycle_intr, mtip_in, msip_in, meip_in, seip_in);
      $display("[INTR_VAL] mip=%h mie=%h pending=%h",
               mip, mie, pending_interrupts);
    end
    if (|pending_interrupts) begin
      $display("[INTR] mip=%h mie=%h pending=%h mti=%b mstatus_mie=%b globally_en=%b intr_pend=%b",
               mip, mie, pending_interrupts, mti_pending, mstatus_mie, interrupts_globally_enabled, interrupt_pending);
      $display("[INTR] current_priv=%b exception_gated=%b exception_taken_r=%b trap_flush=%b PC=%h",
               current_priv, exception_gated, exception_taken_r, trap_flush, pc_current);
      // 显示中断可能被阻止的原因
      if (!interrupt_pending) begin
        $display("[INTR_BLOCKED] globally_en=%b xret_in_pipe=%b xret_completing=%b pending_nonzero=%b",
                 interrupts_globally_enabled, xret_in_pipeline, xret_completing, |pending_interrupts);
        $display("[INTR_BLOCKED] current_priv=%b mstatus_mie=%b mstatus_sie=%b",
                 current_priv, mstatus_mie, mstatus_sie);
      end
    end
    // 跟踪陷阱发生时的 PC
    if (exception_gated) begin
      $display("[TRAP] cycle=%0d exception_gated=1 PC=%h trap_vector=%h mepc=%h exception_pc=%h",
               debug_cycle_intr, pc_current, trap_vector, mepc, exception_pc);
    end
    // 跟踪陷阱后的 PC（下一周期）
    if (exception_taken_r) begin
      $display("[TRAP_PC] cycle=%0d exception_taken PC=%h mepc=%h", debug_cycle_intr, pc_current, mepc);
    end
    // 跟踪 MRET
    if (exmem_is_mret && exmem_valid) begin
      $display("[MRET_MEM] cycle=%0d exmem_PC=%h mepc=%h mret_flush=%b exception=%b interrupt_pending=%b xret_in_pipe=%b xret_completing=%b",
               debug_cycle_intr, exmem_pc, mepc, mret_flush, exception, interrupt_pending, xret_in_pipeline, xret_completing);
    end
    // 跟踪 PC 在周期 520 附近的跳转
    if (debug_cycle_intr >= 515 && debug_cycle_intr <= 545) begin
      $display("[PC_TRACE] cycle=%0d IF_PC=%h pc_next=%h trap_flush=%b mret_flush=%b",
               debug_cycle_intr, pc_current, pc_next, trap_flush, mret_flush);
    end
    // 跟踪执行挂起时的 PC（在“Tasks created...”消息之后）
    // 每 100 个周期采样一次以减少输出（扩展范围）
    if (debug_cycle_intr >= 25000 && debug_cycle_intr <= 150000 && (debug_cycle_intr % 100 == 0)) begin
      $display("[PC_SAMPLE] cycle=%0d PC=%h", debug_cycle_intr, pc_current);
    end
    // 调试 memset 函数入口和循环
    if (pc_current == 32'h00002000) begin
      // Memset 入口 - 跟踪参数：a0=x10, a1=x11, a2=x12
      $display("[MEMSET_ENTRY] cycle=%0d addr(a0/x10)=%h value(a1/x11)=%h size(a2/x12)=%h",
               debug_cycle_intr, regfile.registers[10], regfile.registers[11], regfile.registers[12]);
    end
    // 每 1000 个周期采样 memset 循环以查看进度
    if (pc_current >= 32'h2004 && pc_current <= 32'h200c && (debug_cycle_intr % 1000 == 0)) begin
      $display("[MEMSET_LOOP] cycle=%0d PC=%h counter(a2/x12)=%h",
               debug_cycle_intr, pc_current, regfile.registers[12]);
    end
    // 调试 vPortSetupTimerInterrupt mtime 读取循环
    if (pc_current == 32'h1aec && (debug_cycle_intr % 100 == 0)) begin
      $display("[MTIME_LOOP] cycle=%0d PC=%h a5(x15)=%h a3(x13)=%h a4(x14)=%h",
               debug_cycle_intr, pc_current, regfile.registers[15], regfile.registers[13], regfile.registers[14]);
    end
    // 调试陷阱处理程序 - 进入异常处理程序时检查 mcause
    if (pc_current == 32'h000001c2 || pc_current == 32'h000001d0) begin
      $display("[TRAP_HANDLER] cycle=%0d PC=%h ENTERED - mcause will be in t0(x5) after csrr",
               debug_cycle_intr, pc_current);
    end
    if (pc_current == 32'h000001ce || pc_current == 32'h000001dc) begin
      $display("[TRAP_STUCK] cycle=%0d PC=%h INFINITE_LOOP - t0(mcause)=%h t1(mepc)=%h t2(mstatus)=%h",
               debug_cycle_intr, pc_current, regfile.registers[5], regfile.registers[6], regfile.registers[7]);
    end
  end
  `endif

  //==========================================================================
  // 组合异常/中断处理
  //==========================================================================
  // 合并同步异常和异步中断
  // 同步异常优先于中断

  wire combined_exception;
  wire [4:0] combined_exception_code;
  wire [XLEN-1:0] combined_exception_pc;
  wire [XLEN-1:0] combined_exception_val;
  wire combined_is_interrupt;

  // 同步异常来自 exception_unit
  wire sync_exception;
  wire [4:0] sync_exception_code;
  wire [XLEN-1:0] sync_exception_pc;
  wire [XLEN-1:0] sync_exception_val;

  // 优先级：同步异常 > 中断
  assign exception = sync_exception || interrupt_pending;
  assign exception_code = sync_exception ? sync_exception_code : interrupt_cause;
  assign exception_pc = sync_exception ? sync_exception_pc : pc_current;
  assign exception_val = sync_exception ? sync_exception_val : {XLEN{1'b0}};
  assign combined_is_interrupt = !sync_exception && interrupt_pending;

  //==========================================================================
  // 异常单元（监视所有阶段）
  //==========================================================================

  // 检查是否启用地址转换：satp.MODE != 0 且 当前不在 M 模式
  // M 模式总是绕过地址转换（RISC-V 规范 4.4.1）
  // RV32: 使用 satp[31]（1 位模式字段），RV64: 使用 satp[63:60]（4 位模式字段）
  wire satp_mode_enabled = (XLEN == 32) ? csr_satp[31] : (csr_satp[63:60] != 4'b0000);
  wire translation_enabled = satp_mode_enabled && (current_priv != 2'b11);

  exception_unit #(
    .XLEN(XLEN)
  ) exception_unit_inst (
    // 特权模式（阶段 1）
    // 注意：异常委托由 CSR 文件的 trap_target_priv 输出决定，
    // 该输出使用实际的 current_priv。exception_unit 只负责检测异常。
    .current_priv(current_priv),
    // IF 阶段 - 取指阶段异常（检查 PC 未对齐）
    // 注意：IF 异常在指令进入 IFID 寄存器时进行检查
    .if_pc(ifid_pc),
    .if_valid(ifid_valid),          // 使用 IFID 寄存器输出的 valid 信号
    .if_page_fault(ifid_page_fault),        // Session 117
    .if_fault_vaddr(ifid_fault_vaddr),      // Session 117
    // ID 阶段 - 解码阶段异常（在 EX 流水级中处理）
    // 注意：只有在确实是 CSR 指令时才考虑 illegal_csr
    .id_illegal_inst((idex_illegal_inst | (ex_illegal_csr && idex_is_csr)) && idex_valid),
    .id_ecall(idex_is_ecall && idex_valid),
    .id_ebreak(idex_is_ebreak && idex_valid),
    .id_mret(idex_is_mret && idex_valid),
    .id_sret(idex_is_sret && idex_valid),
    .id_pc(idex_pc),
    .id_instruction(idex_instruction),
    .id_valid(idex_valid),
    // MEM 阶段 - 访存阶段异常
    .mem_addr(exmem_alu_result),
    .mem_read(exmem_mem_read && exmem_valid),
    .mem_write(exmem_mem_write && exmem_valid),
    .mem_funct3(exmem_funct3),
    .mem_pc(exmem_pc),
    .mem_instruction(exmem_instruction),
    .mem_valid(exmem_valid),
    // 页错误输入（阶段 3 - MMU 集成，从 EX 阶段寄存而来）
    // 如果刚刚进入陷阱，则屏蔽页错误（EXMEM 刷新有 1 个周期的延迟）
    // Session 113：关键修复 - 仅在启用地址转换时才产生页错误！
    // M 模式绕过地址转换，因此在 M 模式下不应产生页错误
    .mem_page_fault(exmem_page_fault && !trap_flush_r && translation_enabled),
    .mem_fault_vaddr(exmem_fault_vaddr),
    // 输出（连接到同步异常信号，将与中断合并）
    .exception(sync_exception),
    .exception_code(sync_exception_code),
    .exception_pc(sync_exception_pc),
    .exception_val(sync_exception_val)
  );

  // 确定异常是否来自内存阶段（以便进行精确的异常处理）
  // MEM 阶段异常：加载异常：加载/存储未对齐 (4,6)，加载/存储页错误 (13,15)
  // 使用门控异常以防止虚假异常检测
  wire exception_from_mem = exception_gated && ((exception_code == 5'd4) ||  // 加载未对齐
                                                 (exception_code == 5'd6) ||  // 存储未对齐
                                                 (exception_code == 5'd13) || // 加载页错误
                                                 (exception_code == 5'd15));  // 存储页错误

  //==========================================================================
  // FPU (浮点单元) - F/D 扩展
  //==========================================================================

  // FP 操作数转发多路复用器
  // FP 转发：使用 wb_fp_data 进行 MEMWB 转发以正确处理 FP 加载
  // 对于 FP 加载，数据来自内存 (wb_fp_data)，而不是来自 FPU (memwb_fp_result)
  assign ex_fp_operand_a = (fp_forward_a == 2'b10) ? exmem_fp_result :
                           (fp_forward_a == 2'b01) ? wb_fp_data :
                           idex_fp_rs1_data;

  assign ex_fp_operand_b = (fp_forward_b == 2'b10) ? exmem_fp_result :
                           (fp_forward_b == 2'b01) ? wb_fp_data :
                           idex_fp_rs2_data;

  assign ex_fp_operand_c = (fp_forward_c == 2'b10) ? exmem_fp_result :
                           (fp_forward_c == 2'b01) ? wb_fp_data :
                           idex_fp_rs3_data;

  // FP 舍入模式选择（动态来自 frm CSR 或静态来自指令）
  assign ex_fp_rounding_mode = idex_fp_use_dynamic_rm ? csr_frm : idex_fp_rm;

  // FPU 实例化
  fpu #(
    .FLEN(`FLEN),
    .XLEN(XLEN)
  ) fpu_inst (
    .clk(clk),
    .reset_n(reset_n),
    .start(fpu_start),
    .fp_alu_op(idex_fp_alu_op),
    .funct3(idex_funct3),
    .rs2(idex_rs2_addr),
    .funct7(idex_funct7),
    .rounding_mode(ex_fp_rounding_mode),
    .busy(ex_fpu_busy),
    .done(ex_fpu_done),
    .operand_a(ex_fp_operand_a),
    .operand_b(ex_fp_operand_b),
    .operand_c(ex_fp_operand_c),
    .int_operand(ex_alu_operand_a_forwarded),  // 用于 INT→FP 转换（使用转发的 rs1）
    .fp_result(ex_fp_result),
    .int_result(ex_int_result_fp),
    .flag_nv(ex_fp_flag_nv),
    .flag_dz(ex_fp_flag_dz),
    .flag_of(ex_fp_flag_of),
    .flag_uf(ex_fp_flag_uf),
    .flag_nx(ex_fp_flag_nx)
  );

  // 调试：FPU 输出
  `ifdef DEBUG_FPU_CONVERTER
  always @(posedge clk) begin
    if (ex_fpu_done) begin
      $display("[%0t] [FPU] done=1, fp_result=0x%h, busy=%b", $time, ex_fp_result, ex_fpu_busy);
    end
  end
  `endif

  // 存储数据路径：为 RV32D 支持分离整数和 FP 路径
  // 整数存储（RV64 上的 SB、SH、SW、SD）：使用转发的整数 rs2
  // FP 存储（FSW、FSD）：使用 FP 寄存器数据
  wire [XLEN-1:0] ex_mem_write_data_mux;       // 整数存储数据
  wire [`FLEN-1:0] ex_fp_mem_write_data_mux;   // FP 存储数据
  assign ex_mem_write_data_mux    = ex_rs2_data_forwarded;  // 整数存储始终使用整数 rs2
  assign ex_fp_mem_write_data_mux = ex_fp_operand_b;        // FP 存储使用 FP rs2

  //==========================================================================
  // CSR MRET/SRET 转发
  //==========================================================================
  // 当 MRET/SRET 在 MEM 阶段时，它会在周期结束时更新 mstatus。
  // 如果 mstatus/sstatus 的 CSR 读取在 EX 阶段，它需要更新后的值。
  // 转发“下一个” mstatus 值以避免读取过时数据。
  // 注意：MSTATUS 位位置和 CSR 地址定义在 rv_csr_defines.vh

  // 计算“下一个” mstatus 值（MRET 之后）
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

  // 计算“下一个” mstatus 值（SRET 之后）
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

  // 构造当前 mstatus 从各个位（匹配 csr_file.v 格式）
  wire [XLEN-1:0] current_mstatus_reconstructed;
  assign current_mstatus_reconstructed = {
    {(XLEN-32){1'b0}},            // 上位位（如果 XLEN > 32）
    12'b0,                        // 保留位 [31:20]
    mstatus_mxr,                  // MXR [19]
    mstatus_sum,                  // SUM [18]
    5'b0,                         // 保留位 [17:13]
    mpp,                          // MPP [12:11]
    2'b0,                         // 保留位 [10:9]
    spp,                          // SPP [8]
    mstatus_mpie,                 // MPIE [7]
    1'b0,                         // 保留位 [6]
    mstatus_spie,                 // SPIE [5]
    1'b0,                         // 保留位 [4]
    mstatus_mie,                  // MIE [3]
    1'b0,                         // 保留位 [2]
    mstatus_sie,                  // SIE [1]
    1'b0                          // 保留位 [0]
  };

  // 跟踪 MRET/SRET 来自上一周期（用于在冒险暂停后转发）
  // 这些标志必须保持设置，直到导致冒险的 CSR 读取实际执行
  reg exmem_is_mret_r;
  reg exmem_is_sret_r;
  reg exmem_valid_r;

  // 检测何时 CSR 指令消耗了转发
  // 仅在 CSR 读取实际完成时消耗（未被异常无效）
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
      // 当 MRET/SRET 在 MEM 阶段时设置，CSR 读取消耗时清除
      if (mret_forward_consumed) begin
        exmem_is_mret_r <= 1'b0;  // 转发被消耗时清除
      end else if (exmem_is_mret && exmem_valid && !exception) begin
        exmem_is_mret_r <= 1'b1;  // MRET 进入 MEM 时设置
      end
      // 否则：保持当前值（在暂停期间保持设置）

      if (sret_forward_consumed) begin
        exmem_is_sret_r <= 1'b0;  // 转发被消耗时清除
      end else if (exmem_is_sret && exmem_valid && !exception) begin
        exmem_is_sret_r <= 1'b1;  // SRET 进入 MEM 时设置
      end
      // 否则：保持当前值（在暂停期间保持设置）

      exmem_valid_r <= exmem_valid;

      `ifdef DEBUG_CSR_FORWARD
      if (exmem_is_mret && exmem_valid) begin
        $display("[CSR_FORWARD] MRET in MEM: setting mret_r");
      end
      if (mret_forward_consumed) begin
        $display("[CSR_FORWARD] CSR read consumed MRET forwarding: clearing mret_r");
      end
      if (exmem_is_mret_r && !mret_forward_consumed) begin
        $display("[CSR_FORWARD] Holding mret_r: waiting for CSR read in EX");
      end
      `endif
    end
  end

  // 转发 mstatus 如果：
  // 情况 1：MRET 现在在 MEM 阶段（同一周期 - 没有发生暂停）
  // 情况 2：MRET 在上一周期的 MEM 阶段（CSR 暂停，现在前进）
  // 被读取的 CSR 必须是 mstatus 或 sstatus
  wire forward_mret_mstatus = ((exmem_is_mret && exmem_valid && !exception) || exmem_is_mret_r) &&
                              (idex_is_csr && idex_valid) &&
                              ((idex_csr_addr == CSR_MSTATUS) || (idex_csr_addr == CSR_SSTATUS));

  wire forward_sret_mstatus = ((exmem_is_sret && exmem_valid && !exception) || exmem_is_sret_r) &&
                              (idex_is_csr && idex_valid) &&
                              ((idex_csr_addr == CSR_MSTATUS) || (idex_csr_addr == CSR_SSTATUS));

  wire [XLEN-1:0] ex_csr_rdata_forwarded;
  // 如果 MRET/SRET 是上一周期，mstatus 已经更新 - 只需使用当前值
  // 如果 MRET/SRET 是本周期，计算它将是什么
  wire [XLEN-1:0] mstatus_after_mret = exmem_is_mret_r ? current_mstatus_reconstructed :
                                        compute_mstatus_after_mret(current_mstatus_reconstructed, mstatus_mpie);
  wire [XLEN-1:0] mstatus_after_sret = exmem_is_sret_r ? current_mstatus_reconstructed :
                                        compute_mstatus_after_sret(current_mstatus_reconstructed, mstatus_spie);

  assign ex_csr_rdata_forwarded = forward_mret_mstatus ? mstatus_after_mret :
                                  forward_sret_mstatus ? mstatus_after_sret :
                                  ex_csr_rdata;  // 正常情况：不需要转发

  `ifdef DEBUG_CSR_FORWARD
  always @(posedge clk) begin
    if (forward_mret_mstatus || forward_sret_mstatus) begin
      $display("[CSR_FORWARD] Time=%0t forward_mret=%b forward_sret=%b", $time, forward_mret_mstatus, forward_sret_mstatus);
      $display("[CSR_FORWARD]   current_mstatus=%h forwarded_mstatus=%h", current_mstatus_reconstructed, ex_csr_rdata_forwarded);
      $display("[CSR_FORWARD]   exmem_is_mret=%b exmem_is_sret=%b exmem_valid=%b", exmem_is_mret, exmem_is_sret, exmem_valid);
      $display("[CSR_FORWARD]   idex_is_csr=%b idex_valid=%b idex_csr_addr=%h", idex_is_csr, idex_valid, idex_csr_addr);
    end
    if (idex_is_csr && idex_valid && ((idex_csr_addr == CSR_MSTATUS) || (idex_csr_addr == CSR_SSTATUS))) begin
      $display("[CSR_FORWARD] CSR read: addr=%h rdata=%h (forwarded=%h)", idex_csr_addr, ex_csr_rdata, ex_csr_rdata_forwarded);
      $display("[CSR_FORWARD]   Conditions: exmem_mret=%b exmem_mret_r=%b exmem_valid=%b exc=%b exc_code=%d",
               exmem_is_mret, exmem_is_mret_r, exmem_valid, exception, exception_code);
      $display("[CSR_FORWARD]   forward_mret=%b forward_sret=%b", forward_mret_mstatus, forward_sret_mstatus);
      $display("[CSR_FORWARD]   idex: PC=%h instr=%h is_ebreak=%b is_ecall=%b illegal=%b",
               idex_pc, idex_instruction, idex_is_ebreak, idex_is_ecall, idex_illegal_inst);
    end
  end
  `endif

  //==========================================================================
  // 特权模式前递（Bug 修复：阶段 6）
  //==========================================================================
  // 当 MRET/SRET 位于 MEM 阶段时，它会在该周期结束更新 current_priv。
  // 但是，已经在前面流水级（IF/ID/EX）的指令在进行 CSR 特权检查和
  // 异常委托决策时仍然使用“旧的” current_priv。
  //
  // 这会在 CSR 访问紧跟在 MRET/SRET 之后时导致错误行为：
  // - 例：MRET 将模式从 M→S，下一条指令访问 CSR
  // - CSR 检查看到的特权级仍是旧的 M，而不是新的 S
  // - 委托决策错误（M 模式陷阱永远不会被委托）
  //
  // 解决方案：将来自 MEM 阶段的新的特权模式前递到前面的流水级。
  //
  // 时间线：
  //   周期 N： MRET 在 MEM 阶段，next_instr 在 EX 阶段
  //            - MRET 根据 MPP 计算 new_priv
  //            - 将 new_priv 前递到 EX 阶段
  //            - next_instr 使用前递的特权级进行 CSR 检查
  //   周期 N+1：触发 MRET 刷新，current_priv 更新
  //
  // 注意：这类似于 CSR 数据前递，但作用对象是特权模式。

  // 计算来自 MEM 阶段 MRET/SRET 的新特权模式
  wire [1:0] mret_new_priv = mpp;              // MRET 从 MPP 恢复
  wire [1:0] sret_new_priv = {1'b0, spp};      // SRET 从 SPP 恢复 (0=U, 1=S)

  // 转发特权模式当 MRET/SRET 在 MEM 阶段时
  wire forward_priv_mode = (exmem_is_mret || exmem_is_sret) && exmem_valid && !exception;

  // EX 阶段的有效特权模式（用于 CSR 检查和委托）
  wire [1:0] effective_priv = forward_priv_mode ?
                              (exmem_is_mret ? mret_new_priv : sret_new_priv) :
                              current_priv;

  `ifdef DEBUG_PRIV
  always @(posedge clk) begin
    if (forward_priv_mode) begin
      $display("[PRIV_FORWARD] Time=%0t Forwarding privilege: %s in MEM, current_priv=%b -> effective_priv=%b",
               $time, exmem_is_mret ? "MRET" : "SRET", current_priv, effective_priv);
      if (idex_is_csr && idex_valid) begin
        $display("[PRIV_FORWARD]   CSR access in EX: addr=0x%03x will use effective_priv=%b",
                 idex_csr_addr, effective_priv);
      end
    end
  end
  `endif

  //==========================================================================
  // EX/MEM 流水线寄存器
  //==========================================================================
  exmem_register #(
    .XLEN(XLEN),
    .FLEN(`FLEN)
  ) exmem_reg (
    .clk(clk),
    .reset_n(reset_n),
    .hold(hold_exmem),
    .flush(trap_flush),  // 异常时刷新以防止重新触发
    .alu_result_in(ex_alu_result_sext),
    .mem_write_data_in(ex_mem_write_data_mux),          // 整数存储数据
    .fp_mem_write_data_in(ex_fp_mem_write_data_mux),    // 浮点存储数据
    .rd_addr_in(idex_rd_addr),
    .pc_plus_4_in(ex_pc_plus_4),
    .funct3_in(idex_funct3),
    .mem_read_in(idex_mem_read),
    .mem_write_in(idex_mem_write),
    .reg_write_in(idex_reg_write),
    .wb_sel_in(idex_wb_sel),
    .valid_in(idex_valid && !exception_taken_r),  // 如果上一周期发生异常，则无效
    .mul_div_result_in(ex_mul_div_result),
    .atomic_result_in(ex_atomic_result),
    .is_atomic_in(idex_is_atomic),
    // CSR 输入
    .csr_addr_in(idex_csr_addr),
    .csr_we_in(idex_csr_we),
    .csr_rdata_in(ex_csr_rdata_forwarded),  // 使用前递的值用于 MRET/SRET
    // 异常输入
    // 仅当 xRET 本身导致非法指令异常时才清除 xRET 信号
    // （由于权限不足而非法）。这会阻止 xRET 传播到 MEM 阶段并更改程序计数器 (PC)，而它本应发生陷阱。
    .is_mret_in(idex_is_mret && !(exception && (exception_code == 5'd2))),
    .is_sret_in(idex_is_sret && !(exception && (exception_code == 5'd2))),
    .is_sfence_vma_in(idex_is_sfence_vma),
    .rs1_addr_in(idex_rs1_addr),
    .rs2_addr_in(idex_rs2_addr),
    .rs1_data_in(ex_rs1_data_forwarded),  // Forwarded rs1 data
    .instruction_in(idex_instruction),
    .pc_in(idex_pc),
    // 来自 EX 阶段的 MMU 翻译结果（使用 EX 专用信号，而不是共享的 MMU 输出！）
    .mmu_paddr_in(ex_mmu_req_paddr),
    .mmu_ready_in(ex_mmu_req_ready),
    .mmu_page_fault_in(ex_mmu_req_page_fault),
    .mmu_fault_vaddr_in(ex_mmu_req_fault_vaddr),
    // 输出
    .alu_result_out(exmem_alu_result),
    .mem_write_data_out(exmem_mem_write_data),          // 整数存储写数据
    .fp_mem_write_data_out(exmem_fp_mem_write_data),    // 浮点存储写数据
    .rd_addr_out(exmem_rd_addr),
    .pc_plus_4_out(exmem_pc_plus_4),
    .funct3_out(exmem_funct3),
    .mem_read_out(exmem_mem_read),
    .mem_write_out(exmem_mem_write),
    .reg_write_out(exmem_reg_write),
    .wb_sel_out(exmem_wb_sel),
    .valid_out(exmem_valid),
    .mul_div_result_out(exmem_mul_div_result),
    .atomic_result_out(exmem_atomic_result),
    .is_atomic_out(exmem_is_atomic),
    // FP 输入
    .fp_result_in(ex_fp_result),
    .int_result_fp_in(ex_int_result_fp),
    .fp_rd_addr_in(idex_fp_rd_addr),
    .fp_reg_write_in(idex_fp_reg_write),
    .int_reg_write_fp_in(idex_int_reg_write_fp),
    .fp_mem_op_in(idex_fp_mem_op),
    .fp_fmt_in(idex_fp_fmt),
    .fp_flag_nv_in(ex_fp_flag_nv),
    .fp_flag_dz_in(ex_fp_flag_dz),
    .fp_flag_of_in(ex_fp_flag_of),
    .fp_flag_uf_in(ex_fp_flag_uf),
    .fp_flag_nx_in(ex_fp_flag_nx),
    // FP 输出
    .fp_result_out(exmem_fp_result),
    .int_result_fp_out(exmem_int_result_fp),
    .fp_rd_addr_out(exmem_fp_rd_addr),
    .fp_reg_write_out(exmem_fp_reg_write),
    .int_reg_write_fp_out(exmem_int_reg_write_fp),
    .fp_mem_op_out(exmem_fp_mem_op),
    .fp_fmt_out(exmem_fp_fmt),
    .fp_flag_nv_out(exmem_fp_flag_nv),
    .fp_flag_dz_out(exmem_fp_flag_dz),
    .fp_flag_of_out(exmem_fp_flag_of),
    .fp_flag_uf_out(exmem_fp_flag_uf),
    .fp_flag_nx_out(exmem_fp_flag_nx),
    // CSR 输出
    .csr_addr_out(exmem_csr_addr),
    .csr_we_out(exmem_csr_we),
    .csr_rdata_out(exmem_csr_rdata),
    // 异常输出
    .is_mret_out(exmem_is_mret),
    .is_sret_out(exmem_is_sret),
    .is_sfence_vma_out(exmem_is_sfence_vma),
    .rs1_addr_out(exmem_rs1_addr),
    .rs2_addr_out(exmem_rs2_addr),
    .rs1_data_out(exmem_rs1_data),
    .instruction_out(exmem_instruction),
    .pc_out(exmem_pc),
    // 来自 EX 阶段的 MMU 翻译结果传递到 MEM 阶段
    .mmu_paddr_out(exmem_paddr),
    .mmu_ready_out(exmem_translation_ready),
    .mmu_page_fault_out(exmem_page_fault),
    .mmu_fault_vaddr_out(exmem_fault_vaddr)
  );

  // 调试：EX/MEM 浮点寄存器传输
  `ifdef DEBUG_FPU_CONVERTER
  always @(posedge clk) begin
    if (exmem_fp_reg_write) begin
      $display("[%0t] [EXMEM] FP transfer: f%0d <= 0x%h (fp_result)",
               $time, exmem_fp_rd_addr, exmem_fp_result);
    end
  end
  `endif

  // 调试：EX/MEM 寄存器传输
  `ifdef DEBUG_EXMEM
  always @(posedge clk) begin
    if (exmem_valid && exmem_reg_write && exmem_rd_addr != 5'b0) begin
      $display("[EXMEM] @%0t pc=%h alu_result=%h rd=x%0d wb_sel=%b",
               $time, exmem_pc, exmem_alu_result, exmem_rd_addr, exmem_wb_sel);
    end
  end
  `endif

  // 调试：MMU→EXMEM→内存阶段时序跟踪（会话 100）
  `ifdef DEBUG_MMU_TIMING
  reg [31:0] debug_cycle_mmu;
  always @(posedge clk or negedge reset_n) begin
    if (!reset_n)
      debug_cycle_mmu <= 0;
    else
      debug_cycle_mmu <= debug_cycle_mmu + 1;
  end

  always @(posedge clk) begin
    // 跟踪 EX 阶段的 MMU 请求
    if (mmu_req_valid && (mmu_req_vaddr[31:28] == 4'h9)) begin
      $display("[C%0d] [EX_MMU_REQ] VA=0x%08h is_store=%b funct3=%b valid=%b",
               debug_cycle_mmu, mmu_req_vaddr, mmu_req_is_store, mmu_req_size, idex_valid);
    end

    // 跟踪 EX 阶段的 MMU 输出（组合逻辑/同一时钟周期）
    if (mmu_req_valid && (mmu_req_vaddr[31:28] == 4'h9)) begin
      $display("[C%0d] [EX_MMU_OUT] PA=0x%08h ready=%b fault=%b",
               debug_cycle_mmu, mmu_req_paddr, mmu_req_ready, mmu_req_page_fault);
    end

    // 跟踪被锁存到 EXMEM 寄存器中的内容
    if (!hold_exmem && idex_valid && (idex_mem_read || idex_mem_write) && (ex_alu_result[31:28] == 4'h9)) begin
      $display("[C%0d] [EXMEM_LATCH] Latching MMU output: PA=0x%08h ready=%b fault=%b (from EX)",
               debug_cycle_mmu, mmu_req_paddr, mmu_req_ready, mmu_req_page_fault);
    end

    // 跟踪 EXMEM 输出在 MEM 阶段（寄存器化/下一周期）
    if (exmem_valid && (exmem_mem_read || exmem_mem_write) && (exmem_alu_result[31:28] == 4'h9 || exmem_paddr[31:28] == 4'h8)) begin
      $display("[C%0d] [MEM_EXMEM_OUT] VA=0x%08h PA=0x%08h ready=%b fault=%b",
               debug_cycle_mmu, exmem_alu_result, exmem_paddr, exmem_translation_ready, exmem_page_fault);
    end

    // 跟踪内存地址选择
    if (exmem_valid && (exmem_mem_read || exmem_mem_write) && (exmem_alu_result[31:28] == 4'h9 || exmem_paddr[31:28] == 4'h8)) begin
      $display("[C%0d] [MEM_ADDR] dmem_addr=0x%08h translated_addr=0x%08h use_mmu=%b arb_addr=0x%08h",
               debug_cycle_mmu, dmem_addr, translated_addr, use_mmu_translation, arb_mem_addr);
    end

    // 跟踪寄存器写入 x6, x7
    if (memwb_reg_write && memwb_valid && (memwb_rd_addr == 6 || memwb_rd_addr == 7)) begin
      $display("[C%0d] [WB_WRITE] x%0d <= 0x%08h (wb_data from MEM stage)",
               debug_cycle_mmu, memwb_rd_addr, wb_data);
    end
  end
  `endif

  //==========================================================================
  // MEM 阶段：内存访问
  //==========================================================================

  // 异常防护：如果异常处于活动状态，则不要写入内存或寄存器
  // 仅对 MEM 阶段的异常进行门控内存和寄存器写入（保持精确异常）
  // EX 阶段的异常（EBREAK、ECALL、非法指令）不应阻止 MEM 阶段完成
  wire mem_write_gated = exmem_mem_write && !exception_from_mem;
  wire reg_write_gated = exmem_reg_write && !exception_from_mem;

  // 内存仲裁：当原子单元处于活动状态时，原子单元优先
  // 当执行原子操作时，原子单元控制内存
  // 否则，MEM 阶段的正常加载/存储路径控制内存
  wire [XLEN-1:0] dmem_addr;
  wire [63:0]     dmem_write_data;  // 64 位，支持 RV32D/RV64D
  wire            dmem_mem_read;
  wire            dmem_mem_write;
  wire [2:0]      dmem_funct3;

  // 确定这是否是 FP 存储操作（FSW 或 FSD）
  // FP 存储是带有 fp_mem_op 激活的内存写操作
  wire is_fp_store = exmem_mem_write && exmem_fp_mem_op;

  // 当原子单元忙时，使用原子单元的内存接口
  // 否则，在整数和 FP 写入数据之间选择用于存储
  assign dmem_addr       = ex_atomic_busy ? ex_atomic_mem_addr : exmem_alu_result;
  assign dmem_write_data = ex_atomic_busy ? {{(64-XLEN){1'b0}}, ex_atomic_mem_wdata} :  // 零扩展原子数据
                           is_fp_store    ? exmem_fp_mem_write_data :                    // FP 存储：使用完整的 FLEN 位
                                            {{(64-XLEN){1'b0}}, exmem_mem_write_data};   // 整数存储：零扩展到 64 位
  assign dmem_mem_read   = ex_atomic_busy ? ex_atomic_mem_req && !ex_atomic_mem_we : exmem_mem_read;
  assign dmem_mem_write  = ex_atomic_busy ? ex_atomic_mem_req && ex_atomic_mem_we : mem_write_gated;
  assign dmem_funct3     = ex_atomic_busy ? ex_atomic_mem_size : exmem_funct3;

  // 原子单元内存准备信号 - 处理带寄存器的内存读取
  // 读取：内存具有输出寄存器（匹配 FPGA BRAM 和 ASIC SRAM），需要 1 个周期
  //   第 N 个周期：mem_req=1，mem_we=0（读取地址呈现）
  //   第 N+1 个周期：读取数据可用，mem_ready=1
  // 写入：写入数据立即锁存到内存阵列，耗时 0 个周期
  //   第 N 个周期：mem_req=1，mem_we=1（写入发生）
  //   第 N 个周期：mem_ready=1（写入立即完成）
  reg ex_atomic_mem_read_r;
  always @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
      ex_atomic_mem_read_r <= 1'b0;
    end else begin
      // 跟踪读取请求 (mem_req && !mem_we)
      ex_atomic_mem_read_r <= ex_atomic_mem_req && !ex_atomic_mem_we;
    end
  end
  // 写入立即准备好，读取延迟 1 个周期
  assign ex_atomic_mem_ready = ex_atomic_mem_we ? 1'b1 : ex_atomic_mem_read_r;

  //--------------------------------------------------------------------------
  // MMU: 虚拟内存转换（第 117 课时：添加 IF 阶段转换）
  //--------------------------------------------------------------------------

  // 确定每个阶段何时需要转换
  // 翻译启用：SATP 模式启用且不处于 M 模式
  // (translation_enabled 线已在前面第 2030 行定义)
  wire if_needs_translation = satp_mode_enabled && (current_priv != 2'b11);
  wire ex_needs_translation = satp_mode_enabled && (current_priv != 2'b11) &&
                              (idex_mem_read || idex_mem_write);

  // 第 125 课时：双 TLB MMU（I-TLB + D-TLB，无需仲裁器！）
  // 分离的 TLB 消除了第 119 课时轮询仲裁器的结构性冲突
  // IF 和 EX 可以并行翻译，无需争用

  // IF 阶段 MMU 请求（指令取指翻译）
  assign if_mmu_req_valid = if_needs_translation;
  assign if_mmu_req_vaddr = pc_current;

  // EX 阶段 MMU 请求（数据访问翻译）
  assign ex_mmu_req_valid = ex_needs_translation && idex_valid;
  assign ex_mmu_req_vaddr = ex_alu_result;  // ALU 结果是虚拟地址
  assign ex_mmu_req_is_store = idex_mem_write;

  // TLB 刷新控制来自 SFENCE.VMA 指令
  // SFENCE.VMA 在 MEM 阶段：rs1 指定虚拟地址，rs2 指定 ASID
  // 目前，实现简单刷新：rs1=x0 && rs2=x0 => 刷新所有
  wire sfence_flush_all = exmem_is_sfence_vma && (exmem_rs1_addr == 5'h0) && (exmem_rs2_addr == 5'h0);
  wire sfence_flush_vaddr = exmem_is_sfence_vma && (exmem_rs1_addr != 5'h0);
  wire [XLEN-1:0] sfence_vaddr = exmem_rs1_data;  // rs1 数据包含虚拟地址

  assign tlb_flush_all = sfence_flush_all;
  assign tlb_flush_vaddr = sfence_flush_vaddr;
  assign tlb_flush_addr = sfence_vaddr;

  // MMU 忙信号：正在进行转换 (req_valid && !req_ready)
  // MMU 现在运行在 EX 阶段，因此该信号会阻塞 IDEX→EXMEM 过渡（hold_exmem）
  // 第 103 课时：关键修复 - 当检测到页面错误时也保持流水线！
  // 第 108 课时：保持直到陷阱被接受，而不仅仅是 1 个周期
  // 否则，后续指令在陷阱被接受之前执行
  reg mmu_page_fault_pending;
  reg trap_taken_r;  // 已注册 trap_flush 用于清除 mmu_page_fault_pending
  always @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
      mmu_page_fault_pending <= 1'b0;
      trap_taken_r <= 1'b0;
    end else begin
      trap_taken_r <= trap_flush;  // 仅锁存 trap_flush（不包括 xRET）
      if (mmu_req_ready && mmu_req_page_fault && !mmu_page_fault_pending)
        mmu_page_fault_pending <= 1'b1;  // 检测到错误时设置
      else if (trap_taken_r)
        mmu_page_fault_pending <= 1'b0;  // 陷阱接受后一个周期清除
    end
  end

  // 第 125 课时：双 TLB - 仅在实际转换进行时保持
  // 不再有仲裁器争用！IF 和 EX TLB 独立运行
  // 保持 IF 当：IF 转换未准备好
  // 保持 EX 当：EX 转换未准备好或页面错误待处理
  wire if_mmu_busy = if_needs_translation && !if_mmu_req_ready;
  wire ex_mmu_busy = (ex_needs_translation && !ex_mmu_req_ready) || mmu_page_fault_pending;

  assign mmu_busy = ex_mmu_busy;  // 仅 EX 忙信号保持流水线（IF 保持单独处理）

  // 实例化双 TLB MMU（第 125 课时：I-TLB + D-TLB）
  dual_tlb_mmu #(
    .XLEN(XLEN),
    .ITLB_ENTRIES(8),   // 8 入口 I-TLB 用于指令取指
    .DTLB_ENTRIES(16)   // 16 入口 D-TLB 用于数据访问（更频繁）
  ) dual_mmu_inst (
    .clk(clk),
    .reset_n(reset_n),
    // 指令取指转换（I-TLB）
    .if_req_valid(if_mmu_req_valid),
    .if_req_vaddr(if_mmu_req_vaddr),
    .if_req_ready(if_mmu_req_ready),
    .if_req_paddr(if_mmu_req_paddr),
    .if_req_page_fault(if_mmu_req_page_fault),
    .if_req_fault_vaddr(if_mmu_req_fault_vaddr),
    // 数据访问转换（D-TLB）
    .ex_req_valid(ex_mmu_req_valid),
    .ex_req_vaddr(ex_mmu_req_vaddr),
    .ex_req_is_store(ex_mmu_req_is_store),
    .ex_req_ready(ex_mmu_req_ready),
    .ex_req_paddr(ex_mmu_req_paddr),
    .ex_req_page_fault(ex_mmu_req_page_fault),
    .ex_req_fault_vaddr(ex_mmu_req_fault_vaddr),
    // 页表遍历内存接口（共享 PTW）
    .ptw_req_valid(mmu_ptw_req_valid),
    .ptw_req_addr(mmu_ptw_req_addr),
    .ptw_req_ready(mmu_ptw_req_ready),
    .ptw_resp_data(mmu_ptw_resp_data),
    .ptw_resp_valid(mmu_ptw_resp_valid),
    // CSR 接口
    .satp(csr_satp),
    .privilege_mode(current_priv),
    .mstatus_sum(mstatus_sum),
    .mstatus_mxr(mstatus_mxr),
    // TLB 刷新控制
    .tlb_flush_all(tlb_flush_all),
    .tlb_flush_vaddr(tlb_flush_vaddr),
    .tlb_flush_addr(tlb_flush_addr)
  );

  // 内存仲裁器：在 CPU 数据访问和 MMU PTW 之间多路复用
  // 优先级：当 PTW 活动时优先（MMU 需要内存进行页表遍历）
  // 否则，正常数据内存访问
  wire [XLEN-1:0] arb_mem_addr;
  wire [63:0]     arb_mem_write_data;  // 64 位，用于 RV32D/RV64D 支持
  wire            arb_mem_read;
  wire            arb_mem_write;
  wire [2:0]      arb_mem_funct3;
  wire [63:0]     arb_mem_read_data;   // 64 位，用于 RV32D/RV64D 支持

  // 当 PTW 处于活动状态时，它具有最高优先级
  // 当 PTW 不活动时，使用来自 EXMEM 的已翻译地址（已注册的 MMU 输出）
  // 翻译结果在 EXMEM 中寄存，以打断组合路径
  // satp_mode_enabled 和 translation_enabled 现在在更前面定义（在 exception_unit 之前）
  // 用于对页错误进行门控（第 113 课修复）
  wire use_mmu_translation = translation_enabled && exmem_translation_ready && !exmem_page_fault;
  wire [XLEN-1:0] translated_addr = use_mmu_translation ? exmem_paddr : dmem_addr;


  assign arb_mem_addr       = mmu_ptw_req_valid ? mmu_ptw_req_addr : translated_addr;
  assign arb_mem_write_data = dmem_write_data;  // PTW 从不写入
  assign arb_mem_read       = mmu_ptw_req_valid ? 1'b1 : dmem_mem_read;
  assign arb_mem_write      = mmu_ptw_req_valid ? 1'b0 : dmem_mem_write;
  assign arb_mem_funct3     = mmu_ptw_req_valid ? 3'b010 : dmem_funct3;  // PTW 使用字访问

  // PTW 已准备好用于注册内存的协议（第 115 课修复）
  // - 读取延迟：1 个周期（与 dmem_bus_adapter 相同）
  // - 第一个周期：req_ready=0（内存读取中）
  // - 第二个周期：req_ready=1，resp_valid=1（数据准备好）
  reg ptw_read_in_progress_r;
  always @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
      ptw_read_in_progress_r <= 1'b0;
    end else begin
      // 当 PTW 发出请求时设置，1 个周期后清除
      if (mmu_ptw_req_valid && !ptw_read_in_progress_r) begin
        ptw_read_in_progress_r <= 1'b1;
      end else if (ptw_read_in_progress_r) begin
        ptw_read_in_progress_r <= 1'b0;
      end
    end
  end

  // PTW 就绪信号：第一个周期不就绪，第二个周期就绪
  assign mmu_ptw_req_ready = ptw_read_in_progress_r;
  // PTW 响应有效，当数据准备好时（第二个周期）
  assign mmu_ptw_resp_valid = ptw_read_in_progress_r;
  assign mmu_ptw_resp_data = arb_mem_read_data;

  //--------------------------------------------------------------------------
  // 总线主接口
  //--------------------------------------------------------------------------
  // 将仲裁器信号连接到总线主端口
  // 总线将请求路由到 DMEM 或内存映射外设
  // 注意：funct3 编码访问大小：0=字节，1=半字，2=字，3=双字
  //
  // 关键修复（第 34 课）：生成总线请求作为单次脉冲
  // 问题：如果 MEM 阶段保持多个周期，相同的存储操作会执行多次（例如，UART 字符重复错误）
  // 解决方案：跟踪之前的 MEM 阶段 PC，仅在新的指令进入 MEM 时断言 req_valid（检测 PC 变化）
  reg [XLEN-1:0] exmem_pc_prev;
  reg            exmem_valid_prev;

  always @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
      exmem_pc_prev    <= {XLEN{1'b0}};
      exmem_valid_prev <= 1'b0;
    end else begin
      exmem_pc_prev    <= exmem_pc;
      exmem_valid_prev <= exmem_valid;
    end
  end

  // 仅在 MEM 阶段指令的第一个周期生成总线请求
  // 这可以防止如果相同指令在 MEM 阶段停留多个周期时产生重复请求
  // 新指令检测条件：（PC 变化）或（valid 从 0 变为 1）
  wire mem_stage_new_instr = exmem_valid && ((exmem_pc != exmem_pc_prev) || !exmem_valid_prev);

  // 第 40 课：跟踪是否已经为当前指令发出总线请求
  // 这可以防止当总线未准备好时产生重复请求（带有 FIFO、忙状态的外设）
  // 策略：当发出请求且未准备好时设置标志，当准备好或新指令时清除标志
  reg bus_req_issued;

  always @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
      bus_req_issued <= 1'b0;
    end else begin
      // 设置：当我们首次发出写脉冲时
      if (arb_mem_write_pulse && !bus_req_ready) begin
        bus_req_issued <= 1'b1;
      end
      // 清除：当总线变为就绪或指令离开 MEM 阶段时
      else if (bus_req_ready || !exmem_valid) begin
        bus_req_issued <= 1'b0;
      end
    end
  end

  // 关键：只有写操作需要单次脉冲以防止重复副作用
  // 读取可以是电平信号（多周期操作、原子操作等需要）
  // 例外：原子操作（LR/SC，AMO）需要多周期读-改-写的电平信号
  //       原子单元通过 ex_atomic_busy 控制写入，因此允许连续写入
  // 第 40 课：还检查 !bus_req_issued 以防止总线未准备好时产生重复请求
  wire arb_mem_write_pulse = mmu_ptw_req_valid ? 1'b0 :
                             ex_atomic_busy ? dmem_mem_write :                       // Atomic: level signal
                             (dmem_mem_write && mem_stage_new_instr && !bus_req_issued);  // Normal: one-shot pulse, not already issued

  // 第 52 课：bus_req_valid 必须保持高电平直到 bus_req_ready，以处理慢速外设
  // 当外设注册了 req_ready（CLINT、UART）时，流水线会暂停，但我们必须
  // 保持请求有效直到确认，否则写入不会提交
  assign bus_req_valid = arb_mem_read || arb_mem_write_pulse || bus_req_issued;
  assign bus_req_addr  = arb_mem_addr;
  assign bus_req_wdata = arb_mem_write_data;
  assign bus_req_we    = arb_mem_write_pulse;
  assign bus_req_size  = arb_mem_funct3;

  // 总线读取数据反馈给仲裁器
  assign arb_mem_read_data = bus_req_rdata;

  //===========================================================================
  // 调试：总线事务跟踪（第 50 课 - MTIMECMP 写入错误）
  //===========================================================================
  `ifdef DEBUG_BUS
  always @(posedge clk) begin
    // Trace ALL bus transactions
    if (bus_req_valid) begin
      if (bus_req_we) begin
        $display("[CORE-BUS-WR] Cycle %0d: addr=0x%08h wdata=0x%016h size=%0d valid=%b ready=%b | PC=%h",
                 $time/10, bus_req_addr, bus_req_wdata, bus_req_size,
                 bus_req_valid, bus_req_ready, exmem_pc);
      end else begin
        $display("[CORE-BUS-RD] Cycle %0d: addr=0x%08h size=%0d valid=%b ready=%b rdata=0x%016h | PC=%h",
                 $time/10, bus_req_addr, bus_req_size,
                 bus_req_valid, bus_req_ready, bus_req_rdata, exmem_pc);
      end

      // 特别突出显示 CLINT 范围访问（0x0200_0000 - 0x0200_FFFF）
      if (bus_req_addr >= 32'h0200_0000 && bus_req_addr <= 32'h0200_FFFF) begin
        $display("       *** CLINT ACCESS DETECTED *** offset=0x%04h", bus_req_addr[15:0]);
        if (bus_req_addr >= 32'h0200_4000 && bus_req_addr <= 32'h0200_BFF7) begin
          $display("       *** MTIMECMP RANGE *** (should be 0x4000-0xBFF7)");
        end
        if (bus_req_addr == 32'h0200_4000) begin
          $display("       *** MTIMECMP[0] LOWER 32-bit WRITE ***");
        end
        if (bus_req_addr == 32'h0200_4004) begin
          $display("       *** MTIMECMP[0] UPPER 32-bit WRITE ***");
        end
      end

      // 显示 MEM 阶段状态以便调试
      $display("       MEM: exmem_valid=%b mem_write=%b mem_read=%b new_instr=%b issued=%b",
               exmem_valid, dmem_mem_write, dmem_mem_read, mem_stage_new_instr, bus_req_issued);
    end
  end
  `endif

  // 连接仲裁器读取数据到整数和浮点路径
  // 对于整数加载，使用较低的 XLEN 位（符号/零扩展由总线从属处理）
  // 对于浮点加载，使用完整的 FLEN 位
  assign mem_read_data    = arb_mem_read_data[XLEN-1:0];  // 整数加载：低位
  assign fp_mem_read_data = arb_mem_read_data;             // 浮点加载：完整 64 位

  // MEM/WB 流水线寄存器
  memwb_register #(
    .XLEN(XLEN),
    .FLEN(`FLEN)
  ) memwb_reg (
    .clk(clk),
    .reset_n(reset_n),
    .alu_result_in(exmem_alu_result),
    .mem_read_data_in(mem_read_data),       // 整数加载数据
    .fp_mem_read_data_in(fp_mem_read_data), // 浮点加载数据
    .rd_addr_in(exmem_rd_addr),
    .pc_plus_4_in(exmem_pc_plus_4),
    .reg_write_in(reg_write_gated),     // 门控以防止异常时写入
    .wb_sel_in(exmem_wb_sel),
    .valid_in(exmem_valid && !exception_from_mem && !hold_exmem),  // 仅在 MEM 阶段异常时标记无效（保持精确异常）
    .mul_div_result_in(exmem_mul_div_result),
    .atomic_result_in(exmem_atomic_result),
    // F/D 扩展输入
    .fp_result_in(exmem_fp_result),
    .int_result_fp_in(exmem_int_result_fp),
    .fp_rd_addr_in(exmem_fp_rd_addr),
    .fp_reg_write_in(exmem_fp_reg_write),
    .int_reg_write_fp_in(exmem_int_reg_write_fp),
    .fp_fmt_in(exmem_fp_fmt),
    .fp_flag_nv_in(exmem_fp_flag_nv),
    .fp_flag_dz_in(exmem_fp_flag_dz),
    .fp_flag_of_in(exmem_fp_flag_of),
    .fp_flag_uf_in(exmem_fp_flag_uf),
    .fp_flag_nx_in(exmem_fp_flag_nx),
    // CSR 输入
    .csr_rdata_in(exmem_csr_rdata),
    .csr_we_in(exmem_csr_we),
    // 输出
    .alu_result_out(memwb_alu_result),
    .mem_read_data_out(memwb_mem_read_data),       // 整数加载数据
    .fp_mem_read_data_out(memwb_fp_mem_read_data), // 浮点加载数据
    .rd_addr_out(memwb_rd_addr),
    .pc_plus_4_out(memwb_pc_plus_4),
    .reg_write_out(memwb_reg_write),
    .wb_sel_out(memwb_wb_sel),
    .valid_out(memwb_valid),
    .mul_div_result_out(memwb_mul_div_result),
    .atomic_result_out(memwb_atomic_result),
    // F/D 扩展输出
    .fp_result_out(memwb_fp_result),
    .int_result_fp_out(memwb_int_result_fp),
    .fp_rd_addr_out(memwb_fp_rd_addr),
    .fp_reg_write_out(memwb_fp_reg_write),
    .int_reg_write_fp_out(memwb_int_reg_write_fp),
    .fp_fmt_out(memwb_fp_fmt),
    .fp_flag_nv_out(memwb_fp_flag_nv),
    .fp_flag_dz_out(memwb_fp_flag_dz),
    .fp_flag_of_out(memwb_fp_flag_of),
    .fp_flag_uf_out(memwb_fp_flag_uf),
    .fp_flag_nx_out(memwb_fp_flag_nx),
    // CSR 输出
    .csr_rdata_out(memwb_csr_rdata),
    .csr_we_out(memwb_csr_we)
  );

  // 调试：MEM/WB 浮点寄存器传输
  `ifdef DEBUG_FPU_CONVERTER
  always @(posedge clk) begin
    if (memwb_fp_reg_write) begin
      $display("[%0t] [MEMWB] FP transfer: f%0d <= 0x%h (wb_sel=%b)",
               $time, memwb_fp_rd_addr, memwb_fp_result, memwb_wb_sel);
    end
  end
  `endif

  // 调试：FCVT 流水线跟踪
  `ifdef DEBUG_FCVT_PIPELINE
  always @(posedge clk) begin
    // 跟踪 FCVT 在 ID/EX 阶段
    if (idex_fp_alu_en && idex_fp_alu_op == 5'b01010 && idex_valid) begin
      $display("[%0t] [IDEX] FCVT: fp_reg_write=%b, fp_rd_addr=f%0d, valid=%b, pc=%h",
               $time, idex_fp_reg_write, idex_fp_rd_addr, idex_valid, idex_pc);
    end
    // 跟踪 FCVT 在 EX/MEM 阶段
    if (exmem_fp_reg_write && exmem_valid) begin
      $display("[%0t] [EXMEM] FCVT: fp_reg_write=%b, fp_rd_addr=f%0d, valid=%b, pc=%h, fp_result=%h",
               $time, exmem_fp_reg_write, exmem_fp_rd_addr, exmem_valid, exmem_pc, exmem_fp_result);
    end
    // 跟踪 FCVT 在 MEM/WB 阶段
    if (memwb_fp_reg_write && memwb_valid) begin
      $display("[%0t] [MEMWB] FCVT: fp_reg_write=%b, fp_rd_addr=f%0d, valid=%b, fp_result=%h",
               $time, memwb_fp_reg_write, memwb_fp_rd_addr, memwb_valid, memwb_fp_result);
    end
  end
  `endif

  // 调试：MEM/WB 寄存器传输
  `ifdef DEBUG_MEMWB
  always @(posedge clk) begin
    if (memwb_valid && memwb_reg_write && memwb_rd_addr != 5'b0) begin
      $display("[MEMWB] @%0t alu_result=%h rd=x%0d wb_sel=%b",
               $time, memwb_alu_result, memwb_rd_addr, memwb_wb_sel);
    end
  end
  `endif

  //==========================================================================
  // WB 阶段：写回
  //==========================================================================

  // 写回数据选择（整数寄存器文件）
  assign wb_data = (memwb_wb_sel == 3'b000) ? memwb_alu_result :      // ALU 结果
                   (memwb_wb_sel == 3'b001) ? memwb_mem_read_data :   // 内存数据
                   (memwb_wb_sel == 3'b010) ? memwb_pc_plus_4 :       // PC + 4 (JAL/JALR)
                   (memwb_wb_sel == 3'b011) ? memwb_csr_rdata :       // CSR 数据
                   (memwb_wb_sel == 3'b100) ? memwb_mul_div_result :  // M 扩展结果
                   (memwb_wb_sel == 3'b101) ? memwb_atomic_result :   // A 扩展结果
                   (memwb_wb_sel == 3'b110) ? memwb_int_result_fp :   // FPU 整数结果 (FP 比较, FCLASS, FMV.X.W, FCVT.W.S)
                   {XLEN{1'b0}};

  // 调试：WB 阶段寄存器文件写入
  `ifdef DEBUG_REGFILE_WB
  always @(posedge clk) begin
    // 显示门控和非门控写入以进行调试
    if ((memwb_reg_write || memwb_int_reg_write_fp) && memwb_rd_addr != 5'b0) begin
      if (memwb_valid) begin
        $display("[REGFILE_WB] @%0t Writing rd=x%0d data=%h (wb_sel=%b valid=1 alu=%h mem=%h mul_div=%h)",
                 $time, memwb_rd_addr, wb_data, memwb_wb_sel,
                 memwb_alu_result, memwb_mem_read_data, memwb_mul_div_result);
      end else begin
        $display("[REGFILE_WB] @%0t BLOCKED rd=x%0d data=%h (wb_sel=%b valid=0 GATED BY WRITEBACK LOGIC)",
                 $time, memwb_rd_addr, wb_data, memwb_wb_sel);
      end
    end
  end
  `endif

  // 调试：寄存器损坏检测（0xa5a5a5a5 模式跟踪）
  `ifdef DEBUG_REG_CORRUPTION
  always @(posedge clk) begin
    if (memwb_valid && (memwb_reg_write || memwb_int_reg_write_fp) && memwb_rd_addr != 5'b0) begin
      // 跟踪 0xa5a5a5a5 模式的写入（FreeRTOS 堆栈填充模式）
      if (wb_data == 32'ha5a5a5a5 || wb_data[31:8] == 24'ha5a5a5) begin
        $display("[REG_CORRUPTION] *** PATTERN DETECTED *** @%0t Writing 0xa5a5a5a5 pattern to x%0d! data=%h (wb_sel=%b)",
                 $time, memwb_rd_addr, wb_data, memwb_wb_sel);
        $display("  Source: alu=%h mem=%h pc+4=%h csr=%h mul_div=%h atomic=%h fp_int=%h",
                 memwb_alu_result, memwb_mem_read_data, memwb_pc_plus_4, memwb_csr_rdata,
                 memwb_mul_div_result, memwb_atomic_result, memwb_int_result_fp);
        $display("  Pipeline: PC=%h instr=%h", memwb_pc, memwb_instruction);
      end

      // 跟踪堆栈指针 (x2/sp) 的修改
      if (memwb_rd_addr == 5'd2) begin
        $display("[REG_CORRUPTION] Stack pointer write: sp (x2) <= %h @%0t (wb_sel=%b PC=%h)",
                 wb_data, $time, memwb_wb_sel, memwb_pc);
      end

      // 跟踪在崩溃中使用的关键寄存器 (x7=t2 在第72次会话中出现)
      if (memwb_rd_addr == 5'd7) begin
        $display("[REG_CORRUPTION] t2 (x7) write: t2 <= %h @%0t (wb_sel=%b PC=%h instr=%h)",
                 wb_data, $time, memwb_wb_sel, memwb_pc, memwb_instruction);
      end

      // 跟踪返回地址寄存器 (x1/ra)
      if (memwb_rd_addr == 5'd1) begin
        $display("[REG_CORRUPTION] ra (x1) write: ra <= %h @%0t (wb_sel=%b PC=%h)",
                 wb_data, $time, memwb_wb_sel, memwb_pc);
      end

      // 跟踪 t0 (x5) - 用于 init_array 设置
      if (memwb_rd_addr == 5'd5) begin
        $display("[REG_CORRUPTION] t0 (x5) write: t0 <= %h @%0t (wb_sel=%b PC=%h instr=%h)",
                 wb_data, $time, memwb_wb_sel, memwb_pc, memwb_instruction);
      end

      // 跟踪 t1 (x6) - 用于 init_array 设置
      if (memwb_rd_addr == 5'd6) begin
        $display("[REG_CORRUPTION] t1 (x6) write: t1 <= %h @%0t (wb_sel=%b PC=%h instr=%h)",
                 wb_data, $time, memwb_wb_sel, memwb_pc, memwb_instruction);
      end
    end
  end
  `endif

  // F/D 扩展：FP 写回数据选择
  // FP 结果写入 FP 寄存器文件，INT 到 FP 的转换也写入 FP 寄存器文件
  // FP 加载（FLW/FLD）也通过 fp_mem_read_data 写入 FP 寄存器文件
  // 通过检查 wb_sel == 001（内存数据）且 fp_reg_write 被设置来检测 FP 加载
  // 对于 FLW（当 FLEN=64 时的单精度加载），对加载的值进行 NaN-box 处理
  wire [`FLEN-1:0] fp_load_data_boxed;
  assign fp_load_data_boxed = (`FLEN == 64 && !memwb_fp_fmt) ? {32'hFFFFFFFF, memwb_fp_mem_read_data[31:0]} : memwb_fp_mem_read_data;

  assign wb_fp_data = (memwb_wb_sel == 3'b001) ? fp_load_data_boxed :  // FP 加载（FLW 时进行 NaN-box 处理）
                      memwb_fp_result;                                   // FP ALU 结果

  // FP 到 INT 操作通过 memwb_int_result_fp 写入整数寄存器文件：
  // - FP 比较 (FEQ, FLT, FLE): wb_sel = 3'b110
  // - FP 分类 (FCLASS): wb_sel = 3'b110
  // - FP 移动到整数 (FMV.X.W): wb_sel = 3'b110
  // - FP 到整数转换 (FCVT.W.S, FCVT.WU.S): wb_sel = 3'b110
  //==========================================================================
  // 调试：MRET/SRET 到压缩指令的 PC 跟踪（错误 #41）
  //==========================================================================
  `ifdef DEBUG_MRET_RVC
  reg [31:0] cycle_count;
  reg prev_mret_flush, prev_sret_flush;
  reg [31:0] prev_pc;
  always @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
      cycle_count <= 0;
      prev_mret_flush <= 0;
      prev_sret_flush <= 0;
      prev_pc <= 0;
    end else begin
      cycle_count <= cycle_count + 1;

      // 显示 PC 跟踪每个周期
      $display("[CYC %0d] PC=%h PC_next=%h PC_inc=%h | instr_raw=%h is_comp=%b | mret_fl=%b sret_fl=%b trap_fl=%b exc_code=%h | stall=%b flush_if=%b",
               cycle_count, pc_current, pc_next, pc_increment,
               if_instruction_raw, if_is_compressed,
               mret_flush, sret_flush, trap_flush, exception_code,
               stall_pc, flush_ifid);

      // 异常发生时的详细跟踪
      if (trap_flush) begin
        $display("  [TRAP] exc_pc=%h exc_val=%h exc_code=%h vector=%h",
                 exception_pc, exception_val, exception_code, trap_vector);
      end

      // 当发生 MRET/SRET 时的详细跟踪
      if (mret_flush || sret_flush) begin
        $display("  [%s_FLUSH] Target PC=%h (from %s)",
                 mret_flush ? "MRET" : "SRET",
                 mret_flush ? mepc : sepc,
                 mret_flush ? "MEPC" : "SEPC");
      end

      // 跟踪 xRET 后的指令获取
      if (cycle_count > 0 && (prev_mret_flush || prev_sret_flush)) begin
        $display("  [POST_xRET] Fetched instr_raw=%h at PC=%h | is_compressed=%b pc_inc=%h",
                 if_instruction_raw, pc_current, if_is_compressed, pc_increment);
      end

      // 检测潜在的无限循环（PC 未改变）
      if (cycle_count > 2 && pc_current == prev_pc && !stall_pc) begin
        $display("  [WARNING] PC stuck at %h (not stalling!)", pc_current);
      end

      // 更新先前的值
      prev_mret_flush <= mret_flush;
      prev_sret_flush <= sret_flush;
      prev_pc <= pc_current;
    end
  end
  `endif

  //==========================================================================
  // 调试：跟踪写入 a0 (x10) 以调试错误 #48
  //==========================================================================
  `ifdef DEBUG_A0_TRACKING
  integer cycle_count_a0;

  always @(posedge clk or negedge reset_n) begin
    if (!reset_n)
      cycle_count_a0 <= 0;
    else
      cycle_count_a0 <= cycle_count_a0 + 1;
  end

  // 还跟踪写入 a0 的指令在早期阶段的情况
  always @(posedge clk) begin
    // 跟踪写回阶段
    if (memwb_valid && memwb_reg_write && memwb_rd_addr == 5'd10) begin
      $display("[A0_WRITE] cycle=%0d x10 <= 0x%08h (wb_sel=%b source=%s alu=0x%08h mem=0x%08h)",
               cycle_count_a0, wb_data, memwb_wb_sel,
               (memwb_wb_sel == 3'b000) ? "ALU    " :
               (memwb_wb_sel == 3'b001) ? "MEM    " :
               (memwb_wb_sel == 3'b010) ? "PC+4   " :
               (memwb_wb_sel == 3'b110) ? "FP2INT " : "OTHER  ",
               memwb_alu_result, memwb_mem_read_data);
    end

    // 跟踪 EX 阶段以查看 PC 和指令
    if (idex_valid && idex_reg_write && idex_rd_addr == 5'd10) begin
      $display("[A0_EX   ] cycle=%0d PC=0x%08h instr=0x%08h opcode=%b rd=x10",
               cycle_count_a0, idex_pc, idex_instruction, idex_instruction[6:0]);
    end
  end
  `endif

  // 调试：JAL/RET 压缩指令问题（会话 68）
  `ifdef DEBUG_JAL_RET
  integer debug_cycle;
  initial debug_cycle = 0;

  always @(posedge clk) begin
    if (reset_n) debug_cycle = debug_cycle + 1;

    if (reset_n && pc_current >= 32'h80000010 && pc_current <= 32'h80000040) begin
      $display("[JAL_DEBUG] Cycle=%0d PC=0x%08h instr_raw=0x%08h instr_final=0x%08h is_comp=%b",
               debug_cycle, pc_current, if_instruction_raw, if_instruction, if_is_compressed);
      $display("            instr_raw[15:0]=0x%04h instr_raw[31:16]=0x%04h PC[1:0]=%b",
               if_instruction_raw[15:0], if_instruction_raw[31:16], pc_current[1:0]);
      // 显示流水线状态
      if (idex_valid) begin
        $display("            IDEX: PC=0x%08h opcode=%b rd=x%0d jump=%b",
                 idex_pc, idex_opcode, idex_rd_addr, idex_jump);
      end
      // 显示寄存器写入（特别是 x1/ra）
      if (memwb_reg_write && memwb_valid && memwb_rd_addr == 5'd1) begin
        $display("            WB: x1(ra) <= 0x%08h", wb_data);
      end
    end
  end
  `endif

  //==========================================================================
  // 会话 77：从周期 0 开始的 PC 跟踪
  // 跟踪从复位开始的 PC 值以了解执行流程
  //==========================================================================
  `ifdef DEBUG_PC_TRACE
  integer pc_trace_cycle;
  initial pc_trace_cycle = 0;

  always @(posedge clk) begin
    if (!reset_n) begin
      pc_trace_cycle = 0;
      $display("[PC_TRACE] RESET ASSERTED");
    end else begin
      pc_trace_cycle = pc_trace_cycle + 1;
      if (pc_trace_cycle <= 150) begin
        $display("[PC_TRACE] cycle=%0d PC=0x%08h instr=0x%08h valid=%b stall=%b",
                 pc_trace_cycle, pc_current, if_instruction, ifid_valid, stall_pc);
      end
    end
  end
  `endif

  //==========================================================================
  // 会话 72：增强的流水线调试工具
  // 提供所有流水线阶段的同步视图，便于调试
  //==========================================================================
  `ifdef DEBUG_PIPELINE
  integer pipe_cycle;
  initial pipe_cycle = 0;

  always @(posedge clk) begin
    if (!reset_n) begin
      pipe_cycle = 0;
    end else begin
      pipe_cycle = pipe_cycle + 1;

      // 仅显示具有有效指令或控制流更改的周期
      if (ifid_valid || idex_valid || exmem_valid || memwb_valid ||
          ex_take_branch || trap_flush || mret_flush || sret_flush) begin

        $display("================================================================================");
        $display("[CYCLE %0d] Pipeline State:", pipe_cycle);
        $display("================================================================================");

        // IF 阶段
        $display("IF:  PC=%08h → %08h | instr=%08h comp=%b | stall=%b flush=%b",
                 pc_current, pc_next, if_instruction_raw, if_is_compressed,
                 stall_pc, flush_ifid);
        if (trap_flush) $display("     TRAP: vec=%08h code=%h", trap_vector, exception_code);
        if (mret_flush) $display("     MRET: mepc=%08h", mepc);
        if (sret_flush) $display("     SRET: sepc=%08h", sepc);

        // ID 阶段
        if (ifid_valid && !flush_ifid) begin
          $display("ID:  PC=%08h | instr=%08h | op=%07b func3=%03b rd=x%0d rs1=x%0d rs2=x%0d",
                   ifid_pc, ifid_instruction, id_opcode, id_funct3, id_rd, id_rs1, id_rs2);
          $display("     imm=%08h | br=%b jmp=%b mem_r=%b mem_w=%b reg_w=%b",
                   id_immediate, id_branch, id_jump, id_mem_read, id_mem_write, id_reg_write);
        end else if (flush_ifid) begin
          $display("ID:  <FLUSHED>");
        end else begin
          $display("ID:  <BUBBLE>");
        end

        // EX 阶段
        if (idex_valid && !flush_idex) begin
          $display("EX:  PC=%08h | op=%07b func3=%03b rd=x%0d | br=%b jmp=%b",
                   idex_pc, idex_opcode, idex_funct3, idex_rd_addr, idex_branch, idex_jump);
          $display("     rs1=x%0d(fwd=%08h) rs2=x%0d(fwd=%08h) imm=%08h",
                   idex_rs1_addr, ex_alu_operand_a_forwarded,
                   idex_rs2_addr, ex_rs2_data_forwarded, idex_imm);
          if (idex_branch || idex_jump) begin
            $display("     BR/JMP: take=%b tgt=%08h (br_tgt=%08h jmp_tgt=%08h)",
                     ex_take_branch,
                     idex_jump ? ex_jump_target : ex_branch_target,
                     ex_branch_target, ex_jump_target);
          end
          $display("     ALU: result=%08h", ex_alu_result);
        end else if (flush_idex) begin
          $display("EX:  <FLUSHED>");
        end else begin
          $display("EX:  <BUBBLE>");
        end

        // MEM 阶段
        if (exmem_valid) begin
          $display("MEM: PC=%08h | rd=x%0d alu=%08h | mem_r=%b mem_w=%b",
                   exmem_pc, exmem_rd_addr, exmem_alu_result,
                   exmem_mem_read, exmem_mem_write);
          if (exmem_mem_write) begin
            $display("     MEM_WRITE: data=%08h", exmem_mem_write_data);
          end
        end else begin
          $display("MEM: <BUBBLE>");
        end

        // WB 阶段
        if (memwb_valid) begin
          $display("WB:  rd=x%0d <= %08h | reg_w=%b",
                   memwb_rd_addr, wb_data, memwb_reg_write);
        end else begin
          $display("WB:  <BUBBLE>");
        end

        $display("--------------------------------------------------------------------------------");
        $display("");
      end
    end
  end
  `endif

  //==========================================================================
  // 会话 72：JAL/JALR 特定调试工具
  // 跟踪跳转/分支执行，提供详细的寄存器和目标信息
  //==========================================================================
  `ifdef DEBUG_JAL
  integer jal_cycle;
  initial jal_cycle = 0;

  always @(posedge clk) begin
    if (!reset_n) begin
      jal_cycle = 0;
    end else begin
      jal_cycle = jal_cycle + 1;

      // 检测 ID 阶段的 JAL/JALR
      if (ifid_valid && (id_opcode == 7'b1101111 || id_opcode == 7'b1100111)) begin
        if (id_opcode == 7'b1101111) begin
          $display("[CYCLE %0d] JAL detected in ID stage:", jal_cycle);
          $display("  PC=%08h instr=%08h", ifid_pc, ifid_instruction);
          $display("  rd=x%0d imm=%08h (%0d)", id_rd, id_immediate, $signed(id_immediate));
          $display("  Target: PC + imm = %08h + %08h = %08h",
                   ifid_pc, id_immediate, ifid_pc + id_immediate);
          $display("  Return: PC + 4 = %08h (will be saved to x%0d)",
                   ifid_pc + 4, id_rd);
        end else begin
          $display("[CYCLE %0d] JALR detected in ID stage:", jal_cycle);
          $display("  PC=%08h instr=%08h", ifid_pc, ifid_instruction);
          $display("  rd=x%0d rs1=x%0d imm=%08h", id_rd, id_rs1, id_immediate);
          $display("  Target: rs1 + imm (will be calculated in EX with forwarding)");
          $display("  Return: PC + 4 = %08h (will be saved to x%0d)",
                   ifid_pc + 4, id_rd);
        end
      end

      // 跟踪 EX 阶段的跳转执行
      if (idex_valid && idex_jump && ex_take_branch) begin
        if (idex_opcode == 7'b1101111) begin
          $display("[CYCLE %0d] JAL executing in EX stage:", jal_cycle);
        end else begin
          $display("[CYCLE %0d] JALR executing in EX stage:", jal_cycle);
        end
        $display("  idex_pc=%08h idex_imm=%08h", idex_pc, idex_imm);
        $display("  Jump target: %08h", ex_jump_target);
        $display("  Return addr (PC+4): %08h → x%0d", idex_pc + 4, idex_rd_addr);
        $display("  pc_next will be: %08h", pc_next);
        $display("  Pipeline flush: ifid=%b idex=%b", flush_ifid, flush_idex);
      end

      // 跟踪写入 ra (x1) 的寄存器
      if (memwb_valid && memwb_reg_write && memwb_rd_addr == 5'd1) begin
        $display("[CYCLE %0d] Writing to x1 (ra) in WB stage:", jal_cycle);
        $display("  x1 <= %08h", wb_data);
      end

      // 检测 RET (jalr x0, ra, 0)
      if (ifid_valid && id_opcode == 7'b1100111 && id_rd == 5'd0 && id_rs1 == 5'd1) begin
        $display("[CYCLE %0d] RET detected in ID stage:", jal_cycle);
        $display("  PC=%08h", ifid_pc);
        $display("  Current ra (x1) = %08h", id_rs1_data);
        $display("  Will return to: %08h", id_rs1_data + id_immediate);
      end
    end
  end
  `endif

  //==========================================================================
  // 会话 72：无限循环调试工具
  // 跟踪地址 0x200e（memset 返回）和 0x4ca（prvInitialiseNewTask）周围的执行
  //==========================================================================
  `ifdef DEBUG_LOOP_TRACE
  integer loop_cycle;
  integer loop_count;
  initial begin
    loop_cycle = 0;
    loop_count = 0;
  end

  // 检测无限循环模式
  reg [XLEN-1:0] prev_pc;
  reg [XLEN-1:0] prev_prev_pc;

  always @(posedge clk) begin
    if (!reset_n) begin
      loop_cycle = 0;
      loop_count = 0;
      prev_pc = 0;
      prev_prev_pc = 0;
    end else begin
      loop_cycle = loop_cycle + 1;

      // 跟踪 PC 历史用于循环检测
      prev_prev_pc = prev_pc;
      prev_pc = pc_current;

      // 检测循环：PC 在两个地址之间交替
      if (pc_current == prev_prev_pc && pc_current != prev_pc) begin
        loop_count = loop_count + 1;
        if (loop_count == 1) begin
          $display("\n[LOOP DETECTED] Cycle %0d: Infinite loop between 0x%08h ↔ 0x%08h",
                   loop_cycle, pc_current, prev_pc);
        end
      end else begin
        loop_count = 0;
      end

      // 跟踪关键地址（0x200e、0x4ca、0x4c6）周围的执行
      // 还跟踪整个 memset 函数（0x2000-0x200f）和 prvInitialiseNewTask 范围
      if (pc_current == 32'h0000200e || pc_current == 32'h000004ca || pc_current == 32'h000004c6 ||
          (pc_current >= 32'h000004c0 && pc_current <= 32'h000004d0) ||
          (pc_current >= 32'h00002000 && pc_current <= 32'h0000200f)) begin

        $display("\n[LOOP_TRACE] Cycle %0d ========================================", loop_cycle);
        $display("PC=%08h instr=%08h comp=%b", pc_current, if_instruction_raw, if_is_compressed);

        // 显示关键寄存器（a0-a2、s1、ra、sp）
        $display("Registers: ra=%08h sp=%08h a0=%08h a1=%08h a2=%08h s1=%08h",
                 regfile.registers[1], regfile.registers[2],
                 regfile.registers[10], regfile.registers[11], regfile.registers[12],
                 regfile.registers[9]);

        // 显示流水线状态
        if (ifid_valid) begin
          $display("ID: PC=%08h instr=%08h opcode=%07b jmp=%b br=%b",
                   ifid_pc, ifid_instruction, id_opcode, id_jump, id_branch);
        end
        if (idex_valid) begin
          $display("EX: PC=%08h rd=x%0d alu=%08h jmp=%b br=%b opcode=%07b",
                   idex_pc, idex_rd_addr, ex_alu_result, idex_jump, idex_branch, idex_opcode);
          if (idex_jump || idex_branch) begin
            $display("    Jump/Branch: take=%b target=%08h",
                     ex_take_branch, idex_jump ? ex_jump_target : ex_branch_target);
          end
        end
        if (exmem_valid) begin
          $display("MEM: PC=%08h rd=x%0d result=%08h mem_r=%b mem_w=%b",
                   exmem_pc, exmem_rd_addr, exmem_alu_result,
                   exmem_mem_read, exmem_mem_write);
        end
        if (memwb_valid) begin
          $display("WB: rd=x%0d <= %08h", memwb_rd_addr, wb_data);
        end

        // 0x4ca 处的内存访问细节（加载 s1[48]）
        if (pc_current == 32'h000004ca) begin
          $display("*** At 0x4ca: About to execute 'lw a5,48(s1)'");
          $display("    s1=%08h → s1+48=%08h", regfile.registers[9], regfile.registers[9] + 48);
        end

        // 0x4c6 处的调用（jal 到 memset）
        if (pc_current == 32'h000004c6) begin
          $display("*** At 0x4c6: About to call memset");
          $display("    Target: 0x2000 (memset), Return: 0x4ca");
        end

        // 返回 0x200e
        if (pc_current == 32'h0000200e) begin
          $display("*** At 0x200e: RET from memset");
          $display("    ra=%08h (return target)", regfile.registers[1]);
          $display("    pc_next=%08h (will jump here next cycle)", pc_next);
          $display("    ex_take_branch=%b ex_jump_target=%08h", ex_take_branch, ex_jump_target);
          if (idex_valid && idex_jump) begin
            $display("    EX stage executing JALR:");
            $display("      idex_pc=%08h idex_imm=%08h", idex_pc, idex_imm);
            $display("      rs1_data=%08h (base for jump)", ex_alu_operand_a_forwarded);
            $display("      target = (rs1 + imm) & ~1 = (%08h + %08h) & ~1 = %08h",
                     ex_alu_operand_a_forwarded, idex_imm, ex_jump_target);
          end
        end
      end

      // 在 100 次循环迭代后停止仿真
      if (loop_count > 100) begin
        $display("\n[LOOP_TRACE] ERROR: Stuck in infinite loop for 100+ iterations");
        $display("Loop between: 0x%08h ↔ 0x%08h", pc_current, prev_pc);
        $finish;
      end
    end
  end
  `endif

  //==========================================================================
  // 会话 75：加载指令调试 - 跟踪 LW 错误
  // 目标：确定为什么 LW a5,60(a0) 返回 10 而不是 1
  // 跟踪：1）写入目标地址的内存
  //       2）加载指令数据路径（地址计算、内存读取、转发）
  //       3）写入 a5（x15）的寄存器文件
  //==========================================================================
  `ifdef DEBUG_LOAD_BUG
  integer load_cycle = 0;
  reg [XLEN-1:0] target_addr = 0;  // 将在检测到加载指令时计算
  reg tracking_enabled = 0;

  always @(posedge clk) begin
    if (!reset_n) begin
      load_cycle <= 0;
      target_addr <= 0;
      tracking_enabled <= 0;
    end else begin
      load_cycle <= load_cycle + 1;

      // ============================================================
      // 第 1 部分：跟踪所有内存写入以监视数据损坏
      // ============================================================
      if (exmem_valid && exmem_mem_write) begin
        // 显示所有存储指令的地址和数据
        // funct3[1:0] 编码大小：00=字节，01=半字，10=字，11=双字
        $display("[STORE] Cycle %0d: PC=%08h writes %08h to addr %08h (funct3=%b)",
                 load_cycle, exmem_pc, exmem_mem_write_data, exmem_alu_result,
                 exmem_funct3);

        // 如果我们正在跟踪且此写入命中目标地址，则突出显示
        if (tracking_enabled) begin
          // 检查写入是否与目标地址重叠（考虑大小）
          // funct3[1:0]：00=1 字节，01=2 字节，10=4 字节，11=8 字节
          if (exmem_alu_result <= target_addr &&
              (exmem_alu_result + (1 << exmem_funct3[1:0])) > target_addr) begin
            $display("  *** WRITE TO TRACKED ADDRESS 0x%08h! Data=%08h ***",
                     target_addr, exmem_mem_write_data);
          end
        end
      end

      // ============================================================
      // 第 2 部分：检测有问题的加载指令
      // 跟踪 PC=0x111e 处的 LW 指令（来自会话 75）
      // ============================================================

      // 在 ID 阶段检测加载（解码）
      if (ifid_valid && !flush_ifid && id_opcode == 7'b0000011 && ifid_pc == 32'h0000111e) begin
        $display("\n[LOAD_DETECT] Cycle %0d: Found LW at PC=0x111e in ID stage", load_cycle);
        $display("  Instruction: %08h", ifid_instruction);
        $display("  rs1=x%0d imm=%0d (offset=60)", id_rs1, id_imm_i);
        $display("  ID rs1_data=%08h (from regfile/forward)", id_rs1_data);
        $display("  Expected target addr = rs1_data + 60 = 0x%08h", id_rs1_data + 60);
      end

      // 在 EX 阶段跟踪加载（地址计算）
      if (idex_valid && !flush_idex && idex_opcode == 7'b0000011 && idex_pc == 32'h0000111e) begin
        $display("\n[LOAD_EX] Cycle %0d: LW in EX stage - Address calculation", load_cycle);
        $display("  PC=%08h rd=x%0d", idex_pc, idex_rd_addr);
        $display("  ALU operand A (base) = %08h", ex_alu_operand_a_forwarded);
        $display("  ALU operand B (offset) = %08h", ex_alu_operand_b);
        $display("  Computed address = %08h", ex_alu_result);
        $display("  Forward_A=%b Forward_B=%b", forward_a, forward_b);

        // 启用对该地址的跟踪
        target_addr <= ex_alu_result;
        tracking_enabled <= 1;
      end

      // 在 MEM 阶段跟踪加载（内存读取）
      if (exmem_valid && exmem_mem_read && exmem_pc == 32'h0000111e) begin
        $display("\n[LOAD_MEM] Cycle %0d: LW in MEM stage - Memory access", load_cycle);
        $display("  PC=%08h rd=x%0d", exmem_pc, exmem_rd_addr);
        $display("  Address = %08h", exmem_alu_result);
        $display("  Bus request: valid=%b addr=%08h we=%b size=%b",
                 bus_req_valid, bus_req_addr, bus_req_we, bus_req_size);
        $display("  Bus response: ready=%b rdata=%016h", bus_req_ready, bus_req_rdata);
        $display("  mem_read_data (after arbitration) = %08h", mem_read_data);
        $display("  funct3=%b (load size/sign)", exmem_funct3);
      end

      // 在 WB 阶段跟踪加载（寄存器写入）
      if (memwb_valid && memwb_reg_write && memwb_rd_addr == 5'd15 &&
          memwb_wb_sel == 3'b001) begin  // wb_sel=001 means memory data
        $display("\n[LOAD_WB] Cycle %0d: Writing load result to x15 (a5)", load_cycle);
        $display("  memwb_mem_read_data = %08h", memwb_mem_read_data);
        $display("  wb_data (final) = %08h", wb_data);
        $display("  wb_sel = %b (001=memory)", memwb_wb_sel);

        // 检查这是否是错误的值
        if (wb_data == 32'h0000000a) begin
          $display("  *** BUG DETECTED: Writing 10 (0x0a) instead of expected 1! ***");
        end else if (wb_data == 32'h00000001) begin
          $display("  *** CORRECT: Writing expected value 1 ***");
        end
      end

      // ============================================================
      // 第 3 部分：跟踪所有写入 x15 (a5) 以查看数据流
      // ============================================================
      if (memwb_valid && memwb_reg_write && memwb_rd_addr == 5'd15) begin
        $display("[A5_WRITE] Cycle %0d: x15 <= %08h (source: wb_sel=%b %s) PC=%08h",
                 load_cycle, wb_data, memwb_wb_sel,
                 (memwb_wb_sel == 3'b000) ? "ALU" :
                 (memwb_wb_sel == 3'b001) ? "MEM" :
                 (memwb_wb_sel == 3'b010) ? "PC+4" :
                 (memwb_wb_sel == 3'b011) ? "CSR" :
                 (memwb_wb_sel == 3'b100) ? "MUL/DIV" :
                 (memwb_wb_sel == 3'b101) ? "ATOMIC" :
                 (memwb_wb_sel == 3'b110) ? "FP->INT" : "???",
                 exmem_pc);  // 注意：exmem_pc 落后一周期，但显示了是哪条指令
      end

      // ============================================================
      // 第 4 部分：跟踪目标地址周围的内存读取
      // ============================================================
      if (tracking_enabled && exmem_valid && exmem_mem_read) begin
        // 显示所有内存读取以查看地址计算是否正确
        if (exmem_alu_result >= (target_addr - 32) &&
            exmem_alu_result <= (target_addr + 32)) begin
          $display("[MEM_READ_NEARBY] Cycle %0d: PC=%08h reads from %08h (target=%08h offset=%0d)",
                   load_cycle, exmem_pc, exmem_alu_result, target_addr,
                   $signed(exmem_alu_result - target_addr));
        end
      end
    end
  end
  `endif

endmodule
