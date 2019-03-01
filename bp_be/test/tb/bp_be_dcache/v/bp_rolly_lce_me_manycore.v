/**
 *  bp_rolly_lce_me_manycore.v
 */ 

`include "bsg_manycore_packet.vh"

module bp_rolly_lce_me_manycore
  import bp_common_pkg::*;
  import bp_be_dcache_pkg::*;
  import bp_cce_pkg::*;
  import bsg_noc_pkg::*;
  #(parameter data_width_p="inv"
    , parameter sets_p="inv"
    , parameter ways_p="inv"
    , parameter paddr_width_p="inv"
    , parameter num_lce_p="inv"
    , parameter num_cce_p="inv"
    , parameter num_cce_inst_ram_els_p="inv"
    
    , localparam data_mask_width_lp=(data_width_p>>3)
    , localparam block_size_in_words_lp=ways_p
    , localparam byte_offset_width_lp=`BSG_SAFE_CLOG2(data_mask_width_lp)
    , localparam word_offset_width_lp=`BSG_SAFE_CLOG2(block_size_in_words_lp)
    , localparam index_width_lp=`BSG_SAFE_CLOG2(sets_p)
    , localparam ptag_width_lp=(paddr_width_p-bp_page_offset_width_gp)

    , localparam lce_data_width_lp=(ways_p*data_width_p)
    , localparam block_size_in_bytes_lp=(lce_data_width_lp / 8)

    , localparam lce_id_width_lp=`BSG_SAFE_CLOG2(num_lce_p)
    , localparam cce_id_width_lp=`BSG_SAFE_CLOG2(num_cce_p)
      
    , localparam bp_be_dcache_pkt_width_lp=`bp_be_dcache_pkt_width(bp_page_offset_width_gp,data_width_p)

    , localparam lce_cce_req_width_lp=
      `bp_lce_cce_req_width(num_cce_p,num_lce_p,paddr_width_p,ways_p)
    , localparam lce_cce_resp_width_lp=
      `bp_lce_cce_resp_width(num_cce_p,num_lce_p,paddr_width_p)
    , localparam lce_cce_data_resp_width_lp=
      `bp_lce_cce_data_resp_width(num_cce_p,num_lce_p,paddr_width_p,lce_data_width_lp)
    , localparam cce_lce_cmd_width_lp=
      `bp_cce_lce_cmd_width(num_cce_p,num_lce_p,paddr_width_p,ways_p)
    , localparam cce_lce_data_cmd_width_lp=
      `bp_cce_lce_data_cmd_width(num_cce_p,num_lce_p,paddr_width_p,lce_data_width_lp,ways_p)
    , localparam lce_lce_tr_resp_width_lp=
      `bp_lce_lce_tr_resp_width(num_lce_p,paddr_width_p,lce_data_width_lp,ways_p)

    , localparam inst_ram_addr_width_lp = `BSG_SAFE_CLOG2(num_cce_inst_ram_els_p)
  )
  (
    input clk_i
    , input link_clk_i
    , input reset_i
  
    , input [num_lce_p-1:0][bp_be_dcache_pkt_width_lp-1:0] dcache_pkt_i
    , input [num_lce_p-1:0][ptag_width_lp-1:0] ptag_i
    , input [num_lce_p-1:0] dcache_pkt_v_i
    , output logic [num_lce_p-1:0] dcache_pkt_ready_o

    , output logic [num_lce_p-1:0] v_o
    , output logic [num_lce_p-1:0][data_width_p-1:0] data_o    
  );

  // casting structs
  //
  `declare_bp_be_dcache_pkt_s(bp_page_offset_width_gp,data_width_p);

  // rolly fifo
  //
  logic [num_lce_p-1:0] rollback_li;
  logic [num_lce_p-1:0][ptag_width_lp-1:0] rolly_ptag_lo;
  bp_be_dcache_pkt_s [num_lce_p-1:0] rolly_dcache_pkt_lo;
  logic [num_lce_p-1:0] rolly_v_lo;
  logic [num_lce_p-1:0] rolly_yumi_li;

  for (genvar i = 0; i < num_lce_p; i++) begin
    bsg_fifo_1r1w_rolly #(
      .width_p(bp_be_dcache_pkt_width_lp+ptag_width_lp)
      ,.els_p(8)
    ) rolly (
      .clk_i(clk_i)
      ,.reset_i(reset_i)

      ,.roll_v_i(rollback_li[i])
      ,.clr_v_i(1'b0)
    
      ,.ckpt_v_i(v_o[i])

      ,.data_i({ptag_i[i], dcache_pkt_i[i]})
      ,.v_i(dcache_pkt_v_i[i] & dcache_pkt_ready_o[i])
      ,.ready_o(dcache_pkt_ready_o[i])
  
      ,.data_o({rolly_ptag_lo[i], rolly_dcache_pkt_lo[i]})
      ,.v_o(rolly_v_lo[i])
      ,.yumi_i(rolly_yumi_li[i])
    );
  end

  // dcache
  //
  `declare_bp_lce_cce_req_s(num_cce_p, num_lce_p, paddr_width_p, ways_p);
  `declare_bp_lce_cce_resp_s(num_cce_p, num_lce_p, paddr_width_p);
  `declare_bp_lce_cce_data_resp_s(num_cce_p, num_lce_p, paddr_width_p, lce_data_width_lp);
  `declare_bp_cce_lce_cmd_s(num_cce_p, num_lce_p, paddr_width_p, ways_p);
  `declare_bp_cce_lce_data_cmd_s(num_cce_p, num_lce_p, paddr_width_p, lce_data_width_lp, ways_p);
  `declare_bp_lce_lce_tr_resp_s(num_lce_p, paddr_width_p, lce_data_width_lp, ways_p);

  bp_lce_cce_req_s [num_lce_p-1:0] dcache_lce_req;
  logic [num_lce_p-1:0] dcache_lce_req_v;
  logic [num_lce_p-1:0] dcache_lce_req_ready;

  bp_lce_cce_resp_s [num_lce_p-1:0] dcache_lce_resp;
  logic [num_lce_p-1:0] dcache_lce_resp_v;
  logic [num_lce_p-1:0] dcache_lce_resp_ready;

  bp_lce_cce_data_resp_s [num_lce_p-1:0] dcache_lce_data_resp;
  logic [num_lce_p-1:0] dcache_lce_data_resp_v;
  logic [num_lce_p-1:0] dcache_lce_data_resp_ready;

  bp_cce_lce_cmd_s [num_lce_p-1:0] dcache_lce_cmd;
  logic [num_lce_p-1:0] dcache_lce_cmd_v;
  logic [num_lce_p-1:0] dcache_lce_cmd_ready;

  bp_cce_lce_data_cmd_s [num_lce_p-1:0] dcache_lce_data_cmd;
  logic [num_lce_p-1:0] dcache_lce_data_cmd_v;
  logic [num_lce_p-1:0] dcache_lce_data_cmd_ready;

  bp_lce_lce_tr_resp_s [num_lce_p-1:0] dcache_lce_tr_resp_li;
  logic [num_lce_p-1:0] dcache_lce_tr_resp_v_li;
  logic [num_lce_p-1:0] dcache_lce_tr_resp_ready_lo;

  bp_lce_lce_tr_resp_s [num_lce_p-1:0] dcache_lce_tr_resp_lo;
  logic [num_lce_p-1:0] dcache_lce_tr_resp_v_lo;
  logic [num_lce_p-1:0] dcache_lce_tr_resp_ready_li;
  
  logic [num_lce_p-1:0] dcache_tlb_miss_li;
  logic [num_lce_p-1:0][ptag_width_lp-1:0] dcache_ptag_li;
  logic [num_lce_p-1:0] cache_miss_lo;
  logic [num_lce_p-1:0] dcache_ready_lo;

  for (genvar i = 0; i < num_lce_p; i++) begin
    bp_be_dcache #(
      .data_width_p(data_width_p)
      ,.paddr_width_p(paddr_width_p)
      ,.sets_p(sets_p)
      ,.ways_p(ways_p)
      ,.num_cce_p(num_cce_p)
      ,.num_lce_p(num_lce_p)
      ,.debug_p(1)
    ) dcache (
      .clk_i(clk_i)
      ,.reset_i(reset_i)
      ,.lce_id_i((lce_id_width_lp)'(i))
 
      ,.dcache_pkt_i(rolly_dcache_pkt_lo[i])
      ,.v_i(rolly_v_lo[i])
      ,.ready_o(dcache_ready_lo[i])

      ,.v_o(v_o[i])
      ,.data_o(data_o[i])

      ,.tlb_miss_i(dcache_tlb_miss_li[i])
      ,.ptag_i(dcache_ptag_li[i])

      // ctrl
      ,.cache_miss_o(cache_miss_lo[i])
      ,.poison_i(cache_miss_lo[i])

      // LCE-CCE interface
      ,.lce_req_o(dcache_lce_req[i])
      ,.lce_req_v_o(dcache_lce_req_v[i])
      ,.lce_req_ready_i(dcache_lce_req_ready[i])

      ,.lce_resp_o(dcache_lce_resp[i])
      ,.lce_resp_v_o(dcache_lce_resp_v[i])
      ,.lce_resp_ready_i(dcache_lce_resp_ready[i])

      ,.lce_data_resp_o(dcache_lce_data_resp[i])
      ,.lce_data_resp_v_o(dcache_lce_data_resp_v[i])
      ,.lce_data_resp_ready_i(dcache_lce_data_resp_ready[i])

      // CCE-LCE interface
      ,.lce_cmd_i(dcache_lce_cmd[i])
      ,.lce_cmd_v_i(dcache_lce_cmd_v[i])
      ,.lce_cmd_ready_o(dcache_lce_cmd_ready[i])

      ,.lce_data_cmd_i(dcache_lce_data_cmd[i])
      ,.lce_data_cmd_v_i(dcache_lce_data_cmd_v[i])
      ,.lce_data_cmd_ready_o(dcache_lce_data_cmd_ready[i])

      // LCE-LCE interface
      ,.lce_tr_resp_i(dcache_lce_tr_resp_li[i])
      ,.lce_tr_resp_v_i(dcache_lce_tr_resp_v_li[i])
      ,.lce_tr_resp_ready_o(dcache_lce_tr_resp_ready_lo[i])

      ,.lce_tr_resp_o(dcache_lce_tr_resp_lo[i])
      ,.lce_tr_resp_v_o(dcache_lce_tr_resp_v_lo[i])
      ,.lce_tr_resp_ready_i(dcache_lce_tr_resp_ready_li[i])
    );
  end

  for (genvar i = 0; i < num_lce_p; i++) begin
    assign rollback_li[i] = cache_miss_lo[i];
    assign rolly_yumi_li[i] = rolly_v_lo[i] & dcache_ready_lo[i];
  end

  // mock tlb
  //
  for (genvar i = 0; i < num_lce_p; i++) begin
    mock_tlb #(
      .tag_width_p(ptag_width_lp)
    ) tlb (
      .clk_i(clk_i)

      ,.v_i(rolly_yumi_li[i])
      ,.tag_i(rolly_ptag_lo[i])

      ,.tag_o(dcache_ptag_li[i])
      ,.tlb_miss_o(dcache_tlb_miss_li[i])
    );
  end

  logic [inst_ram_addr_width_lp-1:0] cce_inst_boot_rom_addr;
  logic [`bp_cce_inst_width-1:0] cce_inst_boot_rom_data;

  // CCE Boot ROM
  bp_cce_inst_rom
    #(.width_p(`bp_cce_inst_width)
      ,.addr_width_p(inst_ram_addr_width_lp)
      )
    cce_inst_rom
     (.addr_i(cce_inst_boot_rom_addr)
      ,.data_o(cce_inst_boot_rom_data)
      );

  bp_lce_cce_req_s cce_lce_req;
  logic cce_lce_req_v;
  logic cce_lce_req_ready;

  bp_lce_cce_resp_s cce_lce_resp;
  logic cce_lce_resp_v;
  logic cce_lce_resp_ready;

  bp_lce_cce_data_resp_s cce_lce_data_resp;
  logic cce_lce_data_resp_v;
  logic cce_lce_data_resp_ready;

  bp_cce_lce_cmd_s cce_lce_cmd;
  logic cce_lce_cmd_v;
  logic cce_lce_cmd_ready;

  bp_cce_lce_data_cmd_s cce_lce_data_cmd;
  logic cce_lce_data_cmd_v;
  logic cce_lce_data_cmd_ready;

  // coherence network
  //
  bp_coherence_network #(
    .num_lce_p(num_lce_p)
    ,.num_cce_p(num_cce_p)
    ,.paddr_width_p(paddr_width_p)
    ,.lce_assoc_p(ways_p)
    ,.block_size_in_bytes_p(block_size_in_bytes_lp)
  ) coh_network (
    .clk_i(clk_i)
    ,.reset_i(reset_i)

    ,.lce_cmd_o(dcache_lce_cmd)
    ,.lce_cmd_v_o(dcache_lce_cmd_v)
    ,.lce_cmd_ready_i(dcache_lce_cmd_ready)

    ,.lce_cmd_i(cce_lce_cmd)
    ,.lce_cmd_v_i(cce_lce_cmd_v)
    ,.lce_cmd_ready_o(cce_lce_cmd_ready)

    ,.lce_data_cmd_o(dcache_lce_data_cmd)
    ,.lce_data_cmd_v_o(dcache_lce_data_cmd_v)
    ,.lce_data_cmd_ready_i(dcache_lce_data_cmd_ready)

    ,.lce_data_cmd_i(cce_lce_data_cmd)
    ,.lce_data_cmd_v_i(cce_lce_data_cmd_v)
    ,.lce_data_cmd_ready_o(cce_lce_data_cmd_ready)

    ,.lce_req_i(dcache_lce_req)
    ,.lce_req_v_i(dcache_lce_req_v)
    ,.lce_req_ready_o(dcache_lce_req_ready)

    ,.lce_req_o(cce_lce_req)
    ,.lce_req_v_o(cce_lce_req_v)
    ,.lce_req_ready_i(cce_lce_req_ready)

    ,.lce_resp_i(dcache_lce_resp)
    ,.lce_resp_v_i(dcache_lce_resp_v)
    ,.lce_resp_ready_o(dcache_lce_resp_ready)

    ,.lce_resp_o(cce_lce_resp)
    ,.lce_resp_v_o(cce_lce_resp_v)
    ,.lce_resp_ready_i(cce_lce_resp_ready)

    ,.lce_data_resp_i(dcache_lce_data_resp)
    ,.lce_data_resp_v_i(dcache_lce_data_resp_v)
    ,.lce_data_resp_ready_o(dcache_lce_data_resp_ready)

    ,.lce_data_resp_o(cce_lce_data_resp)
    ,.lce_data_resp_v_o(cce_lce_data_resp_v)
    ,.lce_data_resp_ready_i(cce_lce_data_resp_ready)

    ,.lce_tr_resp_i(dcache_lce_tr_resp_lo)
    ,.lce_tr_resp_v_i(dcache_lce_tr_resp_v_lo)
    ,.lce_tr_resp_ready_o(dcache_lce_tr_resp_ready_li)

    ,.lce_tr_resp_o(dcache_lce_tr_resp_li)
    ,.lce_tr_resp_v_o(dcache_lce_tr_resp_v_li)
    ,.lce_tr_resp_ready_i(dcache_lce_tr_resp_ready_lo)
  );

  // Memory End
  //
  `declare_bp_me_if(paddr_width_p,lce_data_width_lp,num_lce_p,ways_p);

  bp_mem_cce_resp_s mem_resp;
  logic mem_resp_v;
  logic mem_resp_ready;

  bp_mem_cce_data_resp_s mem_data_resp;
  logic mem_data_resp_v;
  logic mem_data_resp_ready;

  bp_cce_mem_cmd_s mem_cmd;
  logic mem_cmd_v;
  logic mem_cmd_ready;

  bp_cce_mem_data_cmd_s mem_data_cmd;
  logic mem_data_cmd_v;
  logic mem_data_cmd_ready;

  bp_cce_top #(
    .num_lce_p(num_lce_p)
    ,.num_cce_p(num_cce_p)
    ,.paddr_width_p(paddr_width_p)
    ,.lce_assoc_p(ways_p)
    ,.lce_sets_p(sets_p)
    ,.block_size_in_bytes_p(block_size_in_bytes_lp)
    ,.num_cce_inst_ram_els_p(num_cce_inst_ram_els_p)
  ) me (
    .clk_i(clk_i)
    ,.reset_i(reset_i)

    ,.lce_cmd_o(cce_lce_cmd)
    ,.lce_cmd_v_o(cce_lce_cmd_v)
    ,.lce_cmd_ready_i(cce_lce_cmd_ready)

    ,.lce_data_cmd_o(cce_lce_data_cmd)
    ,.lce_data_cmd_v_o(cce_lce_data_cmd_v)
    ,.lce_data_cmd_ready_i(cce_lce_data_cmd_ready)

    ,.lce_req_i(cce_lce_req)
    ,.lce_req_v_i(cce_lce_req_v)
    ,.lce_req_ready_o(cce_lce_req_ready)

    ,.lce_resp_i(cce_lce_resp)
    ,.lce_resp_v_i(cce_lce_resp_v)
    ,.lce_resp_ready_o(cce_lce_resp_ready)

    ,.lce_data_resp_i(cce_lce_data_resp)
    ,.lce_data_resp_v_i(cce_lce_data_resp_v)
    ,.lce_data_resp_ready_o(cce_lce_data_resp_ready)

    ,.boot_rom_addr_o(cce_inst_boot_rom_addr)
    ,.boot_rom_data_i(cce_inst_boot_rom_data)

    ,.cce_id_i(cce_id_width_lp'(0))

    ,.mem_resp_i(mem_resp)
    ,.mem_resp_v_i(mem_resp_v)
    ,.mem_resp_ready_o(mem_resp_ready)

    ,.mem_data_resp_i(mem_data_resp)
    ,.mem_data_resp_v_i(mem_data_resp_v)
    ,.mem_data_resp_ready_o(mem_data_resp_ready)

    ,.mem_cmd_o(mem_cmd)
    ,.mem_cmd_v_o(mem_cmd_v)
    ,.mem_cmd_yumi_i(mem_cmd_v & mem_cmd_ready)

    ,.mem_data_cmd_o(mem_data_cmd)
    ,.mem_data_cmd_v_o(mem_data_cmd_v)
    ,.mem_data_cmd_yumi_i(mem_data_cmd_v & mem_data_cmd_ready)
  );

  localparam link_data_width_p = 32;
  localparam link_addr_width_p = 15;
  localparam x_width_p = 4;
  localparam x_cord_width_p = 2;
  localparam y_cord_width_p = 1;
  localparam load_id_width_p = 11;

  `declare_bsg_manycore_link_sif_s(link_addr_width_p,link_data_width_p,
    x_cord_width_p,y_cord_width_p,load_id_width_p);
  localparam link_sif_width_lp=`bsg_manycore_link_sif_width(link_addr_width_p,link_data_width_p,
    x_cord_width_p,y_cord_width_p,load_id_width_p);

  logic [x_width_p-1:0][S:W][link_sif_width_lp-1:0] router_link_sif_li, router_link_sif_lo;
  logic [x_width_p-1:0][link_sif_width_lp-1:0] proc_link_sif_li, proc_link_sif_lo;

  for (genvar i = 0; i < x_width_p; i++) begin
    bsg_manycore_mesh_node #(
      .x_cord_width_p(x_cord_width_p)
      ,.y_cord_width_p(y_cord_width_p)
      ,.data_width_p(link_data_width_p)
      ,.addr_width_p(link_addr_width_p)
      ,.load_id_width_p(load_id_width_p)
    ) mesh_node (
      .clk_i(link_clk_i)
      ,.reset_i(reset_i)

      ,.links_sif_i(router_link_sif_li[i])
      ,.links_sif_o(router_link_sif_lo[i])
      
      ,.proc_link_sif_i(proc_link_sif_li[i])
      ,.proc_link_sif_o(proc_link_sif_lo[i])

      ,.my_x_i(x_cord_width_p'(i))
      ,.my_y_i(y_cord_width_p'(0))
    );

    if (i != 0) begin
      assign router_link_sif_li[i][W] = router_link_sif_lo[i-1][E];

      bsg_manycore_link_sif_tieoff #(
        .addr_width_p(link_addr_width_p)
        ,.data_width_p(link_data_width_p)
        ,.load_id_width_p(load_id_width_p)
        ,.x_cord_width_p(x_cord_width_p)
        ,.y_cord_width_p(y_cord_width_p)
      ) node_p_tieoff (
        .clk_i(link_clk_i)
        ,.reset_i(reset_i)
        ,.link_sif_i(proc_link_sif_lo[i])
        ,.link_sif_o(proc_link_sif_li[i])
      );
    end
    if (i != x_width_p-1) begin
      assign router_link_sif_li[i][E] = router_link_sif_lo[i+1][W];
    end

    if (i == 0) begin
      bsg_manycore_link_sif_tieoff #(
        .addr_width_p(link_addr_width_p)
        ,.data_width_p(link_data_width_p)
        ,.load_id_width_p(load_id_width_p)
        ,.x_cord_width_p(x_cord_width_p)
        ,.y_cord_width_p(y_cord_width_p)
      ) node_w_tieoff (
        .clk_i(link_clk_i)
        ,.reset_i(reset_i)
        ,.link_sif_i(router_link_sif_lo[i][W])
        ,.link_sif_o(router_link_sif_li[i][W])
      );
    end

    bsg_manycore_link_sif_tieoff #(
      .addr_width_p(link_addr_width_p)
      ,.data_width_p(link_data_width_p)
      ,.load_id_width_p(load_id_width_p)
      ,.x_cord_width_p(x_cord_width_p)
      ,.y_cord_width_p(y_cord_width_p)
    ) node_n_tieoff (
      .clk_i(link_clk_i)
      ,.reset_i(reset_i)
    
      ,.link_sif_i(router_link_sif_lo[i][N])
      ,.link_sif_o(router_link_sif_li[i][N])
    );

    if (i == x_width_p-1) begin
      bsg_manycore_link_sif_tieoff #(
        .addr_width_p(link_addr_width_p)
        ,.data_width_p(link_data_width_p)
        ,.load_id_width_p(load_id_width_p)
        ,.x_cord_width_p(x_cord_width_p)
        ,.y_cord_width_p(y_cord_width_p)
      ) node_e_tieoff (
        .clk_i(link_clk_i)
        ,.reset_i(reset_i)
    
        ,.link_sif_i(router_link_sif_lo[i][E])
        ,.link_sif_o(router_link_sif_li[i][E])
      );
    end
  end

  bsg_manycore_link_to_cce #(
    .link_data_width_p(link_data_width_p)
    ,.link_addr_width_p(link_addr_width_p)
    ,.x_cord_width_p(x_cord_width_p)
    ,.y_cord_width_p(y_cord_width_p)
    ,.load_id_width_p(load_id_width_p)    
    
    ,.bp_addr_width_p(paddr_width_p)
    ,.num_lce_p(num_lce_p)
    ,.lce_assoc_p(ways_p)
    ,.block_size_in_bits_p(lce_data_width_lp)
  ) link_to_cce (
    .link_clk_i(link_clk_i)
    ,.bp_clk_i(clk_i)
    ,.async_reset_i(reset_i)

    ,.my_x_i((x_cord_width_p)'(0))
    ,.my_y_i((y_cord_width_p)'(0))

    ,.link_sif_i(proc_link_sif_lo[0])
    ,.link_sif_o(proc_link_sif_li[0])

    ,.mem_cmd_i(mem_cmd)
    ,.mem_cmd_v_i(mem_cmd_v)
    ,.mem_cmd_ready_o(mem_cmd_ready)

    ,.mem_data_cmd_i(mem_data_cmd)
    ,.mem_data_cmd_v_i(mem_data_cmd_v)
    ,.mem_data_cmd_ready_o(mem_data_cmd_ready)

    ,.mem_resp_o(mem_resp)
    ,.mem_resp_v_o(mem_resp_v)
    ,.mem_resp_ready_i(mem_resp_ready)

    ,.mem_data_resp_o(mem_data_resp)
    ,.mem_data_resp_v_o(mem_data_resp_v)
    ,.mem_data_resp_ready_i(mem_data_resp_ready)
    
    ,.reset_o()
    ,.freeze_o()
  );

  for (genvar i = 0; i < x_width_p; i++) begin
    bsg_manycore_ram_model #(
      .x_cord_width_p(x_cord_width_p)
      ,.y_cord_width_p(y_cord_width_p)
      ,.data_width_p(link_data_width_p)
      ,.addr_width_p(link_addr_width_p)
      ,.load_id_width_p(load_id_width_p)
      ,.self_reset_p(1)

      ,.els_p(2**(link_addr_width_p-1))
    ) ram_model (
      .clk_i(link_clk_i)
      ,.reset_i(reset_i)

      ,.link_sif_i(router_link_sif_lo[i][S])
      ,.link_sif_o(router_link_sif_li[i][S])
  
      ,.my_x_i(x_cord_width_p'(i))
      ,.my_y_i(y_cord_width_p'(1))
    );
  end

endmodule
