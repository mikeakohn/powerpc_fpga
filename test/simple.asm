.powerpc

.org 0x4000

main:
  li r6, 123
  li r7, 7
  add. r6, r6, r7
  tw 3, r6, r7

loop:
  b loop

