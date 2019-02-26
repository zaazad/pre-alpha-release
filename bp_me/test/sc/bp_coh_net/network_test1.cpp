//Assuming for this test 1 src to 1 dest
//packet_width_p = 4
//parameter num_src_p = 1
//parameter num_dst_p = 1


#include <verilated.h>    //Defines common routuines
#include <iostream>       //Used to get cout
#include "Vbp_coherence_network_channel.h" //From verilating bp_coherence_network.v
#include <verilated_vcd_c.h>       //Used to create vcd traces for gtkwave for debugging
#include <time.h>     //Used to help set the seed for "rand" values
//declare functions used
int num_bits(int i);
int bitmask(int i);



//Parameters are set on the command line -G<name>=<value> ex/ -Gpacket_width_p=3
//Be aware that the dest id is in the packet so it's like (data value)(dest id)
//Useful to have variables with the same values too

//IMPORTANT!!!!!!!!!
//Packets for these tests will be only packet = {[src_id][dest_id]} to make things simpler to track
//To do this the packet width will just be the #of bits for the src and #of bits for the dest
//so by default packet_width_p should be 0 on the command line
int num_src = 1;
int num_dst = 1;



//Used for creating "random" packet values
srand(time(NULL));

//An 64 bit val but could be double if worried about time wrap over
vluint64_t main_time = 0; //Current simulation time



int main(int argc, char** argv) 
{
    
    //Verilated::commandArgs(argc, argv); //Remember args: used if passing arguements to a verilated exe
    Vbp_coherence_network_channel* bp_ntwk_c = new Vbp_coherence_network_channel; //Create instance to get and set memebers to .v file



    /*************************************************************************************************
    * TRACE SETUP
    *************************************************************************************************/
    //Since we invoke verilator with the --trace arguement for debug purposes
    //and if at run time passed the +trace argument, turn on tracing
    VerilatedVcdC* tfp = NULL;     //Used to create trace file pointer
    Verilated::traceEverOn(true);  //No real description, just says we need to call this for traces
    VL_PRINTF("Enabling waves vlt_dump.vcd...\n"); 
    tfp = new VerilatedVcdC;       //New trace instance
    bp_ntwk_c->trace(tfp, 99);     //Trace has 99 levels of hierarchy from this file
    tfp->open("vlt_dump.vcd");     //Open the dump file 

    

    //Local Variables
    int dst_ready;                 //Used to create the dst_ready_i string of bits
    int src_v;                     //Used to create the src_v_i string of bits
    int src_data;                  //Used to create the src_data_i string of bits
    int i,j,k,l;                   //Iterator variables
    int ledger[num_src][num_dst];  //A ledger keeping track of who sent data where and how many
    int num_src_bitwidth  = bit_num(num_src);  //The width of the number of bits to represent the num srcs
    int num_dst_bitwidth  = bit_num(num_dest); //The width of the number of bits to represent the num dsts
    int data_packet_bitwidth = num_src_bitwidth+num_dst_bitwidth; //The width of the packet
    int num_src_bitmask   = bitmask(num_src_bitwidth); //Bitmask that is num_src_bitwidth wide
    int num_dst_bitmask   = bitmask(num_dst_bitwidth); //Bitmask that is num_dst_bitwidth wide
    int data_packet_bitmask = bitmask(data_packet_bitwidth); //Bitmask that is packet wide
    int src;      //Just a temp variable
    int dst;      //Just a temp variable
    int dst_data; //Just a temp variable


    //This shouldn't really be a problem since you can have 2^5 sources and 2^5 dests * 5 per 
    //source or dest and still only be at 30 bits, but just in case someone pushes the limits
    if(((num_src*data_packet_bitwidth) > 32) || ((num_dst*data_packet_bitwidth) > 32))
    {
        std::cout << "ERROR: too many src's or dest's, would cause overflow for 32 bit int data packets" << std::endl;
        return -1;
    }


    //Initialize all the ledger values to 0
    for(k=0; k<num_src; k++)
    {
        for(l=0; l<num_dst; l++)
        {
            ledger[k][l]=0;
        }
    }


    //Main execution loop, main_time is in delta ticks but defaults as ns in gtkwave
    while (main_time < 1000) 
    {

        /************************************************************************************************
        * RESET 
        * - 10 delta cycle high reset before deasserting
        ************************************************************************************************/
        bp_ntwk_c->reset_i = (main_time <= 10) ? 1 : 0;

        /************************************************************************************************
        * CLOCK
        * - Main clock driving network with a period of 4 delta ticks
        ************************************************************************************************/
        if(main_time%4 == 0)
        {
            bp_ntwk_c->clk_i = 1;
        }
        else if(main_time%4 == 2)
        {
            bp_ntwk_c->clk_i = 0;   
        }



        /************************************************************************************************
        * Recieving data packets
        ************************************************************************************************/
        dst_ready = 0; //0 by default and by using bit operators create the actual value, since just local variable can reset to 0 every cycle
    
        //Basically like reading on the falling edge so don't have to worry about racing data or double reading data
        if(main_time%4 == 2)
        {
            //Loop through all the dst nodes
            for(i = 0; i<num_dst; i++)
            {
                //Since dst_v_o is a string of bits can use bitwise operations to read and create new values too
                //This if checks if there is valid data at the current dst node
                if(((1<<i) & bp_ntwk_c->dst_v_o) != 0)
                {
                    //randomly accept the dst packet, if accepted read and remove data
                    if(rand()%2 == 0)
                    {
                        dst_ready |= (1<<i); //Since we are going to be reading the data send a ready back so channel knows we read

                        //The data at this destination node is in this section of the concatinated data packet string
                        dst_data = ((bp_ntwk_c->dst_data_o >> (i * data_packet_bitwidth)) & data_packet_bitmask);

                        //If we bit mask it with the dst bit mask (since the dst is always at the bottom bits) and it isn't = to i we recieved another node's packet
                        if((dst_data & num_dst_bitmask) != i)
                        {
                            std::cout << "ERROR: Packet at the wrong destination, expecting " << i << " got " << (dst_data & num_dst_bitmask) << std::endl;
                            return -1;
                        }
                        //If data packet is at the right destination
                        else
                        {
                            //The source is the upper bits of the dst_data so just shift out the dst_id bits
                            src = dst_data >> num_dst_bitwidth;

                            //Check to see if data was ever sent from this source to this destination, if it wasn't in the ledger then there is an error
                            if(ledger[src][i] <= 0)
                            {
                                std::cout << "ERROR: Packet recieved at dest " << i << " was never sent by source " << src << std::endl;
                                return -1;
                            }
                            //If it exists in the ledger, decrement the ledger count
                            else
                            {
                                ledger[src][i]--;
                                //For debugging
                                std::cout << "SUCCESSFUL TRANSFER" << std::endl;
                            }
                              
                        }
            
                    }
                }   
            }

            //After the for loop send the value of ready to the actual module so it can remove the data from its fifos
            bp_ntwk_c->dst_ready_i = dst_ready;
        }                                                    




        /*************************************************************************************************
        * Sending data packets
        *************************************************************************************************/
        src_v    = 0; //0 by default and by using bit operators create the actual value, since just local variable can reset to 0 every cycle
        src_data = 0; //Also 0 by default for same reason

        //Although same if as above it is neater to seperate the two
        if(main_time%4 == 2)
        {
            //Loop through all the src nodes
            for(j = 0; j<num_src; j++)
            {
                //If ready to send new data
                if(((1<<j) & bp_ntwk_c->src_ready_o) != 0)
                {
                    //randomly decide wheter or not to send data
                    if(rand()%2 == 0)
                    {
                        //Since we're sending data need to update our valid in bit
                        src_v |= (1<<j);

                        //Shouldn't need to be bit masked since 0 indexed and mod'd
                        dst = rand()%num_dest;
                       
                        //Add to ledger that this source sent a packet to a dest
                        ledger[j][dst]++;

                        //New data aka {[src_id][dst_id]}
                        src_data |= ((j << num_dst_bitwidth) | dst) << (j * data_packet_bitwidth);
                    }
                }
            }

            //After the for loop send the values of the data and the valid in to the actual module
            bp_ntwk_c->src_data_i = src_data;
            bp_ntwk_c->src_v_i    = src_v;
        }



        /********************************************************************************************* 
        * UPDATE SIM
        * - defacto end of changes in current state to register and propagate changes through the system 
        *********************************************************************************************/ 
        bp_ntwk_c->eval();      //Evaluate current simulation delta cycle
        tfp->dump(main_time); //Dump trace data for this cycle
        main_time++;          //Increment so time passes...
    
    }

    /********************************************************************************************
    * WRAP UP SIM
    * - Finish up your simulation and ensure that the trace file was written too
    ********************************************************************************************/ 
    test_module->final(); // Done simulating
    tfp->close();
    tfp = NULL;
    delete bp_ntwk_c;
    return 0;
}

//This function returns how many bits it takes for a number like num_src = 7 returns 3 bits
int num_bits(int i)
{ 
    int num=0;
    while(i != 0)
    {
        num++;
        i = i>>1;
    }
    return num;
}

//This function returns a bitmasked value for the number of bits so 3 bits returns 111
int bitmask(int i)
{
    mask = 0;
    for(int x=0; x<i; x++)
    {
        //Shift first since 0 comes through here and mask initialized to 0 so passes by
        mask = mask<<1;
        mask |= 1;
    }
    return mask;
}
