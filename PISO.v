`timescale 1ns / 1ps

module PISO(
    input [1343:0] data_in,
    input rst,
    input load_en,
    input shift_en,
    input clk,
    input count_zero,
    output out_ready,
    output [`DATA_SIZE-1:0] data_out,
    output pack
    );
    
    reg [1343:0] data;
    reg out_ready;

    assign pack = load_en; 
    
    always @ (posedge clk, posedge rst) begin
        if (rst) begin
            data <= 0;
        end
        else begin
            if(load_en)
                data <= data_in;
            else if(shift_en)
                data <= data<<`DATA_SIZE;
        end
    end
    always @ (posedge clk, posedge rst) begin
        if(rst) out_ready <= 0;
        else if(load_en) out_ready <= 1;
        else if(~shift_en) out_ready <= 0;
    end
    assign data_out = data[1343-:`DATA_SIZE];
    
endmodule
