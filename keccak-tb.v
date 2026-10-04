`define CYCLE 4

module test_keccak;

    // Inputs
    reg clk;
    reg rst;
    reg [63:0] in;
    reg [1:0] mode;
    reg is_last;
    reg start_calc;
    reg gimme;
    reg in_valid;

    // Outputs
    wire ack;
    wire [63:0] out;
    wire out_valid;
    wire out_buf_empty;

    // Instantiate the Unit Under Test (UUT)
    keccak uut (
        .clk(clk),
        .rst(rst),
        .in(in),
        .mode(mode),
        .is_last(is_last),
        .start_calc(start_calc),
        .gimme(gimme),
        .ack(ack),
        .in_valid(in_valid),
        .out(out),
        .out_valid(out_valid)
    );

    // Clock generation
    always #(`CYCLE/2) clk = ~clk;
    integer i;
    integer j;
    // Initial block for stimulus
    initial begin
        // Initialize inputs
        clk = 0;
        rst = 1;
        in = 0;
        mode = 0;
        is_last = 0;
        start_calc = 0;
        gimme = 0;
        in_valid = 0;

        // Wait 100 ns for global reset to finish
        #9;
        rst = 0;

        // Test sequence
        // Stage 1: Start Calculation
        start_calc = 1;
        mode = 2'b01; // Example mode
        in = 64'hF0E1D2C3B4A59687;
        in_valid = 1;
        #(`CYCLE);

        // Check ack and out_valid should be 0 initially
        if (ack != 0) error;
        if (out_valid !== 0) error;

        // Stage 2: Input valid data to padder
        start_calc = 0;
        in_valid = 1;
        #(`CYCLE);

        // Feed multiple data words
        for ( i = 0; i < 5; i = i + 1) begin
            // if (i == 4) is_last = 1; // Indicate the last word
            in = in + 64'h0101010101010101;
            #(`CYCLE);
        end

        in_valid = 0;
        // is_last = 0;
        #100;
        // Wait for f_permutation to complete and check out_valid and out values
        // wait (out_valid == 1);
        #(`CYCLE);
        #500;

        // Verify output buffer
        gimme = 1;
        // #100;
        

        // // Stage 3: Verify the output matches the expected hash
        // // if (out !== 64'hExpectedHashValue) error;

        // // Additional cases: Absorb more data, toggle gimme, check buffer status
        wait(ack == 0);
        for (j = 0; j < 12; j = j + 1) begin
            if(j == 11) is_last = 1;
            in = in + 64'h0202020202020202;
            in_valid = 1;
            #(`CYCLE);
            wait(ack == 1);
            is_last = 0;
            in_valid = 0;
        end
        #200;
        gimme=1;
        #1000;
        start_calc = 1;
        mode = 2'b10; // Example mode
        in = 64'hF0E1D2C3B4A59687;
        in_valid = 1;
        #(`CYCLE);

        // Check ack and out_valid should be 0 initially
        if (ack != 0) error;
        if (out_valid !== 0) error;

        // Stage 2: Input valid data to padder
        start_calc = 0;
        in_valid = 1;
        #(`CYCLE);

        // Feed multiple data words
        for ( i = 0; i < 5; i = i + 1) begin
            // if (i == 4) is_last = 1; // Indicate the last word
            in = in + 64'h0101010101010101;
            #(`CYCLE);
        end

        in_valid = 0;
        // is_last = 0;
        #100;
        // Wait for f_permutation to complete and check out_valid and out values
        // wait (out_valid == 1);
        #(`CYCLE);
        #500;

        // Verify output buffer
        gimme = 1;
        // #100;
        

        // // Stage 3: Verify the output matches the expected hash
        // // if (out !== 64'hExpectedHashValue) error;

        // // Additional cases: Absorb more data, toggle gimme, check buffer status
        wait(ack == 0);
        for (j = 0; j < 3; j = j + 1) begin
            if(j == 2) is_last = 1;
            in = in + 64'h0202020202020202;
            in_valid = 1;
            #(`CYCLE);
            wait(ack == 1);
            is_last = 0;
            in_valid = 0;
        end
        #200;
        gimme=1;
        #1000;
        // // Wait for buffer to fill and empty
        // wait (out_buf_empty == 1);
        // #(`CYCLE);

        // End the test with success message
        $display("Test Passed!");
        $finish;
    end

    // Error task for debugging
    task error;
        begin
            $display("Error: Test Failed!");
            $finish;
        end
    endtask

    // Dump waveforms for debugging
    initial begin
        $dumpfile("test_keccak.vcd");
        $dumpvars(0, test_keccak);
    end

endmodule