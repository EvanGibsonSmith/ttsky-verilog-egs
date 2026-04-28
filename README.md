# Bernoulli Stochastic Multiplier + LIF Neuron

A hardware stochastic multiplier using Bernoulli streams, with a bonus Linear Leaky Integrate-and-Fire (LIF) neuron sharing the tile.

## How it works

Two independent 8-bit LFSRs generate uniform random thresholds each cycle. Input operands `A` and `B` (each 4-bit, representing values in [0,1] as `A/16` and `B/16`) are compared against these thresholds. The AND of the two comparisons fires with probability `(A/16)·(B/16)` — exactly the product. Accumulating over W cycles and dividing by W recovers the product estimate. Variance decreases as `1/W`, so accuracy is tunable by stream length.

The LIF neuron (project select `uio[7]=1`) is an independent bonus module sharing the tile.

## Pin Reference

| Pin | Direction | Description |
|-----|-----------|-------------|
| `ui[7:4]` | input | Operand A (4-bit, represents A/16) |
| `ui[3:0]` | input | Operand B (4-bit, represents B/16) |
| `uo[7:0]` | output | `count[7:0]` — running stream accumulator (Bernoulli mode) / `{membrane[7:1], spike}` (LIF mode) |
| `uio[7]` | input | Project select: 0 = Bernoulli, 1 = LIF |
| `uio[6]` | input | LIF config write strobe |
| `uio[5:3]` | input | LIF config register address |
| `uio[2:0]` | input | Unused |
| `clk` | input | Clock |
| `rst_n` | input | Active-low synchronous reset |

### LIF Config Register Map (`uio[5:3]`)

| Address | Register | Description |
|---------|----------|-------------|
| `3'h1` | `decay_val` | Signed decay amount per cycle |
| `3'h2` | `threshold` | Signed firing threshold |
| `3'h3` | `v_reset` | Signed reset potential after spike |
| `3'h4` | `mode_ctrl` | `[1]=mode_decay`, `[0]=mode_add` |

## How to Test

### Bernoulli Multiplier (`uio[7]=0`)

1. Assert `rst_n` low for at least 4 cycles, then release.
2. Set `uio[7]=0` to select the Bernoulli multiplier.
3. Drive `ui[7:4]` and `ui[3:0]` with your two 4-bit operands.
4. After W clock cycles, read `uo_out`. The estimate of `(A/16)·(B/16)` is `uo_out / W`.
5. For higher accuracy, increase W — variance scales as `1/W`.

**Example:** A=8, B=8 → true product = 0.25. After W=256 cycles, expect `uo_out ≈ 64`.

> Note: `count` is 16-bit internally but only the lower 8 bits are exposed via `uo_out`. For small operands and moderate W this is sufficient. For large W, reset periodically and accumulate externally.

### LIF Neuron (`uio[7]=1`)

1. Assert `rst_n` low for at least 4 cycles, then release.
2. Set `uio[7]=1` to select the LIF neuron.
3. Write config registers by asserting `uio[6]=1` and setting `uio[5:3]` to the register address, with the value on `ui[7:0]`.
4. Deassert `uio[6]=0` to enter run mode. Drive `ui[7:0]` with the signed input each cycle.
5. Read `uo[0]` for spike output, `uo[7:1]` for upper membrane bits.

## External Hardware

None required.

## References

- [Stochastic Computing (Wikipedia)](https://en.wikipedia.org/wiki/Stochastic_computing)
- Tiny Tapeout: [https://tinytapeout.com](https://tinytapeout.com)
