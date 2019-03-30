/*
 *bp_fe_instr_scan.v
 * 
 *Instr scan check if the intruction is aligned, compressed, or normal instruction.
 *The entire block is implemented in combinational logic, achieved within one cycle.
*/

module instr_scan
 import bp_common_pkg::*;
 import bp_fe_pkg::*; 
 #(parameter eaddr_width_p="inv"
   , parameter instr_width_p="inv"
   , localparam bp_fe_instr_scan_width_lp=`bp_fe_instr_scan_width 
  ) 
  (input [instr_width_p-1:0]                      instr_i
   , output logic [bp_fe_instr_scan_width_lp-1:0] scan_o
  );

logic call_instr, ret_instr;
   
//assign the struct to the port signals
bp_fe_instr_scan_s scan;
assign scan_o = scan;
   
//is_compressed signal indicates if the instruction from icache is compressed
assign scan.is_compressed = (instr_i[1:0] != 2'b11);
assign call_instr = ((instr_i[6:0]   == `opcode_rvi_jalr ) | (instr_i[6:0]   == `opcode_rvi_jal)) & instr_i[7] & ~instr_i[8] & ~instr_i[9] & ~instr_i[10] & ~instr_i[11];
assign ret_instr  =  (instr_i[6:0]   == `opcode_rvi_jalr ) & ~instr_i[7] & ~instr_i[19] & ~instr_i[18] & ~instr_i[16] & instr_i[15];

   
assign scan.instr_scan_class = bp_fe_instr_scan_class_e'(
  (call_instr)                           ? `bp_fe_instr_scan_class_width'(e_rvi_call  ) :
  (ret_instr)                            ? `bp_fe_instr_scan_class_width'(e_rvi_ret   ) :
  (instr_i[6:0]   == `opcode_rvi_branch) ? `bp_fe_instr_scan_class_width'(e_rvi_branch) :
  (instr_i[6:0]   == `opcode_rvi_jalr  ) ? `bp_fe_instr_scan_class_width'(e_rvi_jalr  ) :
  (instr_i[6:0]   == `opcode_rvi_jal   ) ? `bp_fe_instr_scan_class_width'(e_rvi_jal   ) :
                                           `bp_fe_instr_scan_class_width'(e_default   ) );
   

assign scan.imm =
  (instr_i[6:0]   == `opcode_rvi_branch) ? {{51{instr_i[31]}}, instr_i[31], instr_i[7], instr_i[30:25], instr_i[11:8], 1'b0} :
  (instr_i[6:0]   == `opcode_rvi_jalr  ) ? {{52{instr_i[31]}}, instr_i[31:20]} :
  (instr_i[6:0]   == `opcode_rvi_jal   ) ? {{44{instr_i[31]}}, instr_i[19:12], instr_i[20], instr_i[30:21], 1'b0} :
					   {64{1'b0}};
   
endmodule


