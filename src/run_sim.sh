#!/usr/bin/env bash
# =============================================================================
# run_sim.sh — compile and simulate all testbenches with iverilog
#
# Usage: ./run_sim.sh
# Exits 0 if all tests pass, 1 on any compile or simulation failure.
# =============================================================================

set -euo pipefail

PASS=0
FAIL=0

# Colours
RED='\033[0;31m'
GRN='\033[0;32m'
YLW='\033[1;33m'
NC='\033[0m'

# Source files shared across all testbenches
SHARED_SRC="lfsr8.sv bm_project.sv mult4.sv linear_lif.sv tt_um_bn_lif_evan.sv"

# -----------------------------------------------------------------------------
# Helper: compile + run one testbench
#   $1 = human-readable name
#   $2 = top-level testbench file
#   $3 = grep pattern that must appear in output to confirm all tests passed
#        (leave empty to just check exit code)
# -----------------------------------------------------------------------------
run_tb() {
    local name="$1"
    local tb_file="$2"
    local pass_pattern="$3"
    local out_file="${tb_file%.sv}.out"
    local vvp_file="${tb_file%.sv}.vvp"

    echo ""
    echo "---------------------------------------------------------------------"
    echo -e "${YLW}[SIM] ${name}${NC}"
    echo "---------------------------------------------------------------------"

    # Compile
    if ! iverilog -g2012 -Wall -o "${vvp_file}" ${SHARED_SRC} "${tb_file}" 2>&1; then
        echo -e "${RED}[FAIL] Compilation failed: ${tb_file}${NC}"
        FAIL=$((FAIL + 1))
        return
    fi

    # Simulate
    if ! vvp "${vvp_file}" 2>&1 | tee "${out_file}"; then
        echo -e "${RED}[FAIL] Simulation error: ${tb_file}${NC}"
        FAIL=$((FAIL + 1))
        return
    fi

    # Check for $fatal or explicit failure strings
    if grep -qiE '^\s*(ERROR|FAIL|fatal)' "${out_file}"; then
        echo -e "${RED}[FAIL] Test failures detected in output — see ${out_file}${NC}"
        FAIL=$((FAIL + 1))
        return
    fi

    # Check for required pass pattern if provided
    if [[ -n "${pass_pattern}" ]]; then
        if ! grep -q "${pass_pattern}" "${out_file}"; then
            echo -e "${RED}[FAIL] Expected pass string not found: '${pass_pattern}'${NC}"
            echo -e "${RED}       Check ${out_file} for details${NC}"
            FAIL=$((FAIL + 1))
            return
        fi
    fi

    echo -e "${GRN}[PASS] ${name}${NC}"
    PASS=$((PASS + 1))
}

# -----------------------------------------------------------------------------
# Confirm tools are available
# -----------------------------------------------------------------------------
echo "Checking tools..."
if ! command -v iverilog &> /dev/null; then
    echo -e "${RED}iverilog not found — install with: sudo apt install iverilog${NC}"
    exit 1
fi
if ! command -v vvp &> /dev/null; then
    echo -e "${RED}vvp not found — should ship with iverilog${NC}"
    exit 1
fi
echo -e "${GRN}iverilog $(iverilog -V 2>&1 | head -1)${NC}"

# -----------------------------------------------------------------------------
# Run testbenches
# -----------------------------------------------------------------------------

# 1. Bernoulli multiplier unit testbench
#    Pass condition: simulation completes and prints "Done."
run_tb \
    "Bernoulli multiplier (bm_project_tb)" \
    "bm_project_tb.sv" \
    "Done."

# 2. Linear LIF unit testbench
#    Pass condition: "ALL TESTS PASSED" printed by the testbench
run_tb \
    "Linear LIF (tb_linear_lif)" \
    "tb_linear_lif.sv" \
    "ALL TESTS PASSED"

# 3. Top-level integration testbench
#    Pass condition: "DONE" printed at end of initial block
run_tb \
    "Top-level integration (tb_top)" \
    "tb_top.sv" \
    "DONE"

# -----------------------------------------------------------------------------
# Summary
# -----------------------------------------------------------------------------
echo ""
echo "====================================================================="
if [[ ${FAIL} -eq 0 ]]; then
    echo -e "${GRN}ALL TESTBENCHES PASSED (${PASS}/${PASS})${NC}"
    echo "Safe to submit."
    EXIT_CODE=0
else
    echo -e "${RED}${FAIL} TESTBENCH(ES) FAILED — do not submit${NC}"
    echo "Check the .out files for details."
    EXIT_CODE=1
fi
echo "====================================================================="

# Clean up intermediate files on success, leave them on failure for debugging
if [[ ${EXIT_CODE} -eq 0 ]]; then
    rm -f ./*.vvp
fi

exit ${EXIT_CODE}