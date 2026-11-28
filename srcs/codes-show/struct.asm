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
ttt struct
    x DWORD ?
    y DWORD ?
ttt ends

tri struct
    a DWORD ?
    b DWORD ?
    d DWORD ?
tri ends

box struct
    p ttt <>
    tag DWORD ?
    buf BYTE 16 dup(?)
box ends

ldh1 proto :ttt

.data
stttt ttt <1,2>
zero ttt <>
part ttt <7>
holes tri <1,?,2>
fmt db "value is %d",0dh,0ah,0

.data?
fuck dd ?
blank ttt <>
packed box <>
__cone_itmp dd ?

.code
ldh1 proc stdcall uses ebx esi edi, arg1:ttt
    mov eax, arg1.x
    mov arg1.y, eax
    mov eax, arg1.y
    ret
ldh1 endp

start proc uses ebx esi edi
    local localst:ttt
    local lpst:DWORD
    mov localst.x, 3
    mov localst.y, 4
    invoke ldh1, stttt
    invoke crt_printf, offset fmt, eax
    mov stttt.x, 5
    mov eax, offset stttt
    mov lpst, eax
    mov eax, dword ptr [lpst+0]
    invoke crt_printf, offset fmt, eax
    mov eax, offset stttt
    mov eax, dword ptr [eax+4]
    invoke crt_printf, offset fmt, eax
    mov eax, localst.y
    invoke crt_printf, offset fmt, eax
    mov eax, holes.a
    invoke crt_printf, offset fmt, eax
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
