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
Pt struct
    x DWORD ?
Pt ends

probe proto stdcall :DWORD

.data?
fuck dd ?
mode dd ?
table dd ?
hit dd ?
arr db 8 dup(?)
pt Pt <>
__cone_itmp dd ?

.code
start proc uses ebx esi edi
    mov eax, mode
    mov edi, eax
    cmp edi, 0
    je __cone_match_start_0_c0
    cmp edi, table
    je __cone_match_start_0_c1
    cmp edi, dword ptr [arr]
    je __cone_match_start_0_c2
    cmp edi, pt.x
    je __cone_match_start_0_c3
    cmp edi, 8
    je __cone_match_start_0_c4
    cmp edi, 5
    je __cone_match_start_0_c5
    push edi
    invoke probe, 1
    pop edi
    cmp edi, eax
    je __cone_match_start_0_c6
    push edi
    mov eax, mode
    cmp eax, 7
    sete al
    movzx eax, al
    pop edi
    cmp edi, eax
    je __cone_match_start_0_c7
    push edi
    mov eax, table
    add eax, 1
    pop edi
    cmp edi, eax
    je __cone_match_start_0_c8
    jmp __cone_match_start_0_default
__cone_match_start_0_c0:
    mov hit, 1
    jmp __cone_match_start_0_end
__cone_match_start_0_c1:
    mov hit, 2
    jmp __cone_match_start_0_end
__cone_match_start_0_c2:
    mov hit, 3
    jmp __cone_match_start_0_end
__cone_match_start_0_c3:
    mov hit, 4
    jmp __cone_match_start_0_end
__cone_match_start_0_c4:
    mov hit, 5
    jmp __cone_match_start_0_end
__cone_match_start_0_c5:
    mov hit, 6
    jmp __cone_match_start_0_end
__cone_match_start_0_c6:
    mov hit, 7
    jmp __cone_match_start_0_end
__cone_match_start_0_c7:
    mov hit, 8
    jmp __cone_match_start_0_end
__cone_match_start_0_c8:
    mov hit, 9
    jmp __cone_match_start_0_end
__cone_match_start_0_default:
    mov hit, 0
__cone_match_start_0_end:
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
