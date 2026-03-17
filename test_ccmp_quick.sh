#!/bin/bash
#
# Quick APX ccmp vs Branch Performance Test
# Focus on the most important scenarios
#

set -e

if [ "$EUID" -ne 0 ]; then
    echo "Error: Requires root privileges"
    echo "Usage: sudo $0"
    exit 1
fi

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Create minimal branch config (architectural events only for ES chip)
cat > branch_quick_config.txt << 'EOF'
C4.00 BR_INST_RETIRED.ALL_BRANCHES
C5.00 BR_MISP_RETIRED.ALL_BRANCHES
C2.02 UOPS_RETIRED.SLOTS
3C.00 CORE_CYCLES
C0.00 INST_RETIRED.ANY
EOF

CONFIG="branch_quick_config.txt"

echo -e "${YELLOW}========================================${NC}"
echo -e "${YELLOW}Quick ccmp vs Branch Performance Test${NC}"
echo -e "${YELLOW}========================================${NC}\n"

# Test 1: Unpredictable branches (the killer scenario)
echo -e "${BLUE}Test 1: Unpredictable Branch Pattern (0xAAAA = alternating)${NC}"
echo -e "${GREEN}Traditional (cmp+jmp):${NC}"
./nanoBench.sh \
  -asm_init "mov r8, 0xAAAAAAAAAAAAAAAA; mov rax, 1; mov rbx, 2" \
  -asm "bt r8, 0; jnc 1f; cmp rax, rbx; 1: ror r8, 1" \
  -config $CONFIG -loop_count 100 -unroll_count 10 | \
  grep -E "CORE_CYCLES|BR_INST_RETIRED|BR_MISP_RETIRED|UOPS_RETIRED"

echo -e "\n${GREEN}APX ccmp:${NC}"
# ccmpc rax, rbx, 0 = EVEX{P0=F4,P1=84(W=1,dfv=0),P2=02(cc=carry)} CMP(3B) ModRM(C3=rax,rbx)
./nanoBench.sh \
  -asm_init "mov r8, 0xAAAAAAAAAAAAAAAA; mov rax, 1; mov rbx, 2" \
  -asm "bt r8, 0; .byte 0x62,0xF4,0x84,0x02,0x3B,0xC3; ror r8, 1" \
  -config $CONFIG -loop_count 100 -unroll_count 10 | \
  grep -E "CORE_CYCLES|BR_INST_RETIRED|BR_MISP_RETIRED|UOPS_RETIRED"

echo ""

# Test 2: Condition chains (if A && B && C)
echo -e "${BLUE}Test 2: Condition Chain (A==B && C==D && E==F)${NC}"
echo -e "${GREEN}Traditional (multiple branches):${NC}"
./nanoBench.sh \
  -asm_init "mov rax, 1; mov rbx, 1; mov rcx, 2; mov rdx, 2; mov r8, 3; mov r9, 3" \
  -asm "cmp rax, rbx; jne 1f; cmp rcx, rdx; jne 1f; cmp r8, r9; 1:" \
  -config $CONFIG -loop_count 500 -unroll_count 5 | \
  grep -E "CORE_CYCLES|BR_INST_RETIRED|BR_MISP_RETIRED|UOPS_RETIRED"

echo -e "\n${GREEN}APX ccmp (chained):${NC}"
# ccmpe rcx, rdx, 0 = EVEX{F4,84,04(cc=equal)} 3B CA(rcx,rdx)
# ccmpe r8, r9, 0  = EVEX{54(~R=0,~B=0),84,04} 3B C1(r8,r9)
./nanoBench.sh \
  -asm_init "mov rax, 1; mov rbx, 1; mov rcx, 2; mov rdx, 2; mov r8, 3; mov r9, 3" \
  -asm "cmp rax, rbx; .byte 0x62,0xF4,0x84,0x04,0x3B,0xCA; .byte 0x62,0x54,0x84,0x04,0x3B,0xC1" \
  -config $CONFIG -loop_count 500 -unroll_count 5 | \
  grep -E "CORE_CYCLES|BR_INST_RETIRED|BR_MISP_RETIRED|UOPS_RETIRED"

echo ""

# Test 3: Random pattern (worst case for branch predictor)
echo -e "${BLUE}Test 3: Random Pattern (rdtsc-based)${NC}"
echo -e "${GREEN}Traditional (random branches):${NC}"
./nanoBench.sh \
  -asm_init "mov rax, 1; mov rbx, 2" \
  -asm "rdtsc; bt rax, 0; jnc 1f; cmp rax, rbx; 1:" \
  -config $CONFIG -loop_count 100 -unroll_count 10 | \
  grep -E "CORE_CYCLES|BR_INST_RETIRED|BR_MISP_RETIRED|UOPS_RETIRED"

echo -e "\n${GREEN}APX ccmp (no branches):${NC}"
# ccmpc rax, rbx, 0 = 0x62,0xF4,0x84,0x02,0x3B,0xC3
./nanoBench.sh \
  -asm_init "mov rax, 1; mov rbx, 2" \
  -asm "rdtsc; bt rax, 0; .byte 0x62,0xF4,0x84,0x02,0x3B,0xC3" \
  -config $CONFIG -loop_count 100 -unroll_count 10 | \
  grep -E "CORE_CYCLES|BR_INST_RETIRED|BR_MISP_RETIRED|UOPS_RETIRED"

echo ""
echo -e "${YELLOW}========================================${NC}"
echo -e "${YELLOW}Key Metrics to Compare:${NC}"
echo -e "${YELLOW}========================================${NC}"
echo -e "1. ${RED}BR_MISP_RETIRED${NC}: Branch mispredictions (lower is better)"
echo -e "2. ${BLUE}BR_INST_RETIRED${NC}: Total branch instructions (ccmp should be 0 or much lower)"
echo -e "3. ${GREEN}CORE_CYCLES${NC}: Total cycles (ccmp should be lower in unpredictable cases)"
echo ""
echo -e "${GREEN}Expected Results:${NC}"
echo -e "  • ccmp should eliminate branch instructions (BR_INST_RETIRED ≈ 0)"
echo -e "  • ccmp should eliminate branch misses (BR_MISP_RETIRED ≈ 0)"
echo -e "  • ccmp should be faster when branches are unpredictable"
