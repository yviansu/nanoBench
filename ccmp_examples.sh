#!/bin/bash
#
# Manual ccmp Testing Examples
# These are individual commands you can run to test specific scenarios
#

# NOTE: Run each command with sudo
# Example: sudo bash -c "command_here"

echo "=== Manual ccmp Test Examples ==="
echo ""
echo "Before running tests, create the config file:"
echo ""
cat << 'EOF'
cat > branch_config.txt << 'CONFIG'
C4.00 BR_INST_RETIRED.ALL_BRANCHES
C5.00 BR_MISP_RETIRED.ALL_BRANCHES
3C.00 CORE_CYCLES
C0.00 INST_RETIRED.ANY
CONFIG
EOF

echo ""
echo "=== Example 1: Basic ccmp vs cmp+jmp ==="
echo ""
echo "Traditional:"
echo 'sudo ./nanoBench.sh -asm "cmp rax, rbx; je .+2; xor rcx, rcx" -config branch_config.txt -unroll_count 100'
echo ""
echo "APX ccmp:"
echo 'sudo ./nanoBench.sh -asm "cmp rax, rbx; ccmpe rcx, rdx, 0" -config branch_config.txt -unroll_count 100'
echo ""

echo "=== Example 2: Unpredictable Pattern (Critical Test) ==="
echo ""
echo "Traditional (will have branch misses):"
echo 'sudo ./nanoBench.sh -asm_init "mov r15, 0xAAAAAAAAAAAAAAAA; mov rax, 1; mov rbx, 2" -asm "bt r15, 0; jnc .+4; cmp rax, rbx; ror r15, 1" -config branch_config.txt -loop_count 100 -unroll_count 10'
echo ""
echo "APX ccmp (should eliminate branches):"
echo 'sudo ./nanoBench.sh -asm_init "mov r15, 0xAAAAAAAAAAAAAAAA; mov rax, 1; mov rbx, 2" -asm "bt r15, 0; ccmpc rax, rbx, 0; ror r15, 1" -config branch_config.txt -loop_count 100 -unroll_count 10'
echo ""

echo "=== Example 3: Condition Chain (A && B && C) ==="
echo ""
echo "Traditional (multiple branches):"
echo 'sudo ./nanoBench.sh -asm_init "mov rax, 1; mov rbx, 1; mov rcx, 2; mov rdx, 2; mov r8, 3; mov r9, 3" -asm "cmp rax, rbx; jne done; cmp rcx, rdx; jne done; cmp r8, r9; done:" -config branch_config.txt -loop_count 500'
echo ""
echo "APX ccmp (chained conditional compares):"
echo 'sudo ./nanoBench.sh -asm_init "mov rax, 1; mov rbx, 1; mov rcx, 2; mov rdx, 2; mov r8, 3; mov r9, 3" -asm "cmp rax, rbx; ccmpe rcx, rdx, 0; ccmpe r8, r9, 0" -config branch_config.txt -loop_count 500'
echo ""

echo "=== Example 4: Random Pattern (Worst Case for Branch Predictor) ==="
echo ""
echo "Traditional:"
echo 'sudo ./nanoBench.sh -asm_init "mov rax, 1; mov rbx, 2" -asm "rdtsc; bt rax, 0; jnc .+4; cmp rax, rbx" -config branch_config.txt -loop_count 100'
echo ""
echo "APX ccmp:"
echo 'sudo ./nanoBench.sh -asm_init "mov rax, 1; mov rbx, 2" -asm "rdtsc; bt rax, 0; ccmpc rax, rbx, 0" -config branch_config.txt -loop_count 100'
echo ""

echo "=== Example 5: Different ccmp Conditions ==="
echo ""
echo "ccmp with 'equal' condition:"
echo 'sudo ./nanoBench.sh -asm "cmp rax, rbx; ccmpe rcx, rdx, 0" -config branch_config.txt'
echo ""
echo "ccmp with 'not equal' condition:"
echo 'sudo ./nanoBench.sh -asm "cmp rax, rbx; ccmpne rcx, rdx, 0" -config branch_config.txt'
echo ""
echo "ccmp with 'less than' condition:"
echo 'sudo ./nanoBench.sh -asm "cmp rax, rbx; ccmpl rcx, rdx, 0" -config branch_config.txt'
echo ""
echo "ccmp with 'greater than' condition:"
echo 'sudo ./nanoBench.sh -asm "cmp rax, rbx; ccmpg rcx, rdx, 0" -config branch_config.txt'
echo ""

echo "=== Key Metrics to Watch ==="
echo ""
echo "BR_INST_RETIRED.ALL_BRANCHES  - Total branch instructions (ccmp should be much lower)"
echo "BR_MISP_RETIRED.ALL_BRANCHES  - Branch mispredictions (ccmp should be 0)"
echo "CORE_CYCLES                   - CPU cycles (ccmp should be lower in unpredictable cases)"
echo "INST_RETIRED.ANY              - Total instructions (should be similar or lower)"
echo ""

echo "=== Understanding dfv (Default Flags Value) ==="
echo ""
echo "The dfv parameter in ccmp sets flags when condition is NOT met:"
echo "  dfv = 0  : All flags clear (ZF=0, CF=0, SF=0, OF=0)"
echo "  dfv = 4  : Zero flag set (ZF=1)"
echo "  dfv = 8  : Carry flag set (CF=1)"
echo "  dfv = 12 : Both ZF and CF set"
echo ""
echo "Example with dfv:"
echo 'sudo ./nanoBench.sh -asm "cmp rax, rbx; ccmpe rcx, rdx, 4" -config branch_config.txt'
echo "(If rax != rbx, flags will be set to 4, which means ZF=1)"
echo ""

echo "=== Run the automated tests ==="
echo ""
echo "Quick test (3 key scenarios):"
echo "  sudo ./test_ccmp_quick.sh"
echo ""
echo "Comprehensive test (6 scenarios + detailed report):"
echo "  sudo ./test_ccmp_vs_branch.sh"
echo ""
