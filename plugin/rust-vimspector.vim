if exists('g:loaded_rustvimspector') | finish | endif

let s:save_cpo = &cpo
set cpo&vim

if !has('nvim')
    echohl Error
    echom "Sorry this plugin only works with versions of neovim that support lua"
    echohl clear
    finish
endif

command! RustDebugTest lua require'rust-vimspector'.debug("test")
command! RustDebugBuild lua require'rust-vimspector'.debug("build")

let g:loaded_rustvimspector = 1

let &cpo = s:save_cpo
unlet s:save_cpo
