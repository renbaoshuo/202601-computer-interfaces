; ============================================================
; 题目
; ------------------------------------------------------------
; 5. 试在实验箱上设计一个系统，该系统收到一个负脉冲就开始 1 分钟倒计时，
; 并将剩余的时间显示在实验箱的两个七段数码管上，
; 计时结束时，点亮实验箱的红色 LED 灯。
; ============================================================
; 线路连接
; ------------------------------------------------------------
; 主机 D0-D7 -- 8255A D0-D7（箱内已连接）
; 主机 IOR/IOW -- 8255A RD/WR（箱内已连接）
; 主机 A0/A1 -- 8255A A0/A1（箱内已连接）
; EIO8_CS1 -- 8255A CS（基地址 210H，译码范围 210H-21FH）
; 8255A PB0-PB7 -- J2(LEDB) a-h（依次对应，共阴高有效）
; 8255A PC4 -- J3(BIT) BIG1（十位，高电平选通）
; 8255A PC5 -- J3(BIT) BIG2（个位，高电平选通）
; 8255A PC7 -- 红色 LED（高电平点亮）
; 8255A PC0 -- J17 AN2 负脉冲输出
; 8255A PC1 -- 1 Hz 时钟输出（代码需要，接线图未标出）
; PA 口无需接线
; ============================================================

.MODEL SMALL
.486

IO_8255  EQU 0210H          ; CS1 片选对应的 8255 I/O 基地址。
PA_8255  EQU IO_8255        ; 210H：A 口，本题未使用。
PB_8255  EQU IO_8255+1      ; 211H：B 口，PB0-PB7 驱动数码管 a-h。
PC_8255  EQU IO_8255+2      ; 212H：C 口，PC4/PC5 选位，PC7 控制红灯。
KZ_8255  EQU IO_8255+3      ; 213H：控制端口，用于设置工作方式和端口方向。

DATA SEGMENT
    seconds DB ?
    tens    DB ?
    ones    DB ?
    redflag DB ?            ; PC7 的输出掩码：00H 灭灯，80H 亮灯
    ; 段码位 0-7 依次对应 a-h，高电平点亮相应段。
    dCodes  DB 3FH,06H,5BH,4FH,66H,6DH,7DH,07H,7FH,67H   ; 数字 0-9 的共阴段码
DATA ENDS

CODE SEGMENT
    ASSUME CS:CODE, DS:DATA
START:
    MOV  AX, DATA
    MOV  DS, AX
    CALL init8255
    MOV  redflag, 0

; 空闲时显示 00，收到负脉冲后重新开始倒计时
IDLE:
    MOV  seconds, 0
    CALL scanShow
    CALL WaitNegPulse
    MOV  redflag, 0         ; 清除 PC7 的输出掩码，下一次扫描时熄灭红灯。
    MOV  seconds, 60

COUNTDOWN:
    CALL scanShow
    CALL Wait1Sec
    DEC  seconds
    CMP  seconds, 0
    JNZ  COUNTDOWN

    MOV  redflag, 80H       ; 计时结束后保持红灯点亮
    CALL scanShow
    JMP  IDLE

init8255 PROC
    MOV  DX, KZ_8255
    ; D7=1：选择方式设置控制字，配置各端口的工作方式和方向。
    ; D6-D5=00：A 组使用方式 0，包含 PA 和 PC4-PC7。
    ; D4=1：PA0-PA7 设为输入，本题未使用 A 口。
    ; D3=0：PC4-PC7 设为输出，PC4/PC5 选位、PC7 控制红灯。
    ; D2=0：B 组使用方式 0，包含 PB 和 PC0-PC3。
    ; D1=0：PB0-PB7 设为输出，两位数码管共用这组段线。
    ; D0=1：PC0-PC3 设为输入，PC0 检测负脉冲、PC1 读取 1 Hz 时钟。
    MOV  AL, 10010001B
    OUT  DX, AL             ; 将 91H 写入 213H，使上述端口配置生效。
    RET
init8255 ENDP

; 等待 PC0 完成高-低-高的负脉冲，期间持续刷新显示
WaitNegPulse PROC
WN_HIGH1:
    CALL scanShow
    MOV  DX, PC_8255
    IN   AL, DX
    TEST AL, 01H            ; 01H 只检查 PC0，其他 C 口引脚不参与脉冲判断。
    JZ   WN_HIGH1           ; 先等待空闲高电平，为检测新的负脉冲作准备。
WN_LOW:
    CALL scanShow
    MOV  DX, PC_8255
    IN   AL, DX
    TEST AL, 01H
    JNZ  WN_LOW             ; 等待 PC0 变低，检测负脉冲的起始。
WN_HIGH2:
    CALL scanShow
    MOV  DX, PC_8255
    IN   AL, DX
    TEST AL, 01H
    JZ   WN_HIGH2           ; 等待 PC0 回高，确保本次负脉冲已经结束。
    RET
WaitNegPulse ENDP

; 等待 PC1 先为低再变高，轮询时持续刷新显示
Wait1Sec PROC
W1_LOW:
    CALL scanShow
    MOV  DX, PC_8255
    IN   AL, DX
    TEST AL, 02H            ; 02H 只检查 PC1 上的 1 Hz 时钟信号。
    JNZ  W1_LOW             ; 先等待低电平，使后续检测对应一次新的上升沿。
W1_HIGH:
    CALL scanShow
    MOV  DX, PC_8255
    IN   AL, DX
    TEST AL, 02H
    JZ   W1_HIGH            ; PC1 变高时返回，主循环随后将剩余秒数减一。
    RET
Wait1Sec ENDP

; 轮流显示剩余秒数的十位和个位，并保留 PC7 的红灯状态
scanShow PROC
    MOV  AL, seconds
    XOR  AH, AH
    MOV  BL, 10
    DIV  BL                 ; AL 保存十位，AH 保存个位
    MOV  tens, AL
    MOV  ones, AH

    MOV  DX, PC_8255
    MOV  AL, 10H            ; 10H 使 PC4=1、PC5=0，选通显示十位的 BIG1。
    OR   AL, redflag        ; 合并 PC7 的红灯掩码，切换位选时保留灯态。
    OUT  DX, AL             ; 只改变 PC4-PC7 的输出，PC0-PC3 的输入方向不变。
    XOR  BX, BX
    MOV  BL, tens
    MOV  AL, dCodes[BX]
    MOV  DX, PB_8255
    OUT  DX, AL             ; 将当前数字的段码送到 PB0-PB7，驱动共用段线。
    CALL smallDelay

    MOV  DX, PC_8255
    MOV  AL, 20H            ; 20H 使 PC5=1、PC4=0，选通显示个位的 BIG2。
    OR   AL, redflag        ; 选通个位时仍保留 PC7 的红灯状态。
    OUT  DX, AL
    XOR  BX, BX
    MOV  BL, ones
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
