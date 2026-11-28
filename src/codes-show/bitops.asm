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
Bits struct
    a DWORD ?
    b DWORD ?
Bits ends

take proto stdcall :DWORD, :DWORD, :DWORD

.data
bits Bits <3,8>

.data?
fuck dd ?
flg dd ?
g dd ?
buf db 16 dup(?)
__cone_itmp dd ?

.code
start proc uses ebx esi edi
    mov eax, (GENERIC_READ or GENERIC_WRITE)
    mov flg, eax
    invoke take, (GENERIC_READ or GENERIC_WRITE), 3221225472, 3
    mov g, 7
    mov g, 15
    mov g, 256
    mov g, -1
    mov eax, flg
    or eax, g
    mov flg, eax
    and flg, 15
    xor flg, 255
    shl flg, 2
    push ecx
    mov eax, flg
    push eax
    mov ecx, g
    pop eax
    shr eax, cl
    pop ecx
    mov flg, eax
    mov eax, flg
    not eax
    mov g, eax
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
