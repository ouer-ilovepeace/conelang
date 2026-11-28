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
Holder struct
    box RECT <>
    n DWORD ?
Holder ends

SAME struct
    v DWORD ?
SAME ends

SHARE_DELETE equ FILE_SHARE_DELETE
SHARE_READ equ FILE_SHARE_READ
SHARE_WRITE equ FILE_SHARE_WRITE
take_proto proto stdcall :RECT

.const
__cone_stt_0 RECT <0,0,1,1>
__cone_stt_1 RECT <2,3,4,5>

.data
grc RECT <0,0,640,480>

.data?
fuck dd ?
gr RECT <>
lpst dd ?
cell dd ?
__cone_itmp dd ?

.code
memmove proc uses ebx esi edi, _lpdst:DWORD, _lpsrc:DWORD, _size:DWORD
        cld
        mov ecx,_size
        mov esi,_lpsrc
        mov edi,_lpdst
        rep movsb
    ret
memmove endp

getsize proc uses ebx esi edi, _hFile:DWORD
    local @FileSizeHigh:DWORD
    invoke GetFileSize, _hFile, addr @FileSizeHigh
    .if (eax != INVALID_FILE_SIZE)
    mov edx, @FileSizeHigh
    ret
    .endif
    mov eax, 0
    ret
getsize endp

seek proc uses ebx esi edi, _hFile:DWORD, _size:QWORD, _startfrom:DWORD
    push _startfrom
    mov eax, dword ptr [_size]
    mov edx, dword ptr [_size+4]
    push edx
    push eax
    push _hFile
    call SetFilePointer
    ret
seek endp

open proc uses ebx esi edi, _filename:DWORD, _mode:DWORD, _share:DWORD
    mov eax, _mode
    cmp eax, 1816
    je __cone_match_open_0_c0
    cmp eax, 1817
    je __cone_match_open_0_c1
    cmp eax, 1818
    je __cone_match_open_0_c2
    cmp eax, 1819
    je __cone_match_open_0_c3
    cmp eax, 1820
    je __cone_match_open_0_c4
    cmp eax, 1821
    je __cone_match_open_0_c5
    jmp __cone_match_open_0_default
__cone_match_open_0_c0:
    invoke CreateFile, _filename, (GENERIC_READ or GENERIC_WRITE), _share, 0, OPEN_ALWAYS, FILE_ATTRIBUTE_NORMAL, 0
    .if (eax != INVALID_HANDLE_VALUE)
    .else
    mov eax, 0
    ret
    .endif
    jmp __cone_match_open_0_end
__cone_match_open_0_c1:
    jmp __cone_match_open_0_end
__cone_match_open_0_c2:
    jmp __cone_match_open_0_end
__cone_match_open_0_c3:
    jmp __cone_match_open_0_end
__cone_match_open_0_c4:
    jmp __cone_match_open_0_end
__cone_match_open_0_c5:
    jmp __cone_match_open_0_end
__cone_match_open_0_default:
__cone_match_open_0_end:
    mov eax, 0
    ret
open endp

read proc uses ebx esi edi
    mov eax, 0
    ret
read endp

close proc uses ebx esi edi
    mov eax, 0
    ret
close endp

write proc uses ebx esi edi
    mov eax, 0
    ret
write endp

setattr proc uses ebx esi edi
    mov eax, 0
    ret
setattr endp

take_rect proc uses ebx esi edi, r:RECT
    local lr:RECT
    mov eax, r
    mov lr, eax
    mov eax, 0
    ret
take_rect endp

start proc uses ebx esi edi
    local rct:RECT
    local sv:SAME
    local late:LATE_TYPE
    mov rct.left, 0
    invoke MessageBoxA, 0, 0, 0, MB_OKCANCEL
    invoke take_rect, __cone_stt_0
    invoke take_rect, offset __cone_stt_1
    mov eax, offset gr
    mov lpst, eax
    mov eax, dword ptr [lpst+RECT.left]
    mov cell, eax
    mov sv.v, 3
    mov eax, sv.v
    mov cell, eax
    mov eax, MB_OKCANCEL
    mov cell, eax
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
