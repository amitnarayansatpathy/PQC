// `include "padder.v"
// `include "SIPO.v"
// `include "f_permutation.v"
`define DATA_SIZE 64

module keccak(
    input clk,
    input rst,
    input [63:0] in, // Represents the seed
    input [1:0] mode,
    input is_last, // Indicated the last input seed
    input start_calc, // signifies vaild instruction
    input gimme, // handshaking from parse and CBD
    output ack,
    input in_valid,//total goes to padding
    output [63:0] out,
    output out_valid
    );

    wire[63:0] pad_out;
    wire pad_out_ready;
    wire shift_en;
    reg [1:0]mode_reg;
    wire f_in_ready;
    wire f_out_ready;
    wire[1343:0]f_in;
    wire cntr_zero;
    wire f_ack;
    wire absorb;
    wire squeeze;
    wire [1599:0] f_out;
    wire p_out_ready;
    wire [63:0] p_out;
    wire buf_ful;
    wire takein_reg;
    wire is_loaded;
    reg out_read;
    reg takein;
    wire load_en;

    // assign f_in_ready = is_loaded & takein_reg;
    assign f_in_ready =is_loaded;
    assign load_en = pad_out_ready & ~f_ack;
    wire hash_init;
    reg[4:0] cntr_out;
    wire out_count_zero;//outside FIFO counter
    wire pack;
    wire calc;
    reg last_in;
    reg absorb_done;
    wire out_buf_empty;

    padder pad(
        .in_valid(in_valid),
        .takein(takein),
        .clk(clk),
        .rst(rst),
        .in(in),
        .out(pad_out),
        .out_ready(pad_out_ready),
        .is_last(is_last),
        .mode(mode),
        .ack(ack),
        .start_calc(start_calc),
        .cntr_zero(cntr_zero),
        .takein_reg(takein_reg)
        );
    
    SIPO sipo (
        .data_in(pad_out),
        .hash_init(hash_init),
        .load_en(load_en),
        .clk(clk),
        .cntr_zero(cntr_zero),
        .is_loaded(is_loaded),
        .data_out(f_in),
        .calc(calc)
    );

    f_permutation f(
        .mode(mode_reg),
        .clk(clk),
        .reset(rst),
        .in(f_in),
        .in_ready(f_in_ready),
        .ack(f_ack),
        .out(f_out),
        .out_ready(f_out_ready),
        .squeeze(squeeze),
        .pack(pack),
        .calc_out(calc),
        .last_in(last_in),
        .first_last(is_loaded & ~takein_reg)
    );

    PISO piso(
        .data_in(f_out[1599-:1344]),
        .count_zero(out_count_zero),
        .rst(rst),
        .load_en(f_out_ready),
        .shift_en(shift_en),
        .clk(clk),
        .out_ready(p_out_ready),
        .data_out(p_out),
        .pack(pack)
    );
    
    Sync_FIFO fifo ( 
        .clk(clk), 
        .rst(rst), 
        .buf_in(p_out), 
        .buf_out(out), 
        .wr_en(p_out_ready), 
        .rd_en(gimme), 
        .buf_empty(out_buf_empty), 
        .buf_full(buf_ful)
        ,.out_valid(out_valid)
        ); 

    assign hash_init = rst | start_calc;
    assign squeeze = gimme & out_buf_empty  & ~shift_en & absorb_done &mode_reg[1];
    // assign absorb = 1;

   
    always @(posedge clk, posedge rst) begin
        if(rst) mode_reg<=0;
        else if(start_calc) mode_reg<=mode;
    end

    always @ (posedge clk, posedge rst) begin
        if (rst) takein <= 0;
        else if (start_calc) takein <= 1;
        else if (is_last) takein <= 0;
    end
    always @ (posedge clk, posedge rst) begin
        if (rst) out_read <= 0;
        else
            out_read <= p_out_ready;
    end

    always @ (posedge clk, posedge rst) begin
        if (rst) cntr_out <= 0;
        else if(p_out_ready) begin
            if(cntr_out == 0) cntr_out <= 0;
            else cntr_out <= cntr_out - 1;
        end
        else if (f_out_ready) begin
            case(mode_reg)
                0: cntr_out <=4;
                1: cntr_out <= 8;
                2: cntr_out <= 21;
                3: cntr_out <= 17;
            endcase
        end  
    end
    always @ (posedge clk, posedge rst) begin
        if(rst|start_calc) absorb_done<=0;
        else if(f_out_ready) absorb_done<=1;
    end

    always @(posedge clk,posedge rst) begin
        if(rst|start_calc) last_in<=0;
        else if(is_loaded & ~takein) last_in<=1;
    end

    assign out_count_zero = (cntr_out==1 | cntr_out==0);

    // assign out_ready = out_read & ~out_buf_empty;
    assign shift_en = ~buf_ful & ~out_count_zero;

endmodule