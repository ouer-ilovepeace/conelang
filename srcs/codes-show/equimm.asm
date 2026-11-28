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
LIST equ 1,2,3
RAW equ <crt_printf>
ALIAS equ crt_printf
print equ <crt_printf>

.data?
fuck dd ?
buf db 32 dup(?)
loc db 36 dup(?)
__cone_itmp dd ?

.code
start proc uses ebx esi edi
    local x:DWORD
    local y:DWORD
    mov x, 8
    mov y, 3221225477
        mov eax,32
        mov ebx,7
        mov ecx,0C0000005h
    mov eax, x
    cmp eax, 16
    je __cone_match_start_0_c0
    cmp eax, 8
    je __cone_match_start_0_c1
    jmp __cone_match_start_0_default
__cone_match_start_0_c0:
    jmp __cone_match_start_0_end
__cone_match_start_0_c1:
    jmp __cone_match_start_0_end
__cone_match_start_0_default:
__cone_match_start_0_end:
    push 0
    push offset __cone_seh_start_0_handler
    push fs:[0]
    mov fs:[0], esp
    mov x, 1
    jmp __cone_seh_start_0_normal
__cone_seh_start_0_dispatch:
    mov eax, [esp+8]
    mov fuck, eax
    push edx
    mov edx, [esp+4]
    mov fs:[0], edx
    pop edx
    add esp, 12
    cmp eax, 0C0000005h
    je __cone_seh_start_0_e0
    jmp __cone_seh_start_0_e1
__cone_seh_start_0_e0:
    mov x, 2
    jmp __cone_seh_start_0_end
__cone_seh_start_0_e1:
    mov x, 3
    jmp __cone_seh_start_0_end
__cone_seh_start_0_handler:
    mov eax, [esp+4]
    mov ecx, [eax]
    cmp ecx, 0C0000005h
    je __cone_seh_start_0_match
    jmp __cone_seh_start_0_match
__cone_seh_start_0_match:
    mov edx, [esp+8]
    mov [edx+8], ecx
    mov eax, [esp+12]
    mov dword ptr [eax+184], offset __cone_seh_start_0_dispatch
    mov dword ptr [eax+196], edx
    xor eax, eax
    jmp __cone_seh_ret_stub
__cone_seh_start_0_normal:
    push edx
    mov edx, [esp+4]
    mov fs:[0], edx
    pop edx
    add esp, 12
    jmp __cone_seh_start_0_end
__cone_seh_start_0_end:
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
