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
i dd ?
n dd ?
acc dd ?
__cone_itmp dd ?

.code
start proc uses ebx esi edi
    mov i, 12
    mov n, 2
    mov acc, 0
    mov eax, i
    imul eax, i
    cmp eax, 123
    jae __cone_if_start_0_c0
    mov acc, 1
    jmp __cone_if_start_0_end
__cone_if_start_0_c0:
    mov eax, i
    imul eax, i
    add eax, acc
    cmp eax, 200
    jb __cone_if_start_0_c1
    mov acc, 2
    jmp __cone_if_start_0_end
__cone_if_start_0_c1:
    mov acc, 3
__cone_if_start_0_end:
__cone_for_start_0_cond:
    mov eax, i
    mov ebx, n
    xor edx, edx
    div ebx
    cmp eax, 3
    jbe __cone_for_start_0_end
    dec i
    jmp __cone_for_start_0_cond
__cone_for_start_0_end:
    mov eax, i
    and eax, 3
    cmp eax, 2
    jne __cone_if_start_1_c0
    inc acc
__cone_if_start_1_c0:
__cone_if_start_1_end:
    mov eax, i
    shl eax, 1
    cmp eax, 8
    jbe __cone_if_start_2_c0
    inc acc
__cone_if_start_2_c0:
__cone_if_start_2_end:
    mov eax, i
    neg eax
    cmp eax, 0
    jae __cone_if_start_3_c0
    inc acc
__cone_if_start_3_c0:
__cone_if_start_3_end:
    .if (i == 6)
    add acc, 10
    .endif
    .if ((acc > 20) && (i != 0))
    add acc, 100
    .endif
    invoke ExitProcess, acc
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
