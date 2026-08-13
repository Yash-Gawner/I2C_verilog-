# I2C_verilog-
Verilog I2C master/slave FSM implementation with Icarus Verilog testbench — single-byte write transaction, verified via simulation with documented debugging notes on FSM edge-timing bugs.


# I2C Master–Slave (Verilog)

A from-scratch Verilog implementation of an I2C master and slave, built as part of
FPGA/digital-design coursework. The master generates SCL from a system clock and
shifts out a 7-bit address + R/W bit followed by a data byte; the slave detects
START/STOP conditions on the bus, decodes the address, and ACKs/receives the byte.
Verified with an Icarus Verilog testbench (single master ↔ single slave, one
full write transaction).

## Features

- SCL generated from a free-running `clk` via a configurable clock divider
- Open-drain-style `SDA` modeling (`sda_drive_low ? 0 : z`) with an external
  pull-up in the testbench, matching real I2C bus electrical behavior
- Registered (non-predictive) edge detection for SCL, so SDA changes are
  guaranteed to happen strictly after SCL has settled — required for valid
  START/STOP timing (see *Debugging Notes* below)
- START/STOP condition detection on the slave via level-transition comparison,
  independent of the SCL edge
- Address match / ACK / NACK handling
- Self-checking testbench (`PASS`/`FAIL` with expected-vs-actual reporting)

## File Structure

```
.
├── i2c_master.v      # I2C_MASTER — generates SCL, drives address+data onto SDA
├── i2c_slave.v        # I2C_SLAVE  — detects START/STOP, decodes address, receives data
├── tb_i2c.v            # Self-checking testbench (instantiates both, checks result)
└── README.md
```

*(Rename the files above to match whatever you've saved locally — the testbench
instantiates by module name, `I2C_MASTER` / `I2C_SLAVE`, not by filename.)*

## Architecture

Both modules are Moore-style FSMs with these states:

**Master:** `IDLE → ADDRESS → ACK_ADD → DATA → ACK_DATA → STOP → (back to IDLE)`
**Slave:** `IDLE → ADDRESS → ACK_ADD → DATA → ACK_DATA → (back to IDLE)`, with
`start_condition` / `stop_condition` able to force a state jump at any time
(so a repeated START mid-transaction is handled correctly).

SCL is derived from `clk` via a divider (`clock_div == 24` triggers a toggle);
the master's own FSM is clocked on `clk` as well, using a registered edge
detector (`scl_d`) rather than clocking sequential logic directly off the
self-generated `SCL`, which avoids multi-driver/clock-domain issues in
synthesis.

## Prerequisites

- [Icarus Verilog](http://iverilog.icarus.com/) (`iverilog`, `vvp`)
- [GTKWave](http://gtkwave.sourceforge.net/) (optional, for waveform inspection)

## Build & Simulate

```bash
iverilog -o sim i2c_master.v i2c_slave.v tb_i2c.v
vvp sim
```

Expected output:
```
PASS: data=0xa5 address=0x50 rw=0
```

To inspect the waveform:
```bash
gtkwave i2c_wave.vcd
```
(The testbench's `$dumpvars` call captures every signal in the hierarchy —
expand the `tb_i2c` instance in GTKWave's SST panel and drag in `SCL`, `SDA`,
and the `state` regs of both modules.)

## Known Limitations / Future Work

- **No enable/start input on the master.** It free-runs into a new transaction
  immediately after every `STOP`. A `start_tx` input + a real `IDLE`-wait state
  would be needed for a master used inside a larger design.
- **Single data byte per transaction.** No multi-byte burst support.
- **No clock stretching.** The slave never holds SCL low to pause the master.
- **No multi-master arbitration.** Assumes a single master on the bus.
- **Write-only from the slave's perspective.** `rw` is decoded and exposed, but
  the slave doesn't currently drive read data back onto SDA for a read transaction.

## Debugging Notes (verification lessons from building this)

A few non-obvious bugs surfaced only through simulation, not from reading the
code — worth keeping in mind for future FSM/bus-protocol designs:

- **Predictive vs. registered edge detection matters for causality, not just
  style.** Deriving `scl_rising`/`scl_falling` from the *same* counter that
  triggers SCL's own toggle (`clock_div == 24`) makes SDA and SCL change on the
  identical clock edge — which breaks START detection, since START requires
  SCL to be *already stable high* before SDA falls. A registered one-cycle-delayed
  comparison (`scl_d <= SCL`, then `SCL & ~scl_d`) fixes this by construction.
- **Blocking vs. nonblocking assignment can silently break an edge detector.**
  Using `SCL = ~SCL` (blocking) instead of `SCL <= ~SCL` (nonblocking) inside
  the clock-divider block caused a *different* always block reading `SCL` in
  the same timestep to see the already-updated value — collapsing the intended
  one-cycle delay in the registered edge detector to zero, so the derived
  `scl_rising`/`scl_falling` pulses never fired at all.
- **A "wasted" state costs more than it looks like.** An extra `START` state
  that does nothing but transition to `ADDRESS` still consumes a full SCL
  cycle from the slave's point of view, shifting every subsequent sampled bit
  by one position.
- **A signal computed one cycle later than it's needed produces a real glitch,
  not just a logical delay.** Registering `add_match` inside the `ACK_ADD`
  state body meant it wasn't valid until the *next* SCL rising edge, but the
  ACK-driving logic needed it on the falling edge in between — producing a
  transient `x` on the bus. Making `add_match` combinational fixed it.
- **Counters need explicit resets on every path that starts a new phase**, not
  just the global `reset`. A `count_data` that only resets on `reset` (and not
  on entering a new transaction) can carry a stale value forward if any
  earlier transaction is cut short, corrupting the next one's data alignment.

All of the above were caught and confirmed by running the design through
Icarus Verilog and comparing expected vs. actual signal traces — reinforcing
that reading an FSM's code is not a substitute for simulating its actual
edge-by-edge behavior.
