.powerpc

;; Set to 0xc000 for eeprom.
;.org 0xc000
.org 0x4000

;; Registers.
BUTTON     equ 0x00
SPI_TX     equ 0x04
SPI_RX     equ 0x08
SPI_CTL    equ 0x0c
PORT0      equ 0x20
SOUND      equ 0x24
SPI_IO     equ 0x28

;; Bits in SPI_CTL.
SPI_BUSY   equ 0x01
SPI_START  equ 0x02
SPI_16     equ 0x04

;; Bits in SPI_IO.
LCD_RES    equ 0x01
LCD_DC     equ 0x02
LCD_CS     equ 0x04

;; Bits in PORT0
LED0       equ 0x01

COMMAND_DISPLAY_OFF     equ 0xae
COMMAND_SET_REMAP       equ 0xa0
COMMAND_START_LINE      equ 0xa1
COMMAND_DISPLAY_OFFSET  equ 0xa2
COMMAND_NORMAL_DISPLAY  equ 0xa4
COMMAND_SET_MULTIPLEX   equ 0xa8
COMMAND_SET_MASTER      equ 0xad
COMMAND_POWER_MODE      equ 0xb0
COMMAND_PRECHARGE       equ 0xb1
COMMAND_CLOCKDIV        equ 0xb3
COMMAND_PRECHARGE_A     equ 0x8a
COMMAND_PRECHARGE_B     equ 0x8b
COMMAND_PRECHARGE_C     equ 0x8c
COMMAND_PRECHARGE_LEVEL equ 0xbb
COMMAND_VCOMH           equ 0xbe
COMMAND_MASTER_CURRENT  equ 0x87
COMMAND_CONTRASTA       equ 0x81
COMMAND_CONTRASTB       equ 0x82
COMMAND_CONTRASTC       equ 0x83
COMMAND_DISPLAY_ON      equ 0xaf

.define mandel mulw

.macro send_command(value)
  li r20, value
  bl lcd_send_cmd
.endm

.macro square_fixed(result, var)
.scope
  add r21, r0, var
  andi. r11, r21, 0x8000
  beq not_signed
  neg r21, r21
  andi. r21, r21, 0xffff
not_signed:
  add r22, r0, r21
  bl multiply
  add result, r0, r23
.ends
.endm

.macro multiply_signed(var_0, var_1)
.scope
  add r21, r0, var_0
  add r22, r0, var_1
  li r12, 0x0000
  ;; Check of var_0 is negative and make it positive if it is.
  andi. r11, r21, 0x8000
  beq not_signed_0
  xori r12, r12, 1
  neg r21, r21
  andi. r21, r21, 0xffff
not_signed_0:
  ;; Check of var_1 is negative and make it positive if it is.
  andi. r11, r22, 0x8000
  beq not_signed_1
  xori r12, r12, 1
  neg r22, r22
  andi. r22, r22, 0xffff
not_signed_1:
  bl multiply
  ;;cmpwi cr0, r12, 0
  cmpi 0, 0, r12, 0
  beq dont_add_sign
  neg r23, r23
  andi. r23, r23, 0xffff
dont_add_sign:
.ends
.endm

start:
  ;; Hardwire r0 to 0 so unsigned 16 bit numbers can be an ori.
  li r0, 0
  ;; Point r31 to peripherals.
  ori r31, r0, 0x8000
  ;; Turn on LED.
  li r10, 1
  stw r10, PORT0(r31)

main:
  bl lcd_init
  bl lcd_clear

  li r2, 0
main_while_1:
  lwz r10, BUTTON(r31)
  andi. r10, r10, 1
  bne run
  xori r2, r2, 1
  stw r2, PORT0(r31)
  bl delay
  b main_while_1

run:
  bl lcd_clear_2
  bl mandelbrot
  li r2, 1
  b main_while_1

lcd_init:
  mfspr r1, lr
  li r10, LCD_CS
  stw r10, SPI_IO(r31)
  bl delay
  li r10, LCD_CS | LCD_RES
  stw r10, SPI_IO(r31)

  send_command(COMMAND_DISPLAY_OFF)
  send_command(COMMAND_SET_REMAP)
  send_command(0x72)
  send_command(COMMAND_START_LINE)
  send_command(0x00)
  send_command(COMMAND_DISPLAY_OFFSET)
  send_command(0x00)
  send_command(COMMAND_NORMAL_DISPLAY)
  send_command(COMMAND_SET_MULTIPLEX)
  send_command(0x3f)
  send_command(COMMAND_SET_MASTER)
  send_command(0x8e)
  send_command(COMMAND_POWER_MODE)
  send_command(COMMAND_PRECHARGE)
  send_command(0x31)
  send_command(COMMAND_CLOCKDIV)
  send_command(0xf0)
  send_command(COMMAND_PRECHARGE_A)
  send_command(0x64)
  send_command(COMMAND_PRECHARGE_B)
  send_command(0x78)
  send_command(COMMAND_PRECHARGE_C)
  send_command(0x64)
  send_command(COMMAND_PRECHARGE_LEVEL)
  send_command(0x3a)
  send_command(COMMAND_VCOMH)
  send_command(0x3e)
  send_command(COMMAND_MASTER_CURRENT)
  send_command(0x06)
  send_command(COMMAND_CONTRASTA)
  send_command(0x91)
  send_command(COMMAND_CONTRASTB)
  send_command(0x50)
  send_command(COMMAND_CONTRASTC)
  send_command(0x7d)
  send_command(COMMAND_DISPLAY_ON)
  ;; ret
  mtspr lr, r1
  bclr 0x14, 0

lcd_clear:
  mfspr r1, lr
  li r11, 96 * 64
  li r20, 0xff0f
lcd_clear_loop:
  bl lcd_send_data
  addic. r11, r11, -1
  bne lcd_clear_loop
  ;; ret
  mtspr lr, r1
  bclr 0x14, 0

lcd_clear_2:
  mfspr r1, lr
  li r11, 96 * 64
  li r20, 0xf00f
lcd_clear_loop_2:
  bl lcd_send_data
  addic. r11, r11, -1
  bne lcd_clear_loop_2
  ;; ret
  mtspr lr, r1
  bclr 0x14, 0

;; multiply(r21, r22) -> r23
multiply:
  li r23, 0
  li r10, 16
multiply_repeat:
  andi. r24, r21, 1
  beq multiply_ignore_bit
  add r23, r23, r22
multiply_ignore_bit:
  add r22, r22, r22
  srawi r21, r21, 1
  addic. r10, r10, -1
  bne multiply_repeat
  ;; For FIXED point math (shift right by 10 after multiply).
  srawi r23, r23, 10
  andi. r23, r23, 0xffff
  ;; ret
  bclr 0x14, 0

mandelbrot:
  ;; final int DEC_PLACE = 10;
  ;; final int r0 = (-2 << DEC_PLACE);
  ;; final int i0 = (-1 << DEC_PLACE);
  ;; final int r1 = (1 << DEC_PLACE);
  ;; final int i1 = (1 << DEC_PLACE);
  ;; final int dx = (r1 - r0) / 96; (0x0020)
  ;; final int dy = (i1 - i0) / 64; (0x0020)

  mfspr r1, lr
  ori r8, r0, colors

  ;; for (y = 0; y < 64; y++)
  li r3, 64
  ;; int i = -1 << 10;
  ori r5, r0, 0xfc00
mandelbrot_for_y:

  ;; for (x = 0; x < 96; x++)
  li r2, 96
  ;; int r = -2 << 10;
  ori r4, r0, 0xf800
mandelbrot_for_x:
  ;; zr = r; (r6)
  ;; zi = i; (r7)
  add r6, r0, r4
  add r7, r0, r5

  ;; for (int count = 15; count >= 0; count--)
  li r20, 15
mandelbrot_for_count:
  ;; zr2 = (zr * zr) >> DEC_PLACE;  (r26)
  square_fixed(r26, r6)

  ;; zi2 = (zi * zi) >> DEC_PLACE;  (r27)
  square_fixed(r27, r7)

  ;; if (zr2 + zi2 > (4 << DEC_PLACE)) { break; }
  ;; cmp  does: (zr2 + zi2) > (4 << 10).
  ;; subf does: -4 + (zr2 + zi2).. if r25 positive it's bigger than 4.
  add r25, r26, r27

  cmpi 0, 0, r25, 4 << 10
  bgt mandelbrot_stop

  ;; tr = zr2 - zi2;   (r25)
  subf r25, r27, r26
  andi. r25, r25, 0xffff

  ;; ti = ((zr * zi * 2) >> DEC_PLACE) << 1;   (r23)
  multiply_signed(r6, r7)
  add r23, r23, r23

  ;; zr = tr + curr_r;
  add r6, r25, r4
  andi. r6, r6, 0xffff

  ;; zi = ti + curr_i;
  add r7, r23, r5
  andi. r7, r7, 0xffff

  addic. r20, r20, -1
  bne mandelbrot_for_count
mandelbrot_stop:

  ;; r20 = r20 << 1;
  add r20, r20, r20
  lhzx r20, r8, r20

  bl lcd_send_data

  addi r4, r4, 0x0020
  andi. r4, r4, 0xffff
  addic. r2, r2, -1
  bne mandelbrot_for_x

  addi r5, r5, 0x0020
  andi. r5, r5, 0xffff
  addic. r3, r3, -1
  bne mandelbrot_for_y

  ;; ret
  mtspr lr, r1
  bclr 0x14, 0

;; lcd_send_cmd(r20)
lcd_send_cmd:
  li r10, LCD_RES
  stw r10, SPI_IO(r31)
  stw r20, SPI_TX(r31)
  li r10, SPI_START
  stw r10, SPI_CTL(r31)
lcd_send_cmd_wait:
  lwz r10, SPI_CTL(r31)
  andi. r10, r10, SPI_BUSY
  bne lcd_send_cmd_wait
  li r10, LCD_CS | LCD_RES
  stw r10, SPI_IO(r31)
  ;; ret
  bclr 0x14, 0

;; lcd_send_data(r20)
lcd_send_data:
  li r10, LCD_DC | LCD_RES
  stw r10, SPI_IO(r31)
  stw r20, SPI_TX(r31)
  li r10, SPI_16 | SPI_START
  stw r10, SPI_CTL(r31)
lcd_send_data_wait:
  lwz r10, SPI_CTL(r31)
  andi. r10, r10, SPI_BUSY
  bne lcd_send_data_wait
  li r10, LCD_CS | LCD_RES
  stw r10, SPI_IO(r31)
  ;; ret
  bclr 0x14, 0

delay:
  addis r10, r0, 1
delay_loop:
  addic. r10, r10, -1
  bne delay_loop
  ;; ret
  bclr 0x14, 0

;; colors is referenced by address instead of an offset, which makes this
;; program not relocatable.
colors:
  .dc16 0x0000
  .dc16 0x000c
  .dc16 0x0013
  .dc16 0x0015
  .dc16 0x0195
  .dc16 0x0335
  .dc16 0x04d5
  .dc16 0x34c0
  .dc16 0x64c0
  .dc16 0x9cc0
  .dc16 0x6320
  .dc16 0xa980
  .dc16 0xaaa0
  .dc16 0xcaa0
  .dc16 0xe980
  .dc16 0xf800

