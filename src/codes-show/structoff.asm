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
xy struct
    x DWORD ?
    y DWORD ?
xy ends

nested struct
    a BYTE ?
    b xy <>
    w2 WORD ?
nested ends

aligned struct
    a BYTE ?
    _padding_0 BYTE 3 dup(?)
    b DWORD ?
    w2 WORD ?
    _padding_1 BYTE 6 dup(?)
    d QWORD ?
aligned ends

.data
hello db "Hello World",0dh,0ah,0
stxy xy <>
stalign aligned <>

.data?
fuck dd ?
wrc RECT <>
__cone_itmp dd ?

.code
start proc uses ebx esi edi
    local a:DWORD
    local b:DWORD
    local n1:DWORD
    local n2:DWORD
    local n3:DWORD
    local s1:DWORD
    local s2:DWORD
    local s3:DWORD
    local s4:DWORD
    local s5:DWORD
    local arr[6]:DWORD
    local p:DWORD
    local q:DWORD
    local r:DWORD
    mov a, 0
    mov b, 4
    mov n1, 5
    mov n2, 4
    mov n3, 16
    mov s1, 4
    mov s2, 8
    mov s3, 24
    mov s4, 14
    mov s5, 24
    mov eax, offset stxy
    mov p, eax
    mov q, 14
    mov r, 18
        mov eax, 4
        mov ebx, 24
        mov ecx, 16
        mov edx, 8
    db 0B8h,04h,00h,00h,00h
    db 0B9h,08h,00h,00h,00h
    db 83h,0C0h,04h
    db 0Fh,05h
        mov esi, offset wrc
        mov eax, [esi+RECT.left]
        mov ebx, [esi+win.RECT.top]
    .if (b == 4)
    mov a, 8
    .endif
    mov eax, a
    cmp eax, 8
    je __cone_match_start_0_c0
    jmp __cone_match_start_0_default
__cone_match_start_0_c0:
    mov a, 4
    jmp __cone_match_start_0_end
__cone_match_start_0_default:
    mov a, 0
__cone_match_start_0_end:
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
