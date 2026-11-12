; ============================================================
; 题目
; ------------------------------------------------------------
; 1. 试用 0832 分别产生 1V、2V、3V、4V、4.5V 电压。
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

DAC_PORT  EQU 0280H
; DAOUT = 2 * Uref * N / 256 - 5。
; Uref 为 +5 V 时，切换档位只取消目标行的注释，并注释当前行。
DAC_VALUE EQU 09AH    ; 1 V
; DAC_VALUE EQU 0B3H  ; 2 V
; DAC_VALUE EQU 0CDH  ; 3 V
; DAC_VALUE EQU 0E6H  ; 4 V
; DAC_VALUE EQU 0F3H  ; 4.5 V

CODE SEGMENT
ASSUME CS:CODE

START:
    MOV DX,DAC_PORT
    MOV AL,DAC_VALUE
    OUT DX,AL                ; DAC0832 锁存码值，空转期间保持该档电压。

AGAIN:
    JMP AGAIN

CODE ENDS
END START
