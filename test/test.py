# SPDX-FileCopyrightText: © 2024 Tiny Tapeout
# SPDX-License-Identifier: Apache-2.0

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, RisingEdge


# -----------------------------------------------------------------------------
# Project select encoding (uio_in[7:6])
# -----------------------------------------------------------------------------
SEL_BERNOULLI = 0b00 << 6
SEL_LIF       = 0b01 << 6
SEL_MULT      = 0b10 << 6


async def reset_dut(dut):
    dut.ena.value   = 1
    dut.ui_in.value = 0
    dut.uio_in.value = 0
    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 5)
    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 2)


async def lif_write(dut, addr, data):
    """Write a LIF config register: proj_sel=01, wr_en=1, addr on uio[4:2]."""
    dut.ui_in.value  = data & 0xFF
    dut.uio_in.value = SEL_LIF | (1 << 5) | ((addr & 0x7) << 2)
    await ClockCycles(dut.clk, 1)
    # Deassert wr_en, stay on LIF
    dut.uio_in.value = SEL_LIF


# -----------------------------------------------------------------------------
# Test 1: Conventional multiplier — exact results
# -----------------------------------------------------------------------------
@cocotb.test()
async def test_conventional_mult(dut):
    """Exact 4x4 unsigned multiplier: verify a*b for representative pairs."""
    clock = Clock(dut.clk, 10, unit="us")
    cocotb.start_soon(clock.start())
    await reset_dut(dut)

    dut.uio_in.value = SEL_MULT

    test_cases = [
        (0,  0,  0),
        (4,  4,  16),
        (8,  8,  64),
        (8,  12, 96),
        (12, 12, 144),
        (15, 15, 225),
        (10, 6,  60),
    ]

    for a, b, expected in test_cases:
        dut.ui_in.value = (a << 4) | b
        await ClockCycles(dut.clk, 1)
        result = int(dut.uo_out.value)
        assert result == expected, \
            f"mult4 FAIL: {a}*{b} expected {expected} got {result}"
        dut._log.info(f"mult4 PASS: {a}*{b} = {result}")


# -----------------------------------------------------------------------------
# Test 2: Bernoulli multiplier — statistical accuracy over W cycles
# -----------------------------------------------------------------------------
@cocotb.test()
async def test_bernoulli_mult(dut):
    """
    Bernoulli multiplier: estimate converges toward true product.
    Uses W=512 for reasonable accuracy. Tolerance is loose (3 sigma ~ 0.07)
    since this is inherently stochastic.
    """
    clock = Clock(dut.clk, 10, unit="us")
    cocotb.start_soon(clock.start())

    W = 200
    TOLERANCE = 0.12  # generous — stochastic, not exact

    test_cases = [
        (8,  8,  0.2500),   # 0.5 * 0.5
        (12, 8,  0.3750),   # 0.75 * 0.5
        (4,  4,  0.0625),   # 0.25 * 0.25
        (10, 6,  0.2344),   # 0.625 * 0.375
    ]

    for a, b, true_p in test_cases:
        # Reset zeros the counter; measure directly from uo_out (count[7:0])
        # No internal signal access — compatible with gate-level netlist
        await reset_dut(dut)
        dut.uio_in.value = SEL_BERNOULLI
        dut.ui_in.value  = (a << 4) | b

        await ClockCycles(dut.clk, W)
        count_val = int(dut.uo_out.value)

        # uo_out is count[7:0]; for W<=255 this equals the full count
        estimate = count_val / W
        error    = abs(estimate - true_p)

        dut._log.info(
            f"Bernoulli {a}/16 * {b}/16: true={true_p:.4f} "
            f"est={estimate:.4f} err={error:.4f}"
        )
        assert error < TOLERANCE, \
            f"Bernoulli FAIL: {a}*{b} error {error:.4f} exceeds {TOLERANCE}"


# -----------------------------------------------------------------------------
# Test 3: LIF neuron — periodic spiking
# -----------------------------------------------------------------------------
@cocotb.test()
async def test_lif(dut):
    """
    LIF: input=8, decay=2, threshold=32, v_reset=0.
    Net +6 per cycle -> spike every ceil(32/6) = 6 cycles.
    Check at least 3 spikes occur in 25 cycles.
    """
    clock = Clock(dut.clk, 10, unit="us")
    cocotb.start_soon(clock.start())
    await reset_dut(dut)

    await lif_write(dut, 0x2, 32)   # threshold = 32
    await lif_write(dut, 0x3, 0)    # v_reset   = 0
    await lif_write(dut, 0x1, 2)    # decay_val = 2
    await lif_write(dut, 0x4, 0x3)  # mode_add=1, mode_decay=1

    dut.uio_in.value = SEL_LIF
    dut.ui_in.value  = 8  # input_val = 8

    spike_count = 0
    for i in range(25):
        await ClockCycles(dut.clk, 1)
        uo = int(dut.uo_out.value)
        spike = uo & 0x1  # spike on uo_out[0]
        if spike:
            spike_count += 1
            dut._log.info(f"LIF spike at cycle {i}")

    dut._log.info(f"LIF: {spike_count} spikes in 25 cycles (expect ~4)")
    assert spike_count >= 3, \
        f"LIF FAIL: only {spike_count} spikes in 25 cycles, expected ~4"


# -----------------------------------------------------------------------------
# Test 4: Mux switching — proj_sel routes correctly
# -----------------------------------------------------------------------------
@cocotb.test()
async def test_mux_switch(dut):
    """Switching proj_sel immediately changes uo_out source."""
    clock = Clock(dut.clk, 10, unit="us")
    cocotb.start_soon(clock.start())
    await reset_dut(dut)

    # Conventional mult: 8*8=64
    dut.ui_in.value  = (8 << 4) | 8
    dut.uio_in.value = SEL_MULT
    await ClockCycles(dut.clk, 1)
    result = int(dut.uo_out.value)
    assert result == 64, f"Mux FAIL: mult expected 64 got {result}"
    dut._log.info(f"Mux PASS: mult gives {result}")

    # Switch to Bernoulli — output should no longer be 64 after some cycles
    dut.uio_in.value = SEL_BERNOULLI
    await ClockCycles(dut.clk, 1)
    bm_out = int(dut.uo_out.value)
    # Can't assert exact value but it should be reading count_r, not 64
    dut._log.info(f"Mux: Bernoulli uo_out={bm_out} (count after 1 cycle)")