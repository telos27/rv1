// dual_tlb_mmu.v - 双 TLB MMU（指令 TLB + 数据 TLB，共享 PTW）
// 实现 RISC-V Sv32 (RV32) 与 Sv39 (RV64) 虚拟内存翻译
// 使用独立的指令 TLB (I-TLB) 和数据 TLB (D-TLB)
// 消除单一 TLB 仲裁带来的结构冒险
// 作者：RV1 项目组
// 日期：2025-11-08 (Session 125)

`include "config/rv_config.vh"

module dual_tlb_mmu #(
  parameter XLEN = `XLEN,
  parameter ITLB_ENTRIES = 8,   // I-TLB 项数
  parameter DTLB_ENTRIES = 16   // D-TLB 项数（数据访问更频繁）
) (
  input  wire             clk,
  input  wire             reset_n,

  // 指令取指地址翻译（I-TLB）
  input  wire             if_req_valid,
  input  wire [XLEN-1:0]  if_req_vaddr,
  output wire             if_req_ready,
  output wire [XLEN-1:0]  if_req_paddr,
  output wire             if_req_page_fault,
  output wire [XLEN-1:0]  if_req_fault_vaddr,

  // 数据访问地址翻译（D-TLB）
  input  wire             ex_req_valid,
  input  wire [XLEN-1:0]  ex_req_vaddr,
  input  wire             ex_req_is_store,
  output wire             ex_req_ready,
  output wire [XLEN-1:0]  ex_req_paddr,
  output wire             ex_req_page_fault,
  output wire [XLEN-1:0]  ex_req_fault_vaddr,

  // 用于页表遍历的内存接口（共享 PTW）
  output wire             ptw_req_valid,
  output wire [XLEN-1:0]  ptw_req_addr,
  input  wire             ptw_req_ready,
  input  wire [XLEN-1:0]  ptw_resp_data,
  input  wire             ptw_resp_valid,

  // CSR 接口
  input  wire [XLEN-1:0]  satp,
  input  wire [1:0]       privilege_mode,
  input  wire             mstatus_sum,
  input  wire             mstatus_mxr,

  // TLB 刷新控制
  input  wire             tlb_flush_all,
  input  wire             tlb_flush_vaddr,
  input  wire [XLEN-1:0]  tlb_flush_addr
);

  // =========================================================================
  // 翻译启用检测
  // =========================================================================

  wire satp_mode_enabled;
  wire translation_enabled;

  generate
    if (XLEN == 32) begin : gen_mode_sv32
      assign satp_mode_enabled = (satp[31:31] == 1'b1);
    end else begin : gen_mode_sv39
      assign satp_mode_enabled = (satp[63:60] == 4'h8);
    end
  endgenerate

  assign translation_enabled = satp_mode_enabled && (privilege_mode != 2'b11);

  // =========================================================================
  // I-TLB（指令 TLB）
  // =========================================================================

  wire itlb_hit;
  wire [XLEN-1:0] itlb_paddr;
  wire itlb_page_fault;
  wire itlb_update_valid;
  wire [XLEN-1:0] itlb_update_vpn;
  wire [XLEN-1:0] itlb_update_ppn;
  wire [7:0] itlb_update_pte;
  wire [XLEN-1:0] itlb_update_level;

  tlb #(
    .XLEN(XLEN),
    .TLB_ENTRIES(ITLB_ENTRIES)
  ) itlb_inst (
    .clk(clk),
    .reset_n(reset_n),
    // 查表
    .lookup_valid(if_req_valid),
    .lookup_vaddr(if_req_vaddr),
    .lookup_is_store(1'b0),      // 取指不会是写访问
    .lookup_is_fetch(1'b1),      // 总是取指
    .lookup_hit(itlb_hit),
    .lookup_paddr(itlb_paddr),
    .lookup_page_fault(itlb_page_fault),
    // 来自 PTW 的更新
    .update_valid(itlb_update_valid),
    .update_vpn(itlb_update_vpn),
    .update_ppn(itlb_update_ppn),
    .update_pte(itlb_update_pte),
    .update_level(itlb_update_level),
    // CSR
    .privilege_mode(privilege_mode),
    .mstatus_sum(mstatus_sum),
    .mstatus_mxr(mstatus_mxr),
    .translation_enabled(translation_enabled),
    // 刷新
    .flush_all(tlb_flush_all),
    .flush_vaddr(tlb_flush_vaddr),
    .flush_addr(tlb_flush_addr)
  );

  // =========================================================================
  // D-TLB（数据 TLB）
  // =========================================================================

  wire dtlb_hit;
  wire [XLEN-1:0] dtlb_paddr;
  wire dtlb_page_fault;
  wire dtlb_update_valid;
  wire [XLEN-1:0] dtlb_update_vpn;
  wire [XLEN-1:0] dtlb_update_ppn;
  wire [7:0] dtlb_update_pte;
  wire [XLEN-1:0] dtlb_update_level;

  tlb #(
    .XLEN(XLEN),
    .TLB_ENTRIES(DTLB_ENTRIES)
  ) dtlb_inst (
    .clk(clk),
    .reset_n(reset_n),
    // 查表
    .lookup_valid(ex_req_valid),
    .lookup_vaddr(ex_req_vaddr),
    .lookup_is_store(ex_req_is_store),
    .lookup_is_fetch(1'b0),
    .lookup_hit(dtlb_hit),
    .lookup_paddr(dtlb_paddr),
    .lookup_page_fault(dtlb_page_fault),
    // 来自 PTW 的更新
    .update_valid(dtlb_update_valid),
    .update_vpn(dtlb_update_vpn),
    .update_ppn(dtlb_update_ppn),
    .update_pte(dtlb_update_pte),
    .update_level(dtlb_update_level),
    // CSR
    .privilege_mode(privilege_mode),
    .mstatus_sum(mstatus_sum),
    .mstatus_mxr(mstatus_mxr),
    .translation_enabled(translation_enabled),
    // 刷新
    .flush_all(tlb_flush_all),
    .flush_vaddr(tlb_flush_vaddr),
    .flush_addr(tlb_flush_addr)
  );

  // =========================================================================
  // 共享 PTW 仲裁器
  // =========================================================================
  // 优先级：D-TLB > I-TLB（数据缺页对流水线影响更大）
  // PTW 冲突较少（TLB 预热后缺页很少）

  wire if_needs_ptw = if_req_valid && !itlb_hit && translation_enabled;
  wire ex_needs_ptw = ex_req_valid && !dtlb_hit && translation_enabled;

  // PTW 请求仲裁
  wire ptw_grant_to_if = if_needs_ptw && !ex_needs_ptw;
  wire ptw_grant_to_ex = ex_needs_ptw;  // EX 拥有更高优先级

  // PTW 请求复用
  wire ptw_req_valid_internal;
  wire [XLEN-1:0] ptw_req_vaddr;
  wire ptw_req_is_store;
  wire ptw_req_is_fetch;

  // 在下方定义的 ptw_busy_r 提前声明
  reg ptw_busy_r;

  // 只有在 PTW 当前空闲时才发起新的请求，避免重复遍历
  assign ptw_req_valid_internal = (if_needs_ptw || ex_needs_ptw) && !ptw_busy_r;

  // 调试：详细 MMU 操作跟踪
  always @(posedge clk) begin
    // PTW 请求
    if (ptw_req_valid_internal && reset_n) begin
      $display("[DUAL_MMU] PTW req: VA=0x%h grant_if=%b grant_ex=%b fetch=%b store=%b satp=0x%h",
               ptw_req_vaddr, ptw_grant_to_if, ptw_grant_to_ex, ptw_req_is_fetch, ptw_req_is_store, satp);
    end

    // PTW 完成及 TLB 更新
    if (ptw_result_valid && reset_n) begin
      $display("[DUAL_MMU] PTW result: VPN=0x%h PPN=0x%h route_to=%s pte=0x%02h for_itlb=%b",
               ptw_result_vpn, ptw_result_ppn, ptw_for_itlb ? "I-TLB" : "D-TLB", ptw_result_pte, ptw_for_itlb);
    end

    // TLB 更新
    if (itlb_update_valid && reset_n) begin
      $display("[DUAL_MMU] I-TLB update: VPN=0x%h -> PPN=0x%h", itlb_update_vpn, itlb_update_ppn);
    end
    if (dtlb_update_valid && reset_n) begin
      $display("[DUAL_MMU] D-TLB update: VPN=0x%h -> PPN=0x%h", dtlb_update_vpn, dtlb_update_ppn);
    end
  end
  assign ptw_req_vaddr   = ptw_grant_to_ex ? ex_req_vaddr   : if_req_vaddr;
  assign ptw_req_is_store = ptw_grant_to_ex ? ex_req_is_store : 1'b0;
  assign ptw_req_is_fetch = ptw_grant_to_if;

  // =========================================================================
  // 共享 PTW 实例
  // =========================================================================

  wire ptw_ready;
  wire ptw_page_fault;
  wire [XLEN-1:0] ptw_fault_vaddr;
  wire ptw_result_valid;
  wire [XLEN-1:0] ptw_result_vpn;
  wire [XLEN-1:0] ptw_result_ppn;
  wire [7:0] ptw_result_pte;
  wire [XLEN-1:0] ptw_result_level;

  ptw #(
    .XLEN(XLEN)
  ) ptw_inst (
    .clk(clk),
    .reset_n(reset_n),
    // 请求
    .req_valid(ptw_req_valid_internal),
    .req_vaddr(ptw_req_vaddr),
    .req_is_store(ptw_req_is_store),
    .req_is_fetch(ptw_req_is_fetch),
    .req_ready(ptw_ready),
    .req_page_fault(ptw_page_fault),
    .req_fault_vaddr(ptw_fault_vaddr),
    // 返回给 TLB 的结果
    .result_valid(ptw_result_valid),
    .result_vpn(ptw_result_vpn),
    .result_ppn(ptw_result_ppn),
    .result_pte(ptw_result_pte),
    .result_level(ptw_result_level),
    // 内存接口
    .mem_req_valid(ptw_req_valid),
    .mem_req_addr(ptw_req_addr),
    .mem_req_ready(ptw_req_ready),
    .mem_resp_data(ptw_resp_data),
    .mem_resp_valid(ptw_resp_valid),
    // CSR
    .satp(satp),
    .privilege_mode(privilege_mode),
    .mstatus_sum(mstatus_sum),
    .mstatus_mxr(mstatus_mxr)
  );

  // 记录当前这次 PTW 是由哪个 TLB 发起的（用于结果路由）
  // 只在 PTW 从空闲变为忙时锁存
  reg ptw_for_itlb;
  // 注意：ptw_busy_r 已在上方声明

  always @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
      ptw_for_itlb <= 0;
      ptw_busy_r   <= 0;
    end else begin
      // 更新 busy 状态
      if (ptw_req_valid_internal && !ptw_ready) begin
        ptw_busy_r <= 1;  // PTW 进入忙状态
      end else if (ptw_ready || !ptw_req_valid_internal) begin
        ptw_busy_r <= 0;  // PTW 空闲
      end

      // 仅在 PTW 开始时锁存当前是 I-TLB 还是 D-TLB
      if (ptw_req_valid_internal && !ptw_busy_r) begin
        ptw_for_itlb <= ptw_grant_to_if;
      end
    end
  end

  // 将 PTW 结果路由到正确的 TLB
  assign itlb_update_valid = ptw_result_valid && ptw_for_itlb;
  assign itlb_update_vpn   = ptw_result_vpn;
  assign itlb_update_ppn   = ptw_result_ppn;
  assign itlb_update_pte   = ptw_result_pte;
  assign itlb_update_level = ptw_result_level;

  assign dtlb_update_valid = ptw_result_valid && !ptw_for_itlb;
  assign dtlb_update_vpn   = ptw_result_vpn;
  assign dtlb_update_ppn   = ptw_result_ppn;
  assign dtlb_update_pte   = ptw_result_pte;
  assign dtlb_update_level = ptw_result_level;

  // =========================================================================
  // I-TLB 响应路径
  // =========================================================================

  // Bare 模式（禁用翻译）：直接 VA=PA 透传
  wire if_bare_mode = !translation_enabled;

  // IF ready 条件：（1) bare 模式；（2) TLB 命中；（3) 对应的 PTW 完成
  assign if_req_ready = if_bare_mode ||
                        (if_req_valid && itlb_hit) ||
                        (ptw_ready && ptw_grant_to_if);

  // IF 物理地址：bare 模式→VA；TLB 命中→TLB 结果；PTW 进行中→输出 0（上层应等待）
  assign if_req_paddr = if_bare_mode ? if_req_vaddr :
                        itlb_hit ? itlb_paddr :
                        {XLEN{1'b0}};  // PTW 进行中，流水线应停顿

  // IF 页错误：(1) TLB 命中但权限错误；(2) PTW 为 IF 服务时返回页错误
  assign if_req_page_fault = (if_req_valid && itlb_hit && itlb_page_fault) ||
                             (ptw_page_fault && ptw_grant_to_if);

  assign if_req_fault_vaddr = ptw_fault_vaddr;

  // =========================================================================
  // D-TLB 响应路径
  // =========================================================================

  wire ex_bare_mode = !translation_enabled;

  assign ex_req_ready = ex_bare_mode ||
                        (ex_req_valid && dtlb_hit) ||
                        (ptw_ready && ptw_grant_to_ex);

  assign ex_req_paddr = ex_bare_mode ? ex_req_vaddr :
                        dtlb_hit ? dtlb_paddr :
                        {XLEN{1'b0}};

  assign ex_req_page_fault = (ex_req_valid && dtlb_hit && dtlb_page_fault) ||
                             (ptw_page_fault && ptw_grant_to_ex);

  assign ex_req_fault_vaddr = ptw_fault_vaddr;

endmodule
