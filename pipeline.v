module pipeline (input clk, input reset );

wire [15:0] PC ;  				// Program counter is a wire from reg_array[0]
reg stall =1'b0;  
reg [1:0] NOP  = 2'b0;	
reg [7:0] instr_mem [0:63];		// It is a byte addressable instruction memory 
reg [7:0] data_mem  [0:31];		// It is a byte addressable data memory 
reg flush ;						// Control signal to remove pre-fetched instructions when branch is taken or jump

//Pipeline Register 1
reg [15:0] PR1;

//Pipeline Register 2
reg       PR2_reg_write_en;
reg [2:0] PR2_reg_add1, PR2_reg_add2, PR2_reg_write_add, PR2_alu_ctrl, PR2_nand_ctrl;
reg [3:0] PR2_opcode;
reg [5:0] PR2_imm6;
reg [8:0] PR2_imm9;

//Pipeline Register 3
reg        PR3_reg_write_en;
reg [2:0]  PR3_reg_write_add , PR3_alu_ctrl, PR3_nand_ctrl,PR3_reg_add1, PR3_reg_add2;
reg [3:0]  PR3_opcode;
reg [5:0]  PR3_imm6;
reg [8:0]  PR3_imm9;
reg [15:0] PR3_result,PR3_OperandA,PR3_OperandB,PR3_OperandC,OperandA,OperandB;

//Pipeline Register 4
reg        PR4_reg_write_en, PR3_Mem_add, PR3_CARRY, PR3_ZERO;
reg [2:0]  PR4_reg_write_add, PR4_reg_add1, PR4_reg_add2;
reg [3:0]  PR4_opcode;
reg [15:0] PR4_data, PR4_result, PR4_OperandA;

//Pipeline Register 5
reg        PR5_reg_write_en;
reg [2:0]  PR5_reg_write_add, PR5_reg_add1, PR5_reg_add2;
reg [3:0]  PR5_opcode;	
reg [15:0] PR5_result, PR5_data, PR5_OperandA;
reg [15:0] PR5_LM [7:0];

//Register File
reg        RF_write_en;
reg [2:0]  RF_read_addr_1, RF_read_addr_2, RF_write_dest;
reg [15:0] RF_read_data_1, RF_read_data_2, RF_write_data;
reg [15:0] reg_array [7:0];

always @ (*) begin
	if (reset) begin				// To reset the register file
		flush =0;
		reg_array[0] <= 16'd00;
		reg_array[1] <= 16'd10;
		reg_array[2] <= 16'd00;
		reg_array[3] <= 16'd30;
		reg_array[4] <= 16'd40;
		reg_array[5] <= 16'd50;
		reg_array[6] <= 16'd60;
		reg_array[7] <= 16'd70; end
	else begin if (RF_write_en) begin reg_array[RF_write_dest] <= RF_write_data; end end	// To write data into register file
end
	 	 
always @(*) begin RF_read_data_1 <= reg_array[RF_read_addr_1]; 
				  RF_read_data_2 <= reg_array[RF_read_addr_2]; end  // Accessing data from the register file


// Loading instruction and data memory into registers 
initial begin   
    $readmemh("instr_mem.hex", instr_mem);
	$readmemh("data_mem.hex",  data_mem);
end

// =============================================Instruction Fetch=============================================
assign PC = reg_array[0]; 

// ---------------------------------------------Pipeline register IF/ID---------------------------------------

always @(posedge clk) begin if (!stall) begin PR1 <= {instr_mem[PC], instr_mem[PC+1]}; end end

// =============================================Instruction Decode=============================================
reg        reg_write_en;
reg  [2:0] reg_add1, reg_add2, reg_write_add, alu_ctrl, nand_ctrl;
reg  [3:0] opcode;
reg  [5:0] imm6;
reg  [8:0] imm9;
wire [1:0] flags = PR1[1:0]  ;
wire [2:0] RA    = PR1[11:9] ;
wire [2:0] RB    = PR1[8:6]  ;
wire [2:0] RC    = PR1[5:3]  ;
wire       compl = PR1[2]    ;

always @(*) begin
	alu_ctrl      = 3'bx;
	nand_ctrl     = 3'bx;
	reg_write_en  = 1'bx;
	reg_write_add = 3'bx;
	reg_add1      = 3'bx;
	reg_add2      = 3'bx;
	opcode        = PR1[15:12];
	imm6          = 6'bx;
	imm9          = 9'bx; 

	// Generating Control signals from the instruction 
	case(opcode)
		4'b0000: begin
			reg_add1 = RB; reg_write_add = RA; reg_write_en = 1'b1; imm6 = PR1[5:0];end // ADI
		4'b0001: begin
			reg_add1 = RB; reg_add2 = RC; reg_write_add = RA; reg_write_en = 1'b1;
			if (compl == 0) begin
				if (flags == 2'b00) alu_ctrl = 3'b000;      // ADA
				else if (flags == 2'b10) alu_ctrl = 3'b010; // ADC
				else if (flags == 2'b01) alu_ctrl = 3'b001; // ADZ
				else alu_ctrl = 3'b011;                     // AWC
			end
			else begin
				if (flags == 2'b00) alu_ctrl = 3'b100;      // ACA
				else if (flags == 2'b10) alu_ctrl = 3'b110; // ACC
				else if (flags == 2'b01) alu_ctrl = 3'b101; // ACZ
				else alu_ctrl = 3'b111; // ACW
			end
		end
		4'b0010: begin
			reg_add1 = RB; reg_add2 = RC; reg_write_add = RA; reg_write_en = 1'b1;
			if(compl == 0) begin
				if      (flags == 2'b00) nand_ctrl = 3'b000; // NDU
				else if (flags == 2'b10) nand_ctrl = 3'b010; // NDC
				else if (flags == 2'b01) nand_ctrl = 3'b001; // NDZ 
		    end
			else begin
				if 		(flags == 2'b00) nand_ctrl = 3'b100; // NCU
				else if (flags == 2'b10) nand_ctrl = 3'b110; // NCC
				else if (flags == 2'b01) nand_ctrl = 3'b101; // NCZ
			end
	    end
		4'b0011: begin reg_write_add = RA; imm9 = PR1[8:0];reg_write_en = 1'b1;end // LLI
		4'b0100: begin reg_write_add = RA; reg_add1 = RB; reg_write_en = 1'b1; imm6 = PR1[5:0]; end // LW
		4'b0101: begin reg_add1 = RA; reg_add2 = RB; imm6 = PR1[5:0]; end  // SW
		4'b0110: begin reg_add1 = RA; imm9 = PR1[8:0]; end // LM
		4'b0111: begin reg_add1 = RA; imm9 = PR1[8:0]; end // SM
		4'b1000: begin reg_add1 = RA; reg_add2 = RB;imm6 = PR1[5:0]; end  // BEQ
		4'b1001: begin reg_add1 = RA; reg_add2 = RB;imm6 = PR1[5:0]; end  // BLT
		4'b1010: begin reg_add1 = RA; reg_add2 = RB;imm6 = PR1[5:0]; end  // BLE
		4'b1100: begin reg_write_add = RA; imm9 = PR1[8:0]; end // JAL
		4'b1101: begin reg_write_add = RA;reg_add2 = RB; imm6 = 6'b0; end // JLR
		4'b1111: begin reg_add1 = RA; imm9 = PR1[8:0]; end // JRL
endcase
end
//--------------------------------------------Pipeline Register ID/OR----------------------------------------------
always @(posedge clk) begin

if (!flush ) begin
	if (!stall ) begin
		PR2_reg_write_en  <= reg_write_en;
		PR2_reg_add1  	  <= reg_add1;
		PR2_reg_add2	  <= reg_add2;
		PR2_reg_write_add <= reg_write_add;
		PR2_alu_ctrl	  <= alu_ctrl;
		PR2_nand_ctrl     <= nand_ctrl;
		PR2_opcode		  <= opcode;
		PR2_imm6		  <= imm6;
		PR2_imm9		  <= imm9;
		RF_read_addr_1	  <= reg_add1;
		RF_read_addr_2	  <= reg_add2;
	end
end
else begin 
		PR3_OperandA<=16'bx;
		PR3_OperandB<=16'bx;
		PR3_reg_write_en<=1'bx;
		PR3_reg_add1<= 3'bx;
		PR3_reg_add2<= 3'bx;
		PR3_reg_write_add<=3'bx;
		PR3_alu_ctrl<=3'bx;
		PR3_nand_ctrl<=3'bx;
		PR3_opcode<=4'bx;
		PR3_imm6<=6'bx;
		PR3_imm9<=9'bx; end
end

// =============================================Operand Read==================================================          
// Data Hzarads:Data Forwarding 
always @(*) begin 
	OperandA = RF_read_data_1 ; // Operand data from the register 
	OperandB = RF_read_data_2; // Operand data from the register
	
	casex (PR2_opcode) 
		4'b0000,4'b0001,4'b0010: begin
			//when 'n'th instruction and 'n-1' instruction has data dependency(not load instruction as 'n-1'th instruction)
			if((PR3_reg_write_add == PR2_reg_add1) && (PR3_reg_write_add == PR2_reg_add2) && (PR3_opcode != 4'h4)) begin
				OperandA <= PR3_result ; OperandB <= PR3_result; end //eg:PR3-> R1= R2+R3; PR2->R2 = R1+R1
			else if((PR3_reg_write_add == PR2_reg_add1) && (PR3_opcode != 4'h4)) begin
				OperandA <= PR3_result ; OperandB <= RF_read_data_2; end //eg:PR3-> R1= R2+R3; PR2->R2 = R1+R4
			else if((PR3_reg_write_add == PR2_reg_add2)  && (PR3_opcode != 4'h4)) begin
				OperandA <= RF_read_data_1 ; OperandB <= PR3_result; end //eg:PR3-> R1= R2+R3; PR2->R2 = R5+R1
			//when 'n'th instruction and 'n-2' instruction has data dependency(not load instruction as 'n-2'th instruction)
			if((PR4_reg_write_add == PR2_reg_add1) && (PR4_reg_write_add == PR2_reg_add2) && (PR4_opcode != 4'h4) ) begin
				OperandA <= PR4_result ; OperandB <= PR4_result; end //eg:PR4-> R1= R2+R3; PR3-> 'n-1' instr; PR2->R2 = R1+R1
			else if((PR4_reg_write_add == PR2_reg_add1) && (PR4_opcode != 4'h4) ) begin
				OperandA <= PR4_result ; OperandB <= RF_read_data_2; end //eg:PR4-> R1= R2+R3; PR3-> 'n-1' instr; PR2->R2 = R1+R4
			else if((PR4_reg_write_add == PR2_reg_add2) && (PR4_opcode != 4'h4) ) begin
				OperandA <= RF_read_data_1 ; OperandB <= PR4_result; end //eg:PR4-> R1= R2+R3; PR3-> 'n-1' instr; PR2->R2 = R4+R1

			//load instructions followed by immediate dependency
			//when 'n'th instruction and 'n-1' instruction has data dependency(with load instruction as 'n-1'th instruction)
			if((PR3_reg_write_add == PR2_reg_add1) && (PR3_reg_write_add == PR2_reg_add2) && (PR3_opcode == 4'h4)) begin
				NOP<=2'd1;stall <=1'b1; end//eg:PR3->LOAD R1,R2,00H; PR2->R2 =R1+R1; 
				//add a stall since we can access data memory in MEMORY ACCESS  STAGE
			else if((PR3_reg_write_add == PR2_reg_add1) && (PR3_opcode == 4'h4) ) begin
				NOP<=2'd1;stall <=1'b1; end //eg:PR3->LOAD R1,R2,00H;PR2-> R2 =R1+R4; 
			else if((PR3_reg_write_add == PR2_reg_add2) && (PR3_opcode == 4'h4) ) begin
				NOP<=2'd1;stall <=1'b1; end //eg:PR3->LOAD R1,R2,00H; PR->R2 =R4+R1; 
			//when 'n'th instruction and 'n-2' instruction has data dependency(with load instruction as 'n-2'th instruction)
			if((PR4_reg_write_add == PR2_reg_add1) && (PR4_reg_write_add == PR2_reg_add2) && (PR4_opcode == 4'h4) ) begin
				OperandA <= PR4_data; OperandB <= PR4_data; end //eg:PR4->LOAD R1,R2,00H; PR3-> 'n-1' instr; PR2->R2 =R1+R1; 
			else if((PR4_reg_write_add == PR2_reg_add1)  && (PR4_opcode == 4'h4)) begin
				OperandA <= PR4_data; OperandB <= RF_read_data_2; end //eg:PR4->LOAD R1,R2,00H; PR3-> 'n-1' instr;  PR2->R2 =R1+R4; 
			else if((PR4_reg_write_add == PR2_reg_add2)  && (PR4_opcode == 4'h4)) begin
				OperandA <= RF_read_data_1; OperandB <= PR4_data; end 	//eg:PR4->LOAD R1,R2,00H; PR3-> 'n-1' instr; PR2->R2 =R4+R1; 
		end
		//when 'n'th instruction is 'STORE' and 'n-1' instruction has data dependency
		4'b0101 : begin
			if((PR3_reg_write_add == PR2_reg_add1) && (PR3_reg_write_add == PR2_reg_add2) && (PR3_opcode != 4'h4)) begin OperandA <= PR3_result;
				 OperandB <= PR3_result;end //eg:PR3-> R5 = R6+R7; PR2-> SW R5,R5;
			if((PR3_reg_write_add == PR2_reg_add1) && (PR3_opcode != 4'h4)) begin OperandA <= PR3_result; end //eg:PR3-> R5 = R6+R7; PR2-> SW R5,R6;
			if((PR3_reg_write_add == PR2_reg_add2)&& (PR3_opcode != 4'h4)) begin OperandB <= PR3_result; end //eg::PR3-> R5 = R6+R7; PR2-> SW R6,R5;
			if((PR3_reg_write_add == PR2_reg_add1) && (PR3_reg_write_add == PR2_reg_add2) && (PR3_opcode == 4'h4)) begin 
					NOP<=2'd1;stall <=1'b1; end //eg:PR3->LOAD R1,R2,00H;PR2-> SW R1,R1
			if((PR3_reg_write_add == PR2_reg_add1)  && (PR3_opcode == 4'h4)) begin
				NOP<=2'd1;stall <=1'b1; end //eg:PR3->LOAD R1,R2,00H;PR2-> SW R1,R5;		//when 'n'th instruction is 'STORE' and 'n-2' instruction has data dependency
			if((PR3_reg_write_add == PR3_reg_add2)  && (PR3_opcode == 4'h4)) begin
				NOP<=2'd1;stall <=1'b1; end //eg:PR3->LOAD R1,R2,00H;PR2-> SW R5,R1;
			if((PR4_reg_write_add == PR2_reg_add1) && (PR4_reg_write_add == PR2_reg_add2) && (PR4_opcode != 4'h4)) begin OperandA <= PR4_result;
				 OperandB <= PR4_result;end //eg:PR4-> R5 = R6+R7;PR3 -> N-1th INST; PR2-> SW R5,R5;	
			if((PR4_reg_write_add == PR2_reg_add1)&& (PR4_opcode != 4'h4)) begin OperandA <= PR4_result ; end //eg:PR4-> R5 = R6+R7;PR3-> 'n-1' instr PR2->SW R5,R6;
			if((PR4_reg_write_add == PR2_reg_add2)&& (PR4_opcode != 4'h4)) begin OperandB <= PR4_result ; end //eg::PR4-> R5 = R6+R7;PR3 -> 'n-1' instr PR2->SW R6,R5;
			if((PR4_reg_write_add == PR2_reg_add1) && (PR4_reg_write_add == PR2_reg_add2) && (PR4_opcode == 4'h4)) begin 
				OperandB <= PR4_data;OperandA <= PR4_data; end //eg:PR4->LOAD R1,R2,00H; PR3-> 'n-1' instr;  PR2->SW R1,R1;
			if((PR4_reg_write_add == PR2_reg_add1)  && (PR4_opcode == 4'h4)) begin
				OperandA <= PR4_data;  end //eg:PR4->LOAD R1,R2,00H; PR3-> 'n-1' instr;  PR2->SW R1,R6;
			if((PR4_reg_write_add == PR2_reg_add2)  && (PR4_opcode == 4'h4)) begin
				OperandB <= PR4_data;  end //eg:PR4->LOAD R1,R2,00H; PR3-> 'n-1' instr;  PR2->SW R5,R1;
			
		end
		4'b1000,4'b1001,4'b1010 : begin
			//when 'n'th instruction and 'n-1' instruction has data dependency(not load instruction as 'n-1'th instruction)
			if((PR3_reg_write_add == PR2_reg_add1) && (PR3_reg_write_add == PR2_reg_add2) && (PR3_opcode != 4'h4)) begin
				OperandA <= PR3_result ; OperandB <= PR3_result; end //eg:PR3-> R1= R2+R3; PR2 -> BEQ R1,R1,00H
			else if((PR3_reg_write_add == PR2_reg_add1) && (PR3_opcode != 4'h4)) begin
				OperandA <= PR3_result ; OperandB <= RF_read_data_2; end //eg:PR3-> R1= R2+R3; PR2->BEQ R1,R4,00H
			else if((PR3_reg_write_add == PR2_reg_add2)  && (PR3_opcode != 4'h4)) begin
				OperandA <= RF_read_data_1 ; OperandB <= PR3_result; end //eg:PR3-> R1= R2+R3; PR2->BEQ R4,R1,00H
			//when 'n'th instruction and 'n-2' instruction has data dependency(not load instruction as 'n-2'th instruction)
			if((PR4_reg_write_add == PR2_reg_add1) && (PR4_reg_write_add == PR2_reg_add2) && (PR4_opcode != 4'h4) ) begin
				OperandA <= PR4_result ; OperandB <= PR4_result; end //eg:PR4-> R1= R2+R3; PR3-> 'n-1' instr; PR2-> BEQ R1,R1,00H
			else if((PR4_reg_write_add == PR2_reg_add1) && (PR4_opcode != 4'h4) ) begin
				OperandA <= PR4_result ; OperandB <= RF_read_data_2; end //eg:PR4-> R1= R2+R3; PR3-> 'n-1' instr; PR2->R2 = BEQ R1,R4,00H
			else if((PR4_reg_write_add == PR2_reg_add2) && (PR4_opcode != 4'h4) ) begin
				OperandA <= RF_read_data_1 ; OperandB <= PR4_result; end //eg:PR4-> R1= R2+R3; PR3-> 'n-1' instr; PR2-> BEQ R4,R1,00H

			//load instructions followed by immediate dependency
			//when 'n'th instruction and 'n-1' instruction has data dependency(with load instruction as 'n-1'th instruction)
			if((PR3_reg_write_add == PR2_reg_add1) && (PR3_reg_write_add == PR2_reg_add2) && (PR3_opcode == 4'h4)) begin
				NOP<=2'd1;stall <=1'b1; end//eg:PR3->LOAD R1,R2,00H; PR2 -> BEQ R1,R1,00H
				//add a stall since we can access data memory in MEMORY ACCESS  STAGE
			else if((PR3_reg_write_add == PR2_reg_add1) && (PR3_opcode == 4'h4) ) begin
				NOP<=2'd1;stall <=1'b1; end //eg:PR3->LOAD R1,R2,00H;PR2-> R2 =R1+R4; 
			else if((PR3_reg_write_add == PR2_reg_add2) && (PR3_opcode == 4'h4) ) begin
				NOP<=2'd1;stall <=1'b1; end //eg:PR3->LOAD R1,R2,00H; PR->R2 =R4+R1; 
			//when 'n'th instruction and 'n-2' instruction has data dependency(with load instruction as 'n-2'th instruction)
			if((PR4_reg_write_add == PR2_reg_add1) && (PR4_reg_write_add == PR2_reg_add2) && (PR4_opcode == 4'h4) ) begin
				OperandA <= PR4_data; OperandB <= PR4_data; end //eg:PR4->LOAD R1,R2,00H; PR3-> 'n-1' instr; PR2->R2 =R1+R1; 
			else if((PR4_reg_write_add == PR2_reg_add1)  && (PR4_opcode == 4'h4)) begin
				OperandA <= PR4_data; OperandB <= RF_read_data_2; end //eg:PR4->LOAD R1,R2,00H; PR3-> 'n-1' instr;  PR2->R2 =R1+R4; 
			else if((PR4_reg_write_add == PR2_reg_add2)  && (PR4_opcode == 4'h4)) begin
				OperandA <= RF_read_data_1; OperandB <= PR4_data; end 	//eg:PR4->LOAD R1,R2,00H; PR3-> 'n-1' instr; PR2->R2 =R4+R1; 
		end
		4'b1101,4'b1111:begin
			if((PR3_reg_write_add == PR2_reg_add1) && (PR3_opcode != 4'h4) ) begin OperandA <= PR3_result; end //eg:PR3-> R5 = R6+R7; PR2-> JRL R5,00H;
			if((PR3_reg_write_add == PR2_reg_add2) && (PR3_opcode != 4'h4) ) begin OperandB <= PR3_result; end //eg::PR3-> R6 = R6+R7; PR2->JLR R5,R6;
		//when 'n'th instruction is 'STORE' and 'n-2' instruction has data dependenc
			if((PR4_reg_write_add == PR2_reg_add1) && (PR3_opcode != 4'h4) ) begin OperandA <= PR4_result ; end //eg:PR4-> R6 = R6+R7;PR3-> 'n-1' instr PR2-> JRL R5,00H;
			if((PR4_reg_write_add == PR2_reg_add2) && (PR3_opcode != 4'h4) ) begin OperandB <= PR4_result ; end //eg::PR4-> R6 = R6+R7;PR3 -> 'n-1' instr PR2->JLR R5,R6;
			//load instructions followed by immediate dependency
			//when 'n'th instruction and 'n-1' instruction has data dependency(with load instruction as 'n-1'th instruction)
			if((PR3_reg_write_add == PR2_reg_add1) && (PR3_opcode == 4'h4) ) begin
				NOP<=2'd1;stall <=1'b1; end //eg:PR3->LOAD R1,R2,00H; PR2->JRL R1,00H; 
			else if((PR3_reg_write_add == PR2_reg_add2) && (PR3_opcode == 4'h4) ) begin
				NOP<=2'd1;stall <=1'b1; end //eg:PR3->LOAD R1,R2,00H; PR2->JLR R5,R1; 
			//when 'n'th instruction and 'n-2' instruction has data dependency(with load instruction as 'n-2'th instruction)
			if((PR4_reg_write_add == PR2_reg_add1)  && (PR4_opcode == 4'h4)) begin
				OperandA <= PR4_data;  end //eg:PR4->LOAD R1,R2,00H; PR3-> 'n-1' instr;  PR2->JRL R1,00H;
			else if((PR4_reg_write_add == PR2_reg_add2)  && (PR4_opcode == 4'h4)) begin
				OperandA <= RF_read_data_1;  end 	//eg:PR4->LOAD R1,R2,00H; PR3-> 'n-1' instr; PR2->JLR R5,R1; 
		end
	endcase
end

//--------------------------------------------Pipeline Register OR/EX ----------------------------------------------

always @(posedge clk) begin
	if (!stall && !flush) begin
		PR3_OperandA     <= OperandA;
		PR3_OperandB     <= OperandB;
		PR3_reg_write_en <= PR2_reg_write_en;
		PR3_reg_add1     <= PR2_reg_add1;
		PR3_reg_add2     <= PR2_reg_add2;
		PR3_reg_write_add <= PR2_reg_write_add;
		PR3_alu_ctrl     <= PR2_alu_ctrl;
		PR3_nand_ctrl    <= PR2_nand_ctrl;
		PR3_opcode       <= PR2_opcode;
		PR3_imm6         <= PR2_imm6;
		PR3_imm9         <= PR2_imm9;
	end
	else begin 
		PR3_OperandA<=16'bx;
		PR3_OperandB<=16'bx;
		PR3_reg_write_en<=1'bx;
		PR3_reg_add1<= 3'bx;
		PR3_reg_add2<= 3'bx;
		PR3_reg_write_add<=3'bx;
		PR3_alu_ctrl<=3'bx;
		PR3_nand_ctrl<=3'bx;
		PR3_opcode<=4'bx;
		PR3_imm6<=6'bx;
		PR3_imm9<=9'bx; end

end
// ============================================= Execution Stage ==================================================          

reg [15:0] predicted_BTA;
reg status ;
reg [15:0] Correct_BTA;

always @(*) begin
	PR3_result=16'bx;
    case(PR3_opcode)
    	4'b0000: begin {PR3_CARRY, PR3_result} = PR3_OperandA + {{10{PR3_imm6[5]}}, PR3_imm6};
					  if ({PR3_CARRY, PR3_result}==0) PR3_ZERO = 1; end//ADI
    	4'b0001: begin
        	if (PR3_alu_ctrl[2] == 0) begin
        		if (PR3_alu_ctrl[1:0] == 2'b00) begin 
					{PR3_CARRY,PR3_result}=PR3_OperandA+PR3_OperandB; 
					if ({PR3_CARRY, PR3_result}==0) PR3_ZERO = 1; end // ADA
        		else if (PR3_alu_ctrl[1:0] == 2'b10) begin 
					if(PR3_CARRY) begin {PR3_CARRY,PR3_result} = PR3_OperandA + PR3_OperandB; 
					if({PR3_CARRY, PR3_result}==0) PR3_ZERO = 1;end end // ADC
          		else if (PR3_alu_ctrl[1:0] == 2'b01) begin 
					if(PR3_ZERO)  begin {PR3_CARRY,PR3_result} = PR3_OperandA + PR3_OperandB; 
					if ({PR3_CARRY, PR3_result}==0) PR3_ZERO = 1; end end // ADZ
        		else begin 
					{PR3_CARRY,PR3_result}=PR3_OperandA+PR3_OperandB+PR3_CARRY; 
					if ({PR3_CARRY, PR3_result}==0) PR3_ZERO = 1; end //AWC
				end 
        	else begin
				if (PR3_alu_ctrl[1:0] == 2'b00) begin 
					{PR3_CARRY,PR3_result}=PR3_OperandA+(~PR3_OperandB); 
					if ({PR3_CARRY, PR3_result}==0) PR3_ZERO = 1; end // ACA
        		else if (PR3_alu_ctrl[1:0] == 2'b10) begin 
					if(PR3_CARRY) begin 
						{PR3_CARRY,PR3_result} = PR3_OperandA + (~PR3_OperandB); 
						if ({PR3_CARRY, PR3_result}==0) PR3_ZERO = 1;end end // ACC
          		else if (PR3_alu_ctrl[1:0] == 2'b01) begin 
					if(PR3_ZERO)  begin 
						{PR3_CARRY,PR3_result} = PR3_OperandA + (~PR3_OperandB); 
						if ({PR3_CARRY, PR3_result}==0) PR3_ZERO = 1; end end // ACZ
          		else begin 
					{PR3_CARRY,PR3_result}=PR3_OperandA+(~PR3_OperandB)+PR3_CARRY; 
					if ({PR3_CARRY, PR3_result}==0) PR3_ZERO = 1; end//ACW
			end
		end
		4'b0010: begin
        	if (PR3_nand_ctrl[2] == 0) begin
          		if (PR3_nand_ctrl[1:0] == 2'b00) begin 
					PR3_result=~(PR3_OperandA & PR3_OperandB);
					if ({PR3_CARRY, PR3_result}==0) PR3_ZERO = 1; end// NDU
          		else if (PR3_nand_ctrl[1:0] == 2'b10) begin 
					if(PR3_CARRY) begin PR3_result = ~(PR3_OperandA & PR3_OperandB); 
					if ({PR3_CARRY, PR3_result}==0) PR3_ZERO = 1; end end // NDC
          		else if (PR3_nand_ctrl[1:0] == 2'b01) begin 
					if(PR3_ZERO) begin PR3_result = ~(PR3_OperandA & PR3_OperandB);
					if ({PR3_CARRY, PR3_result}==0) PR3_ZERO = 1; end end // NDZ
        	end
        	else begin
          		if (PR3_nand_ctrl[1:0] == 2'b00) begin 
					PR3_result=~(PR3_OperandA & (~PR3_OperandB));
					if ({PR3_CARRY, PR3_result}==0) PR3_ZERO = 1; end// NCU
          		else if (PR3_nand_ctrl[1:0] == 2'b10) begin
					if(PR3_CARRY) begin PR3_result = ~(PR3_OperandA & (~PR3_OperandB));
					if ({PR3_CARRY, PR3_result}==0) PR3_ZERO = 1; end end // NCC
          		else if (PR3_nand_ctrl[1:0] == 2'b01) begin
					if(PR3_ZERO) begin PR3_result = ~(PR3_OperandA & (~PR3_OperandB));
					if ({PR3_CARRY, PR3_result}==0) PR3_ZERO = 1; end end // NCZ
			end
		end
		4'b0011: begin PR3_result = {7'b0,PR3_imm9[8:0]}; end//LLI
		4'b0110: begin PR3_result = {7'b0,PR3_imm9[8:0]}; end//LM
		4'b0111: begin PR3_result = {7'b0,PR3_imm9[8:0]}; end//SM
		4'b0100: begin PR3_result = PR3_OperandA + {{10{PR3_imm6[5]}}, PR3_imm6}; end//LW
		4'b0101: begin PR3_result = PR3_OperandB + {{10{PR3_imm6[5]}}, PR3_imm6}; end//SW
		4'b1000: begin if(PR3_OperandA==PR3_OperandB) begin PR3_result = PC+ (PR3_imm6-3)*2; end end//BEQ
		4'b1001: begin if(PR3_OperandA<PR3_OperandB)  begin PR3_result = PC+ (PR3_imm6-3)*2; end end//BLT
		4'b1010: begin if(PR3_OperandA>PR3_OperandB)  begin PR3_result = PC+ (PR3_imm6-3)*2; end end//BLE
		4'b1100: begin PR3_result = PC+ (PR3_imm9-3)*2; end//JAL
		4'b1101: begin PR3_result = PR3_OperandB; end//JLR
		4'b1111: begin PR3_result = PR3_OperandA + (PR3_imm9-2)*2; end	//JRI
    endcase
	//new jump instruction entry in the unconditional branch table
	 if ((status == 1'b0) && (PR3_opcode == 4'd12 ||PR3_opcode == 4'd13 || PR3_opcode == 4'd15 )) begin
	 Correct_BTA <= PR3_result; flush=1'b1; end
end

// =========================m================== Unconditional branch table ================================================
localparam A = 1'b1,NA =1'b0; 
reg [2:0] count = 0;
    // Define branch table
reg [15:0] UC_PC_table  [0:7]; 
reg [15:0] UC_BTA_table [0:7]; 
reg [15:0] C_PC_table   [0:7]; 
reg [15:0] C_BTA_table  [0:7];
reg [15:0] BTA ;
always @(*) predicted_BTA = BTA; 
integer m=0,n=0,c=0;
always @(*) begin
    BTA = 16'bx;
	//scanning if the PC is available then gives the BTA 
	for (m = 0; m < count; m = m + 1) begin
			if (UC_PC_table[m] == (PC)) begin BTA =UC_BTA_table[m]; status =A; end
	end	
	//status is made NA  if jump instruction is not avialable in unconditional branch table	
	if (m == 0) begin
		status =NA; 
	end
//updating the PC and BTA in the unconditional branch table 
	for (n = 0; n < count; n = n + 1) begin
		if (UC_PC_table[n] == (PC)) c=1; end 
		if (Correct_BTA > 0 && c==0 ) begin
	        UC_BTA_table[count] = Correct_BTA;Correct_BTA<=0;
			UC_PC_table [count] = PC -16'd6;
			count = count + 1 ;
			c=0;
			BTA = Correct_BTA;
 			end       
end
//--------------------------------- PIPELINED REGISTER EX/MA -----------------------------------------
always @(posedge clk) begin
	PR4_result 		  <= PR3_result;
	PR4_OperandA 	  <= PR3_OperandA ;
	PR4_reg_write_en  <= PR3_reg_write_en;
	PR4_reg_write_add <= PR3_reg_write_add;
	PR4_reg_add1      <= PR3_reg_add1;
	PR4_reg_add2      <= PR3_reg_add2;
	PR4_opcode        <= PR3_opcode;
end
//==================================== MEMORY ACCESS STAGE =================================================================
reg [15:0] PR4_LM [7:0];
integer i,j=0,k;
always @(*) begin
	PR4_data = 16'bx;
	case(PR4_opcode)
		//for LOAD WORD instruction 
    	4'b0100: begin PR4_data={data_mem[PR4_result],data_mem[PR4_result+1]}; end
		4'b0110 : begin//load multiple LM
			k<=0;
			//loading consecutive data from the data memory into corresponding register which is set in immediate field
			for (i = 0; i < 8; i = i + 1) begin
				if(PR4_result[7-i]== 1'b1) begin 
					PR4_LM [i] <= {data_mem[PR4_OperandA +(2*k)],data_mem[PR4_OperandA+(2*k +1)]} ;
					k<=k+1;end
			end end
	endcase
end 
//-------------------------------------- PIPELINE REGISTER MA/WB ------------------------------------------------------------
always @(posedge clk) begin
	{PR5_LM[0],PR5_LM[1],PR5_LM[2],PR5_LM[3],PR5_LM[4],PR5_LM[5],PR5_LM[6],PR5_LM[7]} <= {PR4_LM[0],PR4_LM[1],PR4_LM[2],PR4_LM[3],PR4_LM[4],PR4_LM[5],PR4_LM[6],PR4_LM[7]} ;
	PR5_data          <= PR4_data;
	PR5_result        <= PR4_result;
	PR5_OperandA      <= PR4_OperandA;
	PR5_reg_write_en  <= PR4_reg_write_en;
	PR5_reg_write_add <= PR4_reg_write_add;
	PR5_opcode        <= PR4_opcode;
	PR5_reg_add1      <= PR4_reg_add1;
	PR5_reg_add2      <= PR4_reg_add2;
	//updating PC 
		//updating pc if jump instruction is occured using unconditional branch table 
if (predicted_BTA >0)  reg_array[0] <= predicted_BTA; 
else begin
		//updating PC if branch or jump has not occured 	
	if (flush) begin reg_array[0] <= PR3_result ; flush<=1'b0; end
	else begin
		if (NOP > 0) begin stall <= 1'b0;NOP <= NOP - 2'b1; end
		else begin 
			stall <= 1'b0;
			NOP <=2'b0;
			case (PR4_opcode)  
				4'b1000 : begin if (PR4_result > 0)  reg_array[0] <= PR4_result;
								else reg_array[0] <= reg_array[0]  + 16'h0002;end
				4'b1001 : begin if (PR4_result > 0)  reg_array[0] <= PR4_result;
								else reg_array[0] <= reg_array[0]  + 16'h0002; end
				4'b1010 : begin if (PR4_result > 0)  reg_array[0] <= PR4_result;
								else reg_array[0] <= reg_array[0]  + 16'h0002; end
				4'b1100 : begin reg_array[PR4_reg_write_add] <= reg_array[0] + 16'h0002 ;
									 reg_array[0] <= PR4_result; end
				4'b1101 : begin reg_array[PR4_reg_write_add] <= reg_array[0] + 16'h0002 ; 
									 reg_array[0] <= PR4_OperandA; end
				4'b1111 : begin reg_array[PR4_reg_write_add] <= PR4_result; end
				default : reg_array[0] <= reg_array[0] + 16'h0002;
			endcase
		end end end
end

//============================= WRITE BACK STAGE =========================================================

always @(*) begin
	RF_write_en = 1'bx;
	RF_write_dest = 3'bx;
	RF_write_data = 16'bx;
	casex(PR5_opcode)
		4'b00xx: begin
			RF_write_en <= PR5_reg_write_en;
			RF_write_dest <= PR5_reg_write_add;
			RF_write_data <= PR5_result; end 
      	4'b0100: begin
			RF_write_en <= PR5_reg_write_en;
			RF_write_dest <= PR5_reg_write_add;
			RF_write_data <= PR5_data; end
	 	4'b0101: begin {data_mem[PR5_result],data_mem[PR5_result+1]} <= {PR5_OperandA[15:8],PR5_OperandA[7:0]} ; end
		4'b0110 : begin
			if (PR5_LM[0] > 0) reg_array[0] <= PR5_LM[0];
			if (PR5_LM[1] > 0) reg_array[1] <= PR5_LM[1];
			if (PR5_LM[2] > 0) reg_array[2] <= PR5_LM[2];
			if (PR5_LM[3] > 0) reg_array[3] <= PR5_LM[3];
			if (PR5_LM[4] > 0) reg_array[4] <= PR5_LM[4];
			if (PR5_LM[5] > 0) reg_array[5] <= PR5_LM[5];
			if (PR5_LM[6] > 0) reg_array[6] <= PR5_LM[6];	
			if (PR5_LM[7] > 0) reg_array[7] <= PR5_LM[7]; end
		4'b0111 : begin
		
		for (i = 0; i < 8; i = i + 1) begin
			if (PR5_result[7-i] ==1'b1) begin {data_mem[PR5_OperandA+(2*j)],data_mem[PR5_OperandA+(2*j+1)]} <= {reg_array[j][15:8],reg_array[j][7:0] };
			j=j+1; end	end end
	endcase  
end 
endmodule