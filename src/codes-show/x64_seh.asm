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
printf proto C :QWORD
puts proto C :QWORD
sprintf proto C :QWORD
strlen proto C :QWORD
malloc proto C :QWORD
free proto C :QWORD
exit proto C :DWORD
wsprintfA proto C :QWORD
GetStdHandle proto C :QWORD
WriteFile proto C :QWORD, :QWORD, :QWORD, :QWORD, :QWORD
ReadFile proto C :QWORD, :QWORD, :QWORD, :QWORD, :QWORD
ExitProcess proto C :QWORD
GetLastError proto C
Sleep proto C :QWORD
VirtualAlloc proto C :QWORD, :QWORD, :QWORD, :QWORD
VirtualFree proto C :QWORD, :QWORD, :QWORD
MessageBoxA proto C :QWORD, :QWORD, :QWORD, :QWORD
risky proto C :DWORD

.data
msg db "code=%d r=%d\n",0

.data?
fuck dd ?
__cone_itmp dd ?

.code
guard proc uses ebx esi edi, x:DWORD
    local r:DWORD
    mov r, 0
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
    inc r
    jmp __cone_seh_guard_1_normal
__cone_seh_guard_1_dispatch:
    mov eax, [esp+8]
    mov fuck, eax
    push edx
    mov edx, [esp+4]
    mov fs:[0], edx
    pop edx
    add esp, 12
    cmp eax, 0C0000005h
    je __cone_seh_guard_1_e0
    jmp __cone_seh_guard_1_end
__cone_seh_guard_1_e0:
    mov r, -4
    jmp __cone_seh_guard_1_end
__cone_seh_guard_1_handler:
    mov eax, [esp+4]
    mov ecx, [eax]
    cmp ecx, 0C0000005h
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
    jmp __cone_seh_guard_0_e1
__cone_seh_guard_0_e0:
    mov r, -1
    jmp __cone_seh_guard_0_end
__cone_seh_guard_0_e1:
    mov eax, -3
    add eax, fuck
    mov r, eax
    jmp __cone_seh_guard_0_end
__cone_seh_guard_0_handler:
    mov eax, [esp+4]
    mov ecx, [eax]
    cmp ecx, 0C0000094h
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

loopcase proc uses ebx esi edi
    local i:DWORD
    local r:DWORD
    mov i, 0
    mov r, 0
    .while (i < 3)
    push 0
    push offset __cone_seh_loopcase_2_handler
    push fs:[0]
    mov fs:[0], esp
    inc r
    .if (i == 1)
    .continue
    .endif
    add r, 10
    jmp __cone_seh_loopcase_2_normal
__cone_seh_loopcase_2_dispatch:
    mov eax, [esp+8]
    mov fuck, eax
    push edx
    mov edx, [esp+4]
    mov fs:[0], edx
    pop edx
    add esp, 12
    jmp __cone_seh_loopcase_2_e0
__cone_seh_loopcase_2_e0:
    add r, 100
    .break
    jmp __cone_seh_loopcase_2_end
__cone_seh_loopcase_2_handler:
    mov eax, [esp+4]
    mov ecx, [eax]
    jmp __cone_seh_loopcase_2_match
__cone_seh_loopcase_2_match:
    mov edx, [esp+8]
    mov [edx+8], ecx
    mov eax, [esp+12]
    mov dword ptr [eax+184], offset __cone_seh_loopcase_2_dispatch
    mov dword ptr [eax+196], edx
    xor eax, eax
    jmp __cone_seh_ret_stub
__cone_seh_loopcase_2_normal:
    push edx
    mov edx, [esp+4]
    mov fs:[0], edx
    pop edx
    add esp, 12
    jmp __cone_seh_loopcase_2_end
__cone_seh_loopcase_2_end:
    inc i
    .endw
    mov eax, r
    ret
loopcase endp

retcase proc uses ebx esi edi
    push 0
    push offset __cone_seh_retcase_3_handler
    push fs:[0]
    mov fs:[0], esp
    mov eax, 7
    jmp __cone_seh_retcase_3_ret
__cone_seh_retcase_3_dispatch:
    mov eax, [esp+8]
    mov fuck, eax
    push edx
    mov edx, [esp+4]
    mov fs:[0], edx
    pop edx
    add esp, 12
    jmp __cone_seh_retcase_3_e0
__cone_seh_retcase_3_e0:
    mov eax, 9
    jmp __cone_seh_retcase_3_ret
__cone_seh_retcase_3_handler:
    mov eax, [esp+4]
    mov ecx, [eax]
    jmp __cone_seh_retcase_3_match
__cone_seh_retcase_3_match:
    mov edx, [esp+8]
    mov [edx+8], ecx
    mov eax, [esp+12]
    mov dword ptr [eax+184], offset __cone_seh_retcase_3_dispatch
    mov dword ptr [eax+196], edx
    xor eax, eax
    jmp __cone_seh_ret_stub
__cone_seh_retcase_3_normal:
    push edx
    mov edx, [esp+4]
    mov fs:[0], edx
    pop edx
    add esp, 12
    jmp __cone_seh_retcase_3_end
__cone_seh_retcase_3_ret:
    push edx
    mov edx, [esp+4]
    mov fs:[0], edx
    pop edx
    add esp, 12
    ret
__cone_seh_retcase_3_end:
retcase endp

main proc uses ebx esi edi
    local a:DWORD
    local b:DWORD
    local cc:DWORD
    invoke guard, 1
    mov a, eax
    invoke loopcase
    mov b, eax
    invoke retcase
    mov cc, eax
    mov eax, b
    add eax, cc
    push eax
    push a
    mov eax, offset msg
    xor edx, edx
    push edx
    push eax
    call printf
    add esp, 16
    invoke ExitProcess, 0
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
