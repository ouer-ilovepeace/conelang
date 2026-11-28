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
putq proto stdcall :QWORD, :DWORD
putqc proto C :QWORD
putd proto stdcall :DWORD
cq proto C :QWORD, :DWORD

.data?
fuck dd ?
big dq ?
ratio REAL8 ?
n dd ?
buf db 32 dup(?)
__cone_itmp dd ?

.code
start proc uses ebx esi edi
    local localq:QWORD
    mov n, 7
    mov eax, dword ptr big
    mov dword ptr localq, eax
    mov dword ptr localq+4, 0
    push n
    mov eax, dword ptr [big]
    mov edx, dword ptr [big+4]
    push edx
    push eax
    call putq
    mov eax, dword ptr [big]
    mov edx, dword ptr [big+4]
    push edx
    push eax
    call putqc
    add esp, 8
    mov eax, 12345678
    xor edx, edx
    push edx
    push eax
    call putqc
    add esp, 8
    push dword ptr [big]
    call putd
    push n
    mov eax, dword ptr [big]
    mov edx, dword ptr [big+4]
    push edx
    push eax
    call cq
    add esp, 12
    push n
    fld ratio
    sub esp, 8
    fstp qword ptr [esp]
    call putq
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
