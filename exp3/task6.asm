; ============================================================
; 题目
; ------------------------------------------------------------
; 6. 试在实验箱 LED 点阵显示器上用红色循环显示“接口技术”四个字，
; 要求每个字显示 1.8 秒后再显示下一个字。
; ============================================================
; 线路连接
; ------------------------------------------------------------
; 主机 D0-D7 -- 8255、8253 D0-D7（箱内已连接）
; 主机 IOR/IOW -- 8255、8253 RD/WR（箱内已连接）
; 主机 A0/A1 -- 8255、8253 A0/A1（箱内已连接）
; EIO8_CS0 -- 8255 CS（基地址 200H，译码范围 200H-20FH）
; EIO8_CS1 -- 8253 CS（面板标为 8254/3CS，地址范围 210H-21FH）
; 8255 PA0-PA7 -- J77 ROW1-ROW8（依次对应，低电平选行）
; 8255 PB0-PB7 -- J79 RCO1-RCO8（依次对应，列码为 1 时点亮）
; 8253 OUT0 -- 8255 PC0（高电平表示本轮计数结束）
; 8253 CLK0 -- 固定脉冲 10 Hz 输出
; 8253 GATE0 -- J1(KD) K1（置高，允许计数）
; ============================================================

.model small
.486

pa_8255 equ 200h            ; 200H：PA0-PA7 输出 ROW1-ROW8 的行选码。
pb_8255 equ 201h            ; 201H：PB0-PB7 输出 RCO1-RCO8 的红色列码。
pc_8255 equ 202h            ; 202H：PC0 读取 8253 OUT0 的计数结束电平。
kz_8255 equ 203h            ; 203H：8255 方式和端口方向控制端口。

T0_8253 equ 210h            ; 210H：C0 初值端口，本题以 10 Hz 时钟计时。
T1_8253 equ 211h            ; 211H：C1 端口，本题未使用。
T2_8253 equ 212h            ; 212H：C2 端口，本题未使用。
KZ_8253 equ 213h            ; 213H：8253 方式控制端口。

data segment
; 四组字模依次为“接、口、技、术”，每组 8 字节对应 8 行。
ZK DB 022H,0FFH,052H,076H,023H,072H,052H,08AH  ; “接”的 8 行字模。
   DB 00H, 00H,07EH,042H,042H,07EH, 00H,00H  ; “口”的 8 行字模。
   DB 022H,072H,027H,0FAH,056H,023H,052H,08AH  ; “技”的 8 行字模。
   DB 08H,028H,07FH,008H,01CH,02AH,049H,08H  ; “术”的 8 行字模。

counter dw 0                ; 当前字模的字节偏移，在 0、8、16、24 之间循环。
data ends

code segment
assume cs:code,ds:data
start:
	mov ax,data
	mov ds,ax
	call init8255
	mov bx,offset ZK
	mov counter,0

; 持续显示当前字，计时结束后将 BX 移到下一组字模。
again:
	call displayWord
	call incCounter
	mov bx,offset ZK
	add bx,counter             ; BX 指向 ZK 首址加当前字模偏移。
	jmp again

	hlt                        ; 正常流程始终跳回 again，此指令不可达。

; 字模偏移每次增加 8，并在经过第四个字后回到第一组。
incCounter proc
	add counter,8
	cmp counter,24             ; 24 是第四个字的起始偏移，四个字模共占 32 字节。
	jle next
	mov counter,0
next:
	ret
incCounter endp

init8255 proc
	mov dx,kz_8255
	; D7=1：选择方式设置控制字，配置端口方式和输入输出方向。

	; D6-D5=00：A 组使用方式 0，包含 PA 和 PC4-PC7。

	; D4=0：PA0-PA7 设为输出，依次连接 ROW1-ROW8 行选端。

	; D3=0：PC4-PC7 设为输出，本题未使用这些引脚。

	; D2=0：B 组使用方式 0，包含 PB 和 PC0-PC3。

	; D1=0：PB0-PB7 设为输出，依次驱动红色列 RCO1-RCO8。

	; D0=1：PC0-PC3 设为输入，其中 PC0 读取 OUT0 的计数结束电平。
	mov al,10000001b
	out dx,al
	ret
init8255 endp

; 以 CX 作为 C0 的 16 位初值，先写低 8 位，再写高 8 位。
setTimer0 proc
	mov dx,KZ_8253
	; D7-D6=00：选择计数器 C0，对应 CLK0/GATE0/OUT0。

	; D5-D4=11：使用 16 位初值，先写低 8 位，再写高 8 位。

	; D3-D1=000：方式 0，计数结束时 OUT 由低变高并保持。

	; D0=0：采用二进制计数，初值不是 BCD 编码。
	mov al,00110000b
	out dx,al
	mov dx,T0_8253
	mov ax,cx
	out dx,al                  ; 先写 CX 的低字节。
	mov al,ah
	out dx,al                  ; 再写 CX 的高字节，OUT0 在计数结束前保持低电平。
	ret
setTimer0 endp

; 每次重装 C0 并刷新同一字模，直到 OUT0 变高后返回。
displayWord proc
	mov cx,18                  ; 10 Hz × 1.8 秒 = 18，作为本轮计数初值。
	call setTimer0

; 方式 0 装载需等待输入时钟，实际换字间隔受时钟相位影响。
again_0:
	call flashWord
	mov dx,pc_8255
	in al,dx
	test al,01                 ; 只检查 PC0，OUT0 为 1 表示本轮计数结束。
	jz again_0                 ; 计数未结束时继续扫描，防止等待期间点阵熄灭。
	ret
displayWord endp

; 扫描当前字的 8 行，返回时恢复调用者的 BX 和 CX。
flashWord proc
	push bx
	push cx
	mov cx,8
	mov ah,0feh                ; FEH 仅 PA0 为低，先选通 ROW1，其他七行不选通。

again_1:
	mov dx,pa_8255
	mov al,ah
	out dx,al
	mov al,[bx]                ; 取当前行的列码，位 0-7 依次对应 RCO1-RCO8。
	mov dx,pb_8255
	out dx,al

	mov al,00h                 ; 将 PB 列码清零，熄灭当前行的红色像素。
	out dx,al

	inc bx
	rol ah,1                   ; 将唯一的低位移到下一行，依次选通 ROW1-ROW8。
	loop again_1               ; 八行各扫描一次后返回，外层循环负责持续刷新。

	pop cx
	pop bx
	ret
flashWord endp
code ends

end start
