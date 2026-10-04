
module padder(
    input clk,
    input rst,
    input [63:0]in,
    input in_valid,
    input start_calc,
    input takein,
    output [63:0]out,
    output reg out_ready, //
    input is_last,
    input[1:0] mode,
    output reg ack, //
    output cntr_zero,
    output reg takein_reg // To latch in takein to specify when the data is valid into f_permutation
    );

    reg [63:0] pad_out; //
    reg [4:0] cntr; //
    reg latch_last; //
    reg latch_latch_last; //
    reg pad; //

    // always @(posedge clk, posedge rst) begin
    //     if(rst) begin
    //         pad_out<=0;
    //     end
    // end

    always @(posedge clk, posedge rst) begin
        if (rst) begin
            cntr <= 0;
        end
        else if ( ((start_calc | (takein & (cntr == 0))) & in_valid) & ~rst) begin
            case(mode)
                    0: cntr <= 17;
                    1: cntr <= 9;
                    2: cntr <= 21;
                    3: cntr <= 17;
            endcase
        end
        else if((cntr!=0) & (in_valid | pad))
            cntr <= cntr - 1;
    end

    always @(posedge clk, posedge rst) begin
        // out_ready <= 0;
        ack<=0;
        if (rst) begin
            pad_out<=0;
            ack <= 0;
        end
        else if(in_valid & ((~is_last & cntr!=0))) begin
            pad_out <= in;
            // out_ready <= 1;
            ack <= 1;
        end
        else if(is_last & cntr!=1) begin
            pad_out <= in;
            // out_ready <= 1;
            ack <= 1;
        end
        // else if(latch_latch_last & cntr!=0) begin
        //     pad_out <= 0;
        //     out_ready <= 1;
        // end
        else if(latch_last & cntr != 1)
        begin
            pad_out <= {1'b1, {63{1'b0}}};
            // out_ready<=1;
        end
        else if(cntr != 1 & cntr != 0)
        begin
            pad_out <= 0;
            // out_ready<=1;
        end
        // else if(latch_latch_last & cntr==0)
        // begin
        //     pad_out<=1;
        //     // latch_last<=0;
        //     out_ready<=1;
        // end
        else if (cntr == 1) 
        begin
            pad_out <= 1;
            // out_ready <= 1;
        end
        else if (cntr == 0) begin
            pad_out <= 0;
            // out_ready <= 0;
        end
    end

    always @(posedge clk, posedge rst) begin
        if(rst) begin
            latch_last <= 0;
            latch_latch_last <= 0;
            takein_reg <= 0;
        end
        else begin
            latch_last <= is_last;
            latch_latch_last <= latch_last;
            takein_reg <= takein;
        end
    end
    always@(posedge clk, posedge rst) begin
        if(rst) begin
            pad <= 0;
        end
        else if(is_last & cntr>1) begin
            pad <= 1;
        end
        else if(cntr == 1 | cntr==0) begin
            pad <= 0;
        end
    end
    always @(posedge clk, posedge rst) begin
        if(rst) begin
            out_ready <= 0;
        end
        else if((pad | in_valid)&cntr!=0) begin
            out_ready <= 1;
        end
        else if(~pad & ~in_valid) begin
            out_ready <= 0;
        end
    end

    // always@(posedge clk)
    //     out <= pad_out;

    assign cntr_zero = (cntr==1);
    assign out = pad_out;

endmodule