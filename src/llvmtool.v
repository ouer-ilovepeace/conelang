module main

import os

// cone 0.9.f —— LLVM 工具链驱动（V 实现）
//
// 目录约定：llvm 与 cone.exe 同目录
//   cone.exe
//   masm32\   bin include lib   （x86 默认 MASM32 后端用）
//   llvm\     bin include lib   （x64 LLVM 后端用 bin 下 llc.exe / lld-link.exe / opt.exe）
// CONE_LLVM_BIN 环境变量可覆盖 llvm\bin 路径。
//
// 0.9.f 要点：
//   * 取消 -llvm:x86，只出 -llvm:x64；x64 MSVC ABI 的入口符号不加前导 '_'。
//   * -O0 / -O1 / -O2 / -O3 / -Os / -Oz 只影响 x64 LLVM 后端（llc -O<级别>）。
//     高优化档（2/3/s/z）若 llvm\bin\opt.exe 存在，会先跑 opt -S -O<级别> 做 IR pass，
//     再交给 llc；opt.exe 不存在时直接 llc -O<级别>，不会报错。
//   * 多份 .cone 各出一份 .ll -> 各出一份 .obj -> 一次 lld-link 联成单个 .exe。
//   * CRT 库不固化：msvcrt.lib 由 -addl[/libpath:...] 或系统 LIB 提供。

fn llvm_cone_dir_v() string {
	return os.dir(os.executable())
}

fn llvm_bin_dir_v() string {
	env := os.getenv('CONE_LLVM_BIN')
	if env.len > 0 { return env }
	return llvm_cone_dir_v() + '\\llvm\\bin'
}

fn llvm_entry_symbol_v(entry string, arch string) string {
	return entry
}

fn llvm_basename_v(path string) string {
	mut s := path.replace('\\', '/')
	if s.contains('/') {
		parts := s.split('/')
		return parts[parts.len - 1]
	}
	return s
}

fn llvm_stem_v(path string) string {
	b := llvm_basename_v(path)
	if b.ends_with('.ll') { return b[..b.len - 3] }
	if b.ends_with('.cone') { return b[..b.len - 5] }
	return b
}

fn llvm_opt_is_high_v(opt string) bool {
	return opt == '2' || opt == '3' || opt == 's' || opt == 'z'
}

// 生成 bat 里「(可选) opt.exe -> llc -> .obj」的几行。
fn llvm_llc_bat_lines_v(base string, opt string, addm string) []string {
	mut lines := []string{}
	mut em := ''
	if addm.trim_space().len > 0 { em = ' ' + addm.trim_space() }
	mut src := '"' + base + '.ll"'
	if llvm_opt_is_high_v(opt) {
		lines << 'set "OPT=%LLVM_BIN%\\opt.exe"'
		lines << 'set "SRCLL=' + base + '.ll"'
		lines << 'if exist "%OPT%" ('
		lines << '  "%OPT%" -S -O' + opt + ' "' + base + '.ll" -o "' + base + '.opt.ll"'
		lines << '  if errorlevel 1 goto :fail'
		lines << '  set "SRCLL=' + base + '.opt.ll"'
		lines << ')'
		src = '"%SRCLL%"'
	}
	lines << '"%LLC%" -filetype=obj -mtriple=' + llvm_triple_v('x64') + ' -O' + opt +
		em + ' ' + src + ' -o "' + base + '.obj"'
	lines << 'if errorlevel 1 goto :fail'
	return lines
}

fn llvm_bat_head_v(bindir string) []string {
	mut lines := []string{}
	lines << '@echo off'
	lines << 'rem cone 0.9.f LLVM backend build script (-llvm:x64)'
	lines << 'setlocal'
	lines << 'set "LLVM_BIN=' + bindir + '"'
	lines << 'rem x64 CRT: msvcrt.lib from -addl[/libpath:...] or system LIB.'
	lines << 'if not "%CONE_LLVM_BIN%"=="" set "LLVM_BIN=%CONE_LLVM_BIN%"'
	lines << 'set "LLC=%LLVM_BIN%\\llc.exe"'
	lines << 'set "LLD=%LLVM_BIN%\\lld-link.exe"'
	lines << 'if not exist "%LLC%" echo [cone] llc.exe not found: %LLC% & goto :fail'
	lines << 'if not exist "%LLD%" echo [cone] lld-link.exe not found: %LLD% & goto :fail'
	return lines
}

fn llvm_bat_tail_v(okmsg string) []string {
	mut lines := []string{}
	lines << 'if errorlevel 1 goto :fail'
	lines << okmsg
	lines << 'exit /b 0'
	lines << ':fail'
	lines << 'echo [cone 0.9.f] LLVM build FAILED'
	lines << 'exit /b 1'
	return lines
}

fn llvm_build_bat_v(stem string, arch string, entry string, opt string, addm string, addl string) string {
	bindir := llvm_bin_dir_v()
	ent := llvm_entry_symbol_v(entry, arch)
	base := llvm_stem_v(stem)
	mut el := ''
	if addl.trim_space().len > 0 { el = ' ' + addl.trim_space() }
	mut lines := llvm_bat_head_v(bindir)
	for q in llvm_llc_bat_lines_v(base, opt, addm) { lines << q }
	lines << '"%LLD%" /nologo /subsystem:console /entry:' + ent +
		' /out:"' + base + '.exe" "' + base + '.obj" msvcrt.lib' + el
	for q in llvm_bat_tail_v('echo [cone 0.9.f] LLVM build OK -> ' + base + '.exe') { lines << q }
	return lines.join('\r\n') + '\r\n'
}

// cone 0.9.f：多份 .ll -> 多份 .obj -> 一次 lld-link 联成一个 .exe。
fn llvm_build_bat_multi_v(stems []string, exe_stem string, arch string, entry string,
	opt string, addm string, addl string) string {
	bindir := llvm_bin_dir_v()
	ent := llvm_entry_symbol_v(entry, arch)
	exe := llvm_basename_v(exe_stem)
	mut el := ''
	if addl.trim_space().len > 0 { el = ' ' + addl.trim_space() }
	mut objs := ''
	for st2 in stems {
		objs += ' "' + llvm_stem_v(st2) + '.obj"'
	}
	mut lines := llvm_bat_head_v(bindir)
	lines[1] = 'rem cone 0.9.f LLVM backend build script (-llvm:x64, multi-unit link)'
	for st2 in stems {
		for q in llvm_llc_bat_lines_v(llvm_stem_v(st2), opt, addm) { lines << q }
	}
	lines << '"%LLD%" /nologo /subsystem:console /entry:' + ent +
		' /out:"' + exe + '.exe"' + objs + ' msvcrt.lib' + el
	for q in llvm_bat_tail_v('echo [cone 0.9.f] LLVM multi-unit build OK -> ' + exe + '.exe') {
		lines << q
	}
	return lines.join('\r\n') + '\r\n'
}

fn llvm_llc_cmd_v(stem string, opt string, addm string, bindir string) []string {
	// 返回 0~2 条命令：高优化档且 opt.exe 存在时先跑 opt，再跑 llc。
	mut cmds := []string{}
	base := llvm_stem_v(stem)
	llc_exe := bindir + '\\llc.exe'
	opt_exe := bindir + '\\opt.exe'
	mut em := ''
	if addm.trim_space().len > 0 { em = ' ' + addm.trim_space() }
	mut src := base + '.ll'
	if llvm_opt_is_high_v(opt) && os.exists(opt_exe) {
		cmds << '"' + opt_exe + '" -S -O' + opt + ' "' + base + '.ll" -o "' + base + '.opt.ll"'
		src = base + '.opt.ll'
	}
	cmds << '"' + llc_exe + '" -filetype=obj -mtriple=' + llvm_triple_v('x64') +
		' -O' + opt + em + ' "' + src + '" -o "' + base + '.obj"'
	return cmds
}

// 生成 .llvm.bat；若本机可直接调用 Windows 工具链则继续产出 .obj/.exe。
fn llvm_run_toolchain_v(stem string, arch string, entry string, opt string,
	addm string, addl string, ir_only bool) string {
	bat := llvm_build_bat_v(stem, arch, entry, opt, addm, addl)
	bat_path := stem + '.llvm.bat'
	os.write_file(bat_path, bat) or {
		return '[cone -llvm] 无法写入 ' + bat_path
	}
	if ir_only { return '[cone -llvm] 只生成 .ll 与 .llvm.bat（-s）' }
	bindir := llvm_bin_dir_v()
	llc_exe := bindir + '\\llc.exe'
	link_exe := bindir + '\\lld-link.exe'
	if !os.exists(llc_exe) || !os.exists(link_exe) {
		return '[cone -llvm] 未找到 Windows LLVM 工具链（' + bindir +
			'），已生成 .ll 与 .llvm.bat；在 Windows 上运行该 bat 或设置 CONE_LLVM_BIN 即可产出 .exe'
	}
	ent := llvm_entry_symbol_v(entry, arch)
	base := llvm_stem_v(stem)
	mut el := ''
	if addl.trim_space().len > 0 { el = ' ' + addl.trim_space() }
	for c in llvm_llc_cmd_v(stem, opt, addm, bindir) {
		rc := os.system(c)
		if rc != 0 { return '[cone -llvm] ' + c.split(' ')[0] + ' 失败（退出码 ' + rc.str() + '），请检查 .llvm.bat' }
	}
	cmd2 := '"' + link_exe + '" /nologo /subsystem:console /entry:' + ent +
		' /out:"' + base + '.exe" "' + base + '.obj" msvcrt.lib' + el
	rc2 := os.system(cmd2)
	if rc2 != 0 { return '[cone -llvm] lld-link 失败（退出码 ' + rc2.str() + '）：请检查 .llvm.bat 的库路径 / -addl[...] / include xxx.lib' }
	return '[cone -llvm] ' + base + '.exe'
}

fn llvm_run_toolchain_multi_v(stems []string, exe_stem string, arch string, entry string,
	opt string, addm string, addl string, ir_only bool) string {
	bat := llvm_build_bat_multi_v(stems, exe_stem, arch, entry, opt, addm, addl)
	bat_path := exe_stem + '.llvm.bat'
	os.write_file(bat_path, bat) or {
		return '[cone -llvm] 无法写入 ' + bat_path
	}
	exe := llvm_basename_v(exe_stem)
	if ir_only {
		return '[cone -llvm] 只生成 ' + stems.len.str() + ' 份 .ll 与 ' + exe +
			'.llvm.bat（-s）；在 Windows 上跑该 bat 即联成 ' + exe + '.exe'
	}
	bindir := llvm_bin_dir_v()
	llc_exe := bindir + '\\llc.exe'
	link_exe := bindir + '\\lld-link.exe'
	if !os.exists(llc_exe) || !os.exists(link_exe) {
		return '[cone -llvm] 未找到 Windows LLVM 工具链（' + bindir +
			'），已生成 .ll 与 ' + exe + '.llvm.bat；在 Windows 上运行该 bat 或设置 CONE_LLVM_BIN 即可产出 .exe'
	}
	for st2 in stems {
		for c in llvm_llc_cmd_v(st2, opt, addm, bindir) {
			rc := os.system(c)
			if rc != 0 { return '[cone -llvm] llc 失败（退出码 ' + rc.str() + '），请检查 ' + exe + '.llvm.bat' }
		}
	}
	ent := llvm_entry_symbol_v(entry, arch)
	mut el := ''
	if addl.trim_space().len > 0 { el = ' ' + addl.trim_space() }
	mut cmd2 := '"' + link_exe + '" /nologo /subsystem:console /entry:' + ent +
		' /out:"' + exe + '.exe"'
	for st2 in stems {
		cmd2 += ' "' + llvm_stem_v(st2) + '.obj"'
	}
	cmd2 += ' msvcrt.lib' + el
	rc2 := os.system(cmd2)
	if rc2 != 0 { return '[cone -llvm] lld-link 失败（退出码 ' + rc2.str() + '）：请检查 ' + exe + '.llvm.bat 的库路径 / -addl[...]' }
	return '[cone -llvm] 已把 ' + stems.len.str() + ' 份 .obj 联成 ' + exe + '.exe'
}
