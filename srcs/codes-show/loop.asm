; cone 0.9.p - generated MASM32 assembly
.586
.model flat, stdcall
option casemap :none
option scoped
assume fs:nothing

include /data/workspace/masm32/include/windows.inc
include /data/workspace/masm32/include/kernel32.inc
includelib /data/workspace/masm32/lib/kernel32.lib
include /data/workspace/masm32/include/user32.inc
includelib /data/workspace/masm32/lib/user32.lib
include /data/workspace/masm32/include/msvcrt.inc
includelib /data/workspace/masm32/lib/msvcrt.lib
msgbox proto stdcall :DWORD, :DWORD

.const
__cone_str_0 db "logic",0ah,0
__cone_str_1 db "eax is ",0ah,"IDRETRY!",0
__cone_str_2 db "gt9",0ah,0
__cone_str_3 db "unsigned gt9",0ah,0
__cone_str_4 db "signed gt9",0ah,0
__cone_str_5 db "mem-mem",0ah,0
__cone_str_6 db "loop",0ah,0
__cone_str_7 db "again",0
__cone_str_8 db "degraded body",0ah,0

.data?
fuck dd ?
i dd ?
total dd ?
limit dd ?
__cone_itmp dd ?

.code
start proc uses ebx esi edi
    .if ((!(i) && (i >= 0)) || (limit > 100))
    invoke crt_printf, offset __cone_str_0
    .endif
    invoke msgbox, offset __cone_str_1, 0
    cmp eax, 9
    jbe __cone_if_start_1_c0
    invoke crt_printf, offset __cone_str_2
__cone_if_start_1_c0:
__cone_if_start_1_end:
    .if (i > 9)
    invoke crt_printf, offset __cone_str_3
    .endif
    mov eax, i
    cmp eax, 9
    jle __cone_if_start_3_c0
    invoke crt_printf, offset __cone_str_4
__cone_if_start_3_c0:
__cone_if_start_3_end:
    mov ebx, i
    mov esi, limit
    .if ((ebx > esi) || (ebx == esi))
    invoke crt_printf, offset __cone_str_5
    .endif
    mov i, 0
    .while (i < 10)
    inc i
    .if (i == 3)
    .continue
    .endif
    .if (i == 8)
    .break
    .endif
    invoke crt_printf, offset __cone_str_6
    .endw
    .while 1
    dec i
    .if (i == 0)
    .break
    .endif
    .endw
__cone_for_start_2_cond:
    invoke msgbox, offset __cone_str_7, 0
    cmp eax, 0
    jbe __cone_for_start_2_end
    invoke crt_printf, offset __cone_str_8
    jmp __cone_for_start_2_end
__cone_for_start_2_end:
__cone_for_start_3_cond:
    mov eax, i
    cmp eax, limit
    jb __cone_for_start_3_end
    dec i
    jmp __cone_for_start_3_cond
__cone_for_start_3_end:
__cone_for_start_4_cond:
    mov eax, i
    cmp eax, limit
    jl __cone_for_start_4_end
    dec i
    jmp __cone_for_start_4_end
__cone_for_start_4_end:
__cone_for_start_5_cond:
    mov eax, i
    cmp eax, limit
    jae __cone_for_start_5_end
    inc i
    jmp __cone_for_start_5_end
__cone_for_start_5_end:
    invoke ExitProcess, 0
start endp

__cone_default_seh_handler:
    mov eax, [esp+4]
    mov ecx, [eax]
    mov edx, [esp+8]
    mov [edx+8], ecx
    mov eax, [esp+12]
    mov dword ptr [eax+184], offset __cone_default_seh_dispatch
    mov dword ptr [eax+196], edx
    xor eax, eax
    jmp __cone_seh_ret_stub
__cone_default_seh_dispatch:
    mov eax, [esp+8]
    mov fuck, eax
    push edx
    mov edx, [esp+4]
    mov fs:[0], edx
    pop edx
    add esp, 12
    invoke ExitProcess, fuck

__cone_default_entry:
    push 0
    push offset __cone_default_seh_handler
    push fs:[0]
    mov fs:[0], esp
    call start
    push edx
    mov edx, [esp+4]
    mov fs:[0], edx
    pop edx
    add esp, 12
    ret

__cone_seh_ret_stub:
    ret

end __cone_default_entry
