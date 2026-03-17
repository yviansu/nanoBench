## APX ccmp rule
### preudocode for ccmp
```
IF (src_flags satisfies scc) :  
    dst_flags = compare(src1 ,src2)  
ELSE:  
    dst_flags = flags(evex.[of, sf, zf, cf] )
```
### ccmp instructions
FROM
ND
NF
PP
OPC
REG
MOD
ICLASS
OPERANDS

Legacy-map0
0
0
NP
38
CCMPscc
m8/r8_b, r8_r, dfv

Legacy-map0
0
0
NP/66
39
CCMPscc
mv/rv_b, rv_r, dfv

Legacy-map0
0
0
NP
3A
CCMPscc
r8_r, m8/r8_b, dfv

Legacy-map0
0
0
NP/66
3B
CCMPscc
rv_r, mv/rv_b, dfv

Legacy-map0
0
0
NP
80
7
CCMPscc
m8/r8_b, i8, dfv

Legacy-map0
0
0
NP/66
81
7
CCMPscc
mv/rv_b, iz, dfv

Legacy-map0
0
0
NP/66
83
7
CCMPscc
mv/rv_b, i8, dfv
