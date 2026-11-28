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
abs proto C :DWORD
strlen proto C :QWORD

.data
msg db "hello",0

.data?
fuck dd ?
__cone_itmp dd ?

.code
big proc uses ebx esi edi
    local v:QWORD
    mov v, 123456
    mov eax, dword ptr [v]
    mov edx, dword ptr [v+4]
    ret
big endp

main proc uses ebx esi edi
    local n:QWORD
    local m:QWORD
    local d:DWORD
    invoke big
    mov dword ptr n, eax
    mov dword ptr n+4, edx
    mov eax, offset msg
    xor edx, edx
    push edx
    push eax
    call strlen
    add esp, 8
    mov dword ptr m, eax
    mov dword ptr m+4, edx
    invoke abs, -9
    mov d, eax
    invoke ExitProcess, d
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
