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
tiny struct
    aa BYTE ?
    bb BYTE ?
tiny ends

quad struct
    xx DWORD ?
quad ends

pair struct
    p1 DWORD ?
    p2 DWORD ?
pair ends

big struct
    m1 DWORD ?
    m2 DWORD ?
    m3 DWORD ?
big ends

.const
__cone_flt_0 REAL4 3

.data
gtiny tiny <>
gquad quad <>
gpair pair <>
gbig big <>
fbig REAL8 1.5

.data?
fuck dd ?
__cone_itmp dd ?

.code
rtiny proc uses ebx esi edi
    movzx eax, word ptr [gtiny]
    ret
rtiny endp

rquad proc uses ebx esi edi
    mov eax, dword ptr [gquad]
    ret
rquad endp

rpair proc uses ebx esi edi
    mov eax, dword ptr [gpair]
    mov edx, dword ptr [gpair+4]
    ret
rpair endp

rbig proc uses ebx esi edi
    lea eax, [gbig]
    ret
rbig endp

rmem proc uses ebx esi edi
    mov eax, gpair.p2
    ret
rmem endp

rf proc uses ebx esi edi
    fld __cone_flt_0
    sub esp, 4
    fst dword ptr [esp]
    pop eax
    ret
rf endp

rf8 proc uses ebx esi edi
    fld qword ptr fbig
    sub esp, 8
    fst qword ptr [esp]
    pop eax
    pop edx
    ret
rf8 endp

start proc uses ebx esi edi
    invoke rtiny
    invoke rquad
    invoke rpair
    invoke rbig
    invoke rmem
    invoke rf
    invoke rf8
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
