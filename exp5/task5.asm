; ============================================================
; 题目
; ------------------------------------------------------------
; 实验七 8259 中断实验 2 及复习（本文件对应第 1 题 A、B）
; 1. 试在试验箱中并发完成以下任务：
; A) 间隔 2 秒显示 1 个 led 灯，至亮 8 个后，熄灭，然后重复该过程；
; B) 间隔 1 秒计数，并将数值显示在 8 段数码管上，计数范围 0 至 20；
; 计数至 20 后清零，然后重复上述过程。
; C) 间隔 1.5 秒倒计数，并将数值显示在 8 段数码管上，计数范围 15 至 0；
; 计数至 0 后将计数值重置为 15，然后重复上述过程。
; D) 间隔 0.1 秒计数，并将数值显示在 8 段数码管上，计数范围 0 至 60；
; 计数至 60 后清零，然后重复上述过程。
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
; 8255A PC0 -- J3(BIT) BIG1（十位，需反相后接实验箱高有效位选）
; 8255A PC1 -- J3(BIT) BIG2（个位，需反相后接实验箱高有效位选）
; 8255A PB0-PB7 -- J4(LD) L1-L8（依次经反相，程序输出低有效灯码）
; J7 10 Hz 固定脉冲输出 -- 主 8259A IRQ0（上升沿触发）
; ============================================================

.model small
.486

PA_8255   EQU 200H               ; A 口，输出数码管段码。
PB_8255   EQU 201H               ; B 口，输出 8 路低有效 LED 灯码。
PC_8255   EQU 202H               ; C 口，PC0 和 PC1 输出位选。
KZ_8255   EQU 203H               ; 8255A 控制端口，设置工作方式和引脚方向。
M8259A0   EQU 210H               ; 主片命令口（A0=0），写 ICW1 和 EOI。
M8259A1   EQU 211H               ; 主片数据口（A0=1），写 ICW2-ICW4 和屏蔽字。
S8259A0   EQU 220H               ; 从片命令口（A0=0），写 ICW1。
S8259A1   EQU 221H               ; 从片数据口（A0=1），写 ICW2-ICW4 和屏蔽字。

DATA SEGMENT
    ; D0-D6 依次对应 a-g，1 点亮对应的段。
    ; 段码按数字 0-9 排列，D7 恒为 1，接到 h 时小数点亮。
    LEDS    db 0BFH,86H,0DBH,0CFH,0E6H
            db 0EDH,0FDH,87H,0FFH,0EFH

    ; 灯码表按亮 1-8 盏排列，PB0 起连续置低。
    LED_PATTERN db 0FEH,0FCH,0F8H,0F0H,0E0H,0C0H,80H,00H

    led_num  db 1                ; A 任务的灯数，0 表示全灭。
    count_b  db 0                ; B 任务的计数范围为 0-20。
    a_tick   db 0
    b_tick   db 0
    tens     db ?
    units    db ?
DATA ENDS

CODE SEGMENT
ASSUME CS:CODE, DS:DATA

START:
    MOV AX, DATA
    MOV DS, AX

    CALL INIT8255
    CALL INITM8259
    CALL INITS8259

    CLI
    CALL setINTVector
    STI

; 前台刷新 LED 和两位数码管，计时由 IRQ0 驱动。
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
    MOV SI, 64                   ; 实模式向量 10H 的表项在 0000:0040H（10H × 4）。
    MOV [SI], AX                 ; 表项的低字保存入口偏移 IP。
    MOV AX, CS
    MOV [SI+2], AX               ; 表项的高字保存入口段地址 CS。

    MOV DX, M8259A1
    IN  AL, DX
    AND AL, 11111110B            ; 只清 OCW1 的 D0，开放主片 IRQ0。
    OUT DX, AL

    POP DX
    POP AX
    POP DS
    RET
setINTVector ENDP

; 同一个 IRQ0 节拍推进 A、B 两组计数。
intHandler PROC
    PUSH AX
    PUSH DX

    INC a_tick
    CMP a_tick, 15               ; 每 15 个 10 Hz 节拍推进一次（1.5 秒，题面要求 2 秒）。
    JB  A_DONE
    MOV a_tick, 0

    CMP led_num, 8
    JAE A_LED_NEXT
    INC led_num                  ; 在 0-7 的状态下，下一个 A 节拍多亮一盏。
    JMP A_DONE

A_LED_NEXT:
    CMP led_num, 8
    JNE A_LED_SET1
    MOV led_num, 0               ; 八盏灯全亮后的下一拍全灭。
    JMP A_DONE

A_LED_SET1:
    MOV led_num, 1

A_DONE:

    INC b_tick
    CMP b_tick, 10               ; 每 10 个 10 Hz 节拍加一（1 秒）。
    JB  B_DONE
    MOV b_tick, 0

    INC count_b
    CMP count_b, 20
    JBE B_DONE
    MOV count_b, 0               ; 20 保持一拍，下一秒回到 0。

B_DONE:
    CALL SENDM8259EOI

    POP DX
    POP AX
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
    ; D1=0 将 PB0-PB7 设为输出，每位控制一路低有效 LED。
    ; D0=0 将 PC0-PC3 设为输出，PC0 和 PC1 分别低电平选通十位和个位。
    MOV AL, 10000000B
    OUT DX, AL                   ; 将 80H 写入 203H，使端口配置生效。
    RET
INIT8255 ENDP

INITM8259 PROC
    MOV DX, M8259A0
    MOV AL, 11H                  ; ICW1 的 D3=0 选上升沿，D1=0 选级联，D0=1 要求写 ICW4。
    OUT DX, AL

    MOV DX, M8259A1
    MOV AL, 16                   ; ICW2 设置向量基址 10H，对应 IRQ0-IRQ7 的向量 10H-17H。
    OUT DX, AL

    MOV AL, 10000000B            ; ICW3 的 D7=1，配置主片 IRQ7 连接从片。
    OUT DX, AL

    MOV AL, 01H                  ; ICW4 的 D0=1 选 8086 模式，D3=0 选非缓冲，D1=0 选手动 EOI。
    OUT DX, AL

    MOV AL, 11111111B            ; OCW1 先屏蔽全部 IRQ，安装向量后再开放 IRQ0。
    OUT DX, AL
    RET
INITM8259 ENDP

INITS8259 PROC
    MOV DX, S8259A0
    MOV AL, 11H                  ; ICW1 的 D3=0 选上升沿，D1=0 选级联，D0=1 要求写 ICW4。
    OUT DX, AL

    MOV DX, S8259A1
    MOV AL, 70H                  ; ICW2 设置从片向量范围 70H-77H。
    OUT DX, AL

    MOV AL, 07                   ; ICW3 的从片标识为 7，对应主片 IRQ7。
    OUT DX, AL

    MOV AL, 01H                  ; ICW4 的 D0=1 选 8086 模式，D3=0 选非缓冲，D1=0 选手动 EOI。
    OUT DX, AL

    MOV AL, 11111111B            ; OCW1 屏蔽从片的全部 IRQ。
    OUT DX, AL
    RET
INITS8259 ENDP

SENDM8259EOI PROC
    PUSHF
    MOV AL, 20H                  ; OCW2 非特定 EOI，清除主片 IRQ0 的在服务标志。
    MOV DX, M8259A0
    OUT DX, AL
    POPF
    RET
SENDM8259EOI ENDP

DISP PROC
    PUSHAD

    MOV AL, 0FFH                 ; PB 八位全为高时，八个低有效 LED 熄灭。
    CMP led_num, 0
    JE  LED_OUT
    ; 若 IRQ0 在比较和取值之间清零 led_num，灯码下标会变成 FFH。
    MOV AL, led_num
    DEC AL                       ; 将亮灯数 1-8 转成灯码表的下标 0-7。
    MOV BX, OFFSET LED_PATTERN
    XLAT
LED_OUT:
    MOV DX, PB_8255
    OUT DX, AL

    MOV AL, count_b
    XOR AH, AH
    MOV BL, 10
    DIV BL                       ; 计数除以 10，商为十位，余数为个位。
    MOV tens, AL
    MOV units, AH

    MOV AL, 0FEH                 ; PC0=0 选通十位，PC1=1 关闭个位。
    MOV DX, PC_8255
    OUT DX, AL

    MOV AL, tens
    MOV BX, OFFSET LEDS
    XLAT                         ; 用当前数字查 LEDS 段码表，再从 PA 输出。
    MOV DX, PA_8255
    OUT DX, AL

    CALL SHORT_DELAY             ; 保持段码和位选，让当前数字点亮一段时间。

    MOV AL, 0FFH                 ; 两根位选线均拉高，切换下一位前关闭显示。
    MOV DX, PC_8255
    OUT DX, AL

    MOV AL, 0FDH                 ; PC1=0 选通个位，PC0=1 关闭十位。
    MOV DX, PC_8255
    OUT DX, AL

    MOV AL, units
    MOV BX, OFFSET LEDS
    XLAT
    MOV DX, PA_8255
    OUT DX, AL

    CALL SHORT_DELAY

    MOV AL, 0FFH
    MOV DX, PC_8255
    OUT DX, AL

    POPAD
    RET
DISP ENDP

SHORT_DELAY PROC
    PUSH CX
    MOV CX, 300
D1:
    LOOP D1
    POP CX
    RET
SHORT_DELAY ENDP

CODE ENDS
END START
