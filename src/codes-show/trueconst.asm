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

.data?
fuck dd ?
__cone_itmp dd ?

.code
start proc uses ebx esi edi
    local a:DWORD
    local b:DWORD
    local z:DWORD
    local d:DWORD
    local TRUEVAR:DWORD
    mov a, 1
    mov b, 0
    mov z, 0
    mov d, 4
    mov TRUEVAR, 1
    .if (a == 1)
    mov eax, b
    add eax, d
    mov b, eax
    .endif
    .if (z == 0)
    mov eax, TRUEVAR
    add eax, d
    mov TRUEVAR, eax
    .endif
    mov eax, a
    add eax, b
    add eax, z
    add eax, d
    add eax, TRUEVAR
    invoke ExitProcess, eax
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
