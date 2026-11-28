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
cell struct
    val DWORD ?
    tag BYTE ?
cell ends

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
one cell <7,1>
fmt db "x=%d y=%d z=%d\n",0

.data?
fuck dd ?
buf dd 6 dup(?)
__cone_itmp dd ?

.code
x64lib_add proc uses ebx esi edi, a:DWORD, b:DWORD
    mov eax, a
    add eax, b
    ret
x64lib_add endp

x64lib_twice proc uses ebx esi edi, v:DWORD
    mov eax, v
    imul eax, 2
    ret
x64lib_twice endp

x64lib_sum3 proc uses ebx esi edi, a:DWORD, b:DWORD, k:DWORD
    mov eax, a
    add eax, b
    add eax, k
    ret
x64lib_sum3 endp

main proc uses ebx esi edi
    local i:DWORD
    local acc:DWORD
    local arr[4]:WORD
    mov i, 0
    mov acc, 0
    .while (i < 6)
    invoke x64lib_twice, i
    mov ebx, eax
    mov dword ptr [buf+i*4], ebx
    mov eax, acc
    mov ebx, dword ptr [buf+i*4]
    add eax, ebx
    mov acc, eax
    inc i
    .endw
    mov i, 0
    .while (i < 4)
    mov ebx, i
    add ebx, 1
    mov word ptr [arr+i*2], bx
    inc i
    .endw
    mov eax, one.val
    add eax, acc
    mov one.val, eax
    push 5
    movzx ebx, word ptr [arr+4]
    push ebx
    push one.val
    mov eax, offset fmt
    xor edx, edx
    push edx
    push eax
    call printf
    add esp, 20
    invoke x64lib_add, acc, 3
    invoke ExitProcess, eax
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
