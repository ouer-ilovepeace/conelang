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
big struct
    aa DWORD ?
    bb DWORD ?
    cc DWORD ?
big ends

pt struct
    xx DWORD ?
    yy DWORD ?
pt ends

q struct
    a BYTE ?
    _padding_0 BYTE 3 dup(?)
    b DWORD ?
    z BYTE ?
    _padding_1 BYTE 3 dup(?)
q ends

mkbig proto stdcall __cone_sret_ptr:DWORD
mkpt proto __cone_sret_ptr:DWORD
mkq proto __cone_sret_ptr:DWORD

.data
gbig big <>
dstbig big <>
gpt pt <>
gq q <1,<>,2,3>

.data?
fuck dd ?
__cone_itmp dd ?

.code
mkbig proc stdcall uses ebx esi edi, __cone_sret_ptr:DWORD
    mov edi, __cone_sret_ptr
    cld
    mov esi, offset gbig
    mov ecx, 3
    rep movsd
    mov eax, __cone_sret_ptr
    ret
mkbig endp

mkpt proc uses ebx esi edi, __cone_sret_ptr:DWORD
    mov edi, __cone_sret_ptr
    cld
    mov esi, offset gpt
    mov ecx, 2
    rep movsd
    mov eax, __cone_sret_ptr
    ret
mkpt endp

mkq proc uses ebx esi edi, __cone_sret_ptr:DWORD
    mov edi, __cone_sret_ptr
    cld
    mov esi, offset gq
    mov ecx, 3
    rep movsd
    mov eax, __cone_sret_ptr
    ret
mkq endp

start proc uses ebx esi edi
    local p2:big
    local p3:pt
    local dstq:q
    invoke mkbig, offset dstbig
    invoke mkbig, addr p2
    invoke mkpt, addr p3
    invoke mkq, addr dstq
    sub esp, 12
    mov ebx, esp
    push ebx
    call mkbig
    add esp, 12
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
