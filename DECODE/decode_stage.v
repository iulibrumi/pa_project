module decode #(parameter ROB_REG_SIZE=41)(
  //common inputs
  input clk,   //the clock is the same for ev.
  input reset, //the reset is the same for everyone
  
  //fetch outputs
  output reg [1:0]  sel_pc,   //pc selection for fetch stage
  output [15:0]     branch_pc,//where fetch should jump if branch done 

  //enable_pc= enable_pc_opA | enable_pc_opB
  output        enable_pc,
    
  //alu outputs
  //forward
  output [15:0] pc_output,
  output ticketWE_output,

  
  //bypass mux
  output [15:0]     regA,
  output [15:0]     regB,
    
  //data to store
  output [15:0]     dataReg,
  output reg [1:0] ldSt_enable,
  
  //fixed
  output reg [3:0]      cop,
  output [2:0]      destReg_addr,
  output reg        writeEnableALU,
  
  //output to BYPASS ROB  
  output reg[2:0]   bypass_rob_addr,
  output reg[2:0]   bypass_rob_data,
  output reg        bypass_rob_we,
  
  output reg[2:0]   bypass_rob_read_porta,
  output reg[2:0]   bypass_rob_read_portb,
  
  //output to FSTAGES: look in fstages for opa and opb
  output reg[2:0]   opa_addr_fstages,
  output reg[2:0]   opb_addr_fstages,
    
  //enable PIPELINE 
  output reg        enableALU,
  output reg        enableFSTAGES,

  //logic dependent
  output reg[8:0]      inmed,
  output reg [1:0]  bp_output,

  //control
  output        clean_alu,  
  
  //output to ROB
  output tail_rob_increment_enable,

  //inputs from fetch
  input[15:0]pc_input,

  //inputs from ALU
  input[2:0]destReg_addrALU,
  input[15:0]alu_result,
  input[1:0] bp_ALU,
  input[2:0] ticketALU, 
  
  //inputs from TLB
  input[2:0]destReg_addrTLB,
  input[15:0]tlblookup_result,
  input[1:0] bp_TLB,
  input[2:0] ticketTLB, 
  
  //inputs from CACHE
  input[2:0]destReg_addrCACHE,
  input[15:0]cache_result,
  input[1:0] bp_CACHE,
  input[2:0] ticketCACHE, 

  //inputs from WB
  input[2:0]destReg_addrWB,
  input[15:0]wb_result,
  input[1:0] bp_WB,
  input[2:0] ticketWB, 

  //inputs from ROB
  input [2:0] tail_rob_input,
  input       rob_empty,
  
  input [15:0] dROB,
  input [2:0] writeAddrROB,
  input writeEnableROB,
  
  input [ROB_REG_SIZE-1:0] bypass_rob_opa,
  input [ROB_REG_SIZE-1:0] bypass_rob_opb,
  
  //Exception info
  input [15:0] ex_pc,
  input [15:0] ex_dTLB,
  input [1:0]  ex_vectorROB,

  //from ROB_BYPASS STRUCTURE
  input [2:0] updated_ticket_opa,
  input [2:0] updated_ticket_opb,

  //from FSTAGES
  input [1:0] bypass_here_ready_a,
  input [1:0] bypass_here_ready_b,
  input [15:0] bypass_data_fstages,
  
  //EX
  input[15:0]instruction_code_a,
  input[1:0]  ex_vector_input_a,
  output[1:0] ex_vector_output
  
);
  
  reg [1:0] sel_pc_aux;
  
  //EXCEPTIONS
  wire [15:0] instruction_code;
  wire [1:0]  ex_vector_input;
  reg Ex_sel;
  
  mux2 #(16) my_Exmux(
  .a(instruction_code_a),
  .b(16'h0000),
  .sel(Ex_sel),
  .out(instruction_code)
  );
  
  mux2 #(2) my_Exmux_2(
  .a(ex_vector_input_a),
  .b(2'b10),
  .sel(Ex_sel),
  .out(ex_vector_input)
  );
  
  always @(*)
  begin
    if(instruction_code_a[15:12]==4'b1111)begin
        Ex_sel<=1'b1;
    end
    else begin
        Ex_sel<=1'b0;
    end
  end
  
  
  
  //Used for enable/disable the ROB tail increment
  reg        inst_needs_ticket;
  reg        inst_needs_ticket_2;
    
  reg        enable_pc_a;
  reg        enable_pc_b;
  reg        enable_pc_reset;
  
  reg        clean_alu_a;
  reg        clean_alu_b;  
  reg        clean_alu_reset;  
  
  reg[2:0]    operating_a;
  reg[2:0]    operating_b;
  wire [15:0]   q_instruction_code;
  wire [15:0]   regAWire;
  wire [15:0]   regBWire;
  
  reg[2:0]      sel_bypass_a;
  reg[2:0]      sel_bypass_b;
  reg           enable_decode_a;
  reg           enable_decode_b;
  reg           enable_decode_reset;
  reg           clean_instruction_code;
  
  
  // maybe the ALU shouldn't see the instruction code  
  //assign cop = q_instruction_code[15:12]; 
  assign destReg_addr = q_instruction_code[11:9];

  // goes to FETCH. The other inputs to the PC have their source in fetch.
  assign branch_pc =regB; 
  //data for STORE comes from regB
  assign dataReg =regB; 

  assign enable_pc= (enable_pc_a & enable_pc_b & enable_pc_reset);
  assign clean_alu= clean_alu_a | clean_alu_b | clean_alu_reset;
  
  //ROB tail enable
  //assign tail_rob_increment_enable= enable_decode_a & enable_decode_b & writeEnableALU;
  assign tail_rob_increment_enable= enable_decode_a & enable_decode_b &inst_needs_ticket_2;
  
  assign ticketWE_output=inst_needs_ticket_2;
  register #(34) decode_register(
    .clk(clk),
    .enable(enable_decode_a & enable_decode_b), //the enable is generated by the decode itself
    .reset(reset & ~clean_instruction_code),
    .d({instruction_code, pc_input, ex_vector_input}),
    .q({q_instruction_code, pc_output, ex_vector_output})
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
  .d(dROB),
  .writeAddr(writeAddrROB),
  .writeEnable(writeEnableROB)


);

//ddavila: MUXs for BYPASS

  mux8 mux_bypass_a(
  .a(regAWire),           //Register File
  .b(alu_result),
  .c(tlblookup_result),
  .d(cache_result),
  .e(wb_result),

  .f(bypass_data_fstages), //FSTAGE 6
  .g(bypass_rob_opa[ROB_REG_SIZE-4:ROB_REG_SIZE-19]),      //ROB

  .h(16'hxxxx),
  .sel(sel_bypass_a),
  .out(regA)
  );
  
  mux8 mux_bypass_b(
  .a(regBWire),
  .b(alu_result),
  .c(tlblookup_result),
  .d(cache_result),
  .e(wb_result),
  
  .f(bypass_data_fstages), //FSTAGE 6
  .g(bypass_rob_opb[ROB_REG_SIZE-4:ROB_REG_SIZE-19]),

  .h(16'hxxxx),
  .sel(sel_bypass_b),
  .out(regB)
  );  
  
  
  always @(*)
  begin
    if (reset == 0)begin
      sel_pc <= 2'b00; //select the initial address if we're in reset
      clean_alu_reset<=0;
      enable_decode_reset<=1;
      enable_pc_reset<= 1;
    end
    else begin
      sel_pc <= sel_pc_aux;
    end
  end

 
      
     


  //BYPASSES
  always @(*)
  begin
     //OPERATING A
      case(cop)
        //ADD, SUB, CMP, BNZ, LD
        4'b0001, 4'b0010, 4'b0100, 4'b0101, 4'b0110:
          //if my operating is in ALU and is NOT a NOP
          if(operating_a==destReg_addrALU & ticketALU==updated_ticket_opa & bp_ALU!=2'b00)begin
            if(bp_ALU==2'b01)begin // result is at ALU
              sel_bypass_a<= 3'b001;
              clean_alu_a<=0;
              enable_decode_a<=1;
              enable_pc_a<= 1;
            end
            else if(bp_ALU==2'b10)begin //result will be at CACHE
              //stop pipeline and insert a bubble
              clean_alu_a<=1;
              enable_decode_a<=0;
              enable_pc_a<=0;
            end
          end
        else 
          
          if(operating_a == destReg_addrTLB & ticketTLB==updated_ticket_opa & bp_TLB!=2'b00)begin
            if(bp_TLB==2'b01)begin // result is at TLB
              sel_bypass_a<= 3'b010;
              clean_alu_a<=0;
              enable_decode_a<=1;
              enable_pc_a<= 1;
            end
            else if(bp_TLB==2'b10)begin //result is at CACHE
              //stop pipeline and insert a bubble
              clean_alu_a<=1;
              enable_decode_a<=0;
              enable_pc_a<=0;
            end
          end
        else 
          
          if(operating_a == destReg_addrCACHE & ticketCACHE==updated_ticket_opa & bp_CACHE!=2'b00)begin
              sel_bypass_a<= 3'b011;
              clean_alu_a<=0;
              enable_decode_a<=1;
              enable_pc_a<= 1;
          end
        else
          if(operating_a == destReg_addrWB & ticketWB==updated_ticket_opa & bp_WB!=2'b00)begin
              sel_bypass_a<= 3'b100;
              clean_alu_a<=0;
              enable_decode_a<=1;
              enable_pc_a<= 1;
          end
        else
          
          //FSTAGES
          if(bypass_here_ready_a==2'b11)begin
              sel_bypass_a<= 3'b101;
              clean_alu_a<=0;
              enable_decode_a<=1;
              enable_pc_a<= 1;
            end
            else if(bypass_here_ready_a==2'b10)begin //result will be at las stage
              //stop pipeline and insert a bubble
              clean_alu_a<=1;
              enable_decode_a<=0;
              enable_pc_a<=0;
            end
        else 
        
         //ROB
          if(operating_a==bypass_rob_opa[ROB_REG_SIZE-1:ROB_REG_SIZE-3] & bypass_rob_opa[ROB_REG_SIZE-20]==1'b1)begin
              sel_bypass_a<= 3'b110;
              clean_alu_a<=0;
              enable_decode_a<=1;
              enable_pc_a<= 1;
          end
           
        //NO BYPASS NEEDED
        else begin
          sel_bypass_a<= 3'b000;
          clean_alu_a<=0;
          enable_decode_a<=1;
          enable_pc_a<= 1;
        end
        default : begin
                  sel_bypass_a<= 3'b000;
                  clean_alu_a<=0;
                  enable_decode_a<=1;
                  enable_pc_a<= 1;
                  end
      endcase
    
        
  end
  
  
  
  
  //BYPASSES
  always @(*)
  begin
     //OPERATING B
      case(cop)
        //ADD, SUB, CMP, BNZ
        4'b0001, 4'b0010, 4'b0100, 4'b0101:
          //if my operating is in ALU and is NOT a NOP
          if(operating_b==destReg_addrALU & ticketALU==updated_ticket_opb & bp_ALU!=2'b00)begin
            if(bp_ALU==2'b01)begin // result is at ALU
              sel_bypass_b<= 3'b001;
              clean_alu_b<=0;
              enable_decode_b<=1;
              enable_pc_b<= 1;
            end
            else if(bp_ALU==2'b10)begin //result will be at CACHE
              //stop pipeline and insert a bubble
              clean_alu_b<=1;
              enable_decode_b<=0;
              enable_pc_b<=0;
            end
          end
        else 
          
          if(operating_b == destReg_addrTLB & ticketTLB==updated_ticket_opb & bp_TLB!=2'b00)begin
            if(bp_TLB==2'b01)begin // result is at TLB
              sel_bypass_b<= 3'b010;
              clean_alu_b<=0;
              enable_decode_b<=1;
              enable_pc_b<= 1;
            end
            else if(bp_TLB==2'b10)begin //result is at CACHE
              //stop pipeline and insert a bubble
              clean_alu_b<=1;
              enable_decode_b<=0;
              enable_pc_b<=0;
            end
          end
        else 
          
          if(operating_b == destReg_addrCACHE & ticketCACHE==updated_ticket_opb & bp_CACHE!=2'b00)begin
              sel_bypass_b<= 3'b011;
              clean_alu_b<=0;
              enable_decode_b<=1;
              enable_pc_b<= 1;
          end
        else
          if(operating_b == destReg_addrWB & ticketWB==updated_ticket_opb & bp_WB!=2'b00)begin
              sel_bypass_b<= 3'b100;
              clean_alu_b<=0;
              enable_decode_b<=1;
              enable_pc_b<= 1;
          end
        else
          
          //FSTAGES
          if(bypass_here_ready_b==2'b11)begin
              sel_bypass_b<= 3'b101;
              clean_alu_b<=0;
              enable_decode_b<=1;
              enable_pc_b<= 1;
            end
            else if(bypass_here_ready_b==2'b10)begin //result will be at las stage
              //stop pipeline and insert a bubble
              clean_alu_b<=1;
              enable_decode_b<=0;
              enable_pc_b<=0;
            end
        else 
        
         //ROB
          if(operating_b==bypass_rob_opb[ROB_REG_SIZE-1:ROB_REG_SIZE-3]& bypass_rob_opb[ROB_REG_SIZE-20]==1'b1)begin
              sel_bypass_b<= 3'b110;
              clean_alu_b<=0;
              enable_decode_b<=1;
              enable_pc_b<= 1;
          end
           
        //NO BYPASS NEEDED
        else begin
          sel_bypass_b<= 3'b000;
          clean_alu_b<=0;
          enable_decode_b<=1;
          enable_pc_b<= 1;
        end
        
        4'b0111: //STORE
          if(rob_empty==1)begin
            $display("ST: continue");
            sel_bypass_b<= 3'b000;
            clean_alu_b<=0;
            enable_decode_b<=1;
            enable_pc_b<= 1;
          end
          else begin
              //stop pipeline and insert a bubble
              $display("ST: stop");
              clean_alu_b<=1;
              enable_decode_b<=0;
              enable_pc_b<=0;
          end
          
        default : begin
                  sel_bypass_b<= 3'b000;
                  clean_alu_b<=0;
                  enable_decode_b<=1;
                  enable_pc_b<= 1;
                  end
      endcase
  end
    

  //read bypass information from ROB an FSTAGE
  always @(*)
  begin
    bypass_rob_read_porta<=operating_a;
    bypass_rob_read_portb<=operating_b;
    opa_addr_fstages<=operating_a;
    opb_addr_fstages<=operating_b;
  end

  //UPDATE THE VALUE oF ROB_BYPASS STRUCTURE
  always @(*)begin
    if(writeEnableALU==1 & enable_decode_a & enable_decode_b)begin
      bypass_rob_addr<=destReg_addr;
      bypass_rob_data<=tail_rob_input;
      bypass_rob_we<=1'b1;
    end
    else begin
      bypass_rob_addr<=0'b000;
      bypass_rob_data<=0'b000;
      bypass_rob_we<=1'b0;
    end
  end
    
  //INSTRUCTION DETAILS
  always @(*)
  begin
    cop<=q_instruction_code[15:12];
    if(cop==4'b0110 | cop == 4'b0111)
      inmed <= {3'b000, q_instruction_code[5:0]};
    else
      inmed <= q_instruction_code[8:0];

    operating_a<=q_instruction_code[8:6];
    case(cop)//cop
      4'b0101 : begin //BRANCH
                  //if needed to branch  
                  operating_b<=q_instruction_code[2:0];
                  ldSt_enable<=2'b00;
                  if(regA==16'b0000000000000000)begin
                    sel_pc_aux<=2'b01;
                    clean_instruction_code<=0;      
                  end
                  else begin
                    sel_pc_aux<=2'b10;
                    clean_instruction_code<=1;
                  end
                end
                
      4'b0111 : begin //STORE
                  operating_b<=q_instruction_code[11:9];
                  ldSt_enable<=2'b01;
                  clean_instruction_code<=0;
                  sel_pc_aux<=1;
                end
                
      4'b0110 : begin //LOAD
                  operating_b<=q_instruction_code[2:0];
                  ldSt_enable<=2'b10;
                  clean_instruction_code<=0;
                  sel_pc_aux<=1;
                end

      default : begin 
                  operating_b<=q_instruction_code[2:0];
                  ldSt_enable<=2'b00;
                  clean_instruction_code<=0;
                  sel_pc_aux<=1;
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
      4'b0000 : writeEnableALU <= 0;
      4'b0001 : writeEnableALU <= 1;
      4'b0010 : writeEnableALU <= 1;
      4'b0011 : writeEnableALU <= 1;
      4'b0100 : writeEnableALU <= 1; 
      4'b0101 : writeEnableALU <= 0; 
      4'b0110 : writeEnableALU <= 1;       
      4'b0111 : writeEnableALU <= 0;
      4'b1000 : writeEnableALU <= 1;
      default : writeEnableALU <= 0; 
    endcase
   
  end
  
  
  
  always @(*)
  begin
    //ROB tail increment enable, almost same case as WE.
    case(q_instruction_code[15:12])
      4'b0000 : if(ex_vector_output!=2'b00)begin
                  inst_needs_ticket_2 <= 1;
                end
                else begin
                  inst_needs_ticket_2 <= 0;
                end
      4'b0001 : inst_needs_ticket_2 <= 1;
      4'b0010 : inst_needs_ticket_2 <= 1;
      4'b0011 : inst_needs_ticket_2 <= 1;
      4'b0100 : inst_needs_ticket_2 <= 1; 
      4'b0101 : inst_needs_ticket_2 <= 0; 
      4'b0110 : inst_needs_ticket_2 <= 1;       
      4'b0111 : inst_needs_ticket_2 <= 1;
      4'b1000 : inst_needs_ticket_2 <= 1;
      default : inst_needs_ticket_2 <= 0; 
    endcase
  
  end
  
  
  //SELECT one PIPELINE
  always @(*)
  begin
    if(q_instruction_code[15:12]== 4'b1000)begin
      enableFSTAGES<=1;
      enableALU<=0;
    end
  else begin
      enableFSTAGES<=0;
      enableALU<=1;
    end
      
  end

endmodule

