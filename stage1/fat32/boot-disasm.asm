00000000  E94C01            jmp 0x14f
00000003  0000              add [bx+si],al
00000005  0000              add [bx+si],al
00000007  0000              add [bx+si],al
00000009  0000              add [bx+si],al
0000000B  0000              add [bx+si],al
0000000D  0000              add [bx+si],al
0000000F  0000              add [bx+si],al
00000011  0000              add [bx+si],al
00000013  0000              add [bx+si],al
00000015  0000              add [bx+si],al
00000017  0000              add [bx+si],al
00000019  0000              add [bx+si],al
0000001B  0000              add [bx+si],al
0000001D  0000              add [bx+si],al
0000001F  0000              add [bx+si],al
00000021  0000              add [bx+si],al
00000023  0000              add [bx+si],al
00000025  0000              add [bx+si],al
00000027  0000              add [bx+si],al
00000029  0000              add [bx+si],al
0000002B  0000              add [bx+si],al
0000002D  0000              add [bx+si],al
0000002F  0000              add [bx+si],al
00000031  0000              add [bx+si],al
00000033  0000              add [bx+si],al
00000035  0000              add [bx+si],al
00000037  0000              add [bx+si],al
00000039  0000              add [bx+si],al
0000003B  0000              add [bx+si],al
0000003D  0000              add [bx+si],al
0000003F  0000              add [bx+si],al
00000041  0000              add [bx+si],al
00000043  0000              add [bx+si],al
00000045  0000              add [bx+si],al
00000047  0000              add [bx+si],al
00000049  0000              add [bx+si],al
0000004B  0000              add [bx+si],al
0000004D  0000              add [bx+si],al
0000004F  0000              add [bx+si],al
00000051  0000              add [bx+si],al
00000053  0000              add [bx+si],al
00000055  0000              add [bx+si],al
00000057  0000              add [bx+si],al
00000059  0000              add [bx+si],al
0000005B  0000              add [bx+si],al
0000005D  0000              add [bx+si],al
0000005F  42                inc dx
00000060  4F                dec di
00000061  4F                dec di
00000062  54                push sp
00000063  2020              and [bx+si],ah
00000065  2020              and [bx+si],ah
00000067  53                push bx
00000068  59                pop cx
00000069  53                push bx
0000006A  46                inc si
0000006B  61                popa
0000006C  7461              jz 0xcf
0000006E  6C                insb
0000006F  206572            and [di+0x72],ah
00000072  726F              jc 0xe3
00000074  722E              jc 0xa4
00000076  00600F            add [bx+si+0xf],ah
00000079  B60E              mov dh,0xe
0000007B  0D7C89            or ax,0x897c
0000007E  0E                push cs
0000007F  B47D              mov ah,0x7d
00000081  66891EB67D        mov [0x7db6],ebx
00000086  66A3BA7D          mov [0x7dba],eax
0000008A  B442              mov ah,0x42
0000008C  8A165E7C          mov dl,[0x7c5e]
00000090  31DB              xor bx,bx
00000092  8EDB              mov ds,bx
00000094  BEB27D            mov si,0x7db2
00000097  CD13              int 0x13
00000099  61                popa
0000009A  50                push ax
0000009B  51                push cx
0000009C  A10B7C            mov ax,[0x7c0b]
0000009F  0FB60E0D7C        movzx cx,[0x7c0d]
000000A4  F7E1              mul cx
000000A6  01C3              add bx,ax
000000A8  5B                pop bx
000000A9  58                pop ax
000000AA  C3                ret
000000AB  83E802            sub ax,byte +0x2
000000AE  F6260D7C          mul byte [0x7c0d]
000000B2  03065A7C          add ax,[0x7c5a]
000000B6  C3                ret
000000B7  0FB606107C        movzx ax,[0x7c10]
000000BC  F726247C          mul word [0x7c24]
000000C0  03060E7C          add ax,[0x7c0e]
000000C4  A35A7C            mov [0x7c5a],ax
000000C7  6631C0            xor eax,eax
000000CA  A15C7C            mov ax,[0x7c5c]
000000CD  C1E002            shl ax,byte 0x2
000000D0  F7360B7C          div word [0x7c0b]
000000D4  03060E7C          add ax,[0x7c0e]
000000D8  66BB00460000      mov ebx,0x4600
000000DE  E896FF            call 0x77
000000E1  66A12C7C          mov eax,[0x7c2c]
000000E5  E8C3FF            call 0xab
000000E8  66BB00100000      mov ebx,0x1000
000000EE  E886FF            call 0x77
000000F1  C3                ret
000000F2  60                pusha
000000F3  B91000            mov cx,0x10
000000F6  BF0010            mov di,0x1000
000000F9  89F2              mov dx,si
000000FB  51                push cx
000000FC  B90B00            mov cx,0xb
000000FF  89D6              mov si,dx
00000101  57                push di
00000102  F3A6              repe cmpsb
00000104  5F                pop di
00000105  59                pop cx
00000106  7408              jz 0x110
00000108  83C720            add di,byte +0x20
0000010B  E2EE              loop 0xfb
0000010D  61                popa
0000010E  F9                stc
0000010F  C3                ret
00000110  31D2              xor dx,dx
00000112  8B551A            mov dx,[di+0x1a]
00000115  89165C7C          mov [0x7c5c],dx
00000119  61                popa
0000011A  C3                ret
0000011B  53                push bx
0000011C  A15C7C            mov ax,[0x7c5c]
0000011F  5B                pop bx
00000120  E888FF            call 0xab
00000123  E851FF            call 0x77
00000126  53                push bx
00000127  8B1E5C7C          mov bx,[0x7c5c]
0000012B  6BDB04            imul bx,bx,byte +0x4
0000012E  06                push es
0000012F  BA0046            mov dx,0x4600
00000132  8EC2              mov es,dx
00000134  268B17            mov dx,[es:bx]
00000137  07                pop es
00000138  89165C7C          mov [0x7c5c],dx
0000013C  83FAF8            cmp dx,byte -0x8
0000013F  72DB              jc 0x11c
00000141  5B                pop bx
00000142  C3                ret
00000143  AC                lodsb
00000144  3C00              cmp al,0x0
00000146  7406              jz 0x14e
00000148  B40E              mov ah,0xe
0000014A  CD10              int 0x10
0000014C  EBF5              jmp short 0x143
0000014E  C3                ret
0000014F  FA                cli
00000150  31C0              xor ax,ax
00000152  8ED8              mov ds,ax
00000154  8EC0              mov es,ax
00000156  8ED0              mov ss,ax
00000158  BCFF09            mov sp,0x9ff
0000015B  FB                sti
0000015C  88165E7C          mov [0x7c5e],dl
00000160  E854FF            call 0xb7
00000163  BE5F7C            mov si,0x7c5f
00000166  E889FF            call 0xf2
00000169  723F              jc 0x1aa
0000016B  68E007            push word 0x7e0
0000016E  0FA1              pop fs
00000170  BF0000            mov di,0x0
00000173  BDB900            mov bp,0xb9
00000176  E8A2FF            call 0x11b
00000179  722F              jc 0x1aa
0000017B  83FDFF            cmp bp,byte -0x1
0000017E  752A              jnz 0x1aa
00000180  64813E00005949    cmp word [fs:0x0],0x4959
00000187  7521              jnz 0x1aa
00000189  64813E02004646    cmp word [fs:0x2],0x4646
00000190  7518              jnz 0x1aa
00000192  FA                cli
00000193  F4                hlt
00000194  1E                push ds
00000195  0FA1              pop fs
00000197  681B7D            push word 0x7d1b
0000019A  68F27C            push word 0x7cf2
0000019D  FF360B7C          push word [0x7c0b]
000001A1  FF365E7C          push word [0x7c5e]
000001A5  EA047E0000        jmp 0x0:0x7e04
000001AA  BE6A7C            mov si,0x7c6a
000001AD  E893FF            call 0x143
000001B0  FA                cli
000001B1  F4                hlt
000001B2  1000              adc [bx+si],al
000001B4  0000              add [bx+si],al
000001B6  0000              add [bx+si],al
000001B8  0000              add [bx+si],al
000001BA  0000              add [bx+si],al
000001BC  0000              add [bx+si],al
000001BE  0000              add [bx+si],al
000001C0  0000              add [bx+si],al
000001C2  0000              add [bx+si],al
000001C4  0000              add [bx+si],al
000001C6  0000              add [bx+si],al
000001C8  0000              add [bx+si],al
000001CA  0000              add [bx+si],al
000001CC  0000              add [bx+si],al
000001CE  0000              add [bx+si],al
000001D0  0000              add [bx+si],al
000001D2  0000              add [bx+si],al
000001D4  0000              add [bx+si],al
000001D6  0000              add [bx+si],al
000001D8  0000              add [bx+si],al
000001DA  0000              add [bx+si],al
000001DC  0000              add [bx+si],al
000001DE  0000              add [bx+si],al
000001E0  0000              add [bx+si],al
000001E2  0000              add [bx+si],al
000001E4  0000              add [bx+si],al
000001E6  0000              add [bx+si],al
000001E8  0000              add [bx+si],al
000001EA  0000              add [bx+si],al
000001EC  0000              add [bx+si],al
000001EE  0000              add [bx+si],al
000001F0  0000              add [bx+si],al
000001F2  0000              add [bx+si],al
000001F4  0000              add [bx+si],al
000001F6  0000              add [bx+si],al
000001F8  0000              add [bx+si],al
000001FA  0000              add [bx+si],al
000001FC  0000              add [bx+si],al
000001FE  55                push bp
000001FF  AA                stosb
