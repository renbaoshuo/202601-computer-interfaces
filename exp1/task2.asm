; ============================================================
; 题目
; ------------------------------------------------------------
; 2. 试在实验箱上设计一个系统，该系统每 1 秒钟就读取一次实验箱上
; 八个开关 Ki 的电平，并统计其高电平开关的数量 N，若 N<=3，
; 则点亮试验箱的绿灯；若 3<N<=6；则点亮黄灯；否则点亮红灯。
; ============================================================
; 线路连接
; ------------------------------------------------------------
; 主机 D0-D7 -- 8255A D0-D7（箱内已连接）
; 主机 IOR/IOW -- 8255A RD/WR（箱内已连接）
; 主机 A0/A1 -- 8255A A0/A1（箱内已连接）
; EIO8_CS1 -- 8255A CS（基地址 210H，译码范围 210H-21FH）
; 8255A PA0-PA7 -- J1(KD) K1-K8（依次对应，上拨为高电平）
; 8255A PB0 -- J4/J5(LD) L1（绿灯）
; 8255A PB1 -- J4/J5(LD) L2（黄灯）
; 8255A PB2 -- J4/J5(LD) L3（红灯）
; PC 口无需接线，秒节拍由软件延时产生
; ============================================================

.MODEL SMALL
.486

IO_8255  EQU 0210H          ; CS1 片选对应的 8255 I/O 基地址。
PA_8255  EQU IO_8255        ; 210H：A 口，PA0-PA7 读取 K1-K8。
PB_8255  EQU IO_8255+1      ; 211H：B 口，PB0-PB2 驱动绿、黄、红灯。
PC_8255  EQU IO_8255+2      ; 212H：C 口，本题未使用。
KZ_8255  EQU IO_8255+3      ; 213H：控制端口，用于设置工作方式和端口方向。

D1S_HI   EQU 0064H          ; 按实验箱主频调整此值以校准秒节拍
D1S_LO   EQU 0FFFFH

DATA SEGMENT
    n DB ?
DATA ENDS

CODE SEGMENT
    ASSUME CS:CODE, DS:DATA
START:
    MOV  AX, DATA
    MOV  DS, AX
    CALL init8255
AGAIN:
    CALL Delay1s
    CALL readPA
    CALL countHigh
    CALL outputLED
    JMP  AGAIN

init8255 PROC
    MOV  DX, KZ_8255
    ; D7=1：选择方式设置控制字，配置各端口的工作方式和方向。

    ; D6-D5=00：A 组使用方式 0，包含 PA 和 PC4-PC7。

    ; D4=1：PA0-PA7 设为输入，依次读取开关 K1-K8 的电平。

    ; D3=0：PC4-PC7 设为输出，本题未使用这些引脚。

    ; D2=0：B 组使用方式 0，包含 PB 和 PC0-PC3。

    ; D1=0：PB0-PB7 设为输出，其中 PB0/PB1/PB2 分别控制绿/黄/红灯。

    ; D0=1：PC0-PC3 设为输入，本题不读取这些引脚。
    MOV  AL, 10010001B
    OUT  DX, AL             ; 将 91H 写入 213H，使上述端口配置生效。
    RET
init8255 ENDP

; 用双重循环产生约 1 秒延时
Delay1s PROC
    PUSH BX
    PUSH CX
    MOV  BX, D1S_HI
D1S_A:
    MOV  CX, D1S_LO
D1S_B:
    LOOP D1S_B
    DEC  BX
    JNZ  D1S_A
    POP  CX
    POP  BX
    RET
Delay1s ENDP

; 将八个开关的电平读入 AL
readPA PROC
    MOV  DX, PA_8255
    IN   AL, DX             ; AL 的位 0-7 依次对应 K1-K8 的当前电平。
    RET
readPA ENDP

; 统计 AL 中的高电平位数，结果保存到 n
countHigh PROC
    MOV  n, 0
    MOV  CX, 8
CH_LOOP:
    TEST AL, 01H            ; 检查当前最低位，为 1 时计入高电平数量。
    JZ   CH_NEXT
    INC  n
CH_NEXT:
    ROR  AL, 1              ; 将下一位移到最低位，八次循环覆盖全部开关。
    LOOP CH_LOOP
    RET
countHigh ENDP

; 按 n 的范围选择绿灯、黄灯或红灯
outputLED PROC
    MOV  BL, n
    CMP  BL, 3
    JBE  LED_GREEN
    CMP  BL, 6
    JBE  LED_YELLOW
    MOV  AL, 04H            ; 仅 PB2 输出高电平，点亮红灯。
    JMP  OUT_LED
LED_GREEN:
    MOV  AL, 01H            ; 仅 PB0 输出高电平，点亮绿灯。
    JMP  OUT_LED
LED_YELLOW:
    MOV  AL, 02H            ; 仅 PB1 输出高电平，点亮黄灯。
OUT_LED:
    MOV  DX, PB_8255
    OUT  DX, AL             ; 灯码写入 B 口后保持有效，直到下一次更新。
    RET
outputLED ENDP

CODE ENDS
    END START
