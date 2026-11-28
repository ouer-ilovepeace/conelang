module main

import os

// cone 0.6 fix 1 —— 位运算 / 任意 match case / ++-- / 取消名称修饰 / 整数赋值优化。
// 控制台输出统一英文；报错统一一行格式；无参数不再跑默认样例 / 打印完整 .asm。

// first_number: 取消息里第一段连续数字作为行号。
// 语义层的报错基本都以 `第 N 行: ...` 或 `file:N:M ...` / `@ N:M` 开头，
// 因此第一段数字就是最精确的行号；找不到时为 0。
fn first_number(s string) int {
	mut i := 0
	for i < s.len {
		if s[i] >= 48 && s[i] <= 57 {
			mut n := 0
			mut j := i
			for j < s.len && s[j] >= 48 && s[j] <= 57 {
				n = n * 10 + int(s[j] - 48)
				j = j + 1
			}
			return n
		}
		i = i + 1
	}
	return 0
}

// strip_cn_line_prefix: 去掉 `第 N 行: ` 的中文前缀（UTF-8 "行: " = E8 A1 8C 3A 20），
// 让 Error Details 只剩技术描述，行号由 line[N] 单独承载。
fn strip_cn_line_prefix(s string) string {
	mut i := 0
	for i + 5 <= s.len {
		if s[i] == 232 && s[i + 1] == 161 && s[i + 2] == 140 && s[i + 3] == 58 && s[i + 4] == 32 {
			return s[i + 5..]
		}
		i = i + 1
	}
	return s
}

// 统一的 CLI 错误信息：只输出「[cone] error: 具体原因」，不再出现
// 无意义的 Error Type / line[0] 占位。各阶段用 `Type|` 前缀分类，此处剥掉。
fn format_error(raw string) string {
	mut msg := raw
	mut i := 0
	for i < raw.len {
		if raw[i] == 124 { // '|'
			msg = raw[i + 1..]
			break
		}
		i = i + 1
	}
	return '[cone] error: ' + strip_cn_line_prefix(msg)
}

fn base_name(path string) string {
	mut last := 0
	mut i := 0
	for i < path.len {
		if path[i] == 47 || path[i] == 92 { // / 或 \
			last = i + 1
		}
		i = i + 1
	}
	return path[last..]
}


fn main() {
	// cone 0.9.p 预发布：不再每次运行打印 banner / 计时（只在 -v 输出版本）
	mut diags := Diagnostics{} // cone 0.9.3：一次编译收集全部 error / warning

	mut opts := parse_cli(os.args) or {
		eprintln(format_error('Usage|' + err.msg()))
		exit(1)
	}
	if opts.show_version {
		print_version()
		exit(0)
	}

	// cone 0.8prelease：多文件编译。每个 .cone 独立走完整流水线、各生成一份 .asm；
	// 源码里的 __compile__ / __link__ 汇入附加参数，最后一次性跑编译 / 链接。
	// cone 0.9.f：x64 多文件时不再各出一个 exe，而是各出 .obj 后联合链接成单个 exe。
	mut multi_llvm := opts.llvm_arch.len > 0 && opts.src_paths.len > 1
	mut llvm_stems := []string{}
	mut llvm_entry := ''
	for fi := 0; fi < opts.src_paths.len; fi++ {
		src_path := opts.src_paths[fi]
		out_path := opts.out_paths[fi]
		println('[cone] ${base_name(src_path)} -> ${base_name(out_path)}')

		src := os.read_file(src_path) or {
			eprintln(format_error('IO|Cannot read source file ${src_path}'))
			exit(1)
		}
		x64_mode := opts.llvm_arch.len > 0
		toks_raw := lex(src, src_path, x64_mode) or {
			diags.add_error(src_path, first_number(err.msg()), err.msg())
			eprintln(diags.render())
			exit(1)
		}
	// cone 0.9.p：去掉阶段 / 计时调试输出

		mut toks := expand_imports(toks_raw, src_path, opts.cone_dir, x64_mode) or {
			diags.add_error(src_path, first_number(err.msg()), err.msg())
			eprintln(diags.render())
			exit(1)
		}
	// cone 0.9.p：去掉阶段 / 计时调试输出

		// cone 0.9.f：源码级预处理（defsym / ifdef / ifndef / elsedef / enum）
		toks = preprocess_v(toks, opts.defsyms, x64_mode) or {
			diags.add_error(src_path, first_number(err.msg()), err.msg())
			eprintln(diags.render())
			exit(1)
		}

		prog := parse(toks) or {
			diags.add_error(src_path, first_number(err.msg()), err.msg())
			eprintln(diags.render())
			exit(1)
		}
	// cone 0.9.p：去掉阶段 / 计时调试输出

		st := analyze(prog, src_path, x64_mode) or {
			diags.add_error(src_path, first_number(err.msg()), err.msg())
			SymTab{} // 部分符号表：collect_diagnostics 仍可扫描其余独立错误
		}
	// cone 0.9.p：去掉阶段 / 计时调试输出

		collect_diagnostics(prog, st, mut diags, src_path)
		if opts.llvm_arch.len > 0 {
			mut kept := []Diagnostic{}
			for d in diags.items {
				if d.msg.contains('edx:eax') || d.msg.contains('coneABI') { continue }
				kept << d
			}
			diags.items = kept
		}
		if diags.has_errors() {
			continue // 有 error 不生成 .asm；继续下一个源文件以收集全部诊断
		}

		// cone 0.9.f：-llvm:x64 分支。MASM32 路径（下面的 generate）一字不改。
		if opts.llvm_arch.len > 0 {
			ir, lerr, lfile, lline := gen_llvm_v(prog, st, opts.llvm_arch, opts.llvm_opt)
			if lerr.len > 0 {
				mut ff := src_path
				if lfile.len > 0 { ff = lfile }
				diags.add_error(ff, lline, lerr)
				continue
			}
			os.write_file(out_path, ir) or {
				eprintln(format_error('CodeGen|Cannot write LLVM IR file ${out_path}'))
				exit(1)
			}
	// cone 0.9.p：去掉阶段 / 计时调试输出
			// 源码内 __compile__ / __link__ 与 include 的 .lib 都要在工具链调用前汇入
			for ca in prog.compile_args { opts.addm = append_arg(opts.addm, ca) }
			for la in prog.link_args { opts.addl = append_arg(opts.addl, la) }
			for lib in x64_include_libs_v(prog) {
				if !opts.addl.contains(lib) { opts.addl = append_arg(opts.addl, lib) }
			}
			if multi_llvm {
				// 收集单元；入口由带 `end` 的那个单元提供
				llvm_stems << out_path
				if prog.has_entry {
					if llvm_entry.len > 0 && llvm_entry != prog.entry {
						eprintln(format_error('Toolchain|多文件联合链接只允许一个 end 入口，发现 ${llvm_entry} 与 ${prog.entry}'))
						exit(1)
					}
					llvm_entry = prog.entry
				}
				continue
			}
			mut ent1 := prog.entry
			if ent1.len == 0 { ent1 = 'main' }
			tmsg := llvm_run_toolchain_v(out_path, opts.llvm_arch, ent1,
				opts.llvm_opt, opts.addm, opts.addl, opts.llvm_ir_only)
			println(tmsg)
			continue
		}
		asm_text := generate(prog, st, GenOpts{
			cone_dir:       opts.cone_dir
			short_include:  opts.short_include
			no_default_seh: opts.no_default_seh
			o1:             opts.o1
			o1_opts:        opts.o1_opts
			src_path:       src_path
		})
		os.write_file(out_path, asm_text) or {
			eprintln(format_error('CodeGen|Cannot write output file ${out_path}'))
			exit(1)
		}
	// cone 0.9.p：去掉阶段 / 计时调试输出

		// cone 0.8prelease：源码内 __compile__ / __link__ 等价于 -addm / -addl。
		for ca in prog.compile_args {
			opts.addm = append_arg(opts.addm, ca)
		}
		for la in prog.link_args {
			opts.addl = append_arg(opts.addl, la)
		}
	}

	// cone 0.9.f：多份 .ll 各自 llc 成 .obj，再一次性 lld-link 成单个 .exe。
	if multi_llvm {
		mut exe_base := opts.out_name
		if exe_base.len == 0 {
			exe_base = llvm_stem_v(opts.src_paths[0])
		}
		exe_stem := os.join_path(os.dir(opts.out_paths[0]), exe_base)
		mut ent := llvm_entry
		if ent.len == 0 { ent = 'main' }
		tmsg := llvm_run_toolchain_multi_v(llvm_stems, exe_stem, opts.llvm_arch, ent,
			opts.llvm_opt, opts.addm, opts.addl, opts.llvm_ir_only)
		println(tmsg)
	}

	// cone 0.9.3：一次输出全部诊断；warning 不中断，error 以退出码 1 结束。
	if diags.items.len > 0 {
		eprintln(diags.render())
	}
	if diags.has_errors() {
		exit(1)
	}

	// -m / -l / -ml / -lw / -lc：把所有 .asm / .obj 一次性传给工具链。
	run_toolchain(opts, opts.out_paths) or {
		eprintln(format_error('Toolchain|' + err.msg()))
		exit(1)
	}

}
