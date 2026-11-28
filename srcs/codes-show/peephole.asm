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

mkbig proto __cone_sret_ptr:DWORD

.data
gbig big <>
dstbig big <>

.data?
fuck dd ?
__cone_itmp dd ?

.code
mkbig proc uses ebx esi edi, __cone_sret_ptr:DWORD
    mov edi, __cone_sret_ptr
    cld
    mov esi, offset gbig
    mov ecx, 3
    rep movsd
    mov eax, __cone_sret_ptr
    ret
mkbig endp

start proc uses ebx esi edi
    local v1:DWORD
    mov v1, 1
    inc v1
    dec v1
    inc v1
    invoke mkbig, offset dstbig
    invoke ExitProcess, v1
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
