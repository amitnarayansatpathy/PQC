`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 29.08.2024 10:25:59
// Design Name: 
// Module Name: SIPO_reg
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////

`define DATA_SIZE 64

module SIPO (
    input [`DATA_SIZE-1:0] data_in,
    input hash_init,
    input load_en,
    input clk,
    input cntr_zero,
    input calc,
    output reg is_loaded,
    output reg [1343:0] data_out
    );
    
    reg is_loaded_temp;

    always @ (posedge clk, posedge hash_init) begin
        if (hash_init) begin
            data_out <= 0;
            // is_loaded_temp <= 0;
        end
        else begin
            if (load_en) begin
                data_out <= data_out << `DATA_SIZE;
                // data_out[1343-:`DATA_SIZE] <= data_in;
                data_out[63:0] <= data_in;
                // if (cntr_zero) is_loaded_temp <= 1;
                // else if(~calc) is_loaded_temp <= 0; 
            end
            else data_out <= data_out;
        end
    end
    always @ (posedge clk, posedge cntr_zero) begin
        if(hash_init)
         is_loaded_temp <= 0;
        else begin
            if (cntr_zero) is_loaded_temp <= 1;
            else if(~calc) is_loaded_temp <= 0; 
        end
    end

    always @ (posedge clk, posedge hash_init) begin
        if (hash_init) is_loaded <= 0;
        else is_loaded <= is_loaded_temp;
    end
    
endmodule
