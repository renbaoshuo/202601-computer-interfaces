; ============================================================
; 题目
; ------------------------------------------------------------
; 5. 试实现交通信号灯控制系统，要求延时用 8253 实现。
; ============================================================
; 线路连接
; ------------------------------------------------------------
; 主机 D0-D7 -- 8255、8253 D0-D7（箱内已连接）
; 主机 IOR/IOW -- 8255、8253 RD/WR（箱内已连接）
; 主机 A0/A1 -- 8255、8253 A0/A1（箱内已连接）
; EIO8_CS0 -- 8255 CS（基地址 200H，译码范围 200H-20FH）
; EIO8_CS1 -- 8253 CS（面板标为 8254/3CS，地址范围 210H-21FH）
; 8253 CLK0 -- 固定脉冲 1 MHz 输出
; 8253 OUT0 -- 8253 CLK1（100 Hz 级联时钟）
; 8253 GATE0、GATE1 -- J1(KD) K1（置高，允许计数）
; 8253 OUT1 -- 8255 PC0（1 Hz 秒节拍）
; 8255 PA0 -- 南北红灯输入端（高电平点亮）
; 8255 PA1 -- 南北黄灯输入端（高电平点亮）
; 8255 PA2 -- 南北绿灯输入端（高电平点亮）
; 8255 PA3 -- 东西红灯输入端（高电平点亮）
; 8255 PA4 -- 东西黄灯输入端（高电平点亮）
; 8255 PA5 -- 东西绿灯输入端（高电平点亮）
; ============================================================

.MODEL SMALL
.486
.STACK 100H

PPI_A      EQU 0200H        ; 200H：PA0-PA5 输出六路交通灯的灯码。
PPI_C      EQU 0202H        ; 202H：PC0 读取 8253 OUT1 的秒节拍。
PPI_CTRL   EQU 0203H        ; 203H：8255 方式和端口方向控制端口。

TIMER0     EQU 0210H        ; 210H：C0 端口，产生 100 Hz 级联时钟。
TIMER1     EQU 0211H        ; 211H：C1 端口，输出 1 Hz 方波供 PC0 查询。
TIMER_CTRL EQU 0213H        ; 213H：8253 方式控制端口，与 CS1 片选一致。

DATA SEGMENT
; SI=0-5 依次索引灯码表和时长表，同一下标对应同一状态。
; 0CH：南北绿、东西红，持续 10 秒。
; 0AH：南北黄、东西红，持续 3 秒。
; 09H：南北红、东西红，持续 1 秒后切换通行方向。
; 21H：南北红、东西绿，持续 10 秒。
; 11H：南北红、东西黄，持续 3 秒。
; 09H：再次全红 1 秒，然后返回第一种状态。
MASK_TABLE DB 00CH,00AH,009H,021H,011H,009H
DUR_TABLE  DB 10,3,1,10,3,1  ; 各状态的持续秒数，与 MASK_TABLE 的六个灯码一一对应。
DATA ENDS

CODE SEGMENT
ASSUME CS:CODE,DS:DATA
START:
    MOV AX,DATA
    MOV DS,AX

    MOV DX,PPI_CTRL
    ; D7=1：选择方式设置控制字，配置端口方式和输入输出方向。
    ; D6-D5=00：A 组使用方式 0，包含 PA 和 PC4-PC7。
    ; D4=0：PA0-PA7 设为输出，PA0-PA5 控制六路交通灯。
    ; D3=1：PC4-PC7 设为输入，本题未使用这些引脚。
    ; D2=0：B 组使用方式 0，包含 PB 和 PC0-PC3。
    ; D1=0：PB0-PB7 设为输出，本题未使用 B 口。
    ; D0=1：PC0-PC3 设为输入，其中 PC0 读取 OUT1 的秒节拍。
    MOV AL,089H
    OUT DX,AL
    MOV DX,PPI_A
    MOV AL,009H             ; 09H 使 PA0、PA3 为高，启动时先点亮两方向红灯。
    OUT DX,AL

    ; 先配置 C1 的秒节拍，再启动上游 C0 的 100 Hz 时钟。
    MOV DX,TIMER_CTRL
    ; D7-D6=01：选择计数器 C1，对应 CLK1/GATE1/OUT1。
    ; D5-D4=11：使用 16 位初值，先写低 8 位，再写高 8 位。
    ; D3-D1=011：方式 3，按计数初值分频输出方波。
    ; D0=0：采用二进制计数，初值不是 BCD 编码。
    MOV AL,076H
    OUT DX,AL
    MOV DX,TIMER1
    MOV AX,0064H            ; 100 / 100 Hz = 1 秒，OUT1 高、低电平各占 0.5 秒。
    OUT DX,AL               ; 先写 C1 初值低字节 64H。
    MOV AL,AH
    OUT DX,AL               ; 再写高字节 00H，OUT1 连接 PC0。

    MOV DX,TIMER_CTRL
    ; D7-D6=00：选择计数器 C0，对应 CLK0/GATE0/OUT0。
    ; D5-D4=11：使用 16 位初值，先写低 8 位，再写高 8 位。
    ; D3-D1=010：方式 2，周期末输出一个输入时钟宽度的低脉冲。
    ; D0=0：采用二进制计数，初值不是 BCD 编码。
    MOV AL,034H
    OUT DX,AL
    MOV DX,TIMER0
    MOV AX,02710H           ; 10000 分频：1 MHz / 10000 = 100 Hz。
    OUT DX,AL               ; 先写 C0 初值低字节 10H。
    MOV AL,AH
    OUT DX,AL               ; 再写高字节 27H，启动两级连续分频。

    XOR SI,SI
; 输出当前状态的灯码，再等待该状态规定的秒节拍数。
NEXT_STATE:
    MOV BX,OFFSET MASK_TABLE
    MOV AL,[BX+SI]          ; 灯码只使用 PA0-PA5，PA6、PA7 保持低电平。
    MOV DX,PPI_A
    OUT DX,AL

    MOV BX,OFFSET DUR_TABLE
    MOV CL,[BX+SI]
    XOR CH,CH               ; 清除 CH，使 CX 等于当前状态需等待的秒节拍数。
WAIT_SECONDS:
    CALL WAIT_1S
    LOOP WAIT_SECONDS       ; 每检测到一个上升沿就减计数，到零后切换状态。

    ; 六个状态依次循环，每次全红后交换南北和东西的通行方向。
    INC SI
    CMP SI,6
    JB NEXT_STATE
    XOR SI,SI
    JMP NEXT_STATE

; 等待 PC0 先为低再变高，以 OUT1 的相邻上升沿作为秒节拍。
; 相邻上升沿间隔为 1 秒，首次等待长度取决于进入时的时钟相位。
WAIT_1S PROC NEAR
    PUSH AX
    PUSH DX
    MOV DX,PPI_C
W1_LOW:
    IN AL,DX
    TEST AL,01H             ; 01H 只检查 PC0，其余 C 口引脚不参与计时。
    JNZ W1_LOW              ; 先等待低电平，避免把当前高电平重复计为新节拍。
W1_HIGH:
    IN AL,DX
    TEST AL,01H
    JZ W1_HIGH              ; 等待 PC0 变高，检测到下一个秒节拍后返回。
    POP DX
    POP AX
    RET
WAIT_1S ENDP
CODE ENDS
END START
