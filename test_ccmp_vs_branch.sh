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
    inst_retired=$(echo "$output" | grep "INST_RETIRED" | head -1 | awk '{print $2}')
    br_inst=$(echo "$output" | grep "BR_INST_RETIRED" | head -1 | awk '{print $2}')
    br_misp=$(echo "$output" | grep "BR_MISP_RETIRED" | head -1 | awk '{print $2}')
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

echo -e "${YELLOW}======================================================${NC}"
echo -e "${YELLOW}TEST 1: Predictable Branch Pattern (Best Case)${NC}"
echo -e "${YELLOW}======================================================${NC}\n"

echo "TEST 1: Predictable Branch Pattern" >> $RESULTS_FILE
echo "-----------------------------------" >> $RESULTS_FILE

# Traditional: cmp + conditional jump (always taken)
run_benchmark "Traditional: cmp + je (predictable, always taken)" \
    "./nanoBench.sh -asm_init 'mov rax, 1; mov rbx, 1; mov rcx, 2; mov rdx, 3' \
     -asm 'cmp rax, rbx; je 1f; xor rcx, rcx; 1: cmp rcx, rdx' \
     -config $CONFIG_FILE -loop_count 1000 -unroll_count 10"

# APX ccmp: conditional compare (no branch)
# ccmpe rcx, rdx, 0: if ZF=1 then cmp rcx,rdx; else flags=0
# Encoding: EVEX{F4,84(W=1,dfv=0),04(cc=equal)} 3B CA(rcx,rdx)
run_benchmark "APX ccmp: Conditional compare (no branch)" \
    "./nanoBench.sh -asm_init 'mov rax, 1; mov rbx, 1; mov rcx, 2; mov rdx, 3' \
     -asm 'cmp rax, rbx; .byte 0x62,0xF4,0x84,0x04,0x3B,0xCA' \
     -config $CONFIG_FILE -loop_count 1000 -unroll_count 10"

echo -e "${YELLOW}======================================================${NC}"
echo -e "${YELLOW}TEST 2: Unpredictable Branch Pattern (Alternating)${NC}"
echo -e "${YELLOW}======================================================${NC}\n"

echo "" >> $RESULTS_FILE
echo "TEST 2: Unpredictable Branch Pattern (Alternating)" >> $RESULTS_FILE
echo "--------------------------------------------------" >> $RESULTS_FILE

# Traditional: alternating pattern (0xAAAA... = 10101010...)
run_benchmark "Traditional: cmp + jc (alternating 0101 pattern)" \
    "./nanoBench.sh -asm_init 'mov r10, 0xAAAAAAAAAAAAAAAA; mov rax, 1; mov rbx, 2' \
     -asm 'bt r10, 0; jnc 1f; cmp rax, rbx; 1: ror r10, 1' \
     -config $CONFIG_FILE -loop_count 100 -unroll_count 10"

# APX ccmp: no branch needed
# ccmpc rax, rbx, 0: if CF=1 then cmp rax,rbx; else flags=0
# Encoding: EVEX{F4,84(W=1,dfv=0),02(cc=carry)} 3B C3(rax,rbx)
run_benchmark "APX ccmp: Conditional compare (no branch)" \
    "./nanoBench.sh -asm_init 'mov r10, 0xAAAAAAAAAAAAAAAA; mov rax, 1; mov rbx, 2' \
     -asm 'bt r10, 0; .byte 0x62,0xF4,0x84,0x02,0x3B,0xC3; ror r10, 1' \
     -config $CONFIG_FILE -loop_count 100 -unroll_count 10"

echo -e "${YELLOW}======================================================${NC}"
echo -e "${YELLOW}TEST 3: Complex Condition Chain${NC}"
echo -e "${YELLOW}======================================================${NC}\n"

echo "" >> $RESULTS_FILE
echo "TEST 3: Complex Condition Chain" >> $RESULTS_FILE
echo "-------------------------------" >> $RESULTS_FILE

# Traditional: multiple branches (if A && B && C pattern)
run_benchmark "Traditional: Multiple cmp + jmp chain" \
    "./nanoBench.sh -asm_init 'mov rax, 1; mov rbx, 1; mov rcx, 2; mov rdx, 2; mov r8, 3; mov r9, 3' \
     -asm 'cmp rax, rbx; jne 1f; cmp rcx, rdx; jne 1f; cmp r8, r9; 1:' \
     -config $CONFIG_FILE -loop_count 500 -unroll_count 5"

# APX ccmp: chained conditional compares (using ccmp's conditional execution)
# ccmp rule: IF (flags satisfy condition) THEN compare ELSE use default flags
# ccmpe rcx, rdx, 0: EVEX{F4,84,04} 3B CA
# ccmpe r8, r9, 0:  EVEX{54(~R=0,~B=0),84,04} 3B C1
run_benchmark "APX ccmp: Chained conditional compares" \
    "./nanoBench.sh -asm_init 'mov rax, 1; mov rbx, 1; mov rcx, 2; mov rdx, 2; mov r8, 3; mov r9, 3' \
     -asm 'cmp rax, rbx; .byte 0x62,0xF4,0x84,0x04,0x3B,0xCA; .byte 0x62,0x54,0x84,0x04,0x3B,0xC1' \
     -config $CONFIG_FILE -loop_count 500 -unroll_count 5"

echo -e "${YELLOW}======================================================${NC}"
echo -e "${YELLOW}TEST 4: Random Branch Pattern (Worst Case)${NC}"
echo -e "${YELLOW}======================================================${NC}\n"

echo "" >> $RESULTS_FILE
echo "TEST 4: Random Branch Pattern" >> $RESULTS_FILE
echo "-----------------------------" >> $RESULTS_FILE

# Traditional: random pattern using rdtsc
run_benchmark "Traditional: cmp + jc (random with rdtsc)" \
    "./nanoBench.sh -asm_init 'mov rax, 1; mov rbx, 2' \
     -asm 'rdtsc; bt rax, 0; jnc 1f; cmp rax, rbx; 1:' \
     -config $CONFIG_FILE -loop_count 100 -unroll_count 10"

# APX ccmp: no branch
# ccmpc rax, rbx, 0: EVEX{F4,84,02} 3B C3
run_benchmark "APX ccmp: Conditional compare (random condition)" \
    "./nanoBench.sh -asm_init 'mov rax, 1; mov rbx, 2' \
     -asm 'rdtsc; bt rax, 0; .byte 0x62,0xF4,0x84,0x02,0x3B,0xC3' \
     -config $CONFIG_FILE -loop_count 100 -unroll_count 10"

echo -e "${YELLOW}======================================================${NC}"
echo -e "${YELLOW}TEST 5: Nested Conditions with Early Exit${NC}"
echo -e "${YELLOW}======================================================${NC}\n"

echo "" >> $RESULTS_FILE
echo "TEST 5: Nested Conditions with Early Exit" >> $RESULTS_FILE
echo "-----------------------------------------" >> $RESULTS_FILE

# Traditional: nested if-else with early exit
run_benchmark "Traditional: Nested branches (if-else chain)" \
    "./nanoBench.sh -asm_init 'mov r10, 0x5555555555555555; mov rax, 1; mov rbx, 1' \
     -asm 'bt r10, 0; jc 1f; cmp rax, rbx; jne 2f; inc rcx; jmp 3f; 1: dec rcx; jmp 3f; 2: xor rcx, rcx; 3: ror r10, 1' \
     -config $CONFIG_FILE -loop_count 50 -unroll_count 10"

# APX ccmp: conditional execution without branches
# ccmpc rax, rbx, 0: EVEX{F4,84,02} 3B C3
run_benchmark "APX ccmp: Conditional selection (cmov + ccmp)" \
    "./nanoBench.sh -asm_init 'mov r10, 0x5555555555555555; mov rax, 1; mov rbx, 1; xor rcx, rcx' \
     -asm 'bt r10, 0; .byte 0x62,0xF4,0x84,0x02,0x3B,0xC3; cmovne rcx, rax; ror r10, 1' \
     -config $CONFIG_FILE -loop_count 50 -unroll_count 10"

echo -e "${YELLOW}======================================================${NC}"
echo -e "${YELLOW}TEST 6: Branch with Side Effects${NC}"
echo -e "${YELLOW}======================================================${NC}\n"

echo "" >> $RESULTS_FILE
echo "TEST 6: Branch with Side Effects" >> $RESULTS_FILE
echo "--------------------------------" >> $RESULTS_FILE

# Traditional: branch with memory access
run_benchmark "Traditional: cmp + jne with memory access" \
    "./nanoBench.sh -asm_init 'mov rax, 1; mov rbx, 2; mov r14, r14' \
     -asm 'cmp rax, rbx; je 1f; mov [r14], rax; inc rax; 1:' \
     -config $CONFIG_FILE -loop_count 100 -unroll_count 5"

# APX ccmp: conditional compare + conditional move
# ccmpe rax, rbx, 4(dfv=SF): if ZF=1 then cmp rax,rbx; else SF=1,ZF=0
# Encoding: EVEX{F4,A4(W=1,dfv=SF=0100),04(cc=equal)} 3B C3(rax,rbx)
run_benchmark "APX ccmp: ccmp + cmove pattern" \
    "./nanoBench.sh -asm_init 'mov rax, 1; mov rbx, 2; mov r14, r14' \
     -asm '.byte 0x62,0xF4,0xA4,0x04,0x3B,0xC3; cmovne r8, rax; mov [r14], r8; inc rax' \
     -config $CONFIG_FILE -loop_count 100 -unroll_count 5"

echo -e "\n${GREEN}======================================================${NC}"
echo -e "${GREEN}All tests completed!${NC}"
echo -e "${GREEN}Results saved to: $RESULTS_FILE${NC}"
echo -e "${GREEN}======================================================${NC}\n"

# Generate summary
echo "" >> $RESULTS_FILE
echo "========================================================" >> $RESULTS_FILE
echo "SUMMARY" >> $RESULTS_FILE
echo "========================================================" >> $RESULTS_FILE
echo "Key Observations:" >> $RESULTS_FILE
echo "1. Branch Instructions: ccmp should have fewer BR_INST_RETIRED" >> $RESULTS_FILE
echo "2. Branch Misses: ccmp should have fewer BR_MISP_RETIRED (especially in unpredictable cases)" >> $RESULTS_FILE
echo "3. Cycles: ccmp should have fewer cycles when branch misprediction cost is high" >> $RESULTS_FILE
echo "4. µOps: Compare µOps to understand microarchitectural efficiency" >> $RESULTS_FILE
echo "" >> $RESULTS_FILE

echo -e "${BLUE}To view detailed results:${NC}"
echo -e "  cat $RESULTS_FILE"
echo -e "\n${BLUE}To analyze specific metrics:${NC}"
echo -e "  grep 'BR_MISP_RETIRED' $RESULTS_FILE"
echo -e "  grep 'CORE_CYCLES' $RESULTS_FILE"
