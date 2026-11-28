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

.data
total dd 0
fmt db "v=%d\n",0

.data?
fuck dd ?
buf dd 8 dup(?)
__cone_itmp dd ?

.code
main proc uses ebx esi edi
    local i:DWORD
    mov i, 0
    .while (i < 8)
    .if (i == 2)
    .continue
    .endif
    .if (i == 6)
    .break
    .endif
    mov ebx, i
    mov dword ptr [buf+i*4], ebx
    .if (i < 3)
    mov eax, total
    add eax, i
    mov total, eax
    .elseif (i == 4)
    add total, 10
    .else
    inc total
    .endif
    .endw
    mov eax, total
    cmp eax, 0
    je __cone_match_main_0_c0
    cmp eax, 1
    je __cone_match_main_0_c1
    jmp __cone_match_main_0_default
__cone_match_main_0_c0:
    mov total, 100
    jmp __cone_match_main_0_end
__cone_match_main_0_c1:
    mov total, 101
    jmp __cone_match_main_0_end
__cone_match_main_0_default:
    mov eax, total
    mov total, eax
__cone_match_main_0_end:
    mov ebx, dword ptr [buf+12]
    push ebx
    mov eax, offset fmt
    xor edx, edx
    push edx
    push eax
    call printf
    add esp, 12
    invoke ExitProcess, total
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
