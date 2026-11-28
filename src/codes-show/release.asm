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
	CONE_RELEASE_TAG equ <0500h>
exported_add proto stdcall export :DWORD, :DWORD

.const
fmt db "Hello cone 0.5",0dh,0ah,0
greeting db "Release",0

.data?
fuck dd ?
@shared dd ?
shared dd ?
__cone_itmp dd ?

.code
exported_add proc stdcall export uses ebx esi edi, a:DWORD, b:DWORD
    local shared:DWORD
    mov eax, a
    add eax, b
    mov shared, eax
		mov eax,shared
		test eax,eax
    mov eax, shared
    cmp eax, 0
    je __cone_match_exported_add_0_c0
    jmp __cone_match_exported_add_0_default
__cone_match_exported_add_0_c0:
    mov eax, 0
    ret
__cone_match_exported_add_0_default:
    mov eax, shared
    ret
__cone_match_exported_add_0_end:
    mov eax, 0
    ret
exported_add endp

start proc uses ebx esi edi
    local r:DWORD
    invoke exported_add, 1, 2
    mov r, eax
		mov ebx,offset fmt
		mov ecx,CONE_RELEASE_TAG
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
