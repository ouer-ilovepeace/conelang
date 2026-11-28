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
pt struct
    xx DWORD ?
    yy DWORD ?
pt ends

big struct
    aa DWORD ?
    bb DWORD ?
    cc DWORD ?
big ends

.data
gp pt <3,4>
gb big <1,2,3>

.data?
fuck dd ?
__cone_itmp dd ?

.code
sumpt proc uses ebx esi edi, p:pt
    mov eax, p.xx
    push eax
    mov eax, p.yy
    mov ebx, eax
    pop eax
    add eax, ebx
    ret
sumpt endp

sumbig proc uses ebx esi edi, q:big
    mov eax, q.aa
    push eax
    mov eax, q.bb
    mov ebx, eax
    pop eax
    add eax, ebx
    push eax
    mov eax, q.cc
    mov ebx, eax
    pop eax
    add eax, ebx
    ret
sumbig endp

mkbig proc uses ebx esi edi, __cone_sret_ptr:DWORD
    mov edi, __cone_sret_ptr
    cld
    mov esi, offset gb
    mov ecx, 3
    rep movsd
    mov eax, __cone_sret_ptr
    ret
mkbig endp

main proc uses ebx esi edi
    local a:DWORD
    local b:DWORD
    local cc:big
    local d:big
    local e:DWORD
    invoke sumpt, gp
    mov a, eax
    invoke sumbig, gb
    mov b, eax
    invoke mkbig, addr cc
    mov eax, gb
    mov d, eax
    invoke mkbig, addr d
    mov eax, cc.aa
    push eax
    mov eax, d.cc
    mov ebx, eax
    pop eax
    add eax, ebx
    mov e, eax
    sub esp, 12
    mov ebx, esp
    push ebx
    call mkbig
    add esp, 12
    mov eax, a
    add eax, b
    add eax, e
    invoke ExitProcess, eax
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
