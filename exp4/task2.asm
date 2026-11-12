; ============================================================
; 题目
; ------------------------------------------------------------
; 2. 试用 0832 产生 1 V、2 V、3 V、4 V、4.5 V 电压，每种电压输出持续 3 秒。
; ============================================================
; 线路连接
; ------------------------------------------------------------
; 主机 SD0-SD7 -- DAC0832 DI0-DI7（箱内已连接）
; 主机 SIOW -- DAC0832 WR1/WR2（箱内已连接，低有效）
; VCC -- DAC0832 ILE（箱内已连接，高电平允许锁存）
; 280H 的低有效译码输出 -- J48(0832CS)（箱内接 DAC0832 的 CS/XFER）
; W1 滑端 -- DAC0832 Vref（第 8 脚，调到 +5 V）
; J41(DAOUT) -- 电压表正端，实验箱 GND -- 电压表负端
; 实验箱默认译码范围为 200H-27FH，280H 需另行译码。
; ============================================================

.MODEL SMALL
.486
.STACK 100H

DAC_PORT EQU 0280H

DATA SEGMENT
    ; DAOUT = 2 * Uref * N / 256 - 5。
    ; Uref 为 +5 V 时，表中各码值依次对应约 1、2、3、4、4.5 V。
    DAC_DATA DB 09AH,0B3H,0CDH,0E6H,0F3H
DATA ENDS

CODE SEGMENT
ASSUME CS:CODE,DS:DATA

START:
    MOV AX,DATA
    MOV DS,AX

AGAIN:
    MOV SI,0

NEXT_VOLTAGE:
    MOV AL,DAC_DATA[SI]
    MOV DX,DAC_PORT
    OUT DX,AL                ; DAC0832 锁存码值，延时期间保持该档电压。

    CALL DELAY_3S

    INC SI
    CMP SI,5
    JB NEXT_VOLTAGE

    JMP AGAIN

; 读取 DOS 时钟，返回本分钟内的百分之一秒计数。
GET_TIME PROC
    PUSH BX
    PUSH DX

    MOV AH,2CH
    INT 21H                  ; 功能 2CH 返回 DH=秒、DL=百分之一秒。

    MOV AL,DH
    MOV BL,100
    MUL BL

    XOR DH,DH
    ADD AX,DX                ; AX = 秒数 * 100 + 百分之一秒数。

    POP DX
    POP BX
    RET
GET_TIME ENDP

; 从本次调用起计满 300 个百分之一秒后返回。
DELAY_3S PROC
    PUSH AX
    PUSH BX

    CALL GET_TIME
    MOV BX,AX

WAIT_LOOP:
    CALL GET_TIME
    SUB AX,BX
    JNC CHECK_TIME
    ADD AX,6000              ; 时钟跨过整分钟时补上 6000 个计数。

CHECK_TIME:
    CMP AX,300
    JB WAIT_LOOP

    POP BX
    POP AX
    RET
DELAY_3S ENDP

CODE ENDS
END START
