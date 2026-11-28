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
    include raylib.inc
    includelib raylibdll.lib
void typedef dword
SHARE_DELETE equ FILE_SHARE_DELETE
SHARE_READ equ FILE_SHARE_READ
SHARE_WRITE equ FILE_SHARE_WRITE

.const
__cone_str_0 db "Cone",0
__cone_str_1 db "desk_win.png",0
__cone_str_2 db "desk_win_height.png",0
__cone_str_3 db "base.fs",0
__cone_str_4 db "lightPos",0
__cone_str_5 db "lightColor",0
__cone_str_6 db "normalTex",0
__cone_flt_0 REAL4 1.0

.data
WindowX dd 600
WindowY dd 800
RenderColor Vector3 <1.0,0.95,0.8>
srcRd LRectangle <0.0,0.0,600.0,-800.0>
dstRd LRectangle <0.0,0.0,600.0,800.0>
origin Vector2 <0.0,0.0>

.data?
fuck dd ?
hInstance dd ?
hWnMain dd ?
sttQiao Texture <>
sttNormal Texture <>
rdBase RenderTexture <>
shBase Shader <>
MousePosition Vector2 <>
pos_loc dd ?
light_loc dd ?
normal_loc dd ?
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

main proc uses ebx esi edi
    push 0
    mov eax, 12
    xor edx, edx
    push edx
    push eax
    push 0
    call seek
    invoke GetModuleHandle, 0
    mov hInstance, eax
    invoke SetConfigFlags, (FLAG_WINDOW_TRANSPARENT or FLAG_WINDOW_TOPMOST)
    invoke InitWindow, WindowX, WindowY, offset __cone_str_0
    invoke SetTargetFPS, 60
    invoke GetWindowHandle
    mov hWnMain, eax
    invoke LoadTexture, offset sttQiao, offset __cone_str_1
    invoke LoadTexture, offset sttNormal, offset __cone_str_2
    invoke LoadRenderTexture, offset rdBase, WindowX, WindowY
    invoke LoadShader, 0, offset __cone_str_3
    mov shBase.id, eax
    mov shBase.locs, edx
    invoke GetShaderLocation, shBase, offset __cone_str_4
    mov pos_loc, eax
    invoke GetShaderLocation, shBase, offset __cone_str_5
    mov light_loc, eax
    invoke GetShaderLocation, shBase, offset __cone_str_6
    mov normal_loc, eax
    invoke SetTextureWrap, sttNormal, TEXTURE_WRAP_CLAMP
    invoke SetShaderValueTexture, shBase, normal_loc, sttNormal
__cone_for_main_0_cond:
    invoke WindowShouldClose
    test eax, eax
    sete al
    movzx eax, al
    test eax, eax
    jz __cone_for_main_0_end
    invoke SetShaderValue, shBase, pos_loc, offset MousePosition, SHADER_UNIFORM_VEC2
    invoke GetMousePosition
    mov MousePosition.y, edx
    mov MousePosition.x, eax
    mov eax, WindowX
    mov __cone_itmp, eax
    fild __cone_itmp
    fdivr dword ptr MousePosition.x
    fstp dword ptr MousePosition.x
    fld __cone_flt_0
    mov eax, WindowY
    mov __cone_itmp, eax
    fild __cone_itmp
    fdivr dword ptr MousePosition.y
    fsubp st(1), st(0)
    fstp dword ptr MousePosition.y
    invoke SetShaderValue, shBase, light_loc, offset RenderColor, SHADER_UNIFORM_VEC3
    invoke BeginTextureMode, rdBase
    invoke DrawTexture, sttQiao, 0, 0, 0ffffffffh
    invoke EndTextureMode
    invoke BeginDrawing
    invoke ClearBackground, 0
    invoke BeginShaderMode, shBase
    invoke DrawTexturePro, rdBase.texture, srcRd, dstRd, origin, 0, 0ffffffffh
    invoke EndShaderMode
    invoke EndDrawing
    jmp __cone_for_main_0_cond
__cone_for_main_0_end:
    invoke UnloadTexture, sttQiao
    invoke UnloadTexture, sttNormal
    invoke UnloadRenderTexture, rdBase
    invoke UnloadShader, shBase
    invoke RaylibCloseWindow
    invoke ExitProcess, 0
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
