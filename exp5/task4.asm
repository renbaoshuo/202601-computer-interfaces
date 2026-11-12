; ============================================================
; 题目
; ------------------------------------------------------------
; 实验六 8259 中断实验
; 4. 将 0809 的 INT1 连接到 1 个可变电阻器上，每 1 秒采集一次 0809
; 转换的数字量，将转换后的数字量显示在 8 段数码,用中断方式实现。
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
; 8255A PC0 -- J3(BIT) BIG2（小数位，高电平选通）
; 8255A PC1 -- J3(BIT) BIG1（整数位，高电平选通）
; J7 1 Hz 固定脉冲输出 -- 主 8259A IRQ0（每秒触发一次）
; CS6 -- J10 0809CS（ADC0809 片选基址 260H）
; J6 500 kHz 固定脉冲输出 -- J10 0809CLK
; RW1 VOUT1（0-5 V） -- J43 ADC0809 IN0（程序选择通道 0）
; J10 0809EOC -- 8255A PC4（按程序的 10H 掩码接线）
; 主机 SD0-SD2 -- ADC0809 ADD-A/ADD-B/ADD-C（箱内已连接）
; 主机 SD0-SD7 -- ADC0809 的 8 位数据输出（箱内已连接）
; ADC0809 REF+/REF- -- +5 V/GND（箱内已连接）
; 题面写 INT1，程序选择 IN0。
; 原接线注释写 PC2，当前 8255 配置将 PC2 设为输出。
; ============================================================

.model small
.486

PA_8255 EQU 200H                 ; A 口，输出数码管段码。
PB_8255 EQU PA_8255+1            ; B 口，本题未用。
PC_8255 EQU PA_8255+2            ; C 口，PC0/PC1 输出位选，PC4 读取 EOC。
KZ_8255 EQU PA_8255+3            ; 8255A 控制端口，设置工作方式和引脚方向。
M8259A0 EQU 210H                 ; 主片命令口（A0=0），写 ICW1 和 EOI。
M8259A1 EQU 211H                 ; 主片数据口（A0=1），写 ICW2-ICW4 和屏蔽字。
S8259A0 EQU 220H                 ; 从片命令口（A0=0），写 ICW1。
S8259A1 EQU 221H                 ; 从片数据口（A0=1），写 ICW2-ICW4 和屏蔽字。
OUT0_0809 EQU 260H               ; 向端口写通道号启动转换，从同一端口读结果。

DATA SEGMENT
	buffer db 1024 dup(?)
	counter   db 0H              ; 保存最近一次从 ADC0809 读出的 8 位值。
	; D0-D6 依次对应 a-g，1 点亮对应的段。
	; 段码按数字 0-9 排列，D7 恒为 1，接到 h 时小数点亮。
	LEDS   db 0BFH, 86H, 0DBH, 0CFH, 0E6H
		   db 0EDH, 0FDH, 87H, 0FFH, 0EFH
	n	db ?
	q	db ?
	r	db ?
	s	db ?
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
	sti
; 前台持续刷新数码管，显示最近一次采样换算的电压。
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
	IN AL, DX
	AND AL, 11111110B            ; 只清 OCW1 的 D0，开放主片 IRQ0。
	OUT DX, AL

	POP DX
	POP AX
	POP DS
	RET
setINTVector ENDP

; 中断会改写 AL 和 DX，可能干扰前台写显示端口。
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
	; D3=1 将 PC4-PC7 设为输入，PC4 读取 ADC0809 的 EOC。
	; D2=0 将 B 组（PB、PC0-PC3）设为方式 0。
	; D1=0 将 PB0-PB7 设为输出，B 口无外设。
	; D0=0 将 PC0-PC3 设为输出，PC0 和 PC1 分别高电平选通小数位和整数位。
	MOV AL, 10001000B
	OUT DX, AL                   ; 将 88H 写入 203H，使端口配置生效。
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

; 每次 1 Hz 中断启动一次采样，随后查询 EOC 并读取数据。
ADDCOUNTER PROC
	PUSH AX
	CALL START0809
	CALL CHECK0809
	CALL READ0809
	POP AX
	RET
ADDCOUNTER ENDP

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
	; 沿用实验五第 5 题的换算方法，按 q.s 显示近似电压。
	XOR AX, AX
	MOV AL, COUNTER
	MOV BL, 51
	DIV BL                       ; 除以 51，商 q 为整数位，余数 r 用于求小数位。
	MOV q, AL
	MOV r, AH
	XOR AX, AX
	MOV AL, r
	MOV BL, 5
	DIV BL                       ; r 除以 5 得到小数位的初值。
	MOV s, AL
	CMP AH, 3                    ; 余数达到 3 时，小数位加一。
	JL FLAG
	INC s
FLAG:	
	MOV AL, 1B                   ; PC0=1 选通右侧小数位。
	MOV DX, PC_8255
	OUT DX, AL
	MOV BX, OFFSET LEDS
	; r 为 48-50 时 s=10，查表会越过 LEDS 表尾。
	MOV AL, s
	XLAT
	MOV DX, PA_8255
	OUT DX, AL
	MOV AL, 0                    ; 切换到整数位前把 PA 的段线拉低。
	OUT DX, AL

	MOV AL, 10B                  ; PC1=1 选通左侧整数位。
	MOV DX, PC_8255
	OUT DX, AL
	MOV BX, OFFSET LEDS
	MOV AL, q
	XLAT
	MOV DX, PA_8255
	OUT DX, AL
	MOV AL, 0
	OUT DX, AL

	POPAD
	RET
DISP ENDP

START0809 PROC
	MOV AL, 0                    ; D2-D0=000，选择 ADC0809 的 IN0 通道。
	MOV DX, OUT0_0809
	OUT DX, AL                   ; 向 260H 写入通道号，箱内电路产生 ALE 和 START。
	RET
START0809 ENDP

CHECK0809 PROC
	MOV DX, PC_8255
AGAIN_C:
	IN AL, DX
	AND AL, 00010000B            ; 10H 只保留 PC4 上的 EOC 电平。
	; ADC0809 的 EOC 在转换期间为低，完成后回高。
	TEST AL, 00010000B
	JNE AGAIN_C                  ; PC4 为低即返回，可能在转换完成前读取。
	RET
CHECK0809 ENDP

READ0809 PROC
	MOV DX, OUT0_0809
	IN AL, DX                    ; 从 260H 读取 ADC0809 数据寄存器中的 8 位值。
	MOV COUNTER, AL
	RET
READ0809 ENDP

CODE ENDS
END START
