; ============================================================
; 题目
; ------------------------------------------------------------
; 1、将矩阵键盘的键号（0－F）在 7 段数码管上显示，按下对应的键显示对应的数字。
; ============================================================
; 线路连接
; ------------------------------------------------------------
; 主机 D0-D7 -- 8255A D0-D7（箱内已连接）
; 主机 IOR/IOW -- 8255A RD/WR（箱内已连接）
; 主机 A0/A1 -- 8255A A0/A1（箱内已连接）
; EIO8_CS0 -- 8255A CS（基地址 200H，译码范围 200H-20FH）
; 8255A PA0-PA7 -- J2(LEDB) a-h（依次对应，共阴段码高有效）
; 8255A PC0-PC3 -- 矩阵键盘 KL0-KL3（依次对应，低电平选列）
; 8255A PC4-PC7 -- 矩阵键盘 KH0-KH3（依次对应，低电平表示按下）
; 实验箱 +5V -- J3(BIT) BIG1（固定选通一位，代码未控制位选）
; 外部节拍输出 -- 8255A PB0（仅 delay 使用，主流程未调用）
; ============================================================

.Model small
.486

PA_8255 equ 200h                    ; 200H：A 口输出 a-h 段码。
PB_8255 equ 201h                    ; 201H：B 口输入，备用延时只检测 PB0。
PC_8255 equ 202h                    ; 202H：PC0-PC3 扫列，PC4-PC7 读行。
ctr_8255 equ 203h                   ; 203H：写入 8255 工作方式和端口方向。

data segment
; 0-F 的共阴段码按键值顺序排列，位 0-7 依次对应 a-h。
    LEDCODE DB 3FH,06H,5BH,4FH,66H,6DH,7DH,07H,7FH,67H
            DB 77H,7CH,39H,5EH,79H,71H
data ends

code segment
    assume cs:code,ds:data

start:
    mov ax,data
    mov ds,ax
    call init8255

; 连续两次读取同一行列状态，按键释放后再译码并显示。
again:
    call readKey
    mov bx,ax

    call readKey                    ; 两次读键之间未调用 delay，没有显式消抖延时。
    cmp bx,ax
    jnz again
    call keyUp                      ; 松键后才显示，并用 BX 保留松键前的行列状态。
    mov ax,bx
    call getKeyCode
    call disp

    jmp again
    hlt

; 用 8AH 将 8255 配置为方式 0，C 口按上下半口分别设置方向。
init8255 proc
    mov dx,ctr_8255
    ; D7=1：写入方式设置控制字。
    ; D6-D5=00：A 组采用方式 0，包含 PA 和 PC4-PC7。
    ; D4=0：PA0-PA7 输出数码管段码。
    ; D3=1：PC4-PC7 输入键盘 KH0-KH3 的行状态。
    ; D2=0：B 组采用方式 0，包含 PB 和 PC0-PC3。
    ; D1=1：PB0-PB7 为输入，备用延时子程序只检测 PB0。
    ; D0=0：PC0-PC3 输出键盘 KL0-KL3 的列扫描信号。
    mov al,10001010B
    out dx,al
    ret
init8255 endp

; 返回 AH 中的列扫描掩码及 AL 高四位的行输入状态。
readKey PROC
    mov ah,11111110B                ; FEH 的单个低位从 PC0 开始选列。
scan:
    MOV AL,AH
    MOV DX,pc_8255
    OUT DX,AL
    IN AL,DX
    OR AL,0FH                       ; 将低四位置 1，只保留高四位的行输入供判断。
    CMP AL,0FFH                     ; 高四位全为 1 表示当前扫描列没有按键按下。
    JNE final
    ROL AH,1                        ; 低位轮转到 PC0-PC3 时依次选择四列。
    JMP scan
final:
    RET
readKey ENDP

; 按 PB0 的 30 次高-低变化计数，实际延时取决于外部节拍。

; 备用延时过程，当前主流程未调用。
delay proc
    push cx
    mov cx,30
X1:
    call wait4High
    call wait4Low
    LOOP X1
    POP cx
    ret
delay endp

; 保持当前列的扫描电平，等待该列所有行输入恢复为高。
keyUp proc
noup:
    mov al,ah
    mov dx,pc_8255
    OUT dx,al
    IN  al,dx
    or al,0fh                       ; 忽略低四位的列输出，只检查高四位行输入。
    cmp al,0ffh
    je exit                         ; 行输入全部恢复为高，说明当前列按键已释放。
    jmp noup
exit:
    ret
keyUp endp

; 将低有效的行列状态换算为键值：行号乘 4 再加列号。
getKeyCode PROC
    NOT AH                          ; 把 AH 中选中列的低电平转换为 1。
    NOT AL                          ; 把 AL 高四位中按下行的低电平转换为 1。
    MOV BH,00H
    MOV BL,00H
KK:
    SHR AH,1                        ; 逐位移出列掩码，用 BH 累计列号 0-3。
    JC NEXT1
    ADD BH,1H
    JMP KK
NEXT1:
    SHR AL,1                        ; 逐位移出行掩码，找到被按下的输入位。
    JC NEXT2
    ADD BL,4                        ; 每移过一个零位加 4，累计值含低四位带来的 16。
    JMP NEXT1
NEXT2:
    ADD BH,BL
    MOV AL,BH
    sub al,16                       ; 去掉固定偏移 16，得到行号乘 4 加列号。
CMPEXIT:
    RET
getKeyCode ENDP

; 用 AL 中的 0-F 键值查段码表，并将结果送到 PA。
DISP proc
    push bx
    push dx
    mov bx,offset ledcode
    mov ah,0
    add bx,ax
    mov al,[bx]
    mov dx,pa_8255
    out dx,al                       ; 段码由 PA 锁存输出，BIG1 由外部固定选通。
    pop dx
    pop bx
    ret
DISP endp

; 轮询 PB0，等待外部节拍进入高电平。
wait4High proc
nextH:
    mov dx,pb_8255
    in al,dx
    test al,01h                     ; 01H 只检测 PB0，忽略其他 B 口输入。
    jz nextH
    ret
wait4High endp

; 轮询 PB0，等待外部节拍回到低电平。
wait4Low proc
nextL:
    mov dx,pb_8255
    in al,dx
    test al,01h                     ; PB0 回到低电平后完成本次高-低等待。
    jnz nextL
    ret
wait4Low endp

code ends
end start
