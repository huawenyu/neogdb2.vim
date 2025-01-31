if exists("g:loaded_neogdb2") || &cp || !has("nvim")
    finish
endif
let g:loaded_neogdb2 = "./.gdb_cmdstr"
silent! let s:log = logger#getLogger(expand('<sfile>:t'))
let s:script_path = expand('<sfile>:p:h')


let s:neobugger_help_st = -1
function! NeobuggerHelpStr()
    let s:neobugger_help_st += 1

    let l:cmdstr = ""
    if filereadable(g:loaded_neogdb2)
        let l:cmdstr = join(readfile(g:loaded_neogdb2), " ")
    endif

    if s:neobugger_help_st % 3 == 0
        if empty(l:cmdstr)
            return 'Neobugger file host hostname addr:port'
        else
            return 'Neobugger ' .. l:cmdstr
        endif
    elseif s:neobugger_help_st % 3 == 1
        if exists("g:neobugger_remote")
            return 'Neobugger '.. g:neobugger_remote
        else
            return 'Neobugger sysinit/init dut1 dut1 127.0.0.1:4441'
        endif
    elseif s:neobugger_help_st % 3 == 2
        return 'Neobugger ' .. fnamemodify(expand("%"), ":r")
    endif
endfunction


nnoremap <F2> :<c-u><C-\>e   NeobuggerHelpStr()<cr>
cnoremap <F2> :<c-u><C-\>e   NeobuggerHelpStr()<cr>

command! -nargs=+ Neobugger   call neobugger#Attach(<f-args>)

