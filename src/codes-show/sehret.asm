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
touch proto stdcall :DWORD

.data?
fuck dd ?
__cone_itmp dd ?

.code
pick proc stdcall uses ebx esi edi, x:DWORD
    push 0
    push offset __cone_seh_pick_0_handler
    push fs:[0]
    mov fs:[0], esp
    invoke touch, x
    jmp __cone_seh_pick_0_ret
__cone_seh_pick_0_dispatch:
    mov eax, [esp+8]
    mov fuck, eax
    push edx
    mov edx, [esp+4]
    mov fs:[0], edx
    pop edx
    add esp, 12
    cmp eax, 0C0000094h
    je __cone_seh_pick_0_e0
    jmp __cone_seh_pick_0_e1
__cone_seh_pick_0_e0:
    mov eax, -1
    jmp __cone_seh_pick_0_ret
__cone_seh_pick_0_e1:
    mov eax, -2
    jmp __cone_seh_pick_0_ret
__cone_seh_pick_0_handler:
    mov eax, [esp+4]
    mov ecx, [eax]
    cmp ecx, 0C0000094h
    je __cone_seh_pick_0_match
    jmp __cone_seh_pick_0_match
__cone_seh_pick_0_match:
    mov edx, [esp+8]
    mov [edx+8], ecx
    mov eax, [esp+12]
    mov dword ptr [eax+184], offset __cone_seh_pick_0_dispatch
    mov dword ptr [eax+196], edx
    xor eax, eax
    jmp __cone_seh_ret_stub
__cone_seh_pick_0_normal:
    push edx
    mov edx, [esp+4]
    mov fs:[0], edx
    pop edx
    add esp, 12
    jmp __cone_seh_pick_0_end
__cone_seh_pick_0_ret:
    push edx
    mov edx, [esp+4]
    mov fs:[0], edx
    pop edx
    add esp, 12
    ret
__cone_seh_pick_0_end:
    mov eax, 0
    ret
pick endp

start proc uses ebx esi edi
    local r:DWORD
    invoke pick, 3
    mov r, eax
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
