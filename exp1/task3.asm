; ============================================================
; 题目
; ------------------------------------------------------------
; 3. 试在实验箱上设计一个系统，该系统每收到一个正脉冲，
; 就读取一次实验箱上八个开关 Ki 的电平，并统计其高电平开关的数量 H，
; 然后将 H 显示在实验箱的一个七段数码管上。
; ============================================================
; 线路连接
; ------------------------------------------------------------
; 主机 D0-D7 -- 8255A D0-D7（箱内已连接）
; 主机 IOR/IOW -- 8255A RD/WR（箱内已连接）
; 主机 A0/A1 -- 8255A A0/A1（箱内已连接）
; EIO8_CS1 -- 8255A CS（基地址 210H，译码范围 210H-21FH）
; 8255A PA0-PA7 -- J1(KD) K1-K8（依次对应，上拨为高电平）
; 8255A PB0-PB7 -- J2(LEDB) a-h（依次对应，共阴高有效）
; 8255A PC4 -- J3(BIT) BIG1（高电平选通）
; 8255A PC0 -- J16 AN1 正脉冲输出
; ============================================================

.MODEL SMALL
.486

IO_8255  EQU 0210H          ; CS1 片选对应的 8255 I/O 基地址。
PA_8255  EQU IO_8255        ; 210H：A 口，PA0-PA7 读取 K1-K8。
PB_8255  EQU IO_8255+1      ; 211H：B 口，PB0-PB7 驱动数码管 a-h。
PC_8255  EQU IO_8255+2      ; 212H：C 口，PC4 选位，PC0 接收正脉冲。
KZ_8255  EQU IO_8255+3      ; 213H：控制端口，用于设置工作方式和端口方向。

DATA SEGMENT
    n      DB ?
    ; 段码位 0-7 依次对应 a-h，高电平点亮相应段。
    dCodes DB 3FH,06H,5BH,4FH,66H,6DH,7DH,07H,7FH,67H   ; 数字 0-9 的共阴段码
DATA ENDS

CODE SEGMENT
    ASSUME CS:CODE, DS:DATA
START:
    MOV  AX, DATA
    MOV  DS, AX
    CALL init8255
    MOV  DX, PC_8255
    MOV  AL, 10H            ; 10H 使 PC4=1，持续选通 BIG1。
    OUT  DX, AL             ; 只更新 C 口的输出引脚，PC0-PC3 仍保持输入。
AGAIN:
    CALL WaitPulse
    CALL readPA
    CALL countHigh
    CALL showDigit
    JMP  AGAIN

init8255 PROC
    MOV  DX, KZ_8255
    ; D7=1：选择方式设置控制字，配置各端口的工作方式和方向。
    ; D6-D5=00：A 组使用方式 0，包含 PA 和 PC4-PC7。
    ; D4=1：PA0-PA7 设为输入，依次读取开关 K1-K8 的电平。
    ; D3=0：PC4-PC7 设为输出，其中 PC4 为高时选通 BIG1。
    ; D2=0：B 组使用方式 0，包含 PB 和 PC0-PC3。
    ; D1=0：PB0-PB7 设为输出，高电平点亮数码管的对应段。
    ; D0=1：PC0-PC3 设为输入，其中 PC0 检测 AN1 的正脉冲。
    MOV  AL, 10010001B
    OUT  DX, AL             ; 将 91H 写入 213H，使上述端口配置生效。
    RET
init8255 ENDP

; 等待 PC0 完成低-高-低的正脉冲
WaitPulse PROC
WP_LOW1:
    MOV  DX, PC_8255
    IN   AL, DX
    TEST AL, 01H            ; 01H 只检查 PC0，其他 C 口引脚不参与脉冲判断。
    JNZ  WP_LOW1            ; 先等待空闲低电平，避免把已有高电平当作新脉冲。
WP_HIGH:
    MOV  DX, PC_8255
    IN   AL, DX
    TEST AL, 01H
    JZ   WP_HIGH            ; 等待 PC0 变高，检测正脉冲的起始。
WP_LOW2:
    MOV  DX, PC_8255
    IN   AL, DX
    TEST AL, 01H
    JNZ  WP_LOW2            ; 等待 PC0 回低，防止同一脉冲被重复采样。
    RET
WaitPulse ENDP

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

; 用 n 查共阴段码表，将段码输出到 PB
showDigit PROC
    XOR  BX, BX
    MOV  BL, n
    MOV  AL, dCodes[BX]     ; 以高电平数量为下标，取得对应数字的共阴段码。
    MOV  DX, PB_8255
    OUT  DX, AL             ; B 口锁存段码，配合持续有效的 PC4 显示这一位。
    RET
showDigit ENDP

CODE ENDS
    END START
