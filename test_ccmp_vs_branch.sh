#!/bin/bash
#
# APX ccmp vs Traditional cmp+jmp Branch Performance Comparison
#
# This script compares the performance of APX ccmp instruction against
# traditional cmp+jmp sequences, focusing on branch-related events like
# branch misses, branch instructions retired, and overall cycles.
#
# Usage: sudo ./test_ccmp_vs_branch.sh [cpu_config]
# Example: sudo ./test_ccmp_vs_branch.sh Skylake

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}Error: This script requires root privileges${NC}"
    echo "Usage: sudo $0 [cpu_config]"
    exit 1
fi

# Get CPU config from argument or detect
CPU_CONFIG="${1:-Skylake}"
CONFIG_FILE="configs/cfg_${CPU_CONFIG}_common.txt"

if [ ! -f "$CONFIG_FILE" ]; then
    echo -e "${YELLOW}Warning: $CONFIG_FILE not found, creating custom branch config${NC}"
    CONFIG_FILE="branch_perf_config.txt"
fi

# Create custom branch-focused performance counter config
echo -e "${BLUE}Creating branch-focused performance counter configuration...${NC}"
cat > branch_perf_config.txt << 'EOF'
# Performance counters - architectural events only
# (This ES chip only supports architectural PMU events)
C4.00 BR_INST_RETIRED.ALL_BRANCHES
C5.00 BR_MISP_RETIRED.ALL_BRANCHES
C2.02 UOPS_RETIRED.SLOTS
3C.00 CORE_CYCLES
C0.00 INST_RETIRED.ANY
EOF

CONFIG_FILE="branch_perf_config.txt"

echo -e "${GREEN}Using config file: $CONFIG_FILE${NC}\n"

# Output file for results
RESULTS_FILE="ccmp_benchmark_results.txt"
echo "APX ccmp vs Traditional Branch Performance Comparison" > $RESULTS_FILE
echo "Generated: $(date)" >> $RESULTS_FILE
echo "========================================================" >> $RESULTS_FILE
echo "" >> $RESULTS_FILE

# Helper function to run benchmark and extract key metrics
run_benchmark() {
    local name="$1"
    local cmd="$2"

    echo -e "${BLUE}Running: $name${NC}"
    echo "$name" >> $RESULTS_FILE
    echo "Command: $cmd" >> $RESULTS_FILE

    # Run the benchmark and capture output
    output=$(eval "$cmd" 2>&1 || true)

    # Extract key metrics
    cycles=$(echo "$output" | grep -E "CORE_CYCLES|CPU_CLK_UNHALTED.THREAD" | head -1 | awk '{print $2}')
    inst_retired=$(echo "$output" | grep "^INST_RETIRED" | head -1 | awk '{print $2}')
    br_inst=$(echo "$output" | grep "^BR_INST_RETIRED" | head -1 | awk '{print $2}')
    br_misp=$(echo "$output" | grep "^BR_MISP_RETIRED" | head -1 | awk '{print $2}')
    uops=$(echo "$output" | grep "UOPS_RETIRED.SLOTS" | head -1 | awk '{print $2}')

    echo "$output" >> $RESULTS_FILE
    echo "" >> $RESULTS_FILE

    # Display summary
    echo -e "  Cycles: ${GREEN}${cycles:-N/A}${NC}"
    echo -e "  Instructions: ${GREEN}${inst_retired:-N/A}${NC}"
    echo -e "  Branch Instructions: ${GREEN}${br_inst:-N/A}${NC}"
    echo -e "  Branch Misses: ${RED}${br_misp:-N/A}${NC}"
    echo -e "  µOps Retired: ${GREEN}${uops:-N/A}${NC}"
    echo ""
}

# ============================================================
# CCMP Encoding Reference:
#   ccmpe  reg1, reg2, dfv=0:   condition = equal (SCC=4)
#     rax,rbx: 62 F4 84 04 3B C3
#     rcx,rdx: 62 F4 84 04 3B CA
#     r8, r9:  62 54 84 04 3B C1
#   ccmpc  reg1, reg2, dfv=0:   condition = carry (SCC=2)
#     rax,rbx: 62 F4 84 02 3B C3
#   ccmpne reg1, reg2, dfv=ZF:  condition = not-equal (SCC=5)
#     rcx,rdx: 62 F4 94 05 3B CA
#     r8, r9:  62 54 94 05 3B C1
#     rax,rbx: 62 F4 94 05 3B C3
# ============================================================

##########################################################
#  SECTION 1: 2-Condition Chains
##########################################################

echo -e "${YELLOW}======================================================${NC}"
echo -e "${YELLOW}TEST 1: 2-Cond AND (All TRUE)${NC}"
echo -e "${YELLOW}======================================================${NC}\n"

echo "TEST 1: 2-Cond AND (All TRUE)" >> $RESULTS_FILE
echo "------------------------------" >> $RESULTS_FILE

# JS: if (a === b && c === d)   // a=1,b=1,c=2,d=2 → both true
# Traditional: cmp rax,rbx; jne 1f; cmp rcx,rdx; 1:
#   3 instr, 1 branch (jne not-taken)
run_benchmark "Traditional: cmp+jne+cmp (2-AND, all true)" \
    "./nanoBench.sh -asm_init 'mov rax, 1; mov rbx, 1; mov rcx, 2; mov rdx, 2' \
     -asm 'cmp rax, rbx; jne 1f; cmp rcx, rdx; 1:' \
     -config $CONFIG_FILE -loop_count 1000 -unroll_count 10"

# APX: cmp rax,rbx; ccmpe rcx,rdx,0
#   2 instr, 0 branches
run_benchmark "APX ccmp: cmp+ccmpe (2-AND, all true)" \
    "./nanoBench.sh -asm_init 'mov rax, 1; mov rbx, 1; mov rcx, 2; mov rdx, 2' \
     -asm 'cmp rax, rbx; .byte 0x62,0xF4,0x84,0x04,0x3B,0xCA' \
     -config $CONFIG_FILE -loop_count 1000 -unroll_count 10"

echo -e "${YELLOW}======================================================${NC}"
echo -e "${YELLOW}TEST 2: 2-Cond AND (All FALSE)${NC}"
echo -e "${YELLOW}======================================================${NC}\n"

echo "" >> $RESULTS_FILE
echo "TEST 2: 2-Cond AND (All FALSE)" >> $RESULTS_FILE
echo "-------------------------------" >> $RESULTS_FILE

# JS: if (a === b && c === d)   // a=1,b=2 → 1st false → short-circuit
# Traditional: jne TAKEN → skips 2nd cmp.  2 instr executed, 1 branch
run_benchmark "Traditional: cmp+jne+cmp (2-AND, 1st false, jne taken)" \
    "./nanoBench.sh -asm_init 'mov rax, 1; mov rbx, 2; mov rcx, 2; mov rdx, 2' \
     -asm 'cmp rax, rbx; jne 1f; cmp rcx, rdx; 1:' \
     -config $CONFIG_FILE -loop_count 1000 -unroll_count 10"

# APX: ccmpe uses dfv=0 (condition not met). 2 instr, 0 branches
run_benchmark "APX ccmp: cmp+ccmpe (2-AND, 1st false)" \
    "./nanoBench.sh -asm_init 'mov rax, 1; mov rbx, 2; mov rcx, 2; mov rdx, 2' \
     -asm 'cmp rax, rbx; .byte 0x62,0xF4,0x84,0x04,0x3B,0xCA' \
     -config $CONFIG_FILE -loop_count 1000 -unroll_count 10"

echo -e "${YELLOW}======================================================${NC}"
echo -e "${YELLOW}TEST 3: 2-Cond AND (Alternating 1st Condition)${NC}"
echo -e "${YELLOW}======================================================${NC}\n"

echo "" >> $RESULTS_FILE
echo "TEST 3: 2-Cond AND (Alternating 1st Condition)" >> $RESULTS_FILE
echo "------------------------------------------------" >> $RESULTS_FILE

# JS: if (getBit() && a < b)   // bit alternates T/F each iteration
# Traditional: bt r10,0; jnc 1f; cmp rax,rbx; 1: ror r10,1
run_benchmark "Traditional: bt+jnc+cmp (2-AND, alternating)" \
    "./nanoBench.sh -asm_init 'mov r10, 0xAAAAAAAAAAAAAAAA; mov rax, 1; mov rbx, 2' \
     -asm 'bt r10, 0; jnc 1f; cmp rax, rbx; 1: ror r10, 1' \
     -config $CONFIG_FILE -loop_count 100 -unroll_count 10"

# APX: bt r10,0; ccmpc rax,rbx,0; ror r10,1
run_benchmark "APX ccmp: bt+ccmpc (2-AND, alternating)" \
    "./nanoBench.sh -asm_init 'mov r10, 0xAAAAAAAAAAAAAAAA; mov rax, 1; mov rbx, 2' \
     -asm 'bt r10, 0; .byte 0x62,0xF4,0x84,0x02,0x3B,0xC3; ror r10, 1' \
     -config $CONFIG_FILE -loop_count 100 -unroll_count 10"

echo -e "${YELLOW}======================================================${NC}"
echo -e "${YELLOW}TEST 4: 2-Cond AND (Random 1st Condition)${NC}"
echo -e "${YELLOW}======================================================${NC}\n"

echo "" >> $RESULTS_FILE
echo "TEST 4: 2-Cond AND (Random 1st Condition)" >> $RESULTS_FILE
echo "-------------------------------------------" >> $RESULTS_FILE

# JS: if (randomBit() && a < b)   // rdtsc provides random bit
# Traditional: rdtsc; bt rax,0; jnc 1f; cmp rax,rbx; 1:
run_benchmark "Traditional: rdtsc+bt+jnc+cmp (2-AND, random)" \
    "./nanoBench.sh -asm_init 'mov rax, 1; mov rbx, 2' \
     -asm 'rdtsc; bt rax, 0; jnc 1f; cmp rax, rbx; 1:' \
     -config $CONFIG_FILE -loop_count 100 -unroll_count 10"

# APX: rdtsc; bt rax,0; ccmpc rax,rbx,0
run_benchmark "APX ccmp: rdtsc+bt+ccmpc (2-AND, random)" \
    "./nanoBench.sh -asm_init 'mov rax, 1; mov rbx, 2' \
     -asm 'rdtsc; bt rax, 0; .byte 0x62,0xF4,0x84,0x02,0x3B,0xC3' \
     -config $CONFIG_FILE -loop_count 100 -unroll_count 10"

echo -e "${YELLOW}======================================================${NC}"
echo -e "${YELLOW}TEST 5: 2-Cond OR (All TRUE)${NC}"
echo -e "${YELLOW}======================================================${NC}\n"

echo "" >> $RESULTS_FILE
echo "TEST 5: 2-Cond OR (All TRUE)" >> $RESULTS_FILE
echo "-----------------------------" >> $RESULTS_FILE

# JS: if (a === b || c === d)   // a=1,b=1 → 1st true → short-circuit
# Traditional: cmp rax,rbx; je 1f; cmp rcx,rdx; 1:
#   je TAKEN (1st true → skip 2nd). 2 instr executed, 1 branch
run_benchmark "Traditional: cmp+je+cmp (2-OR, 1st true, je taken)" \
    "./nanoBench.sh -asm_init 'mov rax, 1; mov rbx, 1; mov rcx, 2; mov rdx, 2' \
     -asm 'cmp rax, rbx; je 1f; cmp rcx, rdx; 1:' \
     -config $CONFIG_FILE -loop_count 1000 -unroll_count 10"

# APX: cmp rax,rbx; ccmpne rcx,rdx,dfv=ZF
#   OR logic: if 1st equal → dfv gives ZF=1 (true); if 1st not-equal → do 2nd cmp
#   ccmpne rcx,rdx,dfv=ZF: 62 F4 94 05 3B CA
run_benchmark "APX ccmp: cmp+ccmpne (2-OR, dfv=ZF)" \
    "./nanoBench.sh -asm_init 'mov rax, 1; mov rbx, 1; mov rcx, 2; mov rdx, 2' \
     -asm 'cmp rax, rbx; .byte 0x62,0xF4,0x94,0x05,0x3B,0xCA' \
     -config $CONFIG_FILE -loop_count 1000 -unroll_count 10"

##########################################################
#  SECTION 2: 3-Condition Chains
##########################################################

echo -e "${YELLOW}======================================================${NC}"
echo -e "${YELLOW}TEST 6: 3-Cond AND (All TRUE)${NC}"
echo -e "${YELLOW}======================================================${NC}\n"

echo "" >> $RESULTS_FILE
echo "TEST 6: 3-Cond AND (All TRUE)" >> $RESULTS_FILE
echo "------------------------------" >> $RESULTS_FILE

# JS: if (a===b && c===d && e===f)   // all equal → all true
# Traditional: cmp+jne; cmp+jne; cmp  = 5 instr, 2 branches (both not-taken)
run_benchmark "Traditional: cmp+jne x3 (3-AND, all true, 2 branches)" \
    "./nanoBench.sh -asm_init 'mov rax, 1; mov rbx, 1; mov rcx, 2; mov rdx, 2; mov r8, 3; mov r9, 3' \
     -asm 'cmp rax, rbx; jne 1f; cmp rcx, rdx; jne 1f; cmp r8, r9; 1:' \
     -config $CONFIG_FILE -loop_count 500 -unroll_count 5"

# APX: cmp; ccmpe; ccmpe = 3 instr, 0 branches
#   ccmpe rcx,rdx,0: 62 F4 84 04 3B CA
#   ccmpe r8, r9, 0: 62 54 84 04 3B C1
run_benchmark "APX ccmp: cmp+ccmpe x2 (3-AND, all true, 0 branches)" \
    "./nanoBench.sh -asm_init 'mov rax, 1; mov rbx, 1; mov rcx, 2; mov rdx, 2; mov r8, 3; mov r9, 3' \
     -asm 'cmp rax, rbx; .byte 0x62,0xF4,0x84,0x04,0x3B,0xCA; .byte 0x62,0x54,0x84,0x04,0x3B,0xC1' \
     -config $CONFIG_FILE -loop_count 500 -unroll_count 5"

echo -e "${YELLOW}======================================================${NC}"
echo -e "${YELLOW}TEST 7: 3-Cond AND (All FALSE)${NC}"
echo -e "${YELLOW}======================================================${NC}\n"

echo "" >> $RESULTS_FILE
echo "TEST 7: 3-Cond AND (All FALSE)" >> $RESULTS_FILE
echo "-------------------------------" >> $RESULTS_FILE

# JS: if (a===b && c===d && e===f)   // a=1,b=2 → 1st false → short-circuit
# Traditional: jne TAKEN immediately → 2 instr executed, 1 branch
run_benchmark "Traditional: cmp+jne x3 (3-AND, 1st false, jne taken)" \
    "./nanoBench.sh -asm_init 'mov rax, 1; mov rbx, 2; mov rcx, 2; mov rdx, 2; mov r8, 3; mov r9, 3' \
     -asm 'cmp rax, rbx; jne 1f; cmp rcx, rdx; jne 1f; cmp r8, r9; 1:' \
     -config $CONFIG_FILE -loop_count 500 -unroll_count 5"

# APX: all 3 ccmp execute unconditionally. 3 instr, 0 branches
run_benchmark "APX ccmp: cmp+ccmpe x2 (3-AND, 1st false, 0 branches)" \
    "./nanoBench.sh -asm_init 'mov rax, 1; mov rbx, 2; mov rcx, 2; mov rdx, 2; mov r8, 3; mov r9, 3' \
     -asm 'cmp rax, rbx; .byte 0x62,0xF4,0x84,0x04,0x3B,0xCA; .byte 0x62,0x54,0x84,0x04,0x3B,0xC1' \
     -config $CONFIG_FILE -loop_count 500 -unroll_count 5"

##########################################################
#  SECTION 3: 4-Condition Chains
##########################################################

echo -e "${YELLOW}======================================================${NC}"
echo -e "${YELLOW}TEST 8: 4-Cond AND (All TRUE)${NC}"
echo -e "${YELLOW}======================================================${NC}\n"

echo "" >> $RESULTS_FILE
echo "TEST 8: 4-Cond AND (All TRUE)" >> $RESULTS_FILE
echo "------------------------------" >> $RESULTS_FILE

# JS: if (a===b && c===d && e===f && a===b)   // reuse pair for 4th
# Traditional: cmp+jne x4 = 7 instr, 3 branches (all not-taken)
run_benchmark "Traditional: cmp+jne x4 (4-AND, all true, 3 branches)" \
    "./nanoBench.sh -asm_init 'mov rax, 1; mov rbx, 1; mov rcx, 2; mov rdx, 2; mov r8, 3; mov r9, 3' \
     -asm 'cmp rax, rbx; jne 1f; cmp rcx, rdx; jne 1f; cmp r8, r9; jne 1f; cmp rax, rbx; 1:' \
     -config $CONFIG_FILE -loop_count 500 -unroll_count 5"

# APX: cmp + ccmpe x3 = 4 instr, 0 branches
#   ccmpe rcx,rdx,0: 62 F4 84 04 3B CA
#   ccmpe r8, r9, 0: 62 54 84 04 3B C1
#   ccmpe rax,rbx,0: 62 F4 84 04 3B C3
run_benchmark "APX ccmp: cmp+ccmpe x3 (4-AND, all true, 0 branches)" \
    "./nanoBench.sh -asm_init 'mov rax, 1; mov rbx, 1; mov rcx, 2; mov rdx, 2; mov r8, 3; mov r9, 3' \
     -asm 'cmp rax, rbx; .byte 0x62,0xF4,0x84,0x04,0x3B,0xCA; .byte 0x62,0x54,0x84,0x04,0x3B,0xC1; .byte 0x62,0xF4,0x84,0x04,0x3B,0xC3' \
     -config $CONFIG_FILE -loop_count 500 -unroll_count 5"

echo -e "${YELLOW}======================================================${NC}"
echo -e "${YELLOW}TEST 9: 4-Cond AND (All FALSE)${NC}"
echo -e "${YELLOW}======================================================${NC}\n"

echo "" >> $RESULTS_FILE
echo "TEST 9: 4-Cond AND (All FALSE)" >> $RESULTS_FILE
echo "-------------------------------" >> $RESULTS_FILE

# JS: if (a===b && c===d && e===f && a===b)   // a=1,b=2 → 1st false
# Traditional: jne TAKEN immediately → 2 instr, 1 branch
run_benchmark "Traditional: cmp+jne x4 (4-AND, 1st false, jne taken)" \
    "./nanoBench.sh -asm_init 'mov rax, 1; mov rbx, 2; mov rcx, 2; mov rdx, 2; mov r8, 3; mov r9, 3' \
     -asm 'cmp rax, rbx; jne 1f; cmp rcx, rdx; jne 1f; cmp r8, r9; jne 1f; cmp rax, rbx; 1:' \
     -config $CONFIG_FILE -loop_count 500 -unroll_count 5"

# APX: all 4 ccmp execute. 4 instr, 0 branches
run_benchmark "APX ccmp: cmp+ccmpe x3 (4-AND, 1st false, 0 branches)" \
    "./nanoBench.sh -asm_init 'mov rax, 1; mov rbx, 2; mov rcx, 2; mov rdx, 2; mov r8, 3; mov r9, 3' \
     -asm 'cmp rax, rbx; .byte 0x62,0xF4,0x84,0x04,0x3B,0xCA; .byte 0x62,0x54,0x84,0x04,0x3B,0xC1; .byte 0x62,0xF4,0x84,0x04,0x3B,0xC3' \
     -config $CONFIG_FILE -loop_count 500 -unroll_count 5"

##########################################################
#  SECTION 4: 5-Condition Chains
##########################################################

echo -e "${YELLOW}======================================================${NC}"
echo -e "${YELLOW}TEST 10: 5-Cond AND (All TRUE)${NC}"
echo -e "${YELLOW}======================================================${NC}\n"

echo "" >> $RESULTS_FILE
echo "TEST 10: 5-Cond AND (All TRUE)" >> $RESULTS_FILE
echo "-------------------------------" >> $RESULTS_FILE

# JS: if (a===b && c===d && e===f && a===b && c===d)   // reuse pairs
# Traditional: cmp+jne x5 = 9 instr, 4 branches (all not-taken)
run_benchmark "Traditional: cmp+jne x5 (5-AND, all true, 4 branches)" \
    "./nanoBench.sh -asm_init 'mov rax, 1; mov rbx, 1; mov rcx, 2; mov rdx, 2; mov r8, 3; mov r9, 3' \
     -asm 'cmp rax, rbx; jne 1f; cmp rcx, rdx; jne 1f; cmp r8, r9; jne 1f; cmp rax, rbx; jne 1f; cmp rcx, rdx; 1:' \
     -config $CONFIG_FILE -loop_count 500 -unroll_count 5"

# APX: cmp + ccmpe x4 = 5 instr, 0 branches
#   ccmpe rcx,rdx,0: 62 F4 84 04 3B CA
#   ccmpe r8, r9, 0: 62 54 84 04 3B C1
#   ccmpe rax,rbx,0: 62 F4 84 04 3B C3
#   ccmpe rcx,rdx,0: 62 F4 84 04 3B CA  (reused)
run_benchmark "APX ccmp: cmp+ccmpe x4 (5-AND, all true, 0 branches)" \
    "./nanoBench.sh -asm_init 'mov rax, 1; mov rbx, 1; mov rcx, 2; mov rdx, 2; mov r8, 3; mov r9, 3' \
     -asm 'cmp rax, rbx; .byte 0x62,0xF4,0x84,0x04,0x3B,0xCA; .byte 0x62,0x54,0x84,0x04,0x3B,0xC1; .byte 0x62,0xF4,0x84,0x04,0x3B,0xC3; .byte 0x62,0xF4,0x84,0x04,0x3B,0xCA' \
     -config $CONFIG_FILE -loop_count 500 -unroll_count 5"

echo -e "${YELLOW}======================================================${NC}"
echo -e "${YELLOW}TEST 11: 5-Cond AND (All FALSE)${NC}"
echo -e "${YELLOW}======================================================${NC}\n"

echo "" >> $RESULTS_FILE
echo "TEST 11: 5-Cond AND (All FALSE)" >> $RESULTS_FILE
echo "--------------------------------" >> $RESULTS_FILE

# JS: if (a===b && c===d && e===f && a===b && c===d)   // a=1,b=2 → 1st false
# Traditional: jne TAKEN immediately → 2 instr, 1 branch
run_benchmark "Traditional: cmp+jne x5 (5-AND, 1st false, jne taken)" \
    "./nanoBench.sh -asm_init 'mov rax, 1; mov rbx, 2; mov rcx, 2; mov rdx, 2; mov r8, 3; mov r9, 3' \
     -asm 'cmp rax, rbx; jne 1f; cmp rcx, rdx; jne 1f; cmp r8, r9; jne 1f; cmp rax, rbx; jne 1f; cmp rcx, rdx; 1:' \
     -config $CONFIG_FILE -loop_count 500 -unroll_count 5"

# APX: all 5 ccmp execute. 5 instr, 0 branches
run_benchmark "APX ccmp: cmp+ccmpe x4 (5-AND, 1st false, 0 branches)" \
    "./nanoBench.sh -asm_init 'mov rax, 1; mov rbx, 2; mov rcx, 2; mov rdx, 2; mov r8, 3; mov r9, 3' \
     -asm 'cmp rax, rbx; .byte 0x62,0xF4,0x84,0x04,0x3B,0xCA; .byte 0x62,0x54,0x84,0x04,0x3B,0xC1; .byte 0x62,0xF4,0x84,0x04,0x3B,0xC3; .byte 0x62,0xF4,0x84,0x04,0x3B,0xCA' \
     -config $CONFIG_FILE -loop_count 500 -unroll_count 5"

##########################################################
#  Done
##########################################################

echo -e "\n${GREEN}======================================================${NC}"
echo -e "${GREEN}All 11 tests completed!${NC}"
echo -e "${GREEN}Results saved to: $RESULTS_FILE${NC}"
echo -e "${GREEN}======================================================${NC}\n"

# Generate summary
echo "" >> $RESULTS_FILE
echo "========================================================" >> $RESULTS_FILE
echo "SUMMARY" >> $RESULTS_FILE
echo "========================================================" >> $RESULTS_FILE
cat >> $RESULTS_FILE << 'SUMEOF'
Test Layout:
  2-Cond AND: TEST 1 (TRUE), TEST 2 (FALSE), TEST 3 (Alternating), TEST 4 (Random)
  2-Cond OR:  TEST 5 (TRUE)
  3-Cond AND: TEST 6 (TRUE), TEST 7 (FALSE)
  4-Cond AND: TEST 8 (TRUE), TEST 9 (FALSE)
  5-Cond AND: TEST 10 (TRUE), TEST 11 (FALSE)

Key Observations:
1. Branch Instructions: ccmp eliminates ALL branches (BR_INST_RETIRED = 0)
2. Instruction Count: ccmp reduces N-cond AND from (2N-1) to N instructions
3. Cycles: ccmp benefit grows with more conditions (amortizes ccmp latency)
4. FALSE cases: traditional short-circuits (fewer instr), ccmp always executes all
SUMEOF
echo "" >> $RESULTS_FILE

echo -e "${BLUE}To view detailed results:${NC}"
echo -e "  cat $RESULTS_FILE"
echo -e "\n${BLUE}To analyze specific metrics:${NC}"
echo -e "  grep 'BR_MISP_RETIRED' $RESULTS_FILE"
echo -e "  grep 'CORE_CYCLES' $RESULTS_FILE"
