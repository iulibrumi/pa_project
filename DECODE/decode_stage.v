module decode(
  //common inputs
  input clk,   //the clock is the same for ev.
  input reset, //the reset is the same for everyone
  
  //inputs from fetch
  input[15:0]instruction_code,
  
  //fetch outputs
  output reg [1:0]  sel_pc,   //pc selection for fetch stage
  output [15:0]     branch_pc,//where fetch should jump if branch done 
  output reg        enable_pc,
    
  //alu outputs
  //bypass mux
  output [15:0]     regA,
  output [15:0]     regB,
  
  //data to store
  output [15:0]     dataReg,
  output reg [1:0] ldSt_enable,
  
  //fixed
  output [3:0]      cop,
  output [2:0]      destReg_addr,
  output reg        writeEnableALU,

  //logic dependent
  output reg[8:0]      inmed,
  output reg [1:0]  bp_output,

  //control
  output reg        clean_alu,
  
  //inputs from ALU
  input[2:0]destReg_addrALU,
  input[15:0]alu_result,
  input[1:0] bp_ALU,
  
  //inputs from TLB
  input[2:0]destReg_addrTLB,
  input[15:0]tlblookup_result,
  input[1:0] bp_TLB,
  
  //inputs from CACHE
  input[2:0]destReg_addrCACHE,
  input[15:0]cache_result,
  input[1:0] bp_CACHE,

  //inputs from WB
  input[2:0]destReg_addrWB,
  input[15:0]wb_result,
  input[1:0] bp_WB,

  input [15:0] dWB,
  input [2:0] writeAddrWB,
  input writeEnableWB //when write enable, write d into writeAddr
  
);
  
  reg[2:0]    operating_a;
  reg[2:0]    operating_b;
  wire [15:0]   q_instruction_code;
  wire [15:0]   regAWire;
  wire [15:0]   regBWire;
  
  reg[2:0]      sel_bypass_a;
  reg[2:0]      sel_bypass_b;
  reg           enable_decode;
  reg           bypass_stop_a;
  reg           bypass_stop_b;
  reg           clean_instruction_code;
  
  
  // maybe the ALU shouldn't see the instruction code  
  assign cop = q_instruction_code[15:12]; 
  assign destReg_addr = q_instruction_code[11:9];

  // goes to FETCH. The other inputs to the PC have their source in fetch.
  assign branch_pc =regA; 
  //data for STORE comes from regB
  assign dataReg =regB; 



  register #(16) decode_register(
    .clk(clk),
    .enable(enable_decode), //the enable is generated by the decode itself
    .reset(reset & ~clean_instruction_code),
    .d(instruction_code),
    .q(q_instruction_code)
  );
  
    
 register_file my_register_file(
  .clk(clk), //cambiar a i_I_address
  .reset(reset),
  //read
  .ra(operating_a),
  .rb(operating_b),
  .a(regAWire),
  .b(regBWire),
  //write
  .d(dWB),
  .writeAddr(writeAddrWB),
  .writeEnable(writeEnableWB)

);

//ddavila: MUXs for BYPASS

  mux5 mux_bypass_a(
  .a(regAWire),
  .b(alu_result),
  .c(tlblookup_result),
  .d(cache_result),
  .e(wb_result),
  .sel(sel_bypass_a),
  .out(regA)
  );
  
  mux5 mux_bypass_b(
  .a(regBWire),
  .b(alu_result),
  .c(tlblookup_result),
  .d(cache_result),
  .e(wb_result),
  .sel(sel_bypass_b),
  .out(regB)
  );  

  
  //BYPASSES
  always @(*)
  begin
     
     clean_instruction_code=0;
     clean_alu=0;
     bypass_stop_b=0;
     enable_decode<=1;
     enable_pc<= 1;
     
     if (reset == 0)begin
      sel_pc <= 2'b00; //select the initial address if we're in reset
     end
     else begin
      sel_pc <= 2'b01;

      //OPERATING A
      case(cop)
        //ADD, SUB, CMP, BNZ, LD, ST
        4'b0001, 4'b0010, 4'b0100, 4'b0101, 4'b0110, 4'b0111:
      
          if(operating_a == destReg_addrALU & bp_ALU!=2'b00)begin
            if(bp_ALU==2'b01)begin // result is at ALU
              sel_bypass_a<= 3'b001;
            end
            else if(bp_ALU==2'b10)begin //result is at CACHE
              //stop pipeline and insert a bubble
              enable_pc<=0;
              enable_decode<=0;
              clean_alu=1;
            end
          end
        else 
          
          if(operating_a == destReg_addrTLB & bp_TLB!=2'b00)begin
            if(bp_TLB==2'b01)begin // result is at TLB
              sel_bypass_a<= 3'b010;
            end
            else if(bp_TLB==2'b10)begin //result is at CACHE
              //stop pipeline and insert a bubble
              enable_pc<=0;
              enable_decode<=0;
              clean_alu=1;
            end
          end
        else 
          
          if(operating_a == destReg_addrCACHE & bp_CACHE!=2'b00)begin
              sel_bypass_a<= 3'b011;
          end
        else
          if(operating_a == destReg_addrWB & bp_WB!=2'b00)begin
              sel_bypass_a<= 3'b100;
          end
        //NO BYPASS NEEDED
        else
          sel_bypass_a<= 3'b000;
      
        default : begin
                  sel_bypass_a<= 3'b000;
                  end
      endcase
      
      //OPERATING B
      case(cop)
        //ADD, SUB, CMP, BNZ
        4'b0001, 4'b0010, 4'b0100, 4'b0101:
      
          if(operating_b == destReg_addrALU & bp_ALU!=2'b00)begin
            if(bp_ALU==2'b01)begin // result is at ALU
              sel_bypass_b<= 3'b001;
            end
            else if(bp_ALU==2'b10)begin //result is at CACHE
              //stop pipeline and insert a bubble
              enable_pc<=0;
              enable_decode<=0;
              clean_alu=1;
            end
          end
        else 
          
          if(operating_b == destReg_addrTLB & bp_TLB!=2'b00)begin
            if(bp_TLB==2'b01)begin // result is at TLB
              sel_bypass_b<= 3'b010;
            end
            else if(bp_TLB==2'b10)begin //result is at CACHE
              //stop pipeline and insert a bubble
              enable_pc<=0;
              enable_decode<=0;
              clean_alu=1;
            end
          end
        else 
          
          if(operating_b == destReg_addrCACHE & bp_CACHE!=2'b00)begin
              sel_bypass_b<= 3'b011;
          end
        else
          if(operating_b == destReg_addrWB & bp_WB!=2'b00)begin
              sel_bypass_b<= 3'b100;
          end
        //NO BYPASS NEEDED
        else
          sel_bypass_b<= 3'b000;
      
        default : begin
                  sel_bypass_b<= 3'b000;
                  end
      endcase


     end
  end

  //INSTRUCTION DETAILS
  always @(*)
  begin
    sel_bypass_b<= 3'b000;
    if(cop==4'b0110 | cop == 4'b0111)
      inmed <= {3'b000, q_instruction_code[5:0]};
    else
      inmed <= q_instruction_code[8:0];

    operating_a<=q_instruction_code[8:6];
    case(cop)//cop
      4'b0111 : begin //LOAD
                  operating_b<=q_instruction_code[11:9];
                  ldSt_enable<=2'b01;
                end
      4'b0110 : begin //STORE
                  operating_b<=q_instruction_code[2:0];
                  ldSt_enable<=2'b10;
                end

      default : begin 
                  operating_b<=q_instruction_code[2:0];
                  ldSt_enable<=2'b00;
                end
    endcase
  end
  
  
  //TRACK type of instruction for BYPASS(bp bits)
  always @(*)
  begin
    case(q_instruction_code[15:12])//cop
      4'b0000 : bp_output <= 0;
      4'b0101 : bp_output <= 0;
      4'b0111 : bp_output <= 0;
      4'b0110 : bp_output <= 2;

      default : bp_output <= 1;
    endcase
  end
     
    
  //ALU write_enable
  always @(*)
  begin
    case(q_instruction_code[15:12])
      4'b0000 : writeEnableALU = 0;
      4'b0001 : writeEnableALU = 1;
      4'b0010 : writeEnableALU = 1;
      4'b0011 : writeEnableALU = 1;
      4'b0100 : writeEnableALU = 1; 
      4'b0110 : writeEnableALU = 1;       
      4'b0111 : writeEnableALU = 0;       
      default : writeEnableALU = 1'bx; 
    endcase
  end

endmodule

