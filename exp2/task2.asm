; ============================================================
; 题目
; ------------------------------------------------------------
; 2、试在实验箱上设计一个系统，实现十字路口交通灯控制的模拟系统。
; ============================================================
; 线路连接
; ------------------------------------------------------------
; 主机 D0-D7 -- 8255A D0-D7（箱内已连接）
; 主机 IOR/IOW -- 8255A RD/WR（箱内已连接）
; 主机 A0/A1 -- 8255A A0/A1（箱内已连接）
; EIO8_CS0 -- 8255A CS（基地址 200H，译码范围 200H-20FH）
; 8255A PA7 -- 南北方向红灯输入（高电平点亮）
; 8255A PA6 -- 南北方向黄灯输入（高电平点亮）
; 8255A PA5 -- 南北方向绿灯输入（高电平点亮）
; 8255A PA2 -- 东西方向红灯输入（高电平点亮）
; 8255A PA1 -- 东西方向黄灯输入（高电平点亮）
; 8255A PA0 -- 东西方向绿灯输入（高电平点亮）
; 外部节拍输出 -- 8255A PC0（实际延时由节拍周期与计数共同决定）
; ============================================================

.Model small
.486

PA_8255 equ 200h                    ; 200H：A 口输出六路交通灯状态。
PC_8255 equ 202h                    ; 202H：C 口的 PC0 输入外部节拍。
CTR_8255 equ 203h                   ; 203H：写入 8255 工作方式和端口方向。
FLAG equ 0FFh                       ; 状态表结束标记，不作为灯态输出。
GREEN_NS equ 24h                    ; PA5 与 PA2 为高：南北绿灯、东西红灯。
GREEN_EW equ 81h                    ; PA7 与 PA0 为高：南北红灯、东西绿灯。

data segment
; PA7/PA6/PA5 分别控制南北红/黄/绿灯，PA2/PA1/PA0 控制东西红/黄/绿灯。
states db 24h,44h,04h,44h,04h,44h,04h  ; 24H 后以 44H/04H 让南北黄灯闪烁三次。
        db 81h,82h,80h,82h,80h,82h,80h  ; 81H 后以 82H/80H 让东西黄灯闪烁三次。
        db 0ffh                     ; FFH 仅用于结束当前一轮状态遍历。
data ends

code segment
assume cs:code,ds:data

start:
    mov ax,data
    mov ds,ax
    call init8255

; 按表输出灯态，遇到 FFH 后从头循环。
again:
    mov si,0

nextstate:
    mov al,states[si]
    cmp al,FLAG
    jz again

    mov dx,PA_8255
    out dx,al

    inc si

    cmp al,GREEN_NS
    jz longDelay

    cmp al,GREEN_EW
    jz longDelay

    call delay2s                    ; 黄灯亮、灭阶段均等待一次外部高-低变化。
    jmp next

longDelay:
    call delay30s                   ; 绿灯常亮阶段等待十次外部高-低变化。

next:
    jz nextstate                    ; 依赖 wait4Low 返回时的 ZF=1，继续输出下一灯态。

    hlt

; 当前计数为 10 次高-低变化，过程名不代表固定的 30 秒。
delay30s proc
    mov cx,10
again_30s:
    call wait4High
    call wait4Low
    loop again_30s
    ret
delay30s endp

; 当前只等待一次高-低变化，过程名不代表固定的 2 秒。
delay2s proc
    mov cx,1
again_2s:
    call wait4High
    call wait4Low
    loop again_2s
    ret
delay2s endp

; 用 81H 将 PA、PB 和 PC 高四位设为输出，PC 低四位设为输入。
init8255 proc
    mov dx,CTR_8255
    ; D7=1：写入方式设置控制字。
    ; D6-D5=00：A 组采用方式 0，包含 PA 和 PC4-PC7。
    ; D4=0：PA0-PA7 为输出，其中六位用于驱动交通灯。
    ; D3=0：PC4-PC7 为输出，本题未使用。
    ; D2=0：B 组采用方式 0，包含 PB 和 PC0-PC3。
    ; D1=0：PB0-PB7 为输出，本题未使用。
    ; D0=1：PC0-PC3 为输入，其中 PC0 接收外部节拍。
    mov al,10000001B
    out dx,al
    ret
init8255 endp

; 等待 PC0 为高，作为一次节拍计数的起点。
wait4High proc
    mov dx,PC_8255
nextL:
    in al,dx
    test al,1                       ; 掩码 01H 只检查 PC0。
    jz nextL
    ret
wait4High endp

; 等待 PC0 回低，作为一次节拍计数的终点。
wait4Low proc
    mov dx,PC_8255
nextH:
    in al,dx
    test al,1
    jnz nextH                       ; PC0 为低时 ZF=1，后续 LOOP 和 RET 不改变此标志。
    ret
wait4Low endp

code ends

end start
