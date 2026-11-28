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
s3 struct
    aa BYTE ?
    bb BYTE ?
    cc BYTE ?
s3 ends

s5 struct
    aa DWORD ?
    bb BYTE ?
s5 ends

s6 struct
    aa DWORD ?
    bb WORD ?
s6 ends

s7 struct
    aa DWORD ?
    bb WORD ?
    cc BYTE ?
s7 ends

s8 struct
    aa DWORD ?
    bb DWORD ?
s8 ends

.data
g3 s3 <>
g5 s5 <>
g6 s6 <>
g7 s7 <>
g8 s8 <>

.data?
fuck dd ?
__cone_itmp dd ?

.code
r3 proc uses ebx esi edi
    movzx eax, word ptr [g3]
    movzx ecx, byte ptr [g3+2]
    shl ecx, 16
    or eax, ecx
    ret
r3 endp

r5 proc uses ebx esi edi
    mov eax, dword ptr [g5]
    movzx edx, byte ptr [g5+4]
    ret
r5 endp

r6 proc uses ebx esi edi
    mov eax, dword ptr [g6]
    movzx edx, word ptr [g6+4]
    ret
r6 endp

r7 proc uses ebx esi edi
    mov eax, dword ptr [g7]
    movzx edx, word ptr [g7+4]
    movzx ecx, byte ptr [g7+6]
    shl ecx, 16
    or edx, ecx
    ret
r7 endp

r8 proc uses ebx esi edi
    mov eax, dword ptr [g8]
    mov edx, dword ptr [g8+4]
    ret
r8 endp

start proc uses ebx esi edi
    invoke r3
    invoke r5
    invoke r6
    invoke r7
    invoke r8
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
