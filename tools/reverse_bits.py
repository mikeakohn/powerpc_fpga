#!/usr/bin/env python3

import sys

if len(sys.argv) != 3:
  print("Usage: python3 reverse_bits.py <start> <end>");
  sys.exit(1)

s = int(sys.argv[1])
e = int(sys.argv[2])

s = 31 - s
e = 31 - e

print("[" + str(s) + ":" + str(e) + "]")

