; ============================================================
; 题目
; ------------------------------------------------------------
; 实验六 8259 中断实验
; 1. 用手动产单脉冲作为中断请求信号。要求每按一次开关产生一次中断，
; 在数码管上依次显示 0,1, .. 9；中断 10 次后程序退出。
; ============================================================
; 线路连接
; ------------------------------------------------------------
; 主机 SD0-SD7 -- 8255A、主从 8259A 的 D0-D7（箱内已连接）
; 主机 SIOR/SIOW -- 8255A、主从 8259A 的 RD/WR（箱内已连接）
; 主机 SA0/SA1 -- 8255A A0/A1（箱内已连接）
; 主机 SA0 -- 主从 8259A 的 A0（箱内已连接）
; CS0 -- 8255CS（8255A 端口 200H-203H）
; CS1 -- M8259CS（主片端口 210H-211H）
; CS2 -- S8259CS（从片端口 220H-221H）
; 主 8259A INT -- 主机 INTR
; 主机 INTA -- 主 8259A INTA（主从 INTA 在箱内相连）
; 主 8259A CAS0-CAS2 -- 从 8259A CAS0-CAS2（箱内已连接）
; 从 8259A SINT -- 主 8259A IRQ7（ICW3 的级联配置，IRQ7 已屏蔽，可省略此跳线）
; 8255A PA0-PA7 -- J2(LEDB) a-h（依次对应，高电平点亮）
; 8255A PC0 -- J3(BIT) BIG2（个位，高电平选通）
; 8255A PC1 -- J3(BIT) BIG1（十位，高电平选通）
; J16 AN1 正脉冲输出 -- 主 8259A IRQ0（上升沿触发）
; 图 6-1 的示例使用其他片选和 IRQ2，以上跳线按本程序的端口和掩码列出。
; ============================================================

.model small
.486

PA_8255 EQU 200H                 ; A 口，输出数码管段码。
PB_8255 EQU PA_8255+1            ; B 口，本题未用。
PC_8255 EQU PA_8255+2            ; C 口，PC0 和 PC1 输出位选。
KZ_8255 EQU PA_8255+3            ; 8255A 控制端口，设置工作方式和引脚方向。
M8259A0 EQU 210H                 ; 主片命令口（A0=0），写 ICW1 和 EOI。
M8259A1 EQU 211H                 ; 主片数据口（A0=1），写 ICW2-ICW4 和屏蔽字。
S8259A0 EQU 220H                 ; 从片命令口（A0=0），写 ICW1。
S8259A1 EQU 221H                 ; 从片数据口（A0=1），写 ICW2-ICW4 和屏蔽字。

DATA SEGMENT
buffer db 1024 dup(?)
counter db 0H                    ; 显示初值为 00，第一次中断后显示 01。
; D0-D6 依次对应 a-g，1 点亮对应的段。
; 段码按数字 0-9 排列，D7 恒为 1，接到 h 时小数点亮。
LEDS db 0BFH, 86H, 0DBH, 0CFH, 0E6H
    db 0EDH, 0FDH, 87H, 0FFH, 0EFH
flag db 0
DATA ENDS

CODE SEGMENT
ASSUME CS:CODE, DS:DATA
START:
MOV AX, DATA
MOV DS, AX
CALL INIT8255
CALL INITM8259
CALL INITS8259
cli
CALL setINTVector
CALL cleanMask
sti
; 前台持续扫描两位数码管，计满十次后仍继续运行。
AGAIN:
CALL DISP
JMP AGAIN

setINTVector PROC
PUSH DS
PUSH AX
PUSH DX

MOV AX, 0
MOV DS, AX
MOV AX, OFFSET intHandler
MOV SI, 64                       ; 实模式向量 10H 的表项在 0000:0040H（10H × 4）。
MOV [SI], AX                     ; 表项的低字保存入口偏移 IP。
MOV AX, CS
MOV [SI+2], AX                   ; 表项的高字保存入口段地址 CS。

POP DX
POP AX
POP DS
RET
setINTVector ENDP

cleanMask PROC
MOV DX, M8259A1
IN AL, DX
AND AL, 11111110B                ; 只清 OCW1 的 D0，开放主片 IRQ0。
OUT DX, AL
RET
cleanMask ENDP

; 中断会改写 AL、BL 和 DX，可能干扰前台查表或写端口。
intHandler PROC
CALL ADDCOUNTER
CALL SENDM8259EOI
STI
IRET
intHandler ENDP

INIT8255 PROC
MOV DX, KZ_8255
; D7=1 选择方式设置控制字。
; D6-D5=00 将 A 组（PA、PC4-PC7）设为方式 0。
; D4=0 将 PA0-PA7 设为输出，分别驱动数码管的 a-h。
; D3=0 将 PC4-PC7 设为输出，这四位无外设。
; D2=0 将 B 组（PB、PC0-PC3）设为方式 0。
; D1=0 将 PB0-PB7 设为输出，B 口无外设。
; D0=0 将 PC0-PC3 设为输出，PC0 和 PC1 分别高电平选通个位和十位。
MOV AL, 10000000B
OUT DX, AL                       ; 将 80H 写入 203H，使端口配置生效。
RET
INIT8255 ENDP

INITM8259 PROC
MOV DX, M8259A0
MOV AL, 11H                      ; ICW1 的 D3=0 选上升沿，D1=0 选级联，D0=1 要求写 ICW4。
OUT DX, AL

MOV DX, M8259A1
MOV AL, 16                       ; ICW2 设置向量基址 10H，对应 IRQ0-IRQ7 的向量 10H-17H。
OUT DX, AL

MOV AL, 10000000B                ; ICW3 的 D7=1，配置主片 IRQ7 连接从片。
OUT DX, AL

MOV AL, 01H                      ; ICW4 的 D0=1 选 8086 模式，D3=0 选非缓冲，D1=0 选手动 EOI。
OUT DX, AL

MOV AL, 11111111B                ; OCW1 先屏蔽全部 IRQ，安装向量后再开放 IRQ0。
OUT DX, AL
RET
INITM8259 ENDP

INITS8259 PROC
MOV DX, S8259A0
MOV AL, 11H                      ; ICW1 的 D3=0 选上升沿，D1=0 选级联，D0=1 要求写 ICW4。
OUT DX, AL

MOV DX, S8259A1
MOV AL, 70H                      ; ICW2 设置从片向量范围 70H-77H。
OUT DX, AL

MOV AL, 07                       ; ICW3 的从片标识为 7，对应主片 IRQ7。
OUT DX, AL

MOV AL, 01H                      ; ICW4 的 D0=1 选 8086 模式，D3=0 选非缓冲，D1=0 选手动 EOI。
OUT DX, AL

MOV AL, 11111111B                ; OCW1 屏蔽从片的全部 IRQ。
OUT DX, AL
RET
INITS8259 ENDP

ADDCOUNTER PROC
PUSH AX
INC COUNTER
XOR AX, AX
MOV AL, COUNTER
MOV BL, 10
DIV BL
MOV COUNTER, AH                  ; 取除以 10 的余数，计数在 0-9 间循环。
POP AX
RET
ADDCOUNTER ENDP

SENDM8259EOI PROC
PUSHF
MOV AL, 20H                      ; OCW2 非特定 EOI，清除主片 IRQ0 的在服务标志。
MOV DX, M8259A0
OUT DX, AL
POPF
RET
SENDM8259EOI ENDP

DISP PROC
PUSHF
XOR AX, AX
MOV AL, COUNTER
MOV BL, 10
DIV BL
MOV CX, AX                       ; 除以 10 的商在 CL（十位），余数在 CH（个位）。

MOV AL, 1B                       ; PC0=1 选通个位，PC1=0 关闭十位。
MOV DX, PC_8255
OUT DX, AL
MOV BX, OFFSET LEDS
MOV AL, CH
XLAT                             ; 用 CH 中的个位数字查 LEDS 段码表。
MOV DX, PA_8255
OUT DX, AL
MOV AL, 0                        ; 切换到十位前把 PA 的段线拉低。
OUT DX, AL

MOV AL, 10B                      ; PC1=1 选通十位，PC0=0 关闭个位。
MOV DX, PC_8255
OUT DX, AL
MOV BX, OFFSET LEDS
MOV AL, CL
XLAT
MOV DX, PA_8255
OUT DX, AL
MOV AL, 0
OUT DX, AL

POPF
RET
DISP ENDP

CODE ENDS
END START
