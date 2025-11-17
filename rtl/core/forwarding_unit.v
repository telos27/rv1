// 前递单元
// 检测数据相关并产生前递控制信号
// 为 ID 和 EX 阶段提供完整的前递支持:
//   - ID 阶段: EX→ID, MEM→ID, WB→ID (用于分支提前解析)
//   - EX 阶段: EX→EX, MEM→EX (用于 ALU 操作)

module forwarding_unit (
  // ========================================
  // ID 阶段前递 (用于分支)
  // ========================================
  // 分支在 ID 阶段解析，需要来自仍在流水线中的指令
  // (EX、MEM 或 WB 阶段) 的操作数

  input  wire [4:0] id_rs1,            // ID 阶段整数源寄存器 1
  input  wire [4:0] id_rs2,            // ID 阶段整数源寄存器 2

  output reg  [2:0] id_forward_a,      // ID 阶段 rs1 前递选择
  output reg  [2:0] id_forward_b,      // ID 阶段 rs2 前递选择
  // 编码: 3'b100=EX, 3'b010=MEM, 3'b001=WB, 3'b000=无前递

  // ========================================
  // EX 阶段前递 (用于 ALU)
  // ========================================
  // EX 阶段的 ALU 操作需要来自 MEM 或 WB 阶段的操作数

  input  wire [4:0] idex_rs1,          // EX 阶段整数源寄存器 1
  input  wire [4:0] idex_rs2,          // EX 阶段整数源寄存器 2

  output reg  [1:0] forward_a,         // EX 阶段操作数 A 前递选择
  output reg  [1:0] forward_b,         // EX 阶段操作数 B 前递选择
  // 编码: 2'b10=MEM, 2'b01=WB, 2'b00=无前递

  // ========================================
  // 各流水级写端口 (用于比较)
  // ========================================

  // ID/EX 寄存器输出 (当前在 EX 阶段的指令)
  input  wire [4:0] idex_rd,           // EX 阶段目的寄存器
  input  wire       idex_reg_write,    // EX 阶段写回使能
  input  wire       idex_is_atomic,    // EX 阶段为原子指令 (禁止 EX→ID 前递)

  // EX/MEM 寄存器输出 (在 MEM 阶段的指令)
  input  wire [4:0] exmem_rd,          // MEM 阶段目的寄存器
  input  wire       exmem_reg_write,   // MEM 阶段写回使能
  input  wire       exmem_int_reg_write_fp, // MEM 阶段 FP→INT 写回

  // MEM/WB 寄存器输出 (在 WB 阶段的指令)
  input  wire [4:0] memwb_rd,          // WB 阶段目的寄存器
  input  wire       memwb_reg_write,   // WB 阶段写回使能
  input  wire       memwb_int_reg_write_fp, // WB 阶段 FP→INT 写回
  input  wire       memwb_valid,       // WB 阶段指令有效 (未被冲刷)

  // ========================================
  // 浮点寄存器前递
  // ========================================

  // ID 阶段 FP 前递 (用于 FP 分支/比较)
  input  wire [4:0] id_fp_rs1,         // ID 阶段 FP 源寄存器 1
  input  wire [4:0] id_fp_rs2,         // ID 阶段 FP 源寄存器 2
  input  wire [4:0] id_fp_rs3,         // ID 阶段 FP 源寄存器 3

  output reg  [2:0] id_fp_forward_a,   // ID 阶段 FP rs1 前递选择
  output reg  [2:0] id_fp_forward_b,   // ID 阶段 FP rs2 前递选择
  output reg  [2:0] id_fp_forward_c,   // ID 阶段 FP rs3 前递选择

  // EX 阶段 FP 前递 (用于 FP ALU/FMA)
  input  wire [4:0] idex_fp_rs1,       // EX 阶段 FP 源寄存器 1
  input  wire [4:0] idex_fp_rs2,       // EX 阶段 FP 源寄存器 2
  input  wire [4:0] idex_fp_rs3,       // EX 阶段 FP 源寄存器 3 (FMA)

  output reg  [1:0] fp_forward_a,      // EX 阶段 FP 操作数 A 前递选择
  output reg  [1:0] fp_forward_b,      // EX 阶段 FP 操作数 B 前递选择
  output reg  [1:0] fp_forward_c,      // EX 阶段 FP 操作数 C 前递选择

  // FP 各流水级写端口
  input  wire [4:0] idex_fp_rd,        // EX 阶段 FP 目的寄存器
  input  wire       idex_fp_reg_write, // EX 阶段 FP 写回使能
  input  wire [4:0] exmem_fp_rd,       // MEM 阶段 FP 目的寄存器
  input  wire       exmem_fp_reg_write,// MEM 阶段 FP 写回使能
  input  wire [4:0] memwb_fp_rd,       // WB 阶段 FP 目的寄存器
  input  wire       memwb_fp_reg_write // WB 阶段 FP 写回使能
);

  // ========================================
  // ID 阶段整数前递
  // ========================================
  // 优先级: EX > MEM > WB > RegFile
  // 用于分支在 ID 阶段提前取到最新值

  always @(*) begin
    // 默认：不前递
    id_forward_a = 3'b000;

    // 检查 EX 阶段（最高优先级——最新的指令）
    // 对原子操作禁止 EX 前递（它们需要多个周期，结果尚未就绪）
    if (idex_reg_write && (idex_rd != 5'h0) && (idex_rd == id_rs1) && !idex_is_atomic) begin
      id_forward_a = 3'b100;  // 从 EX 阶段前递
    end
    // 检查 MEM 阶段（第二优先级）
    // 包含 FP→INT 写回（FMV.X.W、FCVT.W.S、浮点比较等）
    else if ((exmem_reg_write | exmem_int_reg_write_fp) && (exmem_rd != 5'h0) && (exmem_rd == id_rs1)) begin
      id_forward_a = 3'b010;  // 从 MEM 阶段前递
    end
    // 检查 WB 阶段（最低优先级——最老的指令）
    // 关键：只在 memwb_valid=1 时才前递（防止从已冲刷的指令前递）
    else if ((memwb_reg_write | memwb_int_reg_write_fp) && (memwb_rd != 5'h0) && (memwb_rd == id_rs1) && memwb_valid) begin
      id_forward_a = 3'b001;  // 从 WB 阶段前递
    end
  end

  always @(*) begin
    // 默认：不前递
    id_forward_b = 3'b000;

    // 检查 EX 阶段（最高优先级）
    // 对原子操作禁止 EX 前递（它们需要多个周期，结果尚未就绪）
    if (idex_reg_write && (idex_rd != 5'h0) && (idex_rd == id_rs2) && !idex_is_atomic) begin
      id_forward_b = 3'b100;  // 从 EX 阶段前递
    end
    // 检查 MEM 阶段（第二优先级）
    // 包含 FP→INT 写回（FMV.X.W、FCVT.W.S、浮点比较等）
    else if ((exmem_reg_write | exmem_int_reg_write_fp) && (exmem_rd != 5'h0) && (exmem_rd == id_rs2)) begin
      id_forward_b = 3'b010;  // 从 MEM 阶段前递
    end
    // 检查 WB 阶段（最低优先级）
    // 关键：只在 memwb_valid=1 时才前递（防止从已冲刷的指令前递）
    else if ((memwb_reg_write | memwb_int_reg_write_fp) && (memwb_rd != 5'h0) && (memwb_rd == id_rs2) && memwb_valid) begin
      id_forward_b = 3'b001;  // 从 WB 阶段前递
    end
  end

  // ========================================
  // EX 阶段整数前递
  // ========================================
  // 优先级: MEM > WB > 寄存器堆
  // 用于 EX 阶段 ALU 操作数
  // 注意: EX 到 EX 的前递由 ID 到 EX 的流水寄存器处理

  always @(*) begin
    // 默认：不前递
    forward_a = 2'b00;

    // MEM 冒险（最高优先级）：从 EX/MEM 前递
    // 条件：EX/MEM.reg_write 且 EX/MEM.rd != 0 且 EX/MEM.rd == ID/EX.rs1
    // 包含 FP→INT 写回（FMV.X.W、FCVT.W.S、浮点比较等）
    if ((exmem_reg_write | exmem_int_reg_write_fp) && (exmem_rd != 5'h0) && (exmem_rd == idex_rs1)) begin
      forward_a = 2'b10;
      `ifdef DEBUG_FORWARD
      $display("[FORWARD_A] @%0t MEM hazard: rs1=x%0d matches exmem_rd=x%0d (fwd=2'b10)", $time, idex_rs1, exmem_rd);
      `endif
    end
    // WB 冒险：从 MEM/WB 前递（仅在没有 MEM 冒险时）
    // 条件：MEM/WB.reg_write 且 MEM/WB.rd != 0 且 MEM/WB.rd == ID/EX.rs1
    // 包含 FP→INT 写回
    // 关键：只在 memwb_valid=1 时才前递（防止从已冲刷的指令前递）
    else if ((memwb_reg_write | memwb_int_reg_write_fp) && (memwb_rd != 5'h0) && (memwb_rd == idex_rs1) && memwb_valid) begin
      forward_a = 2'b01;
      `ifdef DEBUG_FORWARD
      $display("[FORWARD_A] @%0t WB hazard: rs1=x%0d matches memwb_rd=x%0d (fwd=2'b01)", $time, idex_rs1, memwb_rd);
      `endif
    end
    `ifdef DEBUG_FORWARD
    else if (idex_rs1 != 5'h0) begin
      $display("[FORWARD_A] @%0t No forward: rs1=x%0d (fwd=2'b00)", $time, idex_rs1);
    end
    `endif
    end

    always @(*) begin
    // 默认：不前递
    forward_b = 2'b00;

    // MEM 冒险（最高优先级）：从 EX/MEM 前递
    // 包含 FP→INT 写回（FMV.X.W、FCVT.W.S、浮点比较等）
    if ((exmem_reg_write | exmem_int_reg_write_fp) && (exmem_rd != 5'h0) && (exmem_rd == idex_rs2)) begin
      forward_b = 2'b10;
      `ifdef DEBUG_FORWARD
      $display("[FORWARD_B] @%0t MEM hazard: rs2=x%0d matches exmem_rd=x%0d (fwd=2'b10)", $time, idex_rs2, exmem_rd);
      `endif
    end
    // WB 冒险：从 MEM/WB 前递
    // 包含 FP→INT 写回
    // 关键：只在 memwb_valid=1 时才前递（防止从已冲刷的指令前递）
    else if ((memwb_reg_write | memwb_int_reg_write_fp) && (memwb_rd != 5'h0) && (memwb_rd == idex_rs2) && memwb_valid) begin
      forward_b = 2'b01;
      `ifdef DEBUG_FORWARD
      $display("[FORWARD_B] @%0t WB hazard: rs2=x%0d matches memwb_rd=x%0d (fwd=2'b01)", $time, idex_rs2, memwb_rd);
      `endif
    end
    `ifdef DEBUG_FORWARD
    else if (idex_rs2 != 5'h0) begin
      $display("[FORWARD_B] @%0t No forward: rs2=x%0d (fwd=2'b00)", $time, idex_rs2);
    end
    `endif
    end

  // ========================================
  // ID 阶段 FP 前递
  // ========================================
  // 优先级: EX > MEM > WB > FP 寄存器堆
  // 浮点寄存器没有像 x0 那样的硬连零寄存器

  always @(*) begin
    // 默认：不前递
    id_fp_forward_a = 3'b000;

    // 检查 EX 阶段（最高优先级）
    if (idex_fp_reg_write && (idex_fp_rd == id_fp_rs1)) begin
      id_fp_forward_a = 3'b100;  // 从 EX 阶段前递
    end
    // 检查 MEM 阶段（次优先级）
    else if (exmem_fp_reg_write && (exmem_fp_rd == id_fp_rs1)) begin
      id_fp_forward_a = 3'b010;  // 从 MEM 阶段前递
    end
    // 检查 WB 阶段（最低优先级）
    // 关键：只在 memwb_valid=1 时才前递（防止从已冲刷的指令前递）
    else if (memwb_fp_reg_write && (memwb_fp_rd == id_fp_rs1) && memwb_valid) begin
      id_fp_forward_a = 3'b001;  // 从 WB 阶段前递
    end
  end

  always @(*) begin
    // 默认：不前递
    id_fp_forward_b = 3'b000;

    // 检查 EX 阶段（最高优先级）
    if (idex_fp_reg_write && (idex_fp_rd == id_fp_rs2)) begin
      id_fp_forward_b = 3'b100;  // 从 EX 阶段前递
    end
    // 检查 MEM 阶段（次优先级）
    else if (exmem_fp_reg_write && (exmem_fp_rd == id_fp_rs2)) begin
      id_fp_forward_b = 3'b010;  // 从 MEM 阶段前递
    end
    // 检查 WB 阶段（最低优先级）
    // 关键：只在 memwb_valid=1 时才前递（防止从已冲刷的指令前递）
    else if (memwb_fp_reg_write && (memwb_fp_rd == id_fp_rs2) && memwb_valid) begin
      id_fp_forward_b = 3'b001;  // 从 WB 阶段前递
    end
  end

  always @(*) begin
    // 默认：不前递
    id_fp_forward_c = 3'b000;

    // 检查 EX 阶段（最高优先级）
    if (idex_fp_reg_write && (idex_fp_rd == id_fp_rs3)) begin
      id_fp_forward_c = 3'b100;  // 从 EX 阶段前递
    end
    // 检查 MEM 阶段（次优先级）
    else if (exmem_fp_reg_write && (exmem_fp_rd == id_fp_rs3)) begin
      id_fp_forward_c = 3'b010;  // 从 MEM 阶段前递
    end
    // 检查 WB 阶段（最低优先级）
    // 关键：只在 memwb_valid=1 时才前递（防止从已冲刷的指令前递）
    else if (memwb_fp_reg_write && (memwb_fp_rd == id_fp_rs3) && memwb_valid) begin
      id_fp_forward_c = 3'b001;  // 从 WB 阶段前递
    end
  end

  // ========================================
  // EX 阶段 FP 前递
  // ========================================
  // 优先级: MEM > WB > FP RegFile
  // 与整数前递逻辑类似

  always @(*) begin
    // 默认：不前递
    fp_forward_a = 2'b00;

    // MEM hazard (最高优先级): 从 EX/MEM 前递
    if (exmem_fp_reg_write && (exmem_fp_rd == idex_fp_rs1)) begin
      fp_forward_a = 2'b10;
    end
    // WB hazard: 从 MEM/WB 前递（仅当无 MEM hazard 时）
    // 关键：只在 memwb_valid=1 时才前递（防止从已冲刷的指令前递）
    else if (memwb_fp_reg_write && (memwb_fp_rd == idex_fp_rs1) && memwb_valid) begin
      fp_forward_a = 2'b01;
    end
  end

  always @(*) begin
    // 默认：不前递
    fp_forward_b = 2'b00;

    // MEM hazard (最高优先级): 从 EX/MEM 前递
    if (exmem_fp_reg_write && (exmem_fp_rd == idex_fp_rs2)) begin
      fp_forward_b = 2'b10;
    end
    // WB hazard: 从 MEM/WB 前递（仅当无 MEM hazard 时）
    // 关键：只在 memwb_valid=1 时才前递（防止从已冲刷的指令前递）
    else if (memwb_fp_reg_write && (memwb_fp_rd == idex_fp_rs2) && memwb_valid) begin
      fp_forward_b = 2'b01;
    end
  end

  always @(*) begin
    // 默认：不前递
    fp_forward_c = 2'b00;

    // MEM hazard (最高优先级): 从 EX/MEM 前递
    if (exmem_fp_reg_write && (exmem_fp_rd == idex_fp_rs3)) begin
      fp_forward_c = 2'b10;
    end
    // WB hazard: 从 MEM/WB 前递（仅当无 MEM hazard 时）
    // 关键：只在 memwb_valid=1 时才前递（防止从已冲刷的指令前递）
    else if (memwb_fp_reg_write && (memwb_fp_rd == idex_fp_rs3) && memwb_valid) begin
      fp_forward_c = 2'b01;
    end
  end

endmodule
