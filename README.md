PowerPC
=======

This is an implementation of a PowerPC CPU implemented in Verilog
to be run on an FPGA. The board being used here is an iceFUN with
a Lattice iCE40 HX8K FPGA.

This project was created by forking the RISC-V FPGA project and
adapting the rest of the Verilog for PowerPC.

https://www.mikekohn.net/micro/powerpc_fpga.php

This is a stripped down "microcontroller" style version of the
instruction set... aka UnderpoweredPC.

Features
========

IO, Button input, speaker tone generator, and SPI.

Instructions
============

Any instruction labeled omitted could be added later. Instructions
like div and mul are also currently omitted to keep the size of the
core down.

Load/Store
----------

    lbz[u,x] rD d(rA)
    lhz[u,x] rD d(rA)
    lha[u,x] rD d(rA)
    lzw[u,x] rD d(rA)
    stb[u,x] rD d(rA)
    sth[u,x] rD d(rA)
    stw[u,x] rD d(rA)

Load/Store (multiple)
---------------------

    lmw rD d(rA)     (omitted)
    stmw rS, d(rA)   (omitted)

ALU
---

    add<c,e>[o,.] rD, rA, rB
    addi<s,c,c.> rD, (rA/0), SIMM
    adde[o,.] rD, rA, rB
    addme[o,.] rD, rA
    addze[o,.] rD, rA
    neg[o,.] rD, rA
    subf<c,e>[o,.] rD, rA, rB
    subfic rD, rA, SIMM
    subme[o,.] rD, rA
    subze[o,.] rD, rA

    and[c,.] rD, rA, rB
    andi. rD, rA, UIMM
    andis. rD, rA, UIMM
    cntlzw[.] rD, rA      (omitted)
    eqv[.] rD, rA, rB
    extsb[.] rD, rA
    extsh[.] rD, rA
    nand. rD, rA, rB
    nor. rD, rA, rB
    or[c,.] rD, rA, rB
    ori rD, rA, UIMM
    oris rD, rA, UIMM
    slw[.] rD, rA, rB
    srw[.] rD, rA, rB
    srawi[.] rD, rA, UIMM
    sraw[.] rD, rA, rB
    xor[c,.] rD, rA, rB
    xori rD, rA, UIMM
    xoris rD, rA, UIMM

Rotate And Mask
---------------

    rlwimi[.] rD, rA, UIMM, MB, ME (omitted)
    rlwinm[.] rD, rA, UIMM, MB, ME (omitted)
    rlwnm[.] rD, rA, rB, MB, ME    (omitted)

Comparison
----------

    cmp crD, L, rA, rB
    cmpi crD, L, rA, SIMM
    cmpl crD, L, rA, rB
    cmpli crD, L, rA, UIMM

Conditional
-----------

    crand crb0, crbA, crbB
    crandc crb0, crbA, crbB
    creqv crb0, crbA, crbB
    crnand crb0, crbA, crbB
    crnor crb0, crbA, crbB
    cror crb0, crbA, crbB
    crorc crb0, crbA, crbB
    crxor crb0, crbA, crbB
    mcrf crD, crA
    crclr crbD          (alias)
    crmov crb0, crbA    (alias)
    crnot crb0, crbA    (alias)
    crset crb0          (alias)

Branch
------

    b[l,a] target
    bc[l,a] BO, BI, target
    bclr[l] BO, BI
    bcctr[l] BO, BI
    beq target         (alias)
    bge target         (alias)
    bgt target         (alias)
    ble target         (alias)
    blt target         (alias)
    bne target         (alias)
    bng target         (alias)
    bnl target         (alias)
    bns target         (alias)
    bso target         (alias)

Special Purpose Register
------------------------

    mcrxr cr0          (omitted)
    mfcr rD            (omitted)
    mfspr rD, SPR      (omitted)
    mtcrf crM, rS      (omitted)
    mtspr SPR, rS      (omitted)
    mtcr rS            (omitted)

Trap
----

    tw TO, rA, Rb
    twi TO, rA, SIMM

System Call
-----------

    sc                 (omitted)

Memory Map
==========

This implementation of the RISC-V has 4 banks of memory. Each address
contains a 16 bit word instead of 8 bit byte like a typical CPU.

* Bank 0: 0x0000 RAM (4096 bytes)
* Bank 1: 0x4000 ROM
* Bank 2: 0x8000 Peripherals
* Bank 3: 0xc000 RAM (4096 bytes)

On start-up by default, the chip will load a program from a AT93C86A
2kB EEPROM with a 3-Wire (SPI-like) interface but wll run the code
from the ROM. To start the program loaded to RAM, the program select
button needs to be held down while the chip is resetting.

The peripherals area contain the following:

* 0x8000: input from push button
* 0x8004: SPI TX buffer
* 0x8008: SPI RX buffer
* 0x800c: SPI control: bit 2: 8/16, bit 1: start strobe, bit 0: busy
* 0x8020: ioport_A output (in my test case only 1 pin is connected)
* 0x8024: MIDI note value (60-96) to play a tone on the speaker or 0 to stop
* 0x8028: ioport_B output (3 pins)

IO
--

iport_A is just 1 output in my test circuit to an LED.
iport_B is 3 outputs used in my test circuit for SPI (RES/CS/DC) to the LCD.

MIDI
----

The MIDI note peripheral allows the iceFUN board to play tones at specified
frequencies based on MIDI notes.

SPI
---

The SPI peripheral has 3 memory locations. One location for reading
data after it's received, one location for filling the transmit buffer,
and one location for signaling.

For signaling, setting bit 1 to a 1 will cause whatever is in the TX
buffer to be transmitted. Until the data is fully transmitted, bit 0
will be set to 1 to let the user know the SPI bus is busy.

There is also the ability to do 16 bit transfers by setting bit 2 to 1.

