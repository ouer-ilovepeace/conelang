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

.data
m dd 2

.data?
fuck dd ?
r dd ?
__cone_itmp dd ?

.code
main proc uses ebx esi edi
    mov eax, m
    cmp eax, 1
    je __cone_match_main_0_c0
    cmp eax, 2
    je __cone_match_main_0_c1
    jmp __cone_match_main_0_default
__cone_match_main_0_c0:
    mov r, 11
    jmp __cone_match_main_0_end
__cone_match_main_0_c1:
    mov r, 22
    jmp __cone_match_main_0_end
__cone_match_main_0_default:
    mov r, 0
__cone_match_main_0_end:
    invoke ExitProcess, r
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
