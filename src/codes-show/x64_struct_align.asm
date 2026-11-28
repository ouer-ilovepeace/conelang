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
inner struct
    aa BYTE ?
    bb DWORD ?
inner ends

outer struct
    xx BYTE ?
    _padding_0 BYTE 3 dup(?)
    sub2 inner <>
    _padding_1 BYTE 1 dup(?)
    zz WORD ?
outer ends

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
g outer <1,<>,2,<>,3>
fmt db "o=%d n=%d\n",0

.data?
fuck dd ?
__cone_itmp dd ?

.code
main proc uses ebx esi edi
    local loc:inner
    mov loc.aa, 9
    mov loc.bb, 12
    mov eax, loc.bb
    mov g.sub2.bb, eax
    mov g.zz, 10
    push 12
    push g.sub2.bb
    mov eax, offset fmt
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
