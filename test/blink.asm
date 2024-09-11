.powerpc

.org 0x4000

main:
  li r2, 0x8023

loop:
  li r1, 0
  stb r1, 0(r2)

  ;li r6, 0xffff
  ;li r6, 1
  ;ori r6, r6, 0xff
  addis r6, r0, 1
delay_0:
  addic. r6, r6, -1
  bne delay_0

  li r1, 1
  stb r1, 0(r2)

  ;li r6, 0xffff
  ;li r6, 1
  addis r6, r0, 1
delay_1:
  addic. r6, r6, -1
  bne delay_1

  b loop

