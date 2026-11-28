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
mosk struct
    x REAL4 ?
    y REAL4 ?
mosk ends

loser struct
    who mosk <>
loser ends

.const
__cone_flt_0 REAL4 1.0
__cone_flt_1 REAL4 2.5
__cone_flt_2 REAL4 3.5
__cone_flt_3 REAL4 4.5
__cone_flt_4 REAL4 5.5
__cone_flt_5 REAL4 2.0

.data?
fuck dd ?
glob REAL4 ?
buf db 32 dup(?)
__cone_itmp dd ?

.code
start proc uses ebx esi edi
    local ru:loser
    fld __cone_flt_0
    fstp dword ptr ru.who.x
    fld __cone_flt_1
    fstp dword ptr ru.who.y
    fld __cone_flt_2
    fstp dword ptr [buf]
    fld __cone_flt_3
    fstp qword ptr [buf+8]
    fld __cone_flt_4
    fstp glob
    fld glob
    fstp dword ptr ru.who.x
    fld ru.who.x
    fld __cone_flt_5
    fmulp st(1), st(0)
    fstp dword ptr ru.who.y
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
