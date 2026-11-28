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
IO_MODE equ (GENERIC_READ or GENERIC_WRITE)
take proto stdcall :DWORD, :DWORD

.const
__cone_str_0 db "hello win{...}",0ah,0
__cone_str_1 db "g=%d",0ah,0
__cone_str_2 db "still win.xxx",0ah,0

.data?
fuck dd ?
g dd ?
r dd ?
__cone_itmp dd ?

.code
show proc uses ebx esi edi, a:DWORD
    mov eax, MB_OK
    mov g, eax
    invoke crt_printf, offset __cone_str_0
    mov r, eax
    mov eax, r
    ret
show endp

main proc uses ebx esi edi
    invoke take, MB_ICONSTOP, IO_MODE
    invoke crt_printf, offset __cone_str_1, g
    invoke show, 1
    mov g, eax
    invoke crt_printf, offset __cone_str_2
    mov r, eax
    invoke LATER_CALL, 0
    invoke ExitProcess, 0
main endp

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
    call main
    push edx
    mov edx, [esp+4]
    mov fs:[0], edx
    pop edx
    add esp, 12
    ret

__cone_seh_ret_stub:
    ret

end __cone_default_entry
