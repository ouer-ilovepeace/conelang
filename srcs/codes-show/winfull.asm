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
Holder struct
    pt POINT <>
    n DWORD ?
Holder ends

draw proto stdcall p:POINT, r:RECT

.const
__cone_stt_0 POINT <1,2>
__cone_stt_1 RECT <0,0,1,1>
__cone_stt_2 POINT <3,4>

.data
gOrigin POINT <10,20>
gRect RECT <0,0,640,480>

.data?
fuck dd ?
__cone_itmp dd ?

.code
start proc uses ebx esi edi
    local localpt:POINT
    local localrc:RECT
    local h:Holder
    mov eax, SW_SHOW
    mov h.n, eax
    mov eax, gOrigin
    mov localpt, eax
    invoke draw, __cone_stt_0, __cone_stt_1
    invoke draw, offset __cone_stt_2, gRect
    invoke ExitProcess, SM_CXSCREEN
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
