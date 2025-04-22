`timescale 1ns/1ps
module pipeline_tb;
    // Clock generation
    reg clk = 1'b0;
	 reg reset;
	 //wire [15:0] PC_out;
    always #10 clk = ~clk;
	initial begin 
		
		#50;
		reset=1;
		#10;
		reset=0;
		
		#2200;
		$finish;
		
	end

    // Instantiate ALU module
    pipeline uut (clk,reset);

endmodule