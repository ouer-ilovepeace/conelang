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
tail struct
    a DWORD ?
    b BYTE ?
    _padding_0 BYTE 3 dup(?)
tail ends

outer struct
    x BYTE ?
    _padding_0 BYTE 3 dup(?)
    inner tail <>
    z WORD ?
    _padding_1 BYTE 2 dup(?)
outer ends

plain struct
    p BYTE ?
    q DWORD ?
plain ends

.data
g1 tail <>
g2 outer <>

.data?
fuck dd ?
__cone_itmp dd ?

.code
start proc uses ebx esi edi
    local s1:DWORD
    local s2:DWORD
    local s3:DWORD
    local o1:DWORD
    local o2:DWORD
    local o3:DWORD
    local o4:DWORD
    local o5:DWORD
    local e1:DWORD
    local e2:DWORD
    local arr[16]:BYTE
    mov s1, 8
    mov s2, 16
    mov s3, 5
    mov o1, 4
    mov o2, 4
    mov o3, 8
    mov o4, 12
    mov o5, 1
    mov e1, 8
    mov e2, 9
        mov eax, 4
        mov ebx, 16
        mov ecx, 8
        mov edx, 8
    db 0B8h,0Ch,00h,00h,00h
    db 83h,0C0h,05h
    db 0B9h,04h,00h,00h,00h
    db 0Fh,05h
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
