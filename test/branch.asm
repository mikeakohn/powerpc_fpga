.powerpc

.org 0x4000

main:
  li r6, 123
  li r7, 7
repeat:
  add. r6, r6, r7
  beq repeat
  tw 3, r6, r7

