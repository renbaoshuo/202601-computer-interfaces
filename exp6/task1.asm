; ============================================================
; 题目
; ------------------------------------------------------------
; 1. 试在试验箱中并发完成以下任务：
; A) 间隔 2 秒显示 1 个 led 灯，至亮 8 个后，熄灭，然后重复该过程；
; B) 间隔 1 秒计数，并将数值显示在 8 段数码管上，计数范围 0 至 20；
;    计数至 20 后清零，然后重复上述过程。
; C) 间隔 1.5 秒倒计数，并将数值显示在 8 段数码管上，计数范围 15 至 0；
;    计数至 0 后将计数值重置为 15，然后重复上述过程。
; D) 间隔 0.1 秒计数，并将数值显示在 8 段数码管上，计数范围 0 至 60；
;    计数至 60 后清零，然后重复上述过程。
; ============================================================
; 线路连接
; ------------------------------------------------------------
; 主机 SD0-SD7 -- 8255A、8253 和主从 8259A 的 D0-D7（箱内已连接）
; 主机 SIOR/SIOW -- 各接口芯片的 RD/WR（箱内已连接）
; 主机 SA0/SA1 -- 8255A 和 8253 的 A0/A1（箱内已连接）
; 主机 SA0 -- 主从 8259A 的 A0（箱内已连接）
;
; JP5 EIO8_CS0 -- J31 8255CS（8255A 端口 200H-203H）
; JP5 EIO8_CS1 -- J8 M8259CS（主片端口 210H-211H）
; JP5 EIO8_CS2 -- J9 S8259CS（从片端口 220H-221H）
; JP5 EIO8_CS3 -- J18 8254/3CS（8253 端口 230H-233H）
;
; J8 INT -- JP3 INTR（主片向 CPU 请求中断）
; JP3 INTA -- J8 INTA0（两片 8259A 的应答线在箱内相连）
; 主片 CAS0-CAS2 -- 从片 CAS0-CAS2（箱内已连接）
; J9 SINT -- J28 IRQ7（从片接入主片的级联通道）
; J7 10 Hz -- J25 IRQ0（任务 D，向量 60H）
; J7 1 Hz -- J25 IRQ1（任务 B，向量 61H）
; J7 10 Hz -- J19 CLK0、J20 CLK1（与 IRQ0 共用时钟）
; K1 -- J19 GATE0、J20 GATE1（K1 拨高以允许计数）
; J19 OUT0 -- J29 IRQ9（从片 IR1，任务 C，向量 69H）
; J20 OUT1 -- J29 IRQ10（从片 IR2，任务 A，向量 6AH）
;
; J22 PA0-PA7 -- J2(LEDB) A-H（共阴数码管的段码，高电平点亮）
; J23 PB0-PB7 -- J4(LD) L1-L8（高电平点亮）
; J24 PC0-PC5 -- J3(BIT) BIT1-BIT6（高电平选通，PC6/PC7 无需接线）
; 从左到右为 DIG6-DIG1，依次显示 B、C、D 三组计数，每组十位在左。
; ============================================================

.MODEL SMALL
.486
.STACK 100h

PPI_BASE    EQU 200h              ; 8255A 的 A/B/C 口及控制口位于 200H-203H。
PIT_BASE    EQU 230h              ; 8253 的 C0/C1/C2 及控制口位于 230H-233H。
PIC_M_CMD   EQU 210h              ; 主片命令口为 210H，数据口为 211H。
PIC_S_CMD   EQU 220h              ; 从片命令口为 220H，数据口为 221H。

IRQD_VEC    EQU 60h               ; 主片 IR0 对应任务 D。
IRQB_VEC    EQU 61h               ; 主片 IR1 对应任务 B。
IRQC_VEC    EQU 69h               ; 从片 IR1 对应 IRQ9，服务任务 C。
IRQA_VEC    EQU 6Ah               ; 从片 IR2 对应 IRQ10，服务任务 A。

PORT_A      EQU 0
PORT_B      EQU 1
PORT_C      EQU 2

CNT_A_MAX   EQU 8
CNT_B_MAX   EQU 20
CNT_C_INIT  EQU 15
CNT_D_MAX   EQU 60

.DATA
; 共阴段码按 0-F 排列，D0-D7 依次对应 a-g 和小数点。
SegTable    DB 3Fh,06h,5Bh,4Fh,66h,6Dh,7Dh,07h
            DB 7Fh,6Fh,77h,7Ch,39h,5Eh,79h,71h

; 位选掩码与 DispSeg 同序，从 BIT6 扫到 BIT1。
BitTbl      DB 20h,10h,08h,04h,02h,01h

; 下标为亮灯数，掩码从 PB0 起连续置位，0 表示全灭。
LedMaskTbl  DB 00000000b
            DB 00000001b
            DB 00000011b
            DB 00000111b
            DB 00001111b
            DB 00011111b
            DB 00111111b
            DB 01111111b
            DB 11111111b

; 四个 ISR 分别更新各自的计数，任务 A 另存一份灯码供主循环读取。
CntA        DB 0
CntB        DB 0
CntC        DB CNT_C_INIT
CntD        DB 0
LedState    DB 0

; 主循环使用 B、C、D 的计数快照生成六位段码。
SnapB       DB 0
SnapC       DB 0
SnapD       DB 0
DispSeg     DB 6 DUP(0)           ; 按 B、C、D 顺序存放段码，每组先十位再个位。

.CODE
START:
        mov ax, @data
        mov ds, ax

        mov dx, PPI_BASE
        ; D7=1 选择方式设置控制字。
        ; D6-D5=00 使 A 组采用方式 0，包含 PA 和 PC4-PC7。
        ; D4=0 使 PA0-PA7 输出数码管的 A-H 段码。
        ; D3=0 使 PC4-PC7 为输出，其中 PC4/PC5 分别选通 BIT5/BIT6。
        ; D2=0 使 B 组采用方式 0，包含 PB 和 PC0-PC3。
        ; D1=0 使 PB0-PB7 输出 LED L1-L8 的灯码。
        ; D0=0 使 PC0-PC3 分别输出 BIT1-BIT4 的位选信号。
        mov al, 80h
        call PPI_SetMode

        ; C0 在方式 2 下把 10 Hz 按 15 分频，OUT0 每 1.5 秒触发任务 C。
        ; OUT 每个周期拉低一个输入时钟，回到高电平时触发 8259A。
        mov dx, PIT_BASE
        mov bl, 0
        mov bh, 2
        mov ax, 15
        call PIT_Config

        ; C1 在方式 2 下把 10 Hz 按 20 分频，OUT1 每 2 秒触发任务 A。
        mov dx, PIT_BASE
        mov bl, 1
        mov bh, 2
        mov ax, 20
        call PIT_Config

        ; CPU 先关中断，待两片 8259A、向量表和屏蔽字配置完成后再开中断。
        ; 主片向量范围为 60H-67H，从片向量范围为 68H-6FH。
        cli
        mov dx, PIC_M_CMD
        mov bx, PIC_S_CMD
        mov al, 60h
        mov ah, 68h
        mov cl, 7
        call PIC_InitPair

        ; 将任务 D、B、C、A 各自的 ISR 登记到实模式中断向量表。
        mov al, IRQD_VEC
        mov dx, cs
        mov bx, OFFSET IsrTaskD
        call IRQ_SwapVector

        mov al, IRQB_VEC
        mov dx, cs
        mov bx, OFFSET IsrTaskB
        call IRQ_SwapVector

        mov al, IRQC_VEC
        mov dx, cs
        mov bx, OFFSET IsrTaskC
        call IRQ_SwapVector

        mov al, IRQA_VEC
        mov dx, cs
        mov bx, OFFSET IsrTaskA
        call IRQ_SwapVector

        ; 逐路清除 OCW1 的屏蔽位，主片 IRQ7 用来转发从片请求。
        mov dx, PIC_M_CMD
        mov bl, 0
        mov al, 0
        call PIC_SetIRQ

        mov dx, PIC_M_CMD
        mov bl, 1
        mov al, 0
        call PIC_SetIRQ

        mov dx, PIC_M_CMD
        mov bl, 7
        mov al, 0
        call PIC_SetIRQ

        mov dx, PIC_S_CMD
        mov bl, 1                 ; 从片的屏蔽字使用片内 IR1 对应的 D1。
        mov al, 0
        call PIC_SetIRQ

        mov dx, PIC_S_CMD
        mov bl, 2                 ; 从片的屏蔽字使用片内 IR2 对应的 D2。
        mov al, 0
        call PIC_SetIRQ
        sti                       ; 此时主片 OCW1 为 7CH，从片 OCW1 为 F9H。

; 硬件中断推进四个任务，主循环持续输出灯码和扫描数码管。
MainLoop:
        mov dx, PPI_BASE
        mov al, LedState
        mov bl, PORT_B
        call PPI_Write

        ; 短暂关中断，在同一轮快照中复制 B、C、D 三个计数。
        pushf
        cli
        mov al, CntB
        mov SnapB, al
        mov al, CntC
        mov SnapC, al
        mov al, CntD
        mov SnapD, al
        popf

        ; 依显示顺序把三组计数各转换成十位和个位段码。
        mov di, OFFSET DispSeg
        mov al, SnapB
        call ValToSeg2
        add di, 2
        mov al, SnapC
        call ValToSeg2
        add di, 2
        mov al, SnapD
        call ValToSeg2

        ; 每位先关全部位选，再写段码、选通当前位，以免串显。
        xor si, si
ScanNext:
        mov dx, PPI_BASE
        mov bl, PORT_C
        xor al, al
        call PPI_Write

        mov bl, PORT_A
        mov al, DispSeg[si]
        call PPI_Write

        mov bl, PORT_C
        mov al, BitTbl[si]
        call PPI_Write

        call DelayShort
        inc si
        cmp si, 6
        jb ScanNext
        jmp MainLoop

; 将 AL 中的 0-99 转成十位和个位段码，写入 DS:[DI] 起的两个字节并保留前导零。
ValToSeg2 PROC NEAR
        push ax
        push bx
        push dx
        mov ah, 0
        mov bl, 10
        div bl                    ; 商 AL 是十位数字，余数 AH 是个位数字。
        mov dl, ah
        mov bx, OFFSET SegTable
        xlat
        mov [di], al
        mov al, dl
        xlat
        mov [di+1], al
        pop dx
        pop bx
        pop ax
        ret
ValToSeg2 ENDP

; 空循环保持当前位的显示，实际停留时间随 CPU 运行速度而变。
DelayShort PROC NEAR
        push cx
        mov cx, 300
DelayShortLoop:
        loop DelayShortLoop
        pop cx
        ret
DelayShort ENDP

; DX 为 8255A 基地址，AL 为要写入基地址加 3 的方式控制字。
PPI_SetMode PROC NEAR
        pushf
        push dx
        add dx, 3
        out dx, al
        pop dx
        popf
        ret
PPI_SetMode ENDP

; DX 为 8255A 基地址，BL 为端口偏移，AL 为待输出的数据。
PPI_Write PROC NEAR
        pushf
        push dx
        push bx
        movzx bx, bl
        add dx, bx
        out dx, al
        pop bx
        pop dx
        popf
        ret
PPI_Write ENDP

; DX 为 8253 基地址，BL/BH 分别为通道和方式，AX 为 16 位计数初值。
; 本程序使用方式 2，C0 的控制字是 34H，C1 的控制字是 74H。
PIT_Config PROC NEAR
        pushf
        push bx
        push dx
        push ax
        mov al, bl
        shl al, 6                 ; D7-D6 选择通道，C0 为 00B，C1 为 01B。
        mov ah, bh
        shl ah, 1                 ; D3-D1 选择工作方式，方式 2 为 010B。
        or al, ah                 ; D0 保持为 0，使用二进制计数。
        or al, 30h                ; D5-D4=11，先写初值低字节，再写高字节。
        cli
        add dx, 3
        out dx, al
        sub dx, 3
        movzx bx, bl
        add dx, bx
        pop ax
        out dx, al
        xchg al, ah
        out dx, al
        xchg al, ah
        pop dx
        pop bx
        popf
        ret
PIT_Config ENDP

; DX/BX 分别为主片和从片的命令口，AL/AH 为各自的向量基址。
; CL 指定主片上接收 SINT 的片内中断号。
PIC_InitPair PROC NEAR
        pushf
        push ax
        push dx
        push si
        mov si, ax
        cli
        mov ah, 1
        shl ah, cl                ; 主片 ICW3 是从片接入位图，IRQ7 对应 80H。
        call PIC_InitController
        mov dx, bx
        mov ax, si
        mov al, ah
        mov ah, cl                ; 从片 ICW3 的低三位指定级联号，接 IRQ7 时为 07H。
        call PIC_InitController
        pop si
        pop dx
        pop ax
        popf
        ret
PIC_InitPair ENDP

; DX 为当前 8259A 的命令口，AL/AH 分别为 ICW2 和 ICW3。
PIC_InitController PROC NEAR PRIVATE
        push ax
        ; ICW1 的 D3=0 选上升沿触发，D1=0 选级联，D0=1 要求写入 ICW4。
        mov al, 11h
        out dx, al
        inc dx                    ; 命令口的下一个地址是 A0=1 的数据口。
        pop ax
        out dx, al                ; ICW2 提供向量号的高五位，低三位由片内 IR 号给出。
        mov al, ah
        out dx, al                ; ICW3 设置主从级联关系。
        ; ICW4 的 D3=0 采用非缓冲模式，由 SP/EN 引脚电平区分主从。
        mov al, 01h               ; D0=1 选 8086 模式，D1=0 要求程序发送 EOI。
        out dx, al
        mov al, 0FFh              ; 初始化时把 OCW1 全置 1，先屏蔽全部中断输入。
        out dx, al
        ret
PIC_InitController ENDP

; DX 为命令口，BL 为片内 IR 号，AL 为 0 时开放该路、非 0 时屏蔽。
PIC_SetIRQ PROC NEAR
        pushf
        push ax
        push cx
        push dx
        mov cl, bl
        mov ch, al
        mov ah, 1
        shl ah, cl
        inc dx
        cli
        in al, dx                 ; 读取 OCW1，以便保留其它中断输入的屏蔽位。
        test ch, ch
        jz PIC_EnableIRQ
        or al, ah                 ; 置位屏蔽位以禁用该路中断。
        jmp PIC_WriteIRQMask
PIC_EnableIRQ:
        not ah
        and al, ah                ; 清除屏蔽位以开放该路中断。
PIC_WriteIRQMask:
        out dx, al
        pop dx
        pop cx
        pop ax
        popf
        ret
PIC_SetIRQ ENDP

; 向 DX 指定的 8259A 命令口发送非特定 EOI。
PIC_EOI PROC NEAR
        push ax
        mov al, 20h               ; 20H 清除优先级最高的在服务位。
        out dx, al
        pop ax
        ret
PIC_EOI ENDP

; AL 为向量号，DX:BX 传入新入口的段地址和偏移，并返回旧入口。
IRQ_SwapVector PROC NEAR
        pushf
        push ax
        push si
        push es
        ; 实模式向量表从 0000:0000 开始，每项 4 字节。
        movzx si, al
        shl si, 2
        xor ax, ax
        mov es, ax
        cli                       ; 关中断后成对更新表项的偏移和段地址。
        mov ax, es:[si]
        mov es:[si], bx
        mov bx, ax
        mov ax, es:[si+2]
        mov es:[si+2], dx
        mov dx, ax
        pop es
        pop si
        pop ax
        popf
        ret
IRQ_SwapVector ENDP

; ISR 保存用到的寄存器，并切换 DS 后再访问本程序的数据。
; 主片本地中断只向主片发 EOI，从片中断按从片、主片的顺序发送 EOI。

; 任务 D 每 0.1 秒加一，显示到 60 后在下一次中断清零。
IsrTaskD PROC FAR
        push ax
        push dx
        push ds
        mov ax, @data
        mov ds, ax
        inc CntD
        cmp CntD, CNT_D_MAX+1
        jb ID_Done
        mov CntD, 0
ID_Done:
        mov dx, PIC_M_CMD
        call PIC_EOI
        pop ds
        pop dx
        pop ax
        iret
IsrTaskD ENDP

; 任务 B 每 1 秒加一，显示到 20 后在下一次中断清零。
IsrTaskB PROC FAR
        push ax
        push dx
        push ds
        mov ax, @data
        mov ds, ax
        inc CntB
        cmp CntB, CNT_B_MAX+1
        jb IB_Done
        mov CntB, 0
IB_Done:
        mov dx, PIC_M_CMD
        call PIC_EOI
        pop ds
        pop dx
        pop ax
        iret
IsrTaskB ENDP

; 任务 C 从 15 开始每 1.5 秒减一，显示到 00 后在下一次中断重置为 15。
IsrTaskC PROC FAR
        push ax
        push dx
        push ds
        mov ax, @data
        mov ds, ax
        cmp CntC, 0
        jne IC_Dec
        mov CntC, CNT_C_INIT
        jmp IC_EOI
IC_Dec:
        dec CntC
IC_EOI:
        mov dx, PIC_S_CMD
        call PIC_EOI
        mov dx, PIC_M_CMD
        call PIC_EOI
        pop ds
        pop dx
        pop ax
        iret
IsrTaskC ENDP

; 任务 A 每 2 秒多点亮一盏灯，亮满 8 盏后在下一次中断全部熄灭。
IsrTaskA PROC FAR
        push ax
        push bx
        push dx
        push ds
        mov ax, @data
        mov ds, ax
        inc CntA
        cmp CntA, CNT_A_MAX+1
        jb IA_Load
        mov CntA, 0
IA_Load:
        mov bx, OFFSET LedMaskTbl
        mov al, CntA
        xlat                      ; 以亮灯数量查表，生成从 PB0 起连续点亮的灯码。
        mov LedState, al
        mov dx, PIC_S_CMD
        call PIC_EOI
        mov dx, PIC_M_CMD
        call PIC_EOI
        pop ds
        pop dx
        pop bx
        pop ax
        iret
IsrTaskA ENDP

END START
