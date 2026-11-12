; ============================================================
; 题目
; ------------------------------------------------------------
; 3、试在实验箱上设计一个系统，实现十字路口交通灯控制的模拟系统，
; 并通过 8 段数码管显示经多少秒时间信号灯将变换(每秒钟更新一次显示)。
; ============================================================
; 线路连接
; ------------------------------------------------------------
; 主机 D0-D7 -- 8255A D0-D7（箱内已连接）
; 主机 IOR/IOW -- 8255A RD/WR（箱内已连接）
; 主机 A0/A1 -- 8255A A0/A1（箱内已连接）
; EIO8_CS0 -- 8255A CS（基地址 200H，译码范围 200H-20FH）
; 8255A PA0-PA7 -- J77 ROW1-ROW8（依次对应，代码采用单低位行码）
; 8255A PB0-PB7 -- J79 RCO1-RCO8（依次对应，红色列码高有效）
; 8255A PC0-PC7 -- J78 GCO1-GCO8（依次对应，绿色列码高有效）
; 行列有效电平按扫描代码推断，接线时需核对实际点阵驱动。
; ============================================================

; 实现说明：当前代码扫描双色 8x8 点阵，未实现本题的交通灯与秒倒计时。

.Model small
.486

ROW equ 200h                        ; 200H：PA0-PA7 输出行选掩码。
RCOW equ 201h                       ; 201H：PB0-PB7 输出红色列数据。
GCOW equ 202h                       ; 202H：PC0-PC7 输出绿色列数据。
kz_8255 equ 203h                    ; 203H：写入 8255 工作方式和端口方向。

data segment
; 固定图案的 8 行点阵字模，每字节的位 0-7 依次对应列 1-8。
ZK db 04h,0Eh,04h,0AFh,44h,0ADh,0FFh,01h
data ends

code segment
	assume cs:code,ds:data

start:
	mov ax,data
	mov ds,ax
	call init8255
again:
	call cleanDotArray
	mov di,GCOW
	mov si,0
	call displayWord                   ; DI=GCOW、SI=0，仅扫描绿色图案。
	mov di,0
	mov si,RCOW
	call displayWord                   ; DI=0、SI=RCOW，仅扫描红色图案。
	mov di,GCOW
	mov si,RCOW
	call displayWord                   ; 红绿列同时输出相同字模，形成混色图案。
	jmp again
	hlt

; 用 80H 将全部端口设为方式 0 输出，分别驱动行选和两种颜色的列。
init8255 proc
	mov dx,kz_8255
	; D7=1：写入方式设置控制字。
	; D6-D5=00：A 组采用方式 0，包含 PA 和 PC4-PC7。
	; D4=0：PA0-PA7 输出行扫描掩码。
	; D3=0：PC4-PC7 输出绿色列 5-8 的点阵数据。
	; D2=0：B 组采用方式 0，包含 PB 和 PC0-PC3。
	; D1=0：PB0-PB7 输出红色列 1-8 的点阵数据。
	; D0=0：PC0-PC3 输出绿色列 1-4 的点阵数据。
	mov al,80h
	out dx,al
	ret
init8255 endp

; 清零三个输出端口，待两组列码清零后完成灭屏。
cleanDotArray proc
	mov al,0
	mov dx,ROW
	out dx,al                          ; PA 行端口清零，灭屏由后续两组列码清零完成。
	mov dx,GCOW
	out dx,al                          ; 绿色列码清零，熄灭绿色点。
	mov dx,RCOW
	out dx,al                          ; 红色列码清零，熄灭红色点。
	ret
cleanDotArray endp

; 按当前颜色配置连续扫描 300H 次，显示时长由软件延时决定。
displayWord proc
	mov cx,300h
again_0:
	mov bx, offset ZK
	call displayWord1Times
	loop again_0
	ret
displayWord endp

; 扫描八行字模，BX 指向数据，DI/SI 分别指定绿色/红色列端口。

; DI 或 SI 为 0 时跳过对应颜色，已启用的列在每行结束时清零。
displayWord1Times proc
	push cx
	mov cx,8                           ; 字模共八个字节，每轮扫描八行。
	mov ah,0FEh                        ; FEH 仅位 0 为低，代码据此选择第一行。
again_1:
	mov dx,ROW
	mov al,ah
	out dx,al
	mov al,[bx]                        ; 当前字模字节中为 1 的列参与点亮。
	cmp di,0
	je next_0
	mov dx,di
	out dx,al                          ; DI 非零时将当前行数据送到绿色列。
next_0:
	cmp si,0
	je next_1
	mov dx,si
	out dx,al                          ; SI 非零时将同一行数据送到红色列。
next_1:
	call delay
	mov al,0
	cmp di,0
	je next_2
	mov dx,di
	out dx,al                          ; 换行前先清除当前绿色列，减少换行重影。
next_2:
	cmp si,0
	je next_3
	mov dx,si
	out dx,al                          ; 换行前先清除当前红色列，减少换行重影。
next_3:
	inc bx
	rol ah,1                           ; 低位从位 0 轮转到位 7，依次扫描八行。
	loop again_1
	pop cx
	ret
displayWord1Times endp

; 为当前行提供短暂显示时间，并保留外层扫描计数 CX。
delay proc
	push cx
	mov cx,80h                         ; 每行延时 80H 次空循环，不对应固定秒数。
L0:	loop L0
	pop cx
	ret
delay endp

code ends
end start
