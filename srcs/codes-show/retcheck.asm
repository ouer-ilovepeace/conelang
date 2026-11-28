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
pair struct
    xx DWORD ?
    yy DWORD ?
pair ends

fpair proto __cone_sret_ptr:DWORD
flong proto
fint proto
flongmatch proto

.data
gpair pair <>
gl dq 9
gi dd 3

.data?
fuck dd ?
__cone_itmp dd ?

.code
fpair proc uses ebx esi edi, __cone_sret_ptr:DWORD
    mov edi, __cone_sret_ptr
    cld
    mov esi, offset gpair
    mov ecx, 2
    rep movsd
    mov eax, __cone_sret_ptr
    ret
fpair endp

flong proc uses ebx esi edi
    mov eax, gi
    xor edx, edx
    ret
flong endp

fint proc uses ebx esi edi
    mov eax, 1
    ret
fint endp

flongmatch proc uses ebx esi edi
    mov eax, dword ptr [gl]
    mov edx, dword ptr [gl+4]
    ret
flongmatch endp

start proc uses ebx esi edi
    local p1:pair
    local v1:QWORD
    local v2:DWORD
    local v3:QWORD
    invoke fpair, addr p1
    invoke flong
    mov dword ptr v1, eax
    mov dword ptr v1+4, edx
    invoke fint
    mov v2, eax
    invoke flongmatch
    mov dword ptr v3, eax
    mov dword ptr v3+4, edx
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
