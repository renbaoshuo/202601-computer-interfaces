; ============================================================
; 题目
; ------------------------------------------------------------
; 4. 试在实验箱上设计一个系统，该系统每 100 毫秒采样试验箱中一个直流电源
; 的电压，并将所得电压值显示在 8 段数码上。
; ============================================================
; 线路连接
; ------------------------------------------------------------
; EIO8_CS0 -- J31(8255CS)（本程序使用 200H-203H）
; 主机 SD0-SD7 -- 8255A D0-D7（箱内已连接）
; 主机 SA0/SA1、SIOR/SIOW -- 8255A A0/A1、RD/WR（箱内已连接）
; J22 PA0-PA7 -- J2(LEDB) a-g 和小数点（依次对应，段线高有效）
; J23 PB0/PB1 -- 反相器 -- J3(BIT) BIG1/BIG2（分别显示整数位和十分位）
; 程序的位选输出低有效，实验箱 J3 的位选输入高有效。
; 288H 的低有效译码输出 -- J10(0809CS)
; 实验箱默认译码范围为 200H-27FH，288H 需另行译码。
; J6 的 500 kHz 固定脉冲输出 -- J10(0809CLK)
; J10(0809EOC) -- J24 PC0
; RW1 Vout1（0-5 V） -- J43(IN-1) IN0
; 主机 SD0-SD2 -- ADC0809 ADD-A/ADD-B/ADD-C（箱内已连接）
; ADC0809 的 8 位数据输出 -- 主机 SD7-SD0（从高位到低位，箱内已连接）
; ADC0809 REF+/REF- -- +5 V/GND（箱内已连接）
; ============================================================

.MODEL SMALL
.486
.STACK 100H

PPI_A    EQU 0200H           ; A 口输出共阴段码。
PPI_B    EQU 0201H           ; B 口输出两位的位选信号。
PPI_C    EQU 0202H           ; C 口读取 EOC 转换状态。
PPI_CTL  EQU 0203H           ; 8255A 的控制端口。
ADC_PORT EQU 0288H           ; 写入以启动转换，读取以取得转换码。

.DATA
; 共阴段码的位 0-6 对应 a-g，位 7 对应小数点，各段高有效。
SEG_TAB DB 03FH,006H,05BH,04FH,066H,06DH,07DH,007H
        DB 07FH,06FH,077H,07CH,039H,05EH,079H,071H
; 左右两位的段码缓冲区初值为 0.0。
DIGIT_LEFT  DB 0BFH
DIGIT_RIGHT DB 03FH
SAMPLE_START DW 0

.CODE
START:
    MOV AX,@DATA
    MOV DS,AX
    MOV DX,PPI_CTL
    ; D7=1，选择方式设置控制字。
    ; D6-D5=00，A 组使用方式 0，包含 PA 和 PC4-PC7。
    ; D4=0，PA0-PA7 设为输出，驱动数码管的段线。
    ; D3=0，PC4-PC7 设为输出。
    ; D2=0，B 组使用方式 0，包含 PB 和 PC0-PC3。
    ; D1=0，PB0-PB7 设为输出，PB0/PB1 提供低有效位选。
    ; D0=1，PC0-PC3 设为输入，PC0 读取 ADC0809 的 EOC。
    MOV AL,081H
    OUT DX,AL
    MOV DX,PPI_B
    MOV AL,0FFH              ; FFH 关闭两个低有效位选。
    OUT DX,AL

MAIN_LOOP:
    CALL GET_CENTISECONDS
    MOV SAMPLE_START,AX      ; 从本次启动转换前的时刻开始计时。
    CALL ADC_READ_IN0
    JC  ADC_ERROR
    CALL TO_VOLT_SEGMENTS
    JMP WAIT_NEXT_SAMPLE
ADC_ERROR:
    MOV DIGIT_LEFT,040H      ; 两位都只点亮 g 段，以 -- 提示转换超时。
    MOV DIGIT_RIGHT,040H

; 等待下次采样时持续刷新数码管。
WAIT_NEXT_SAMPLE:
    CALL DISPLAY_SCAN
    CALL GET_CENTISECONDS
    SUB AX,SAMPLE_START
    JNC TIME_OK
    ADD AX,6000              ; 时钟跨过整分钟时补上 6000 个计数。
TIME_OK:
    CMP AX,10                ; 以 10 个百分之一秒为采样间隔。
    JB  WAIT_NEXT_SAMPLE
    JMP MAIN_LOOP

; 成功时在 AL 返回转换码且 CF=0，等待 EOC 超时时置 CF=1。
ADC_READ_IN0 PROC NEAR
    PUSH CX
    PUSH DX
    MOV DX,ADC_PORT
    XOR AL,AL                ; SD2-SD0 为 000，选择 IN0。
    OUT DX,AL                ; 片选和写信号产生 ALE/START 脉冲。

    MOV DX,PPI_C
    MOV CX,08000H            ; 最多轮询 32768 次，等待 EOC 拉低以确认转换开始。
WAIT_EOC_LOW:
    IN  AL,DX
    TEST AL,01H              ; 01H 只检查 PC0 上的 EOC。
    JZ  EOC_WENT_LOW
    LOOP WAIT_EOC_LOW
    STC
    JMP ADC_READ_DONE

EOC_WENT_LOW:
    MOV CX,08000H            ; 重新计数，等待 EOC 回高以确认转换完成。
WAIT_EOC_HIGH:
    IN  AL,DX
    TEST AL,01H
    JNZ ADC_READY
    LOOP WAIT_EOC_HIGH
    STC
    JMP ADC_READ_DONE

ADC_READY:
    MOV DX,ADC_PORT
    IN  AL,DX                ; 片选和读信号使能 ADC 的 8 位数据输出。
    CLC
ADC_READ_DONE:
    POP DX
    POP CX
    RET
ADC_READ_IN0 ENDP

; 按题目算法把 8 位 ADC 码换算成一位小数的电压。
TO_VOLT_SEGMENTS PROC NEAR
    XOR AH,AH
    MOV BL,51
    DIV BL                   ; 按每伏 51 码换算，AL 为整数位，AH 为余数。
    MOV BH,AL
    MOV AL,AH
    XOR AH,AH
    MOV BL,5
    DIV BL                   ; 余数除以 5，AL 为十分位的初值。
    CMP AH,3                 ; 余数达到 3 时将十分位加 1。
    JB  ROUND_DONE
    INC AL
ROUND_DONE:
    CMP AL,10
    JB  NO_CARRY
    XOR AL,AL
    INC BH                   ; 十分位满 10 时向整数位进 1。
NO_CARRY:
    MOV DL,AL
    MOV AL,BH
    XOR AH,AH
    MOV SI,AX
    MOV AL,SEG_TAB[SI]
    OR  AL,080H              ; 置位第 7 位，点亮整数位的小数点。
    MOV DIGIT_LEFT,AL
    MOV AL,DL
    XOR AH,AH
    MOV SI,AX
    MOV AL,SEG_TAB[SI]
    MOV DIGIT_RIGHT,AL
    RET
TO_VOLT_SEGMENTS ENDP

; 两位共用段线，每次换段码前先关闭位选以免串显。
DISPLAY_SCAN PROC NEAR
    PUSH AX
    PUSH DX
    MOV DX,PPI_B
    MOV AL,0FFH
    OUT DX,AL
    MOV DX,PPI_A
    MOV AL,DIGIT_LEFT
    OUT DX,AL
    MOV DX,PPI_B
    MOV AL,0FEH              ; PB0=0，选通左位显示整数。
    OUT DX,AL
    CALL SHORT_HOLD

    MOV AL,0FFH
    OUT DX,AL
    MOV DX,PPI_A
    MOV AL,DIGIT_RIGHT
    OUT DX,AL
    MOV DX,PPI_B
    MOV AL,0FDH              ; PB1=0，选通右位显示十分位。
    OUT DX,AL
    CALL SHORT_HOLD

    MOV AL,0FFH              ; 扫描结束时关闭两位。
    OUT DX,AL
    POP DX
    POP AX
    RET
DISPLAY_SCAN ENDP

; 用软件延时给当前选中的数码管留出显示时间。
SHORT_HOLD PROC NEAR
    PUSH CX
    MOV CX,0300H
HOLD_LOOP:
    LOOP HOLD_LOOP
    POP CX
    RET
SHORT_HOLD ENDP

; 读取 DOS 时钟，返回本分钟内的百分之一秒计数。
GET_CENTISECONDS PROC NEAR
    PUSH BX
    PUSH DX
    MOV AH,02CH
    INT 21H                  ; 功能 2CH 返回 DH=秒、DL=百分之一秒。
    MOV AL,DH
    MOV BL,100
    MUL BL
    XOR DH,DH
    ADD AX,DX                ; AX = 秒数 * 100 + 百分之一秒数。
    POP DX
    POP BX
    RET
GET_CENTISECONDS ENDP
END START
