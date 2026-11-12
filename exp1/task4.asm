; ============================================================
; 题目
; ------------------------------------------------------------
; 4. 试在实验箱上设计一个系统，该系统每 2 秒钟就读取一次实验箱上
; 八个开关 Ki 的电平，并统计其高电平与低电平开关的数量 H 与 L，
; 然后将 H 与 L 显示在实验箱的七段数码管上。
; ============================================================
; 线路连接
; ------------------------------------------------------------
; 主机 D0-D7 -- 8255A D0-D7（箱内已连接）
; 主机 IOR/IOW -- 8255A RD/WR（箱内已连接）
; 主机 A0/A1 -- 8255A A0/A1（箱内已连接）
; EIO8_CS1 -- 8255A CS（基地址 210H，译码范围 210H-21FH）
; 8255A PA0-PA7 -- J1(KD) K1-K8（依次对应，上拨为高电平）
; 8255A PB0-PB7 -- J2(LEDB) a-h（依次对应，共阴高有效）
; 8255A PC4 -- J3(BIT) BIG1（左位显示 H，高电平选通）
; 8255A PC5 -- J3(BIT) BIG2（右位显示 L，高电平选通）
; 秒节拍由软件延时产生，无需连接时钟
; ============================================================

.MODEL SMALL
.486

IO_8255  EQU 0210H          ; CS1 片选对应的 8255 I/O 基地址。
PA_8255  EQU IO_8255        ; 210H：A 口，PA0-PA7 读取 K1-K8。
PB_8255  EQU IO_8255+1      ; 211H：B 口，PB0-PB7 驱动数码管 a-h。
PC_8255  EQU IO_8255+2      ; 212H：C 口，PC4/PC5 选择左、右两位。
KZ_8255  EQU IO_8255+3      ; 213H：控制端口，用于设置工作方式和端口方向。

D1S_HI   EQU 0064H          ; 软件延时外层循环的计数初值
D1S_LO   EQU 0FFFFH

DATA SEGMENT
    nH     DB ?
    nL     DB ?
    ; 段码位 0-7 依次对应 a-h，高电平点亮相应段。
    dCodes DB 3FH,06H,5BH,4FH,66H,6DH,7DH,07H,7FH,67H   ; 数字 0-9 的共阴段码
DATA ENDS

CODE SEGMENT
    ASSUME CS:CODE, DS:DATA
START:
    MOV  AX, DATA
    MOV  DS, AX
    CALL init8255
AGAIN:
    CALL readPA
    CALL countHigh
    MOV  AL, 8
    SUB  AL, nH
    MOV  nL, AL             ; 低电平数 L = 8 - H
    CALL Wait2Sec
    JMP  AGAIN

init8255 PROC
    MOV  DX, KZ_8255
    ; D7=1：选择方式设置控制字，配置各端口的工作方式和方向。
    ; D6-D5=00：A 组使用方式 0，包含 PA 和 PC4-PC7。
    ; D4=1：PA0-PA7 设为输入，依次读取开关 K1-K8 的电平。
    ; D3=0：PC4-PC7 设为输出，其中 PC4/PC5 分别选通 BIG1/BIG2。
    ; D2=0：B 组使用方式 0，包含 PB 和 PC0-PC3。
    ; D1=0：PB0-PB7 设为输出，两位数码管共用这组段线。
    ; D0=1：PC0-PC3 设为输入，本题不读取这些引脚。
    MOV  AL, 10010001B
    OUT  DX, AL             ; 将 91H 写入 213H，使上述端口配置生效。
    RET
init8255 ENDP

; 将八个开关的电平读入 AL
readPA PROC
    MOV  DX, PA_8255
    IN   AL, DX             ; AL 的位 0-7 依次对应 K1-K8 的当前电平。
    RET
readPA ENDP

; 统计 AL 中的高电平位数，结果保存到 nH
countHigh PROC
    MOV  nH, 0
    MOV  CX, 8
CH_LOOP:
    TEST AL, 01H            ; 检查当前最低位，为 1 时计入高电平数量。
    JZ   CH_NEXT
    INC  nH
CH_NEXT:
    ROR  AL, 1              ; 将下一位移到最低位，八次循环覆盖全部开关。
    LOOP CH_LOOP
    RET
countHigh ENDP

; 连续调用两次 Delay1s，作为采样间隔
Wait2Sec PROC
    MOV  DX, 2
W2S_LOOP:
    CALL Delay1s
    DEC  DX
    JNZ  W2S_LOOP
    RET
Wait2Sec ENDP

; 在软件延时的外层循环中刷新两位数码管
Delay1s PROC
    PUSH BX
    PUSH CX
    PUSH DX                 ; 保留 Wait2Sec 使用的次数，避免扫描输出改写 DX。
    MOV  BX, D1S_HI
D1S_A:
    CALL scanShow           ; scanShow 会改写外层计数 BX
    MOV  CX, D1S_LO
D1S_B:
    LOOP D1S_B
    DEC  BX
    JNZ  D1S_A
    POP  DX
    POP  CX
    POP  BX
    RET
Delay1s ENDP

; 轮流扫描两位数码管，分别显示 H 和 L
scanShow PROC
    MOV  DX, PC_8255
    MOV  AL, 10H            ; 10H 使 PC4=1、PC5=0，选通显示 H 的左位。
    OUT  DX, AL             ; 只改变 PC4-PC7 的输出，PC0-PC3 的输入方向不变。
    XOR  BX, BX
    MOV  BL, nH
    MOV  AL, dCodes[BX]
    MOV  DX, PB_8255
    OUT  DX, AL             ; 将当前数字的段码送到 PB0-PB7，驱动共用段线。
    CALL smallDelay

    MOV  DX, PC_8255
    MOV  AL, 20H            ; 20H 使 PC5=1、PC4=0，选通显示 L 的右位。
    OUT  DX, AL
    XOR  BX, BX
    MOV  BL, nL
    MOV  AL, dCodes[BX]
    MOV  DX, PB_8255
    OUT  DX, AL
    CALL smallDelay
    RET
scanShow ENDP

; 为当前选中的数码管提供短暂显示时间
smallDelay PROC
    PUSH CX
    MOV  CX, 00FFH
SD:
    LOOP SD
    POP  CX
    RET
smallDelay ENDP

CODE ENDS
    END START
