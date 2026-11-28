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
sample struct
    ratio REAL8 ?
    n DWORD ?
    small REAL4 ?
sample ends

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

.const
__cone_flt_0 REAL4 1.0

.data
fmt db "float: i=%d f=%d\n",0
g sample <2.5,7,1.25>
pi REAL8 3.14

.data?
fuck dd ?
__cone_itmp dd ?

.code
scale proc uses ebx esi edi, v:REAL8, k:REAL8
    fld v
    fld k
    fmulp st(1), st(0)
    sub esp, 8
    fst qword ptr [esp]
    pop eax
    pop edx
    ret
scale endp

main proc uses ebx esi edi
    local fv1:REAL8
    local fv2:REAL4
    local fv3:REAL8
    local fv4:REAL8
    local fv5:REAL8
    local ii:DWORD
    local jj:DWORD
    mov eax, dword ptr [__cone_flt_missing]
    mov dword ptr fv1, eax
    mov dword ptr fv1+4, 0
    mov eax, dword ptr [__cone_flt_missing]
    mov fv2, eax
    mov eax, dword ptr fv1
    imul eax, 2.0
    add eax, fv2
    mov dword ptr fv3, eax
    mov dword ptr fv3+4, 0
    fld __cone_flt_missing
    sub esp, 8
    fstp qword ptr [esp]
    fld pi
    sub esp, 8
    fstp qword ptr [esp]
    call scale
    mov dword ptr fv4, eax
    mov dword ptr fv4+4, edx
    mov eax, g.ratio
    add eax, fv3
    add eax, fv4
    mov dword ptr fv5, eax
    mov dword ptr fv5+4, 0
    mov eax, dword ptr fv5
    mov ii, eax
    mov eax, g.small
    imul eax, 4.0
    mov jj, eax
    .if (fv1 > 1.0)
    inc ii
    .endif
    push jj
    push ii
    mov eax, offset fmt
    xor edx, edx
    push edx
    push eax
    call printf
    add esp, 16
    invoke ExitProcess, ii
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
