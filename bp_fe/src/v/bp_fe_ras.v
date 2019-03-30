module bp_fe_ras
  import bp_fe_pkg::*;

       #(parameter   bp_fe_pc_gen_ras_idx_width_lp=5
               , parameter eaddr_width_p="inv"
               , localparam els_lp=2**bp_fe_pc_gen_ras_idx_width_lp
              )
        (input                                       clk_i
               , input                                     reset_i

               , input                                     push_i
               , input                                     pop_i
               , input [63:0]                              data_i

               , output [63:0]                             data_o
               , output                                    ras_out_v
         );


   reg [bp_fe_pc_gen_ras_idx_width_lp:0] sp;

       // pointers tracking the stack
   reg [els_lp-1:0][63:0]                memory;

   reg [els_lp-1:0]                      valid;

   reg                                   full;

   reg                                   empty;


//   assign full  = (sp == 6'b100000) ? 1 : 0;
     assign full  = (sp == 5'b10000) ? 1 : 0;

  // assign empty = (sp == 6'b000000) ? 1 : 0;
     assign empty = (sp == 5'b00000) ? 1 : 0;
   
        always @(posedge clk_i)
          begin
                           if (reset_i)
                             begin
                                memory <= '{default:64'd0};

                                valid  <= '0;

                                                   //DATAOUT <= 0;
                                sp <= 1;


                             end // if (reset_i)
                           else if (push_i & !full)
                             begin
                                memory[sp] <= data_i;

                                valid[sp] <= '1;

                                sp <= sp + 1;


                             end
                           else if (pop_i & !empty)
                             begin
                                sp <= sp - 1;


                                                //   DATAOUT <= memory[sp];

                             end
          end // always @ (posedge clk_i)

   assign  data_o = memory[sp-1];

   assign  ras_out_v = valid[sp-1];

   endmodule