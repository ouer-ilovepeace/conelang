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
helper proto stdcall x:DWORD

.data?
fuck dd ?
__cone_itmp dd ?

.code
calc proc stdcall uses ebx esi edi, x:DWORD
    local a:DWORD, b:DWORD, z:DWORD
    local small:BYTE
    local mid:WORD
    local r:DWORD
    local buf[4]:BYTE
    mov eax, x
    add eax, 1
    mov a, eax
    mov b, 80
    mov z, 0
    mov small, 7
    mov mid, 41
    invoke helper, a
    add eax, b
    mov r, eax
    mov eax, a
    add eax, b
    add eax, z
    movzx ebx, small
    add eax, ebx
    movzx ebx, mid
    add eax, ebx
    add eax, r
    ret
calc endp

start proc uses ebx esi edi
    local p:DWORD, q:DWORD
    local r:DWORD
    local s:DWORD, t:DWORD
    mov p, 1
    mov q, 2
    mov eax, p
    imul eax, q
    add eax, 10
    mov r, eax
    mov eax, r
    mov s, eax
    mov t, 40
    invoke calc, r
    add eax, s
    add eax, t
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
