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
risky proto stdcall :DWORD

.data
msg db "in guarded block",0dh,0ah,0

.data?
fuck dd ?
slot dd ?
__cone_itmp dd ?

.code
guard proc stdcall uses ebx esi edi, x:DWORD
    local r:DWORD
    push 0
    push offset __cone_seh_guard_0_handler
    push fs:[0]
    mov fs:[0], esp
    invoke risky, x
    mov r, eax
    push 0
    push offset __cone_seh_guard_1_handler
    push fs:[0]
    mov fs:[0], esp
    invoke risky, r
    jmp __cone_seh_guard_1_normal
__cone_seh_guard_1_dispatch:
    mov eax, [esp+8]
    mov fuck, eax
    push edx
    mov edx, [esp+4]
    mov fs:[0], edx
    pop edx
    add esp, 12
    cmp eax, 0C00000FDh
    je __cone_seh_guard_1_e0
    jmp __cone_seh_guard_1_end
__cone_seh_guard_1_e0:
    mov r, -4
    jmp __cone_seh_guard_1_end
__cone_seh_guard_1_handler:
    mov eax, [esp+4]
    mov ecx, [eax]
    cmp ecx, 0C00000FDh
    je __cone_seh_guard_1_match
    mov eax, 1
    jmp __cone_seh_ret_stub
__cone_seh_guard_1_match:
    mov edx, [esp+8]
    mov [edx+8], ecx
    mov eax, [esp+12]
    mov dword ptr [eax+184], offset __cone_seh_guard_1_dispatch
    mov dword ptr [eax+196], edx
    xor eax, eax
    jmp __cone_seh_ret_stub
__cone_seh_guard_1_normal:
    push edx
    mov edx, [esp+4]
    mov fs:[0], edx
    pop edx
    add esp, 12
    jmp __cone_seh_guard_1_end
__cone_seh_guard_1_end:
    jmp __cone_seh_guard_0_normal
__cone_seh_guard_0_dispatch:
    mov eax, [esp+8]
    mov fuck, eax
    push edx
    mov edx, [esp+4]
    mov fs:[0], edx
    pop edx
    add esp, 12
    cmp eax, 0C0000094h
    je __cone_seh_guard_0_e0
    cmp eax, 0C0000005h
    je __cone_seh_guard_0_e1
    jmp __cone_seh_guard_0_e2
__cone_seh_guard_0_e0:
    mov r, -1
    jmp __cone_seh_guard_0_end
__cone_seh_guard_0_e1:
    mov r, -2
    jmp __cone_seh_guard_0_end
__cone_seh_guard_0_e2:
    mov r, -3
    jmp __cone_seh_guard_0_end
__cone_seh_guard_0_handler:
    mov eax, [esp+4]
    mov ecx, [eax]
    cmp ecx, 0C0000094h
    je __cone_seh_guard_0_match
    cmp ecx, 0C0000005h
    je __cone_seh_guard_0_match
    jmp __cone_seh_guard_0_match
__cone_seh_guard_0_match:
    mov edx, [esp+8]
    mov [edx+8], ecx
    mov eax, [esp+12]
    mov dword ptr [eax+184], offset __cone_seh_guard_0_dispatch
    mov dword ptr [eax+196], edx
    xor eax, eax
    jmp __cone_seh_ret_stub
__cone_seh_guard_0_normal:
    push edx
    mov edx, [esp+4]
    mov fs:[0], edx
    pop edx
    add esp, 12
    jmp __cone_seh_guard_0_end
__cone_seh_guard_0_end:
    mov eax, r
    ret
guard endp

start proc uses ebx esi edi
    invoke guard, 7
    mov slot, eax
    invoke crt_printf, offset msg
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
