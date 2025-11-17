// mmu.v - 带 TLB 的内存管理单元 (MMU)
// 实现 RISC-V Sv32（RV32）和 Sv39（RV64）虚拟内存地址转换
// 包含转换后备缓冲 (TLB) 以提高性能
// 支持页错误异常
// 作者: RV1 Project
// 日期: 2025-10-11

`include "config/rv_config.vh"

module mmu #(
  parameter XLEN = `XLEN,
  parameter TLB_ENTRIES = `TLB_ENTRIES  // TLB 项数（2 的幂）
) (
  input  wire             clk,
  input  wire             reset_n,

  // 虚拟地址翻译请求
  input  wire             req_valid,        // 翻译请求有效
  input  wire [XLEN-1:0]  req_vaddr,        // 待翻译的虚拟地址
  input  wire             req_is_store,     // 1=写访问，0=读访问
  input  wire             req_is_fetch,     // 1=取指，0=数据访问
  input  wire [2:0]       req_size,         // 访问大小（0=字节，1=半字，2=字，3=双字）
  output reg              req_ready,        // 翻译完成
  output reg  [XLEN-1:0]  req_paddr,        // 物理地址（翻译结果）
  output reg              req_page_fault,   // 页错误异常
  output reg  [XLEN-1:0]  req_fault_vaddr,  // 发生错误的虚拟地址

  // 页表遍历的存储器接口
  output reg              ptw_req_valid,    // 页表遍历内存请求
  output reg  [XLEN-1:0]  ptw_req_addr,     // PTW 使用的物理地址
  input  wire             ptw_req_ready,    // 存储器就绪
  input  wire [XLEN-1:0]  ptw_resp_data,    // 页表项数据
  input  wire             ptw_resp_valid,   // 响应有效

  // CSR 接口
  input  wire [XLEN-1:0]  satp,             // SATP 寄存器（页表基址 + 模式）
  input  wire [1:0]       privilege_mode,   // 当前特权级（0=U，1=S，3=M）
  input  wire             mstatus_sum,      // S 模式访问 U 模式内存 (SUM)
  input  wire             mstatus_mxr,      // 可执行页可读 (MXR)

  // TLB 刷新控制
  input  wire             tlb_flush_all,    // 刷新整个 TLB
  input  wire             tlb_flush_vaddr,  // 刷新指定虚拟地址
  input  wire [XLEN-1:0]  tlb_flush_addr    // 当 tlb_flush_vaddr 为 1 时，需要刷新的地址
);

  // =========================================================================
  // RISC-V 虚拟内存参数
  // =========================================================================

  // Sv32（RV32）：2 级页表，4KB 页
  // Sv39（RV64）：3 级页表，4KB 页
  localparam PAGE_SHIFT = 12;                    // 4KB 页偏移位数
  localparam PAGE_SIZE = 1 << PAGE_SHIFT;        // 4096 字节

  // Sv32（RV32）参数
  localparam SV32_LEVELS = 2;
  localparam SV32_VPN_BITS = 10;                 // VPN[1:0] 各 10 位
  localparam SV32_PPN_BITS = 22;                 // PPN = 22 位

  // Sv39（RV64）参数
  localparam SV39_LEVELS = 3;
  localparam SV39_VPN_BITS = 9;                  // VPN[2:0] 各 9 位
  localparam SV39_PPN_BITS = 44;                 // PPN = 44 位

  // SATP 模式编码
  localparam SATP_MODE_BARE = (XLEN == 32) ? 4'h0 : 4'h0;  // 不使用地址翻译
  localparam SATP_MODE_SV32 = (XLEN == 32) ? 4'h1 : 4'h0;  // Sv32（仅限 RV32）
  localparam SATP_MODE_SV39 = (XLEN == 64) ? 4'h8 : 4'h0;  // Sv39（仅限 RV64）

  // PTE（页表项）位字段
  localparam PTE_V = 0;  // 有效位
  localparam PTE_R = 1;  // 可读
  localparam PTE_W = 2;  // 可写
  localparam PTE_X = 3;  // 可执行
  localparam PTE_U = 4;  // 用户态可访问
  localparam PTE_G = 5;  // 全局映射
  localparam PTE_A = 6;  // 已访问
  localparam PTE_D = 7;  // 已修改 (Dirty)

  // =========================================================================
  // SATP 寄存器解码
  // =========================================================================

  wire [3:0] satp_mode;
  wire [XLEN-1:0] satp_ppn;
  wire translation_enabled;

  generate
    if (XLEN == 32) begin : gen_satp_sv32
      assign satp_mode = satp[31:31];  // Sv32 模式位为 1 位
      assign satp_ppn = {{10{1'b0}}, satp[21:0]};  // 22 位 PPN
      assign translation_enabled = (satp_mode == 1'b1) && (privilege_mode != 2'b11);
    end else begin : gen_satp_sv39
      assign satp_mode = satp[63:60];  // Sv39 模式位为 4 位
      assign satp_ppn = {{20{1'b0}}, satp[43:0]};  // 44 位 PPN
      assign translation_enabled = (satp_mode == 4'h8) && (privilege_mode != 2'b11);
    end
  endgenerate

  // =========================================================================
  // TLB 结构
  // =========================================================================

  // TLB 项结构
  reg                   tlb_valid [0:TLB_ENTRIES-1];
  reg [XLEN-1:0]        tlb_vpn   [0:TLB_ENTRIES-1];  // 虚拟页号
  reg [XLEN-1:0]        tlb_ppn   [0:TLB_ENTRIES-1];  // 物理页号
  reg [7:0]             tlb_pte   [0:TLB_ENTRIES-1];  // PTE 标志位 (V,R,W,X,U,G,A,D)
  reg [XLEN-1:0]        tlb_level [0:TLB_ENTRIES-1];  // 页级别（用于大页）

  // TLB 替换策略：简单轮询 (round-robin)
  reg [$clog2(TLB_ENTRIES)-1:0] tlb_replace_idx;

  // =========================================================================
  // 页表遍历状态机
  // =========================================================================

  localparam PTW_IDLE       = 3'b000;
  localparam PTW_LEVEL_0    = 3'b001;
  localparam PTW_LEVEL_1    = 3'b010;
  localparam PTW_LEVEL_2    = 3'b011;
  localparam PTW_UPDATE_TLB = 3'b100;
  localparam PTW_FAULT      = 3'b101;

  reg [2:0] ptw_state;
  reg [2:0] ptw_level;           // 当前页表级别
  reg [XLEN-1:0] ptw_pte_addr;   // 当前 PTE 地址
  reg [XLEN-1:0] ptw_pte_data;   // 当前 PTE 数据
  reg [XLEN-1:0] ptw_vpn_save;   // 遍历过程中保存的 VPN
  reg [XLEN-1:0] ptw_vaddr_save; // 遍历过程中保存的完整虚拟地址
  reg ptw_is_store_save;         // 保存的访问类型（写）
  reg ptw_is_fetch_save;         // 保存的取指标志
  reg [1:0] ptw_priv_save;       // 保存的特权级
  reg ptw_sum_save;              // 保存的 SUM 位
  reg ptw_mxr_save;              // 保存的 MXR 位

  // =========================================================================
  // VPN 提取
  // =========================================================================

  function [XLEN-1:0] extract_vpn;
    input [XLEN-1:0] vaddr;
    input integer level;
    begin
      if (XLEN == 32) begin
        // Sv32: VPN[1] = bits[31:22], VPN[0] = bits[21:12]
        case (level)
          0: extract_vpn = vaddr[21:12];
          1: extract_vpn = vaddr[31:22];
          default: extract_vpn = 0;
        endcase
      end else begin
        // Sv39: VPN[2] = bits[38:30], VPN[1] = bits[29:21], VPN[0] = bits[20:12]
        case (level)
          0: extract_vpn = vaddr[20:12];
          1: extract_vpn = vaddr[29:21];
          2: extract_vpn = vaddr[38:30];
          default: extract_vpn = 0;
        endcase
      end
    end
  endfunction

  function [XLEN-1:0] get_full_vpn;
    input [XLEN-1:0] vaddr;
    begin
      if (XLEN == 32) begin
        // Sv32: VPN = bits[31:12]（20 位）
        get_full_vpn = {{(XLEN-20){1'b0}}, vaddr[31:12]};
      end else begin
        // Sv39: VPN = bits[38:12]（27 位）
        get_full_vpn = {{(XLEN-27){1'b0}}, vaddr[38:12]};
      end
    end
  endfunction

  // =========================================================================
  // TLB 查找
  // =========================================================================

  reg tlb_hit;
  reg [$clog2(TLB_ENTRIES)-1:0] tlb_hit_idx;
  reg [XLEN-1:0] tlb_ppn_out;
  reg [7:0] tlb_pte_out;
  reg [XLEN-1:0] tlb_level_out;
  reg perm_check_result;  // 调试：保存权限检查结果

  integer i;
  always @(*) begin
    tlb_hit = 0;
    tlb_hit_idx = 0;
    tlb_ppn_out = 0;
    tlb_pte_out = 0;
    tlb_level_out = 0;

    if (translation_enabled && req_valid) begin
      for (i = 0; i < TLB_ENTRIES; i = i + 1) begin
        if (tlb_valid[i] && (tlb_vpn[i] == get_full_vpn(req_vaddr))) begin
          tlb_hit = 1;
          tlb_hit_idx = i[$clog2(TLB_ENTRIES)-1:0];
          tlb_ppn_out = tlb_ppn[i];
          tlb_pte_out = tlb_pte[i];
          tlb_level_out = tlb_level[i];
        end
      end
    end
  end

  // =========================================================================
  // 权限检查
  // =========================================================================

  function check_permission;
    input [7:0] pte_flags;
    input is_store;
    input is_fetch;
    input [1:0] priv_mode;
    input sum;
    input mxr;
    begin
      check_permission = 1;

      // 检查有效位
      if (!pte_flags[PTE_V]) begin
        check_permission = 0;
      end
      // 检查是否为叶子 PTE（至少 R 或 X 之一必须置位）
      else if (!pte_flags[PTE_R] && !pte_flags[PTE_W] && !pte_flags[PTE_X]) begin
        check_permission = 0;  // 非叶子 PTE 出现在错误级别
      end
      // 检查写权限（W=1 时必须 R=1）
      else if (pte_flags[PTE_W] && !pte_flags[PTE_R]) begin
        check_permission = 0;
      end
      // 检查用户态访问
      else if (priv_mode == 2'b00) begin  // U 模式
        if (!pte_flags[PTE_U]) begin
          check_permission = 0;  // 用户访问 S 页
        end
      end
      else if (priv_mode == 2'b01) begin  // S 模式
        if (pte_flags[PTE_U] && !sum) begin
          check_permission = 0;  // S 模式访问 U 页但 SUM=0
        end
      end

      // 根据访问类型进行检查
      if (check_permission) begin
        if (is_fetch) begin
          check_permission = pte_flags[PTE_X];
        end else if (is_store) begin
          check_permission = pte_flags[PTE_W];
        end else begin
          // 读访问：需要 R 或（X 且 MXR=1）
          check_permission = pte_flags[PTE_R] || (pte_flags[PTE_X] && mxr);
        end
      end
    end
  endfunction

  // =========================================================================
  // 物理地址构造
  // =========================================================================

  // 根据 PPN、虚拟地址和页级别构造物理地址
  // 对于 Sv32:
  //   - Level 1 (大页，4MB): PA = {PPN[1], VA[21:0]}
  //   - Level 0 (4KB 页):    PA = {PPN[1], PPN[0], VA[11:0]}
  // 对于 Sv39:
  //   - Level 2 (1GB 大页):  PA = {PPN[2], VA[29:0]}
  //   - Level 1 (2MB 大页):  PA = {PPN[2], PPN[1], VA[20:0]}
  //   - Level 0 (4KB 页):    PA = {PPN[2], PPN[1], PPN[0], VA[11:0]}
  function [XLEN-1:0] construct_pa;
    input [XLEN-1:0] ppn;    // PTE 中的完整 PPN
    input [XLEN-1:0] vaddr;  // 虚拟地址
    input [XLEN-1:0] level;  // 页表级别
    begin
      if (XLEN == 32) begin
        // Sv32
        case (level)
          0: construct_pa = {ppn[XLEN-PAGE_SHIFT-1:0], vaddr[PAGE_SHIFT-1:0]};     // 4KB: {PPN, VA[11:0]}
          1: construct_pa = {ppn[XLEN-PAGE_SHIFT-1:10], vaddr[PAGE_SHIFT+9:0]};    // 4MB: {PPN[1], VA[21:0]}
          default: construct_pa = {ppn[XLEN-PAGE_SHIFT-1:0], vaddr[PAGE_SHIFT-1:0]};
        endcase
      end else begin
        // Sv39
        case (level)
          0: construct_pa = {ppn[XLEN-PAGE_SHIFT-1:0], vaddr[PAGE_SHIFT-1:0]};     // 4KB: {PPN, VA[11:0]}
          1: construct_pa = {ppn[XLEN-PAGE_SHIFT-1:9], vaddr[PAGE_SHIFT+8:0]};     // 2MB: {PPN[2:1], VA[20:0]}
          2: construct_pa = {ppn[XLEN-PAGE_SHIFT-1:18], vaddr[PAGE_SHIFT+17:0]};   // 1GB: {PPN[2], VA[29:0]}
          default: construct_pa = {ppn[XLEN-PAGE_SHIFT-1:0], vaddr[PAGE_SHIFT-1:0]};
        endcase
      end
    end
  endfunction

  // =========================================================================
  // 页表遍历逻辑
  // =========================================================================

  wire [XLEN-1:0] max_levels = (XLEN == 32) ? SV32_LEVELS : SV39_LEVELS;
  wire [XLEN-1:0] pte_size = (XLEN == 32) ? 4 : 8;  // PTE 大小：RV32 为 4 字节，RV64 为 8 字节

  always @(posedge clk or negedge reset_n) begin
    // 调试：在周期开始时跟踪状态
    if (reset_n && req_valid && req_vaddr[31:16] == 16'h0000) begin
      $display("[DBG] Cycle start: ptw_state=%0d, req_valid=%b, req_vaddr=0x%h", ptw_state, req_valid, req_vaddr);
    end

    if (!reset_n) begin
      ptw_state <= PTW_IDLE;
      ptw_level <= 0;
      ptw_pte_addr <= 0;
      ptw_pte_data <= 0;
      ptw_vpn_save <= 0;
      ptw_vaddr_save <= 0;
      ptw_is_store_save <= 0;
      ptw_is_fetch_save <= 0;
      ptw_priv_save <= 0;
      ptw_sum_save <= 0;
      ptw_mxr_save <= 0;
      ptw_req_valid <= 0;
      ptw_req_addr <= 0;
      req_ready <= 0;
      req_paddr <= 0;
      req_page_fault <= 0;
      req_fault_vaddr <= 0;
      tlb_replace_idx <= 0;

      // 初始化 TLB
      for (i = 0; i < TLB_ENTRIES; i = i + 1) begin
        tlb_valid[i] <= 0;
        tlb_vpn[i] <= 0;
        tlb_ppn[i] <= 0;
        tlb_pte[i] <= 0;
        tlb_level[i] <= 0;
      end
    end else begin
      // 默认输出（在 BARE 模式下保持 req_ready 和 req_paddr 有效）
      // 对 EX 阶段的组合输出使用阻塞赋值 (=)
      if (!translation_enabled && req_valid) begin
        req_ready = 1'b1;
        req_paddr = req_vaddr;  // BARE 模式：VA == PA
        req_page_fault = 0;
      end else begin
        req_ready = 1'b0;
        req_page_fault = 0;
        // 此处不更新 req_paddr —— 由 TLB 命中/未命中路径进行更新
      end
      // 不要在默认情况下清除 ptw_req_valid —— 交给状态机控制
      // 否则在等待 ptw_resp_valid 时 PTW 握手会被破坏
      // ptw_req_valid <= 0;  // BUG: 在响应到来前清除了请求！

      // TLB 刷新逻辑
      if (tlb_flush_all) begin
        for (i = 0; i < TLB_ENTRIES; i = i + 1) begin
          tlb_valid[i] <= 0;
        end
      end else if (tlb_flush_vaddr) begin
        for (i = 0; i < TLB_ENTRIES; i = i + 1) begin
          if (tlb_vpn[i] == get_full_vpn(tlb_flush_addr)) begin
            tlb_valid[i] <= 0;
          end
        end
      end

      case (ptw_state)
        PTW_IDLE: begin
          if (req_valid) begin
            // 检查是否启用地址翻译
            if (!translation_enabled) begin
              // BARE 模式：直接映射（req_ready 和 req_paddr 已在默认值中设置）
              // $display("MMU: Bare mode, VA=0x%h -> PA=0x%h", req_vaddr, req_vaddr);
              // 注意：req_paddr 和 req_ready 在上面的默认逻辑中设置
            end else begin
              // 检查 TLB
              $display("MMU: 翻译模式, VA=0x%h (fetch=%b store=%b), TLB hit=%b, ptw_state=%0d",
                       req_vaddr, req_is_fetch, req_is_store, tlb_hit, ptw_state);
              if (tlb_hit) begin
                // TLB 命中：检查权限
                perm_check_result = check_permission(tlb_pte_out, req_is_store, req_is_fetch,
                                                     privilege_mode, mstatus_sum, mstatus_mxr);
                $display("MMU: TLB HIT VA=0x%h PTE=0x%h[U=%b] priv=%b sum=%b result=%b",
                         req_vaddr, tlb_pte_out, tlb_pte_out[PTE_U], privilege_mode, mstatus_sum, perm_check_result);
                if (perm_check_result) begin
                  // 权限通过——根据页级别构造 PA
                  // 关键：TLB 命中时使用阻塞赋值 (=) 以提供组合输出
                  // 这样 MMU 可以在 EX 阶段工作，而无需额外流水级
                  req_paddr = construct_pa(tlb_ppn_out, req_vaddr, tlb_level_out);
                  req_ready = 1;
                  // if (req_vaddr[31:28] == 4'h9)  // 调试 VA 0x90000000 范围
                  //   $display("[%0t] MMU: TLB HIT - VA=0x%h -> PA=0x%h (PPN=0x%h, level=%0d)",
                  //            $time, req_vaddr, construct_pa(tlb_ppn_out, req_vaddr, tlb_level_out), tlb_ppn_out, tlb_level_out);
                end else begin
                  // 权限不通过
                  $display("MMU：权限被拒绝 - 页面错误！");
                  req_page_fault = 1;
                  req_fault_vaddr = req_vaddr;
                  req_ready = 1;
                end
              end else begin
                // TLB 未命中：开始页表遍历
                $display("MMU: TLB MISS VA=0x%h, starting PTW", req_vaddr);
                ptw_vpn_save <= get_full_vpn(req_vaddr);
                ptw_vaddr_save <= req_vaddr;
                ptw_is_store_save <= req_is_store;
                ptw_is_fetch_save <= req_is_fetch;
                ptw_priv_save <= privilege_mode;
                ptw_sum_save <= mstatus_sum;
                ptw_mxr_save <= mstatus_mxr;
                ptw_level <= max_levels - 1;  // 从最高级别开始

                // 计算第一个 PTE 地址
                // a = satp.ppn * PAGESIZE + va.vpn[i] * PTESIZE
                if (XLEN == 32) begin
                  ptw_pte_addr <= (satp_ppn << PAGE_SHIFT) +
                                  (extract_vpn(req_vaddr, max_levels - 1) << 2);
                end else begin
                  ptw_pte_addr <= (satp_ppn << PAGE_SHIFT) +
                                  (extract_vpn(req_vaddr, max_levels - 1) << 3);
                end

                // 根据级别选择正确的 PTW 状态
                // 对于 Sv32: max_levels=2，从 level 1 开始，状态=PTW_LEVEL_1
                // 对于 Sv39: max_levels=3，从 level 2 开始，状态=PTW_LEVEL_2
                case (max_levels - 1)
                  2: ptw_state <= PTW_LEVEL_2;
                  1: ptw_state <= PTW_LEVEL_1;
                  default: ptw_state <= PTW_LEVEL_0;
                endcase
                $display("[DBG] PTW_IDLE: 在级别 %0d 开始 PTW", max_levels - 1);
              end
            end
          end
        end

        PTW_LEVEL_0, PTW_LEVEL_1, PTW_LEVEL_2: begin
          // 对 PTE 发起内存请求
          if (!ptw_req_valid) begin
            $display("MMU：PTW 级别 %0d - 发起内存请求，地址=0x%h", ptw_level, ptw_pte_addr);
            ptw_req_valid <= 1;
            ptw_req_addr <= ptw_pte_addr;
          end else if (ptw_req_ready && ptw_resp_valid) begin
            // 收到 PTE 响应
            $display("[DBG] PTW 收到响应: data=0x%h, V=%b, R=%b, W=%b, X=%b, U=%b",
                     ptw_resp_data, ptw_resp_data[PTE_V], ptw_resp_data[PTE_R],
                     ptw_resp_data[PTE_W], ptw_resp_data[PTE_X], ptw_resp_data[PTE_U]);
            ptw_pte_data <= ptw_resp_data;
            ptw_req_valid <= 0;

            // 首先检查 PTE 是否有效
            if (!ptw_resp_data[PTE_V]) begin
              // 无效 PTE：页错误
              $display("[DBG] PTW FAULT: 无效的 PTE (V=0)");
              ptw_state <= PTW_FAULT;
            // 检查是否为叶子 PTE
            end else if (ptw_resp_data[PTE_R] || ptw_resp_data[PTE_X]) begin
              // 找到叶子 PTE：检查权限
              if (check_permission(ptw_resp_data[7:0], ptw_is_store_save, ptw_is_fetch_save,
                                   ptw_priv_save, ptw_sum_save, ptw_mxr_save)) begin
                // 权限通过：更新 TLB
                ptw_state <= PTW_UPDATE_TLB;
              end else begin
                // 权限不通过
                $display("[DBG] PTW FAULT: 权限被拒绝");
                ptw_state <= PTW_FAULT;
              end
            end else if (ptw_level == 0) begin
              // 在 level 0 仍是非叶子：错误
              ptw_state <= PTW_FAULT;
            end else begin
              // 非叶子 PTE：进入下一层
              ptw_level <= ptw_level - 1;

              // 计算下一层 PTE 地址
              // a = pte.ppn * PAGESIZE + va.vpn[i-1] * PTESIZE
              if (XLEN == 32) begin
                ptw_pte_addr <= (ptw_resp_data[31:10] << PAGE_SHIFT) +
                                (extract_vpn(req_vaddr, ptw_level - 1) << 2);
              end else begin
                ptw_pte_addr <= (ptw_resp_data[53:10] << PAGE_SHIFT) +
                                (extract_vpn(req_vaddr, ptw_level - 1) << 3);
              end

              // 保持在 PTW 状态（下一层）
              case (ptw_level)
                2: ptw_state <= PTW_LEVEL_1;
                1: ptw_state <= PTW_LEVEL_0;
                default: ptw_state <= PTW_FAULT;
              endcase
            end
          end else begin
            // 等待响应——保持请求有效
            ptw_req_valid <= 1;
          end
        end

        PTW_UPDATE_TLB: begin
          // 使用新的翻译结果更新 TLB
          tlb_valid[tlb_replace_idx] <= 1;
          tlb_vpn[tlb_replace_idx] <= ptw_vpn_save;

          // 从 PTE 中提取 PPN
          // RV32 Sv32: PPN 为 22 位 [31:10]，补零扩展到 XLEN（32-22=10 个 0）
          // RV64 Sv39: PPN 为 44 位 [53:10]，补零扩展到 XLEN（64-44=20 个 0）
          if (XLEN == 32) begin
            tlb_ppn[tlb_replace_idx] <= {{10{1'b0}}, ptw_pte_data[31:10]};
          end else begin
            tlb_ppn[tlb_replace_idx] <= {{20{1'b0}}, ptw_pte_data[53:10]};
          end

          tlb_pte[tlb_replace_idx] <= ptw_pte_data[7:0];
          tlb_level[tlb_replace_idx] <= ptw_level;

          // 调试输出
          $display("MMU: TLB[%0d] 更新: VPN=0x%h, PPN=0x%h, PTE=0x%h",
                   tlb_replace_idx, ptw_vpn_save, ptw_pte_data[53:10], ptw_pte_data[7:0]);

          // 更新替换索引
          tlb_replace_idx <= tlb_replace_idx + 1;

          // 对当前访问进行权限检查（与 TLB 命中的路径相同）
          perm_check_result = check_permission(ptw_pte_data[7:0], ptw_is_store_save, ptw_is_fetch_save,
                                               ptw_priv_save, ptw_sum_save, ptw_mxr_save);
          // $display("MMU: PTW complete VA=0x%h PTE=0x%h[U=%b] priv=%b sum=%b result=%b",
          //          ptw_vaddr_save, ptw_pte_data[7:0], ptw_pte_data[PTE_U], ptw_priv_save, ptw_sum_save, perm_check_result);

          if (perm_check_result) begin
            // 权限通过——生成物理地址
            if (XLEN == 32) begin
              req_paddr <= construct_pa({{10{1'b0}}, ptw_pte_data[31:10]}, ptw_vaddr_save, ptw_level);
            end else begin
              req_paddr <= construct_pa({{20{1'b0}}, ptw_pte_data[53:10]}, ptw_vaddr_save, ptw_level);
            end
            req_ready <= 1;
          end else begin
            // 权限不通过——产生页错误
            $display("MMU: PTW 权限被拒绝 - 页错误! VA=0x%h PTE=0x%h priv=%b sum=%b",
                     ptw_vaddr_save, ptw_pte_data[7:0], ptw_priv_save, ptw_sum_save);
            req_page_fault <= 1;
            req_fault_vaddr <= ptw_vaddr_save;
            req_ready <= 1;
          end

          ptw_req_valid <= 0;  // 清除 PTW 请求
          ptw_state <= PTW_IDLE;
        end

        PTW_FAULT: begin
            // 页错误 - 但仍然更新 TLB 来缓存该地址的转换结果！
            // 这可以防止对发生错误的地址进行无限次的页表遍历
            // TLB 会缓存带有权限位的 PTE，这样后续访问可以快速失败，而无需再次完整页表遍历

          // 仅当我们拥有有效的 PTE 数据时才更新 TLB（权限错误，而非无效 PTE）
          if (ptw_pte_data[PTE_V]) begin
            tlb_valid[tlb_replace_idx] <= 1;
            tlb_vpn[tlb_replace_idx] <= ptw_vpn_save;

            // 从 PTE 提取 PPN
            if (XLEN == 32) begin
              tlb_ppn[tlb_replace_idx] <= {{10{1'b0}}, ptw_pte_data[31:10]};
            end else begin
              tlb_ppn[tlb_replace_idx] <= {{20{1'b0}}, ptw_pte_data[53:10]};
            end

            tlb_pte[tlb_replace_idx] <= ptw_pte_data[7:0];
            tlb_level[tlb_replace_idx] <= ptw_level;

            if (XLEN == 32) begin
              $display("MMU: TLB[%0d] 更新 (FAULT): VPN=0x%h, PPN=0x%h, PTE=0x%h",
                       tlb_replace_idx, ptw_vpn_save, ptw_pte_data[31:10], ptw_pte_data[7:0]);
            end else begin
              $display("MMU: TLB[%0d] 更新 (FAULT): VPN=0x%h, PPN=0x%h, PTE=0x%h",
                       tlb_replace_idx, ptw_vpn_save, ptw_pte_data[53:10], ptw_pte_data[7:0]);
            end

            // 更新替换索引
            tlb_replace_idx <= tlb_replace_idx + 1;
          end

          // 产生页错误信号
          req_page_fault <= 1;
          req_fault_vaddr <= ptw_vaddr_save;
          req_ready <= 1;
          ptw_req_valid <= 0;  // 清除 PTW 请求
          ptw_state <= PTW_IDLE;
        end

        default: ptw_state <= PTW_IDLE;
      endcase
    end
  end

endmodule
