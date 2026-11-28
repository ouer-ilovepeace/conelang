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

.const
__cone_str_0 db "one",0ah,0
__cone_str_1 db "two",0ah,0
__cone_str_2 db "other",0ah,0
__cone_str_3 db "Hello World",0dh,0ah,0
__cone_str_4 db "tab:",09h," end",0ah,0
__cone_str_5 db "zero",0ah,0
__cone_str_6 db "positive",0ah,0
__cone_str_7 db "negative",0ah,0
__cone_str_8 db "range",0ah,0
__cone_str_9 db "cond",0ah,0
__cone_str_10 db "nonzero",0ah,0

.data
hello db "Hello World",0dh,0ah,0
caption db "cone 0.3",0

.data?
fuck dd ?
r dd ?
__cone_itmp dd ?

.code
choose proc stdcall uses ebx esi edi, x:DWORD
    .if (x == 1)
    invoke crt_printf, offset __cone_str_0
    .elseif (x == 2)
    invoke crt_printf, offset __cone_str_1
    .else
    invoke crt_printf, offset __cone_str_2
    .endif
    mov eax, x
    ret
choose endp

start proc uses ebx esi edi
    invoke MessageBoxA, 0, offset caption, offset hello, MB_OK
    mov eax, lpxxx
    mov r, eax
    mov eax, MB_OK
    invoke crt_printf, offset hello
    invoke crt_printf, offset __cone_str_3
    invoke crt_printf, offset __cone_str_3
    invoke crt_printf, offset __cone_str_4
    .if (r == 0)
    invoke crt_printf, offset __cone_str_5
    .elseif (r > 0)
    invoke crt_printf, offset __cone_str_6
    .else
    invoke crt_printf, offset __cone_str_7
    .endif
    .if ((r >= 0) && (r < 100))
    invoke crt_printf, offset __cone_str_8
    .endif
    invoke crt_printf, offset __cone_str_9
    test eax, eax
    jz __cone_if_start_2_c0
    invoke crt_printf, offset __cone_str_10
__cone_if_start_2_c0:
__cone_if_start_2_end:
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
