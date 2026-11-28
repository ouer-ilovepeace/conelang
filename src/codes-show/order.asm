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
msgbox proto :DWORD, :DWORD

.const
__cone_str_0 db "x>=y",0
__cone_str_1 db "Cone",0
__cone_str_2 db "x<y",0

.data
x dd -1

.data?
fuck dd ?
__cone_itmp dd ?

.code
start proc uses ebx esi edi
    local y:DWORD
    mov y, 2
    mov ebx, x
    mov esi, y
    .if ((ebx > esi) || (ebx == esi))
    invoke msgbox, offset __cone_str_0, offset __cone_str_1
    .else
    invoke msgbox, offset __cone_str_2, offset __cone_str_1
    .endif
    invoke ExitProcess, 0
start endp

msgbox proc stdcall uses ebx esi edi, cotent:DWORD, caption:DWORD
    invoke MessageBoxA, 0, cotent, caption, MB_OKCANCEL
    ret
msgbox endp

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
