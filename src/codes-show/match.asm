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
ONE equ <1>
TWO equ <2>

.data?
fuck dd ?
g dd ?
slot dd ?
__cone_itmp dd ?

.code
test_default proc stdcall uses ebx esi edi, x:DWORD
    mov eax, x
    cmp eax, 0
    je __cone_match_test_default_0_c0
    cmp eax, ONE
    je __cone_match_test_default_0_c1
    cmp eax, TWO
    je __cone_match_test_default_0_c2
    cmp eax, 3
    je __cone_match_test_default_0_c3
    cmp eax, -1
    je __cone_match_test_default_0_c4
    cmp eax, 13
    je __cone_match_test_default_0_c5
    jmp __cone_match_test_default_0_default
__cone_match_test_default_0_c0:
    mov slot, 100
    jmp __cone_match_test_default_0_end
__cone_match_test_default_0_c1:
    mov slot, 101
    jmp __cone_match_test_default_0_end
__cone_match_test_default_0_c2:
    mov slot, 102
    jmp __cone_match_test_default_0_end
__cone_match_test_default_0_c3:
    mov slot, 103
    jmp __cone_match_test_default_0_end
__cone_match_test_default_0_c4:
    mov slot, 104
    jmp __cone_match_test_default_0_end
__cone_match_test_default_0_c5:
    mov slot, 105
    jmp __cone_match_test_default_0_end
__cone_match_test_default_0_default:
    mov slot, 999
__cone_match_test_default_0_end:
    mov eax, slot
    ret
test_default endp

test_no_default proc stdcall uses ebx esi edi, x:DWORD
    mov eax, x
    cmp eax, 7
    je __cone_match_test_no_default_0_c0
    cmp eax, 8
    je __cone_match_test_no_default_0_c1
    jmp __cone_match_test_no_default_0_end
__cone_match_test_no_default_0_c0:
    mov eax, 70
    ret
__cone_match_test_no_default_0_c1:
    mov eax, 80
    ret
__cone_match_test_no_default_0_end:
    mov eax, 0
    ret
test_no_default endp

test_return_tail proc stdcall uses ebx esi edi, x:DWORD
    mov eax, x
    cmp eax, 7
    je __cone_match_test_return_tail_0_c0
    jmp __cone_match_test_return_tail_0_default
__cone_match_test_return_tail_0_c0:
    mov eax, 77
    ret
__cone_match_test_return_tail_0_default:
    mov eax, 88
    ret
__cone_match_test_return_tail_0_end:
    mov eax, 0
    ret
test_return_tail endp

test_nested proc stdcall uses ebx esi edi, x:DWORD, y:DWORD
    mov eax, x
    cmp eax, 1
    je __cone_match_test_nested_0_c0
    jmp __cone_match_test_nested_0_default
__cone_match_test_nested_0_c0:
    mov eax, y
    cmp eax, 1
    je __cone_match_test_nested_1_c0
    jmp __cone_match_test_nested_1_default
__cone_match_test_nested_1_c0:
    mov eax, 11
    ret
__cone_match_test_nested_1_default:
    mov eax, 19
    ret
__cone_match_test_nested_1_end:
    jmp __cone_match_test_nested_0_end
__cone_match_test_nested_0_default:
    mov eax, 0
    ret
__cone_match_test_nested_0_end:
    mov eax, 0
    ret
test_nested endp

start proc uses ebx esi edi
    mov g, 3
    invoke test_default, g
    mov slot, eax
    invoke test_no_default, 7
    mov slot, eax
    invoke test_return_tail, 9
    mov slot, eax
    invoke test_nested, 1, 1
    mov slot, eax
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
