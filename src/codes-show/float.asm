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
MousePos struct
    x REAL4 ?
    y REAL4 ?
MousePos ends

.const
__cone_flt_0 REAL4 1.0
__cone_flt_1 REAL4 2.5
__cone_flt_2 REAL4 5

.data?
fuck dd ?
MousePosition MousePos <>
WindowX dd ?
ratio REAL4 ?
__cone_itmp dd ?

.code
start proc uses ebx esi edi
    fld __cone_flt_0
    fmul dword ptr MousePosition.x
    mov eax, WindowX
    mov __cone_itmp, eax
    fild __cone_itmp
    fdivp st(1), st(0)
    fstp dword ptr MousePosition.x
    mov eax, WindowX
    mov __cone_itmp, eax
    fild __cone_itmp
    fdiv dword ptr MousePosition.x
    fstp dword ptr MousePosition.x
    mov eax, WindowX
    mov __cone_itmp, eax
    fild __cone_itmp
    fdivr dword ptr MousePosition.x
    fstp dword ptr MousePosition.x
    mov eax, WindowX
    mov ebx, 2
    xor edx, edx
    div ebx
    mov __cone_itmp, eax
    fild __cone_itmp
    fadd dword ptr MousePosition.y
    fstp dword ptr MousePosition.y
    fld __cone_flt_1
    fadd dword ptr WindowX
    fstp ratio
    mov eax, 2
    mov __cone_itmp, eax
    fild __cone_itmp
    fdivr __cone_flt_2
    fistp dword ptr WindowX
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
