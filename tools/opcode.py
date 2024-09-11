#!/usr/bin/env python3

import sys

def get_mask(s, e):
  s = 31 - s
  e = 31 - e

  l = (s - e) + 1
  mask = (1 << l) - 1

  return mask << e

def get_opcode(s, e, value):
  s = 31 - s
  e = 31 - e

  return value << e

if len(sys.argv) not in [2, 3]:
  print("Usage: python3 reverse_bits.py <opcode> <subopcode>");
  print("   or")
  print("Usage: python3 reverse_bits.py <opcode/32bit>");
  sys.exit(1)

if len(sys.argv) == 3:
  o = int(sys.argv[1])
  s = int(sys.argv[2])

  mask = get_mask(0, 5) | get_mask(21, 30)
  opcode = get_opcode(0, 5, o) | get_opcode(21, 30, s)

  print("0x%08x" % (mask))
  print("0x%08x" % (opcode))
else:
  o = int(sys.argv[1], 0)

  print("opcode=%d subopcode=%d" % ((o >> 26) & 0x3f, (o >> 1) & 0x1ff))
  print("opcode=" + str((o >> 26) & 0x3f))
  print("rd=" + str((o >> 21) & 0x1f))
  print("ra=" + str((o >> 16) & 0x1f))
  print("rb=" + str((o >> 11) & 0x1f))
  print("imm=" + str(o & 0xffff))
  print("subopcode=" + str((o >> 1) & 0x1fff))
  print("rc=" + str(o & 1))
  print("oe=" + str(o & 10))

