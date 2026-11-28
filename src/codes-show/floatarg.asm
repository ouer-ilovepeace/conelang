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
Pos struct
    x REAL4 ?
    y REAL4 ?
Pos ends

sink proto :REAL4

.const
__cone_flt_0 REAL4 1.0

.data?
fuck dd ?
p Pos <>
WindowX dd ?
__cone_itmp dd ?

.code
start proc uses ebx esi edi
    mov eax, WindowX
    mov __cone_itmp, eax
    fild __cone_itmp
    fdivr dword ptr p.x
    sub esp, 4
    fstp dword ptr [esp]
    call sink
    mov eax, WindowX
    mov __cone_itmp, eax
    fild __cone_itmp
    fdiv dword ptr p.x
    sub esp, 4
    fstp dword ptr [esp]
    call sink
    fld __cone_flt_0
    fmul dword ptr p.x
    mov eax, WindowX
    mov __cone_itmp, eax
    fild __cone_itmp
    faddp st(1), st(0)
    sub esp, 4
    fstp dword ptr [esp]
    call sink
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
