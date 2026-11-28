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
MessageBoxW proto C :QWORD, :QWORD, :QWORD, :QWORD

.const
__cone_str_0 db 48h,00h,65h,00h,6Ch,00h,6Ch,00h,6Fh,00h,2Ch,00h,20h,00h,16h,4Eh,4Ch,75h,21h,00h,00h,00h

.data
wcap db 43h,00h,6Fh,00h,6Eh,00h,65h,00h,20h,00h,07h,68h,98h,98h,00h,00h
wmsg db 48h,00h,65h,00h,6Ch,00h,6Ch,00h,6Fh,00h,2Ch,00h,20h,00h,16h,4Eh,4Ch,75h,21h,00h,0Ah,00h,2Ch,7Bh,8Ch,4Eh,4Ch,88h,00h,00h
fmt db "wcap=%d wmsg=%d\n",0

.data?
fuck dd ?
__cone_itmp dd ?

.code
main proc uses ebx esi edi
    mov eax, 0
    xor edx, edx
    push edx
    push eax
    mov eax, offset wcap
    xor edx, edx
    push edx
    push eax
    mov eax, offset __cone_str_0
    xor edx, edx
    push edx
    push eax
    mov eax, 0
    xor edx, edx
    push edx
    push eax
    call MessageBoxW
    add esp, 32
    push 30
    push 16
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
