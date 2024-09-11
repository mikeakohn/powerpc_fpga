// PowerPC FPGA Soft Processor
//  Author: Michael Kohn
//   Email: mike@mikekohn.net
//     Web: https://www.mikekohn.net/
//   Board: iceFUN iCE40 HX8K
// License: MIT
//
// Copyright 2024 by Michael Kohn

module powerpc
(
  output [7:0] leds,
  output [3:0] column,
  input raw_clk,
  output eeprom_cs,
  output eeprom_clk,
  output eeprom_di,
  input  eeprom_do,
  output speaker_p,
  output speaker_m,
  output ioport_0,
  output ioport_1,
  output ioport_2,
  output ioport_3,
  input  button_reset,
  input  button_halt,
  input  button_program_select,
  input  button_0,
  output spi_clk,
  output spi_mosi,
  input  spi_miso
);

// iceFUN 8x4 LEDs used for debugging.
reg [7:0] leds_value;
reg [3:0] column_value;

assign leds = leds_value;
assign column = column_value;

// Memory bus (ROM, RAM, peripherals).
reg [15:0] mem_address = 0;
reg [31:0] mem_write = 0;
reg [3:0] mem_write_mask = 0;
wire [31:0] mem_read;
//wire mem_data_ready;
reg mem_bus_enable = 0;
reg mem_write_enable = 0;

//wire [7:0] mem_debug;

// Clock.
reg [21:0] count = 0;
reg [4:0] state = 0;
reg [19:0] clock_div;
reg [14:0] delay_loop;
wire clk;
assign clk = clock_div[1];

// Registers.
reg [31:0] registers [31:0];
reg [15:0] pc = 0;
reg signed [15:0] pc_current = 0;

// [ lt 0, gt 0, eq 0, so ]
reg [31:0] cr;
reg [3:0]  cr_result;
reg [3:0]  affects_cr;

wire [3:0] cr_value;
assign cr_value[3] = cr[28];
assign cr_value[2] = cr[29];
assign cr_value[1] = cr[30];
assign cr_value[0] = cr[31];

// [ so, ov, ca ]
reg [31:0] xer;
reg [3:0]  affects_xer;

reg [15:0] lr;
reg [31:0] ctr;

// Probably not needed here?
//reg [31:0] ssr0;
//reg [31:0] ssr1;

// Instruction
reg [31:0] instruction;
wire [5:0] opcode;
wire [8:0] subopcode;
wire [9:0] subopcode_10;
wire [4:0] rd;
wire [4:0] ra;
wire [4:0] rb;
wire [15:0] uimm;
wire signed [15:0] simm;
wire rc;
wire oe;
wire lk;
wire aa;
wire [4:0] bo;
wire [4:0] bi;
wire signed [15:0] bd;
wire signed [25:0] li;
wire signed [15:0] st_offset;
wire [2:0] crfd;
wire [5:0] crbd;
wire [5:0] crba;
wire [5:0] crbb;

//reg [4:0] crfd_offset;

assign opcode    = instruction[31:26];
assign rd        = instruction[25:21];
assign ra        = instruction[20:16];
assign rb        = instruction[15:11];
assign subopcode = instruction[9:1];
assign subopcode_10 = instruction[10:1];
assign uimm      = instruction[15:0];
assign simm      = instruction[15:0];
assign rc        = instruction[0];
assign oe        = instruction[10];
assign lk        = instruction[0];
assign aa        = instruction[1];
assign bo        = instruction[25:21];
assign bi        = instruction[20:16];
assign bd        = { instruction[15:2], 2'b00 };
assign li        = { instruction[25:2], 2'b00 };
assign st_offset = $signed(instruction[15:0]);
assign crfd      = instruction[25:23];
assign crbd      = instruction[26:21];
assign crba      = instruction[20:16];
assign crbb      = instruction[15:11];

reg [2:0] st_size;

// ALU temporary registers.
reg signed [31:0] source;
reg signed [31:0] temp;
reg signed [32:0] result;

reg [3:0] alu_op;
reg imm_is_shifted;

// Load / Store / Branch.
//assign memory_size = instruction[14:12];
reg [15:0] ea;
reg [15:0] branch_ea;
reg update_ea;

wire conditional;
//assign conditional = (cr_value & bi) == bi;
assign conditional = cr_value[bi];

// Eeprom.
reg [10:0] eeprom_count;
wire [7:0] eeprom_data_out;
reg  [7:0] eeprom_holding [3:0];
reg [10:0] eeprom_address;
reg [15:0] eeprom_mem_address;
reg eeprom_strobe = 0;
wire eeprom_ready;

// Debug.
//reg [7:0] debug_0 = 0;
//reg [7:0] debug_1 = 0;
//reg [7:0] debug_2 = 0;
//reg [7:0] debug_3 = 0;

parameter STATE_RESET        = 0;
parameter STATE_DELAY_LOOP   = 1;
parameter STATE_FETCH_OP_0   = 2;
parameter STATE_FETCH_OP_1   = 3;
parameter STATE_START_DECODE = 4;
parameter STATE_TRAP         = 5;
parameter STATE_LOAD_0       = 6;
parameter STATE_LOAD_1       = 7;

parameter STATE_STORE_0      = 8;
parameter STATE_STORE_1      = 9;

parameter STATE_ALU_IMM      = 10;
parameter STATE_ALU_REG      = 11;
parameter STATE_ALU_SHIFT    = 12;
parameter STATE_ALU_LOGIC    = 13;
parameter STATE_ALU_0        = 14;
parameter STATE_ALU_1        = 15;
parameter STATE_CMP_U_0      = 16;
parameter STATE_CMP_S_0      = 17;
parameter STATE_CMP_SAVE     = 18;

parameter STATE_BRANCH_1     = 19;

parameter STATE_EEPROM_START = 24;
parameter STATE_EEPROM_READ  = 25;
parameter STATE_EEPROM_WAIT  = 26;
parameter STATE_EEPROM_WRITE = 27;
parameter STATE_EEPROM_DONE  = 28;
parameter STATE_DEBUG        = 29;
parameter STATE_ERROR        = 30;
parameter STATE_HALTED       = 31;

parameter ALU_OP_ADD   = 0;
parameter ALU_OP_AND   = 1;
parameter ALU_OP_NOR   = 2;
parameter ALU_OP_SUB   = 3;
parameter ALU_OP_XOR   = 4;
parameter ALU_OP_OR    = 5;
parameter ALU_OP_SLL   = 6;
parameter ALU_OP_SRL   = 7;
parameter ALU_OP_SRA   = 8;
parameter ALU_OP_ADD_C = 9;
parameter ALU_OP_OR_C  = 10;
parameter ALU_OP_NAND  = 11;
parameter ALU_OP_EQV   = 12;

wire is_sub;
wire overflow;
assign is_sub = alu_op == ALU_OP_SUB;
assign overflow = (source[31] ^ is_sub) == temp[31] && result[31] != temp[31];

parameter ALU_CR_LT = 3;
parameter ALU_CR_GT = 2;
parameter ALU_CR_EQ = 1;
parameter ALU_CR_SO = 0;

parameter ALU_XER_SO = 3;
parameter ALU_XER_OV = 2;
parameter ALU_XER_CA = 1;

/*
function signed [31:0] sign12(input signed [11:0] data);
  sign12 = data;
endfunction
*/

// This block is simply a clock divider for the raw_clk.
always @(posedge raw_clk) begin
  count <= count + 1;
  clock_div <= clock_div + 1;
end

// Debug: This block simply drives the 8x4 LEDs.
always @(posedge raw_clk) begin
  case (count[9:7])
    3'b000: begin column_value <= 4'b0111; leds_value <= ~registers[6][7:0]; end
    3'b010: begin column_value <= 4'b1011; leds_value <= ~registers[6][15:8]; end
    3'b100: begin column_value <= 4'b1101; leds_value <= ~pc[7:0]; end
    3'b110: begin column_value <= 4'b1110; leds_value <= ~state; end
    default: begin column_value <= 4'b1111; leds_value <= 8'hff; end
  endcase
end

// This block is the main CPU instruction execute state machine.
always @(posedge clk) begin
  if (!button_reset)
    state <= STATE_RESET;
  else if (!button_halt)
    state <= STATE_HALTED;
  else
    case (state)
      STATE_RESET:
        begin
          mem_address <= 0;
          mem_write_enable <= 0;
          mem_write <= 0;
          instruction <= 0;
          delay_loop <= 12000;
          lr <= 0;
          ctr <= 0;
          cr <= 0;
          xer <= 0;
          //eeprom_strobe <= 0;
          state <= STATE_DELAY_LOOP;
        end
      STATE_DELAY_LOOP:
        begin
          // This is probably not needed. The chip starts up fine without it.
          if (delay_loop == 0) begin

            // If button is not pushed, start rom.v code otherwise use EEPROM.
            if (button_program_select) begin
              pc <= 16'h4000;
              state <= STATE_FETCH_OP_0;
            end else begin
              pc <= 16'hc000;
              state <= STATE_EEPROM_START;
            end
          end else begin
            delay_loop <= delay_loop - 1;
          end
        end
      STATE_FETCH_OP_0:
        begin
          //registers[0] <= 0;
          update_ea <= 0;
          alu_op <= ALU_OP_ADD;
          imm_is_shifted <= 0;
          affects_cr <= 0;
          affects_xer <= 0;
          mem_bus_enable <= 1;
          mem_write_enable <= 0;
          mem_address <= pc;
          pc_current = pc;
          pc <= pc + 4;
          state <= STATE_FETCH_OP_1;
        end
      STATE_FETCH_OP_1:
        begin
          mem_bus_enable <= 0;
          instruction <= mem_read;
          state <= STATE_START_DECODE;
        end
      STATE_START_DECODE:
        begin
          case (opcode)
             3:
              begin
                // twi (Trap word immediate).
                state <= STATE_TRAP;
              end
             8:
              begin
                // subfic (SUB immediate carrying).
                alu_op <= ALU_OP_SUB;
                affects_xer[ALU_XER_CA] <= 1;
                state <= STATE_ALU_IMM;
              end
            10:
              begin
                // cmpli (CMP logical immediate).
                temp <= uimm;
                state <= STATE_CMP_U_0;
              end
            11:
              begin
                // cmpi (CMP immediate).
                temp <= simm;
                state <= STATE_CMP_S_0;
              end
            12:
              begin
                // addic (ADD immediate carrying).
                affects_xer[ALU_XER_CA] <= 1;
                state <= STATE_ALU_IMM;
              end
            13:
              begin
                // addic. (ADD immediate carrying and record).
                affects_cr = 4'hf;
                affects_xer[ALU_XER_CA] <= 1;
                state <= STATE_ALU_IMM;
              end
            14:
              begin
                // addi (ADD immediate).
                state <= STATE_ALU_IMM;
              end
            15:
              begin
                // addis (ADD immediate shifted).
                imm_is_shifted <= 1;
                state <= STATE_ALU_IMM;
              end
            16:
              begin
                // Branch Conditional: bc, bca, bcl, bcla.
                if (aa == 0)
                  branch_ea <= pc_current + bd;
                else
                  branch_ea <= bd;

                if (lk == 1) lr <= pc;
                if (bo[2] == 0) ctr <= ctr - 1;
                state <= STATE_BRANCH_1;
              end
            18:
              begin
                // Branch: b, ba, bl, bla.
                if (aa == 0)
                  pc <= pc_current + li;
                else
                  pc <= li;

                if (lk == 1) lr <= pc;
                state <= STATE_FETCH_OP_0;
              end
            19:
              begin
                // Branch Condition to CTR: bcctr, bcctrl. (opcode  16)
                // Branch Condition to LR: bclr, bclrl.    (opcode 528)
                if (opcode == 16)
                  branch_ea <= ctr;
                else
                  branch_ea <= lr;

                if (bo[2] == 0) ctr <= ctr - 1;
                state <= STATE_BRANCH_1;
              end
            24:
              begin
                // ori (OR immediate).
                alu_op <= ALU_OP_OR;
                state <= STATE_ALU_IMM;
              end
            25:
              begin
                // oris (OR immediate shifted).
                alu_op <= ALU_OP_OR;
                imm_is_shifted <= 1;
                state <= STATE_ALU_IMM;
              end
            26:
              begin
                // xori (XOR immediate).
                alu_op <= ALU_OP_XOR;
                state <= STATE_ALU_IMM;
              end
            27:
              begin
                // xoris (XOR immediate shifted).
                alu_op <= ALU_OP_XOR;
                imm_is_shifted <= 1;
                state <= STATE_ALU_IMM;
              end
            28:
              begin
                // andi. (AND immediate).
                alu_op <= ALU_OP_AND;
                affects_cr = 4'hf;
                state <= STATE_ALU_IMM;
              end
            29:
              begin
                // andis. (AND immediate shifted).
                alu_op <= ALU_OP_AND;
                affects_cr = 4'hf;
                imm_is_shifted <= 1;
                state <= STATE_ALU_IMM;
              end
            31:
              begin
              case (subopcode)
                0:
                  begin
                    // cmp (CMP).
                    temp <= registers[rb];
                    state <= STATE_CMP_S_0;
                  end
                4:
                  begin
                    // tw (TRAP word).
                    state <= STATE_TRAP;
                  end
                8:
                  begin
                    // subfc, subfc., subfco, subfco. (SUB carrying).
                    alu_op = ALU_OP_SUB;
                    affects_xer[ALU_XER_CA] <= 1;
                    state <= STATE_ALU_REG;
                  end
                10:
                  begin
                    // addc, addc., addco, addco.
                    affects_xer[ALU_XER_CA] <= 1;
                    state <= STATE_ALU_REG;
                  end
                23:
                  begin
                    // lwzx (Load word and zero indexed).
                    if (ra != 0)
                      ea <= $signed(registers[ra]) + registers[rb];
                    else
                      ea <= registers[rb];

                    st_size <= 3'b010;
                    state <= STATE_LOAD_0;
                  end
                24:
                  begin
                    // slw, slw. (Shift left word).
                    alu_op = ALU_OP_SLL;
                    //affects_xer[ALU_XER_CA] <= 1;
                    state <= STATE_ALU_LOGIC;
                  end
                28:
                  begin
                    // and (AND).
                    alu_op = ALU_OP_AND;
                    state <= STATE_ALU_LOGIC;
                  end
/*
                31:
                  begin
                    // ?.
                    alu_op = ALU_OP_ADD_C;
                    affects_xer[ALU_XER_CA] <= 1;
                    state <= STATE_ALU_REG;
                  end
*/
                32:
                  begin
                    // cmpl (Compare logical).
                    temp <= registers[rb];
                    state <= STATE_CMP_U_0;
                  end
                33:
                  begin
                    // crnor crbD, crbA, crbB
                    cr[crbd] <= ~(cr[crba] | cr[crbb]);
                    state <= STATE_FETCH_OP_0;
                  end
                40:
                  begin
                    // subf, subf., subfo, subfo. (SUB from).
                    alu_op = ALU_OP_SUB;
                    state <= STATE_ALU_REG;
                  end
                55:
                  begin
                    // lwzux (Load word and zero with update indexed).
                    if (ra != 0)
                      ea <= $signed(registers[ra]) + registers[rb];
                    else
                      ea <= registers[rb];

                    st_size <= 3'b010;
                    state <= STATE_LOAD_0;
                  end
                87:
                  begin
                    // lbzx (Load byte and zero indexed).
                    if (ra != 0)
                      ea <= $signed(registers[ra]) + registers[rb];
                    else
                      ea <= registers[rb];

                    st_size <= 3'b000;
                    state <= STATE_LOAD_0;
                  end
                104:
                  begin
                    // neg, neg., nego, nego. (Negate).
                    if (rc == 1) affects_cr = 4'hf;
                    if (oe == 1)
                      xer[30] = (registers[ra] == 32'h8000_0000 &&
                                -registers[ra] == 32'h8000_0000);

                    result = -registers[ra];
                    state <= STATE_ALU_1;
                  end
                119:
                  begin
                    // lbzux (Load byte and zero with update indexed).
                    if (ra != 0)
                      ea <= $signed(registers[ra]) + registers[rb];
                    else
                      ea <= registers[rb];

                    st_size <= 3'b000;
                    state <= STATE_LOAD_0;
                  end
                124:
                  begin
                    // nor, nor. (NOR).
                    alu_op = ALU_OP_NOR;
                    state <= STATE_ALU_REG;
                  end
                129:
                  begin
                    // crandc crbD, crbA, crbB
                    cr[crbd] <= cr[crba] & ~cr[crbb];
                    state <= STATE_FETCH_OP_0;
                  end
                144:
                  begin
                    // mtcrf CRM, rS
                    if (instruction[19]) cr[31:28] <= registers[rd][31:28];
                    if (instruction[18]) cr[27:24] <= registers[rd][27:24];
                    if (instruction[17]) cr[23:20] <= registers[rd][23:20];
                    if (instruction[16]) cr[19:16] <= registers[rd][19:16];
                    if (instruction[15]) cr[15:12] <= registers[rd][15:12];
                    if (instruction[14]) cr[11:8]  <= registers[rd][11:8];
                    if (instruction[13]) cr[7:4]   <= registers[rd][7:4];
                    if (instruction[12]) cr[3:0]   <= registers[rd][3:0];

                    state <= STATE_FETCH_OP_0;
                  end
                151:
                  begin
                    // stwx (Store word indexed).
                    if (ra != 0)
                      ea <= $signed(registers[ra]) + registers[rb];
                    else
                      ea <= registers[rb];

                    st_size <= 3'b010;
                    state <= STATE_STORE_0;
                  end
                183:
                  begin
                    // stwux (Store word with update indexed).
                    ea <= $signed(registers[ra]) + registers[rb];
                    update_ea <= 1;
                    st_size <= 3'b010;
                    state <= STATE_STORE_0;
                  end
                193:
                  begin
                    // crxor crbD, crbA, crbB
                    cr[crbd] <= cr[crba] ^ cr[crbb];
                    state <= STATE_FETCH_OP_0;
                  end
                202:
                  begin
                    alu_op = ALU_OP_ADD_C;
                    affects_xer[ALU_XER_CA] <= 1;
                    state <= STATE_ALU_REG;
                  end
                215:
                  begin
                    // stbx (Store byte indexed).
                    if (ra != 0)
                      ea <= $signed(registers[ra]) + registers[rb];
                    else
                      ea <= registers[rb];

                    st_size <= 3'b000;
                    state <= STATE_STORE_0;
                  end
                225:
                  begin
                    // crnand crbD, crbA, crbB
                    cr[crbd] <= ~(cr[crba] & cr[crbb]);
                    state <= STATE_FETCH_OP_0;
                  end
                247:
                  begin
                    // stbux (Store byte with update indexed).
                    ea <= $signed(registers[ra]) + registers[rb];
                    update_ea <= 1;
                    st_size <= 3'b000;
                    state <= STATE_STORE_0;
                  end
                256: state <= STATE_ALU_REG;
                257:
                  begin
                    // crand crbD, crbA, crbB
                    cr[crbd] <= cr[crba] & cr[crbb];
                    state <= STATE_FETCH_OP_0;
                  end
                266:
                  begin
                    // add, add., addo, addo. (ADD).
                    state <= STATE_ALU_REG;
                  end
                279:
                  begin
                    // lhzx (Load half word and zero indexed).
                    if (ra != 0)
                      ea <= $signed(registers[ra]) + registers[rb];
                    else
                      ea <= registers[rb];

                    st_size <= 3'b001;
                    state <= STATE_LOAD_0;
                  end
                284:
                  begin
                    alu_op = ALU_OP_EQV;
                    state <= STATE_ALU_LOGIC;
                  end
                289:
                  begin
                    // creqv crbD, crbA, crbB
                    cr[crbd] <= ~(cr[crba] ^ cr[crbb]);
                    state <= STATE_FETCH_OP_0;
                  end
                311:
                  begin
                    // lhzux (Load half word and zero with update indexed).
                    if (ra != 0)
                      ea <= $signed(registers[ra]) + registers[rb];
                    else
                      ea <= registers[rb];

                    st_size <= 3'b001;
                    state <= STATE_LOAD_0;
                  end
                316:
                  begin
                    // xor, xor. (XOR).
                    alu_op = ALU_OP_XOR;
                    state <= STATE_ALU_LOGIC;
                  end
                339:
                  begin
                    // mfspr
                    case (ra)
                      1: registers[rd] <= xer;
                      8: registers[rd] <= lr;
                      9: registers[rd] <= ctr;
                    endcase

                    state <= STATE_FETCH_OP_0;
                  end
                343:
                  begin
                    // lhax (Load half word algebraic indexed).
                    if (ra != 0)
                      ea <= $signed(registers[ra]) + registers[rb];
                    else
                      ea <= registers[rb];

                    st_size <= 3'b101;
                    state <= STATE_LOAD_0;
                  end
                375:
                  begin
                    // lhaux (Load half word algebraic with update indexed).
                    ea <= $signed(registers[ra]) + registers[rb];
                    update_ea <= 1;
                    st_size <= 3'b101;
                    state <= STATE_LOAD_0;
                  end
                407:
                  begin
                    // sthx (Store half word indexed).
                    if (ra != 0)
                      ea <= $signed(registers[ra]) + registers[rb];
                    else
                      ea <= registers[rb];

                    st_size <= 3'b001;
                    state <= STATE_STORE_0;
                  end
                412:
                  begin
                    // orc, orc. (OR with complement).
                    alu_op = ALU_OP_OR_C;
                    state <= STATE_ALU_LOGIC;
                  end
                417:
                  begin
                    // crorc crbD, crbA, crbB
                    cr[crbd] <= cr[crba] | ~cr[crbb];
                    state <= STATE_FETCH_OP_0;
                  end
                439:
                  begin
                    // sthux (Store half word and update indexed).
                    ea <= $signed(registers[ra]) + registers[rb];
                    update_ea <= 1;
                    st_size <= 3'b001;
                    state <= STATE_STORE_0;
                  end
                444:
                  begin
                    // or, or. (OR).
                    alu_op = ALU_OP_OR;
                    state <= STATE_ALU_LOGIC;
                  end
                449:
                  begin
                    // cror crbD, crbA, crbB
                    cr[crbd] <= cr[crba] | cr[crbb];
                    state <= STATE_FETCH_OP_0;
                  end
                467:
                  begin
                    // mtspr
                    case (ra)
                      1: xer <= registers[rd];
                      8: lr  <= registers[rd];
                      9: ctr <= registers[rd];
                    endcase

                    state <= STATE_FETCH_OP_0;
                  end
                476:
                  begin
                    // nand, nand. (NAND).
                    alu_op = ALU_OP_NAND;
                    state <= STATE_ALU_LOGIC;
                  end
              endcase

              // FIXME: There must be a pattern to pick this out better?
              case (subopcode_10)
                536:
                  begin
                    // srw, srw. (Shift right word).
                    alu_op = ALU_OP_SRL;
                    affects_xer[ALU_XER_CA] <= 1;
                    state <= STATE_ALU_LOGIC;
                  end
                792:
                  begin
                    // sraw, sraw. (Shift right algebraic word).
                    alu_op = ALU_OP_SRA;
                    affects_xer[ALU_XER_CA] <= 1;
                    state <= STATE_ALU_LOGIC;
                  end
                824:
                  begin
                    // srawi, srawi. (Shift right algebraic word immediate).
                    alu_op = ALU_OP_SRA;
                    affects_xer[ALU_XER_CA] <= rc;
                    if (rc == 1) affects_cr <= 4'hf;
                    source <= registers[rd];
                    temp <= rb;
                    state <= STATE_ALU_0;
                  end
                922:
                  begin
                    // extsh, extsh. (Extend sign half word).
                    if (rc == 1) affects_cr = 4'hf;
                    result = $signed(registers[ra][15:0]);
                    state <= STATE_ALU_1;
                  end
                954:
                  begin
                    // extsb, extsb. (Extend sign byte).
                    if (rc == 1) affects_cr = 4'hf;
                    result = $signed(registers[ra][7:0]);
                    state <= STATE_ALU_1;
                  end
              endcase
              end
            32:
              begin
                // lwz (Load word and zero).
                if (ra != 0)
                  ea <= $signed(registers[ra]) + st_offset;
                else
                  ea <= st_offset;

                st_size <= 3'b010;
                state <= STATE_LOAD_0;
              end
            33:
              begin
                // lwzu (Load word and zero with update).
                update_ea <= 1;
                ea <= $signed(registers[ra]) + st_offset;
                st_size <= 3'b010;
                state <= STATE_LOAD_0;
              end
            34:
              begin
                // lbz (Load byte and zero).
                if (ra != 0)
                  ea <= $signed(registers[ra]) + st_offset;
                else
                  ea <= st_offset;

                st_size <= 3'b000;
                state <= STATE_LOAD_0;
              end
            35:
              begin
                // lbzu (Load byte and zero with update).
                update_ea <= 1;
                ea <= $signed(registers[ra]) + st_offset;
                st_size <= 3'b000;
                state <= STATE_LOAD_0;
              end
            36:
              begin
                // stw.
                if (ra != 0)
                  ea <= $signed(registers[ra]) + st_offset;
                else
                  ea <= st_offset;

                st_size <= 3'b010;
                state <= STATE_STORE_0;
              end
            36:
              begin
                // stwu.
                ea <= $signed(registers[ra]) + st_offset;
                update_ea <= 1;
                st_size <= 3'b010;
                state <= STATE_STORE_0;
              end
            38:
              begin
                // stb.
                if (ra != 0)
                  ea <= $signed(registers[ra]) + st_offset;
                else
                  ea <= st_offset;

                st_size <= 3'b000;
                state <= STATE_STORE_0;
              end
            39:
              begin
                // stbu.
                ea <= $signed(registers[ra]) + st_offset;
                update_ea <= 1;
                st_size <= 3'b000;
                state <= STATE_STORE_0;
              end
            40:
              begin
                // lhz.
                if (ra != 0)
                  ea <= $signed(registers[ra]) + st_offset;
                else
                  ea <= st_offset;

                st_size <= 3'b001;
                state <= STATE_LOAD_0;
              end
            41:
              begin
                // lhzu (Load half word and zero with update).A
                update_ea <= 1;
                ea <= $signed(registers[ra]) + st_offset;
                st_size <= 3'b001;
                state <= STATE_LOAD_0;
              end
            42:
              begin
                // lha (Load half word algebraic).
                if (ra != 0)
                  ea <= $signed(registers[ra]) + st_offset;
                else
                  ea <= st_offset;

                st_size <= 3'b101;
                state <= STATE_LOAD_0;
              end
            43:
              begin
                // lhau (Load half word algebraic with update).
                ea <= $signed(registers[ra]) + st_offset;
                update_ea <= 1;
                st_size <= 3'b101;
                state <= STATE_LOAD_0;
              end
            44:
              begin
                // sth.
                if (ra != 0)
                  ea <= $signed(registers[ra]) + st_offset;
                else
                  ea <= st_offset;

                st_size <= 3'b001;
                state <= STATE_STORE_0;
              end
            45:
              begin
                // sthu.
                ea <= $signed(registers[ra]) + st_offset;
                update_ea <= 1;
                st_size <= 3'b001;
                state <= STATE_STORE_0;
              end
          endcase
        end
      STATE_TRAP:
        begin
          // FIXME: Probably should add logic here, but for now just HALT.
          state <= STATE_HALTED;
        end
      STATE_LOAD_0:
        begin
          mem_bus_enable <= 1;
          mem_write_enable <= 0;
          mem_address <= ea;
          state <= STATE_LOAD_1;
        end
      STATE_LOAD_1:
        begin
            case (st_size[1:0])
              3'b00:
                begin
                  case (ea[1:0])
                    3:
                      begin
                        registers[rd][7:0] <= mem_read[7:0];
                        registers[rd][31:8] <= { {24{ mem_read[7] & st_size[2] } } };
                      end
                    2:
                      begin
                        registers[rd][7:0] <= mem_read[15:8];
                        registers[rd][31:8] <= { {24{ mem_read[15] & st_size[2] } } };
                      end
                    1:
                      begin
                        registers[rd][7:0] <= mem_read[23:16];
                        registers[rd][31:8] <= { {24{ mem_read[23] & st_size[2] } } };
                      end
                    0:
                      begin
                        registers[rd][7:0] <= mem_read[31:24];
                        registers[rd][31:8] <= { {24{ mem_read[31] & st_size[2] } } };
                      end
                  endcase
                end
              3'b01:
                begin
                  case (ea[1])
                    1:
                      begin
                        registers[rd][15:0] <= mem_read[15:0];
                        registers[rd][31:16] <= { {16{ mem_read[15] & st_size[2] } } };
                      end
                    0:
                      begin
                        registers[rd][15:0] <= mem_read[31:16];
                        registers[rd][31:16] <= { {16{ mem_read[31] & st_size[2] } } };
                      end
                  endcase
                end
              3'b10:
                begin
                  registers[rd] <= mem_read;
                end
            endcase

            if (update_ea == 1) registers[ra] <= ea;
            mem_bus_enable <= 0;
            state <= STATE_FETCH_OP_0;
        end
      STATE_STORE_0:
        begin
          case (st_size[1:0])
            2'b00:
              begin
                case (ea[1:0])
                  2'b11:
                    begin
                      mem_write <= { 24'h0000, registers[rd][7:0] };
                      mem_write_mask <= 4'b1110;
                    end
                  2'b10:
                    begin
                      mem_write <= { 16'h0000, registers[rd][7:0], 8'h00 };
                      mem_write_mask <= 4'b1101;
                    end
                  2'b01:
                    begin
                      mem_write <= { 8'h00, registers[rd][7:0], 16'h0000 };
                      mem_write_mask <= 4'b1011;
                    end
                  2'b00:
                    begin
                      mem_write <= { registers[rd][7:0], 24'h0000 };
                      mem_write_mask <= 4'b0111;
                    end
                endcase
              end
            2'b01:
              begin
                case (ea[1:0])
                  2'b10:
                    begin
                      mem_write <= { 16'h0000, registers[rd][15:0] };
                      mem_write_mask <= 4'b1100;
                    end
                  2'b00:
                    begin
                      mem_write <= { registers[rd][15:0], 16'h0000 };
                      mem_write_mask <= 4'b0011;
                    end
                endcase
              end
            2'b10:
              begin
                mem_write <= registers[rd];
                mem_write_mask <= 4'b0000;
              end
          endcase

          mem_address <= ea;
          mem_write_enable <= 1;
          mem_bus_enable <= 1;
          state <= STATE_STORE_1;
        end
      STATE_STORE_1:
        begin
          if (update_ea == 1) registers[ra] <= ea;
          mem_bus_enable <= 0;
          mem_write_enable <= 0;
          state <= STATE_FETCH_OP_0;
        end
      STATE_ALU_IMM:
        begin
          // Add immediate shifted (addis).
          if (ra == 0 && alu_op == ALU_OP_ADD)
            source <= 0;
          else if (alu_op == ALU_OP_ADD ||
                   alu_op == ALU_OP_SUB ||
                   alu_op == ALU_OP_ADD_C)
            source <= registers[ra];
          else
            source <= registers[rd];

          if (imm_is_shifted == 1)
            temp <= { uimm, 16'h00 };
          else
            temp <= simm;

          state <= STATE_ALU_0;
        end
      STATE_ALU_REG:
        begin
          if (rc == 1) affects_cr = 4'hf;
          if (oe == 1)
            begin
              affects_xer[ALU_XER_SO] <= 1;
              affects_xer[ALU_XER_OV] <= 1;
            end

          source <= registers[ra];
          temp <= registers[rb];
          state <= STATE_ALU_0;
        end
      STATE_ALU_LOGIC:
        begin
          // ALU reg, reg.
          if (rc == 1) affects_cr = 4'hf;

          source <= registers[rd];
          temp <= registers[rb];
          state <= STATE_ALU_0;
        end
      STATE_ALU_0:
        begin
          // ALU reg, reg.
          case (alu_op)
            ALU_OP_ADD:   result <= source + temp;
            ALU_OP_AND:   result <= source & temp;
            ALU_OP_NOR:   result <= ~(source | temp);
            ALU_OP_SUB:   result <= ~source + temp + 1;
            ALU_OP_XOR:   result <= source ^ temp;
            ALU_OP_OR:    result <= source | temp;
            ALU_OP_SLL:   result <= source << temp;
            ALU_OP_SRL:   result <= $unsigned(source) >> temp;
            ALU_OP_SRA:   result <= source >> temp;
            ALU_OP_ADD_C: result <= source + temp + xer[29];
            ALU_OP_OR_C:  result <= source | ~temp;
            ALU_OP_NAND:  result <= ~(source & temp);
            ALU_OP_EQV:   result <= ~(source ^ temp);
          endcase

          state <= STATE_ALU_1;
        end
      STATE_ALU_1:
        begin
          if (alu_op == ALU_OP_ADD ||
              alu_op == ALU_OP_SUB ||
              alu_op == ALU_OP_ADD_C)
            registers[rd] <= result;
          else
            registers[ra] <= result;

          if (affects_cr[ALU_CR_LT]) cr[31] <= $signed(result[31:0]) < 0;
          if (affects_cr[ALU_CR_GT]) cr[30] <= $signed(result[31:0]) > 0;
          if (affects_cr[ALU_CR_EQ]) cr[29] <= result[31:0] == 0;
          if (affects_cr[ALU_CR_SO]) cr[28] <= xer[31] | overflow;

          if (affects_xer[ALU_XER_SO]) xer[31] <= xer[31] | overflow;
          if (affects_xer[ALU_XER_OV]) xer[30] <= overflow;
          if (affects_xer[ALU_XER_CA]) xer[29] <= result[32];

          state <= STATE_FETCH_OP_0;
        end
      STATE_CMP_U_0:
        begin
          //crfd_offset <= (7 - crfd) << 2;
          cr_result[3] <= registers[ra] < temp;
          cr_result[2] <= registers[ra] > temp;
          cr_result[1] <= registers[ra] == temp;
          cr_result[0] <= 0;
          state <= STATE_CMP_SAVE;
        end
      STATE_CMP_S_0:
        begin
          cr_result[3] <= $signed(registers[ra]) < $signed(temp);
          cr_result[2] <= $signed(registers[ra]) > $signed(temp);
          cr_result[1] <= $signed(registers[ra]) == $signed(temp);
          cr_result[0] <= 0;
          state <= STATE_CMP_SAVE;
        end
      STATE_CMP_SAVE:
        begin
          case (instruction[25:23])
            0: cr[31:28] <= cr_result;
            1: cr[27:24] <= cr_result;
            2: cr[23:20] <= cr_result;
            3: cr[19:16] <= cr_result;
            4: cr[15:12] <= cr_result;
            5: cr[11:8]  <= cr_result;
            6: cr[7:4]   <= cr_result;
            7: cr[3:0]   <= cr_result;
          endcase

          state <= STATE_FETCH_OP_0;
        end
      STATE_BRANCH_1:
        begin
          // BO: (z=don't care, y=hint - branch prediction).
          // 0000y: Decrement CTR, branch if cond FALSE.
          // 0001y: Decrement CTR, branch if cond FALSE.
          // 001zy: Branch if cond FALSE.
          // 0100y: Decrement CTR, branch if cond TRUE.
          // 0101y: Decrement CTR, branch if cond TRUE.
          // 011zy: Branch if cond TRUE.
          // 1z00y: Decrement CTR, branch of CTR != 0.
          // 1z01y: Decrement CTR, branch of CTR == 0.
          // 1z1zz: Branch always.
          if (bo[4] == 1) begin
            if (bo[2] == 1)
              pc <= branch_ea;
            else if (bo[1] == 0 && ctr != 0)
              pc <= branch_ea;
            else if (bo[1] == 1 && ctr == 0)
              pc <= branch_ea;
          end else begin
            case (bo[3:2])
              2'b01:
                // 001zy: Branch if condition is FALSE.
                if (! conditional) pc <= branch_ea;
              2'b11:
                // 011zy: Branch if condition is TRUE.
                if (conditional) pc <= branch_ea;
              2'b00:
                // FIXME: Is this right?
                if (bo[1] == 0)
                  if (! conditional || ctr != 0) pc <= branch_ea;
                else
                  if (! conditional || ctr == 0) pc <= branch_ea;
              2'b10:
                // FIXME: Is this right?
                if (bo[1] == 0)
                  if (conditional || ctr != 0) pc <= branch_ea;
                else
                  if (conditional || ctr == 0) pc <= branch_ea;
            endcase
          end

          state <= STATE_FETCH_OP_0;
        end
      STATE_EEPROM_START:
        begin
          // Initialize values for reading from SPI-like EEPROM.
          if (eeprom_ready) begin
            //eeprom_mem_address <= pc;
            eeprom_mem_address <= 16'hc000;
            eeprom_count <= 0;
            state <= STATE_EEPROM_READ;
          end
        end
      STATE_EEPROM_READ:
        begin
          // Set the next EEPROM address to read from and strobe.
          mem_bus_enable <= 0;
          eeprom_address <= eeprom_count;
          eeprom_strobe <= 1;
          state <= STATE_EEPROM_WAIT;
        end
      STATE_EEPROM_WAIT:
        begin
          // Wait until 8 bits are clocked in.
          eeprom_strobe <= 0;

          if (eeprom_ready) begin

            if (eeprom_count[1:0] == 3) begin
              mem_address <= eeprom_mem_address;
              mem_write_mask <= 4'b0000;
              // After reading 4 bytes, store the 32 bit value to RAM.
              mem_write <= {
                eeprom_data_out,
                eeprom_holding[2],
                eeprom_holding[1],
                eeprom_holding[0]
              };

              state <= STATE_EEPROM_WRITE;
            end else begin
              // Read 3 bytes into a holding register.
              eeprom_holding[eeprom_count[1:0]] <= eeprom_data_out;
              state <= STATE_EEPROM_READ;
            end

            eeprom_count <= eeprom_count + 1;
          end
        end
      STATE_EEPROM_WRITE:
        begin
          // Write value read from EEPROM into memory.
          mem_bus_enable <= 1;
          mem_write_enable <= 1;
          eeprom_mem_address <= eeprom_mem_address + 4;

          state <= STATE_EEPROM_DONE;
        end
      STATE_EEPROM_DONE:
        begin
          // Finish writing and read next byte if needed.
          mem_bus_enable <= 0;
          mem_write_enable <= 0;

          if (eeprom_count == 0) begin
            // Read in 2048 bytes.
            state <= STATE_FETCH_OP_0;
          end else
            state <= STATE_EEPROM_READ;
        end
      STATE_DEBUG:
        begin
          state <= STATE_DEBUG;
        end
      STATE_ERROR:
        begin
          state <= STATE_ERROR;
        end
      STATE_HALTED:
        begin
          state <= STATE_HALTED;
        end
    endcase
end

memory_bus memory_bus_0(
  .address      (mem_address),
  .data_in      (mem_write),
  .write_mask   (mem_write_mask),
  .data_out     (mem_read),
  //.debug        (mem_debug),
  //.data_ready   (mem_data_ready),
  .bus_enable   (mem_bus_enable),
  .write_enable (mem_write_enable),
  .clk          (clk),
  .raw_clk      (raw_clk),
  .speaker_p    (speaker_p),
  .speaker_m    (speaker_m),
  .ioport_0     (ioport_0),
  .ioport_1     (ioport_1),
  .ioport_2     (ioport_2),
  .ioport_3     (ioport_3),
  .button_0     (button_0),
  .reset        (~button_reset),
  .spi_clk      (spi_clk),
  .spi_mosi     (spi_mosi),
  .spi_miso     (spi_miso)
);

eeprom eeprom_0
(
  .address    (eeprom_address),
  .strobe     (eeprom_strobe),
  .raw_clk    (raw_clk),
  .eeprom_cs  (eeprom_cs),
  .eeprom_clk (eeprom_clk),
  .eeprom_di  (eeprom_di),
  .eeprom_do  (eeprom_do),
  .ready      (eeprom_ready),
  .data_out   (eeprom_data_out)
);

endmodule

