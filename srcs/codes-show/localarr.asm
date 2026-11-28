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
includelib /data/workspace/masm32/lib/os.lib
void typedef dword
print proto stdcall :void

.data
msg db "hi",0
fmt db "global",0

.data?
fuck dd ?
__cone_itmp dd ?

.code
dump proc stdcall uses ebx esi edi, p:DWORD, q:DWORD
    local fmt[32]:BYTE
    local buf[16]:BYTE
    invoke wsprintf, addr fmt, addr buf, p, q
    invoke print, addr p
    invoke print, offset msg
    invoke print, 3, addr fmt
    mov eax, p
    ret
dump endp

start proc uses ebx esi edi
    invoke dump, 1, 2
    invoke ExitProcess, eax
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
